class_name CinematicController
extends Node3D

## Controlador del ciclo de vida completo de la cinemática de captura.
##
## El ataque solo solicita la cinemática con [method play_cinematic]. Toda
## transición, pausa, cambio de cámara, captura y restauración vive aquí.
##
## Estructura esperada de la escena:
##
##     CinematicController
##     ├── CameraRig (top_level, no se anima)
##     │   └── CameraMotion (recibe las pistas locales)
##     │       └── CinematicCamera
##     ├── AnimationPlayer (PROCESS_MODE_ALWAYS)
##     └── CameraOcclusionController (PROCESS_MODE_ALWAYS)
##
## La animación de cámara se authored en espacio local respecto a CameraMotion.
## CameraRig recibe el transform global del CinematicMarker y no se anima, de
## modo que el mismo clip funciona en cualquier lugar del mapa.

## Se emite cuando la secuencia quedó iniciada.
signal cinematic_started(id: StringName, attacker: Node3D, target: Node3D)
## Se emite al terminar una secuencia iniciada con [method finish_cinematic].
signal cinematic_finished(id: StringName, captured: bool)
## Se emite al cancelar una secuencia sin capturar.
signal cinematic_cancelled(id: StringName)

enum State {
	IDLE,
	PREPARING,
	PLAYING,
	RESTORING,
}

@export_group("Definitions")
## Definiciones disponibles. Se indexan por [member CinematicDefinition.id].
@export var definitions: Array[CinematicDefinition] = []

@export_group("Placeholder")
## Genera una animación temporal si el clip de cámara no existe.
## La animación definitiva, con el mismo nombre, siempre tiene prioridad.
@export var generate_placeholder_if_missing: bool = true
## Duración de la animación temporal, en segundos.
@export var placeholder_duration: float = 3.0
## Instante de la captura dentro de la animación temporal, en segundos.
@export var placeholder_capture_time: float = 1.5

@onready var camera_rig: Node3D = $CameraRig
@onready var camera_motion: Node3D = $CameraRig/CameraMotion
@onready var cinematic_camera: Camera3D = $CameraRig/CameraMotion/CinematicCamera
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var occlusion_controller: CinematicOcclusionController = $CameraOcclusionController

var _state: State = State.IDLE
var _definitions: Dictionary = {}

var _current_definition: CinematicDefinition = null
var _attacker: Node3D = null
var _target: Node3D = null
var _cinematic_id: StringName = &""
var _current_animation: StringName = &""
var _current_animation_path: StringName = &""
var _captured: bool = false

var _saved_camera: Camera3D = null
var _camera_home_transform: Transform3D = Transform3D.IDENTITY
var _saved_players: Array[Dictionary] = []


func _ready() -> void:
	_camera_home_transform = camera_motion.transform
	_build_definition_map()

	# Respaldo del final: la pista de método final o este evento cierran la
	# cinemática. La guarda de estado evita una doble finalización.
	animation_player.animation_finished.connect(_on_animation_finished)


func _exit_tree() -> void:
	# Debe ser seguro cerrar la escena durante una cinemática.
	if _state != State.IDLE:
		cancel_cinematic()


# -----------------------------------------------------------------------------
# API PÚBLICA
# -----------------------------------------------------------------------------

## Solicita una cinemática. Devuelve true solo si la secuencia quedó iniciada.
##
## Valida que el objetivo sea el objetivo de caza actual, que exista la
## definición y que el atacante exponga un CinematicMarker válido. Si falta
## algo, registra un aviso y devuelve false; el atacante decide el fallback.
func play_cinematic(
	attacker: Node3D,
	target: Node3D,
	cinematic_id: StringName
) -> bool:
	if _state != State.IDLE:
		push_warning("CinematicController: ya hay una cinemática en curso.")
		return false

	if GameState.is_cinematic_active:
		push_warning("CinematicController: GameState ya marca una cinemática activa.")
		return false

	if not is_instance_valid(attacker) or not is_instance_valid(target):
		push_warning("CinematicController: atacante u objetivo no válidos.")
		return false

	var npc := target as NPCBase
	if npc == null:
		push_warning("CinematicController: el objetivo no es un NPCBase.")
		return false

	if not npc.is_hunt_target:
		push_warning("CinematicController: el NPC no es objetivo de caza.")
		return false

	if HuntManager.current_target != npc:
		push_warning("CinematicController: el NPC no es el objetivo de caza actual.")
		return false

	var definition := _definitions.get(cinematic_id) as CinematicDefinition
	if definition == null:
		push_warning(
			"CinematicController: no existe la definición '%s'." % cinematic_id
		)
		return false

	var marker := _get_attacker_marker(attacker)
	if marker == null:
		push_warning(
			"CinematicController: el atacante no expone un CinematicMarker válido."
		)
		return false

	if not _ensure_camera_animation(definition):
		return false

	_current_definition = definition
	_attacker = attacker
	_target = npc
	_cinematic_id = cinematic_id
	_captured = false

	_prepare(attacker, npc, marker)
	return true


## Finaliza una cinemática en curso. Si se llama en PREPARING se trata como
## cancelación. La captura depende de haber recibido la pista de método.
func finish_cinematic() -> void:
	if _state == State.PREPARING:
		cancel_cinematic()
		return

	if _state != State.PLAYING:
		return

	_restore(_captured, false)


## Cancela una cinemática sin capturar y sin elegir un nuevo objetivo.
func cancel_cinematic() -> void:
	if _state == State.IDLE or _state == State.RESTORING:
		return

	_restore(false, true)


## Indica si hay una cinemática preparándose, reproduciéndose o restaurándose.
func is_playing() -> bool:
	return _state != State.IDLE


# -----------------------------------------------------------------------------
# PREPARACIÓN
# -----------------------------------------------------------------------------

func _prepare(attacker: Node3D, target: NPCBase, marker: Marker3D) -> void:
	_state = State.PREPARING

	_saved_camera = get_viewport().get_camera_3d()

	# Guarda el estado de animación antes de que begin_cinematic lo modifique.
	var attacker_player := _get_character_animation_player(attacker)
	_track_animation_player(attacker_player)
	if attacker.has_method(&"begin_cinematic"):
		attacker.begin_cinematic(_current_definition.attacker_animation)

	var target_player := _get_character_animation_player(target)
	_track_animation_player(target_player)
	if target.has_method(&"begin_cinematic"):
		target.begin_cinematic(_current_definition.target_animation)

	# Ancla global del rig y transform local de referencia para CameraMotion.
	camera_rig.global_transform = marker.global_transform
	camera_motion.transform = _camera_home_transform
	cinematic_camera.current = true

	if occlusion_controller != null:
		occlusion_controller.setup(cinematic_camera, attacker, target)
		occlusion_controller.start()

	# GameState es la única autoridad de la pausa.
	GameState.begin_cinematic()

	_current_animation = _current_definition.camera_animation
	_current_animation_path = _resolve_camera_animation_path(_current_animation)

	_state = State.PLAYING
	animation_player.play(_current_animation_path)
	cinematic_started.emit(_cinematic_id, attacker, target)


# -----------------------------------------------------------------------------
# EVENTOS DE LA ANIMACIÓN DE CÁMARA
# -----------------------------------------------------------------------------

## Pista de método de captura. Se ejecuta dentro de la animación de cámara.
func _on_cinematic_capture() -> void:
	if _state != State.PLAYING or _captured:
		return

	if not is_instance_valid(_target):
		push_warning("CinematicController: el objetivo ya no es válido en la captura.")
		return

	if HuntManager.current_target != _target:
		push_warning(
			"CinematicController: la captura no coincide con el objetivo actual."
		)
		return

	_captured = true

	if occlusion_controller != null:
		occlusion_controller.clear_target()

	# A partir de aquí el NPC puede quedar liberado; no conservar la referencia.
	HuntManager.complete_current_target()
	_target = null


## Pista de método final. Autoridad preferida del final de la secuencia.
func _on_cinematic_animation_end() -> void:
	if _state == State.PLAYING:
		finish_cinematic()


## Respaldo del final mediante la señal del AnimationPlayer. El nombre puede
## incluir el prefijo de la librería ("cinematics/nombre").
func _on_animation_finished(animation_name: StringName) -> void:
	if _state != State.PLAYING:
		return

	if _animation_base_name(animation_name) == _current_animation:
		finish_cinematic()


# -----------------------------------------------------------------------------
# RESTAURACIÓN
# -----------------------------------------------------------------------------

func _restore(captured: bool, cancelled: bool) -> void:
	if _state == State.RESTORING:
		return

	_state = State.RESTORING

	animation_player.stop()

	if occlusion_controller != null:
		occlusion_controller.stop()

	_restore_animation_players()

	if is_instance_valid(_attacker) and _attacker.has_method(&"end_cinematic"):
		_attacker.end_cinematic()

	# Si hubo captura el NPC puede estar liberado o en cola de liberación:
	# no se le reproduce nada. Solo se restaura si la secuencia se canceló.
	if not captured and is_instance_valid(_target):
		if _target.has_method(&"end_cinematic"):
			_target.end_cinematic()

	cinematic_camera.current = false
	_restore_gameplay_camera()

	# Reanudar antes de continue_hunt(): HuntManager comprueba la bandera.
	GameState.end_cinematic()

	if not cancelled:
		HuntManager.continue_hunt()

	var finished_id := _cinematic_id

	if cancelled:
		cinematic_cancelled.emit(finished_id)
	else:
		cinematic_finished.emit(finished_id, captured)

	_state = State.IDLE
	_clear_runtime_state()


func _restore_gameplay_camera() -> void:
	if is_instance_valid(_saved_camera):
		_saved_camera.current = true
		return

	var fallback := get_tree().get_first_node_in_group(&"gameplay_camera") as Camera3D
	if fallback != null:
		fallback.current = true
		return

	push_warning(
		"CinematicController: no se encontró una cámara de gameplay para restaurar."
	)


func _clear_runtime_state() -> void:
	_current_definition = null
	_attacker = null
	_target = null
	_cinematic_id = &""
	_current_animation = &""
	_current_animation_path = &""
	_captured = false
	_saved_camera = null
	_saved_players.clear()


# -----------------------------------------------------------------------------
# ANIMACIONES DE PERSONAJE
# -----------------------------------------------------------------------------

func _get_character_animation_player(character: Node3D) -> AnimationPlayer:
	if character == null or not is_instance_valid(character):
		return null

	if character.has_method(&"get_animation_player"):
		return character.get_animation_player() as AnimationPlayer

	return null


## Guarda el estado original de un AnimationPlayer y lo mantiene activo con el
## árbol pausado. El personaje completo NO se pone en PROCESS_MODE_ALWAYS.
func _track_animation_player(player: AnimationPlayer) -> void:
	if player == null or not is_instance_valid(player):
		return

	for entry in _saved_players:
		if entry.get("player") == player:
			return

	_saved_players.append({
		"player": player,
		"process_mode": player.process_mode,
		"speed_scale": player.speed_scale,
	})

	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.speed_scale = 1.0


func _restore_animation_players() -> void:
	for entry in _saved_players:
		# El AnimationPlayer del objetivo puede haber quedado liberado tras la
		# captura. Hay que comprobar la validez antes de convertirlo.
		var saved_player: Variant = entry.get("player")

		if not is_instance_valid(saved_player):
			continue

		var player := saved_player as AnimationPlayer

		if player == null:
			continue

		player.process_mode = int(entry.get("process_mode", Node.PROCESS_MODE_INHERIT))
		player.speed_scale = float(entry.get("speed_scale", 1.0))


# -----------------------------------------------------------------------------
# DEFINICIONES Y ANIMACIÓN DE CÁMARA
# -----------------------------------------------------------------------------

func _build_definition_map() -> void:
	_definitions.clear()

	for definition in definitions:
		if definition == null:
			continue

		if definition.id == &"":
			push_warning("CinematicController: definición sin id; se ignora.")
			continue

		if _definitions.has(definition.id):
			push_warning(
				"CinematicController: id duplicado '%s'; se conserva el primero."
				% definition.id
			)
			continue


		_definitions[definition.id] = definition


func _get_attacker_marker(attacker: Node3D) -> Marker3D:
	if attacker == null or not is_instance_valid(attacker):
		return null

	if not attacker.has_method(&"get_cinematic_marker"):
		return null

	return attacker.get_cinematic_marker() as Marker3D


## Comprueba que exista el clip de cámara o genera el placeholder temporal.
func _ensure_camera_animation(definition: CinematicDefinition) -> bool:
	if definition.camera_animation == &"":
		push_warning(
			"CinematicController: la definición '%s' no tiene animación de cámara."
			% definition.id
		)
		return false

	if _resolve_camera_animation_path(definition.camera_animation) != &"":
		return true

	if not generate_placeholder_if_missing:
		push_warning(
			"CinematicController: no existe '%s' y el placeholder está desactivado."
			% definition.camera_animation
		)
		return false

	# PLACEHOLDER TEMPORAL
	if not _create_placeholder(definition.camera_animation):
		return false

	return _resolve_camera_animation_path(definition.camera_animation) != &""


## Devuelve la ruta reproducible ("librería/nombre" o "nombre") o &"".
func _resolve_camera_animation_path(animation_name: StringName) -> StringName:
	if animation_player.has_animation(animation_name):
		return animation_name

	var library_path := StringName("cinematics/" + String(animation_name))
	if animation_player.has_animation(library_path):
		return library_path

	return &""


func _ensure_cinematics_library() -> AnimationLibrary:
	if animation_player.has_animation_library(&"cinematics"):
		return animation_player.get_animation_library(&"cinematics")

	var library := AnimationLibrary.new()
	var error := animation_player.add_animation_library(&"cinematics", library)

	if error != OK:
		push_warning(
			"CinematicController: no se pudo crear la librería 'cinematics'."
		)
		return null

	return library


# PLACEHOLDER TEMPORAL
# Genera una animación mínima mientras no exista la cinemática definitiva.
# La animación real, creada en el editor con el mismo nombre dentro de la
# librería "cinematics", tiene prioridad y desactiva este generador.
func _create_placeholder(animation_name: StringName) -> bool:
	var duration := maxf(placeholder_duration, 0.1)
	var capture_time := clampf(placeholder_capture_time, 0.0, duration)

	var animation := Animation.new()
	animation.length = duration
	animation.loop_mode = Animation.LOOP_NONE

	var home := _camera_home_transform
	var focus := Vector3(0.0, 1.0, 1.5)
	var start_position := home.origin
	var mid_position := home.origin + Vector3(2.2, 0.9, 0.4)
	var end_position := home.origin

	var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(
		position_track, NodePath("CameraRig/CameraMotion:position")
	)
	animation.position_track_insert_key(position_track, 0.0, start_position)
	animation.position_track_insert_key(position_track, duration * 0.5, mid_position)
	animation.position_track_insert_key(position_track, duration, end_position)

	var rotation_track := animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(
		rotation_track, NodePath("CameraRig/CameraMotion:rotation")
	)
	animation.rotation_track_insert_key(
		rotation_track, 0.0, _look_rotation(start_position, focus)
	)
	animation.rotation_track_insert_key(
		rotation_track, duration * 0.5, _look_rotation(mid_position, focus)
	)
	animation.rotation_track_insert_key(
		rotation_track, duration, _look_rotation(end_position, focus)
	)

	var fov_track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(
		fov_track, NodePath("CameraRig/CameraMotion/CinematicCamera:fov")
	)
	animation.track_insert_key(fov_track, 0.0, 70.0)
	animation.track_insert_key(fov_track, duration * 0.5, 60.0)
	animation.track_insert_key(fov_track, duration, 70.0)

	var capture_track := animation.add_track(Animation.TYPE_METHOD)
	animation.track_set_path(capture_track, NodePath("."))
	animation.track_insert_key(capture_track, capture_time, {
		"method": &"_on_cinematic_capture",
		"args": [],
	})

	var end_track := animation.add_track(Animation.TYPE_METHOD)
	animation.track_set_path(end_track, NodePath("."))
	animation.track_insert_key(end_track, duration, {
		"method": &"_on_cinematic_animation_end",
		"args": [],
	})

	var library := _ensure_cinematics_library()
	if library == null:
		return false

	var error := library.add_animation(animation_name, animation)
	if error != OK:
		push_warning(
			"CinematicController: no se pudo añadir el placeholder '%s'."
			% animation_name
		)
		return false

	return true


func _look_rotation(from: Vector3, focus: Vector3) -> Quaternion:
	var direction := focus - from

	if direction.length_squared() < 0.0001:
		return Quaternion.IDENTITY

	var basis := Basis.looking_at(direction.normalized(), Vector3.UP)
	return basis.get_rotation_quaternion()


func _animation_base_name(animation_name: StringName) -> StringName:
	var text := String(animation_name)
	var slash := text.rfind("/")

	if slash >= 0:
		text = text.substr(slash + 1)

	return StringName(text)
