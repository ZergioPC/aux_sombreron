class_name NPCBase
extends CharacterBody3D

## Clase compartida por todos los NPC.
##
## Centraliza el movimiento, la navegación, las animaciones, la percepción y la
## comunicación con la máquina de estados. Las decisiones de cada tipo de NPC
## viven en su NPCBehavior y en sus estados.

enum Classification {
	NORMAL,
	ENEMY,
}

## Se emite cuando el NPC llega a su zona segura y desaparece sin ser capturado.
signal escaped(npc: NPCBase)
## Se emite cuando un señuelo es destruido por un ataque del jugador.
signal decoy_broken(decoy: NPCBase)

@export_group("Configuration")
## Clasificación del NPC. No determina por sí sola su comportamiento.
@export var classification: Classification = Classification.NORMAL
## Zona segura individual del NPC. Puede quedar vacía.
@export var safe_zone: Node3D

@export_group("Role")
## Marca al NPC como señuelo: no es candidato de caza, no se registra para
## reaparición y se destruye al recibir un ataque del jugador.
@export var is_decoy: bool = false
## Si está desactivado, NPCRespawnManager no guarda un plano de este NPC.
@export var register_for_respawn: bool = true
## Componente opcional para los efectos de aparición y desaparición.
@export var effect_emitter: Node

@export_group("Movement")
## Velocidad usada al caminar (por ejemplo, durante el estado Idle).
@export var walk_speed: float = 0.6
## Velocidad usada al correr (por ejemplo, durante el estado Escape).
@export var run_speed: float = 2.0
@export var acceleration: float = 10.0
@export var rotation_speed: float = 8.0
@export var gravity: float = 20.0
@export var arrival_distance: float = 0.6

@export_group("Movement Modifier")
## Componente opcional que altera la dirección y la velocidad deseadas.
## Si se deja vacío, se resuelve automáticamente por el nodo "MovementModifier".
@export var movement_modifier: NPCMovementModifier

@export_group("Perception")
@export var detection_range: float = 6.0

@export_group("Animations")
@export var idle_animation: StringName = &"idle"
@export var walk_animation: StringName = &"walk"
@export var escape_animation: StringName = &"run"

@export_group("References")
## Si se dejan vacías, se resuelven automáticamente por nombre de nodo.
@export var navigation_agent: NavigationAgent3D
@export var model: Node3D

@export_group("Spawn")
## Posición a la que vuelve el NPC al terminar una cinemática de captura.
## Con [member use_scene_position_as_spawn] activo se sobrescribe en runtime con
## la posición de la escena y solo sirve como lectura.
@export var spawn_position: Vector3 = Vector3.ZERO
## Toma la posición de aparición del transform de la escena. Desactívalo para
## definir manualmente [member spawn_position] en el Inspector.
@export var use_scene_position_as_spawn: bool = true

var behavior: NPCBehavior
var state_machine: NPCStateMachine
var perception: NPCPerception
var impact_receiver: Node

## Indica si este NPC es el objetivo de caza actual.
var is_hunt_target: bool = false
## Indica si este NPC ya fue capturado.
var is_captured: bool = false

var _animation_player: AnimationPlayer
var _is_moving: bool = false
var _has_destination: bool = false
var _destination: Vector3 = Vector3.ZERO
var _movement_elapsed: float = 0.0
var _movement_speed: float = 0.0
var _missing_animations: Dictionary = {}

## Tiempo mínimo antes de confiar en NavigationAgent3D.is_navigation_finished().
## Evita que un destino se considere alcanzado antes de que se calcule la ruta.
const DESTINATION_GRACE_TIME := 0.25


func _ready() -> void:
	add_to_group(&"npc")

	if is_decoy:
		add_to_group(&"npc_decoy")

	# La posición de spawn se toma del transform de aparición antes de que la
	# navegación o la IA puedan desplazar al NPC.
	if use_scene_position_as_spawn:
		spawn_position = global_position

	_resolve_references()
	_configure_perception()

	GameState.player_discovered.connect(_on_player_discovered)

	if behavior != null:
		behavior.setup(self)

	if state_machine != null:
		state_machine.setup(self)
		state_machine.start()

	# Hook de efectos: hoy las escenas están vacías, pero el enganche ya existe.
	_play_effect(&"play_spawn_effect")

	# Si el jugador ya había sido descubierto antes de que este NPC apareciera,
	# hay que notificarlo para que reaccione igual que el resto.
	if GameState.is_discovered:
		_on_player_discovered()


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)

	if state_machine != null:
		state_machine.update(delta)

	if _is_moving:
		_follow_navigation_path(delta)
	else:
		_decelerate(delta)

	if impact_receiver != null:
		impact_receiver.integrate(delta)

	move_and_slide()


# -----------------------------------------------------------------------------
# MOVEMENT AND NAVIGATION
# -----------------------------------------------------------------------------

## Inicia el desplazamiento hacia una posición usando el NavigationAgent3D.
## Si [param speed] es menor o igual a cero se usa walk_speed.
func move_to_position(target_position: Vector3, speed: float = -1.0) -> void:
	if navigation_agent == null:
		push_warning("NPC '%s' no tiene un NavigationAgent3D asignado." % name)
		stop_movement()
		return

	if movement_modifier != null:
		movement_modifier.reset()

	_movement_speed = walk_speed if speed <= 0.0 else speed
	_destination = target_position
	_has_destination = true
	_is_moving = true
	_movement_elapsed = 0.0
	navigation_agent.target_position = target_position


## Detiene el desplazamiento actual y anula la velocidad horizontal.
func stop_movement() -> void:
	if movement_modifier != null:
		movement_modifier.reset()

	_is_moving = false
	_has_destination = false
	_movement_elapsed = 0.0
	velocity.x = 0.0
	velocity.z = 0.0


## Indica si el NPC ya llegó al destino solicitado.
func has_reached_destination() -> bool:
	if not _has_destination:
		return true

	var offset := _destination - global_position
	offset.y = 0.0

	if offset.length() <= arrival_distance:
		return true

	if _movement_elapsed < DESTINATION_GRACE_TIME:
		return false

	if navigation_agent != null and navigation_agent.is_navigation_finished():
		return true

	return false


## Busca un punto aleatorio sobre el mapa de navegación del NPC.
##
## El punto debe estar a una distancia horizontal entre [param min_distance] y
## [param max_distance], y debe ser alcanzable desde la posición actual. Devuelve
## un Dictionary con las claves "found" (bool) y "position" (Vector3). Si no se
## encuentra un punto válido, "found" es false.
func get_random_navigation_position(
	min_distance: float = 1.0,
	max_distance: float = 20.0,
	max_attempts: int = 10
) -> Dictionary:
	var result := {"found": false, "position": Vector3.ZERO}

	if navigation_agent == null:
		return result

	var map_rid := navigation_agent.get_navigation_map()
	if not map_rid.is_valid():
		return result

	var navigation_layers := navigation_agent.navigation_layers
	var attempt_count := maxi(max_attempts, 1)

	for _attempt in attempt_count:
		var candidate := NavigationServer3D.map_get_random_point(
			map_rid, navigation_layers, true
		)

		var offset := candidate - global_position
		offset.y = 0.0
		var distance := offset.length()

		if distance < min_distance or distance > max_distance:
			continue

		if not _is_navigation_position_reachable(
			map_rid, candidate, navigation_layers
		):
			continue

		result["found"] = true
		result["position"] = candidate
		return result

	return result


## Comprueba que exista una ruta de navegación hasta [param target].
func _is_navigation_position_reachable(
	map_rid: RID,
	target: Vector3,
	navigation_layers: int
) -> bool:
	var path := NavigationServer3D.map_get_path(
		map_rid, global_position, target, true, navigation_layers
	)

	if path.is_empty():
		return false

	var path_end := path[path.size() - 1]
	return path_end.distance_to(target) <= maxf(arrival_distance, 1.0)


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta


func _follow_navigation_path(delta: float) -> void:
	if navigation_agent == null:
		stop_movement()
		return

	_movement_elapsed += delta

	if (
		_movement_elapsed >= DESTINATION_GRACE_TIME
		and navigation_agent.is_navigation_finished()
	):
		stop_movement()
		return

	var next_position := navigation_agent.get_next_path_position()
	var direction := next_position - global_position
	direction.y = 0.0

	if direction.length_squared() <= 0.0001:
		return

	direction = direction.normalized()

	var desired_speed := _movement_speed

	if movement_modifier != null:
		var remaining_distance := global_position.distance_to(_destination)
		var modified: Dictionary = movement_modifier.modify_movement(
			direction, desired_speed, delta, remaining_distance
		)
		var modified_direction: Vector3 = modified.get("direction", direction)
		var modified_speed: float = modified.get("speed", desired_speed)
		direction = modified_direction
		desired_speed = modified_speed

	velocity.x = move_toward(velocity.x, direction.x * desired_speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * desired_speed, acceleration * delta)

	_rotate_model_towards(direction, delta)


func _decelerate(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)


func _rotate_model_towards(direction: Vector3, delta: float) -> void:
	if model == null:
		return

	var target_angle := atan2(direction.x, direction.z)
	model.rotation.y = lerp_angle(model.rotation.y, target_angle, rotation_speed * delta)


# -----------------------------------------------------------------------------
# SAFE ZONE
# -----------------------------------------------------------------------------

func has_safe_zone() -> bool:
	return safe_zone != null and is_instance_valid(safe_zone)


func get_safe_zone_position() -> Vector3:
	if not has_safe_zone():
		return global_position
	return safe_zone.global_position


# -----------------------------------------------------------------------------
# HUNT TARGET
# -----------------------------------------------------------------------------

## Marca o desmarca a este NPC como objetivo de caza.
func set_hunt_target(value: bool) -> void:
	is_hunt_target = value


# -----------------------------------------------------------------------------
# DECOY AND ESCAPE
# -----------------------------------------------------------------------------

## Destruye un señuelo al recibir un ataque del jugador.
## Solo actúa si el NPC está marcado como señuelo. Devuelve true si lo destruyó.
func break_decoy() -> bool:
	if not is_decoy or is_queued_for_deletion():
		return false

	decoy_broken.emit(self)
	despawn()
	return true


## Notifica que el NPC llegó a su zona segura y va a desaparecer sin ser
## capturado. [HuntManager] usa esta señal para no conservar una referencia
## liberada como objetivo de caza.
func notify_escaped() -> void:
	escaped.emit(self)


# -----------------------------------------------------------------------------
# DESPAWN
# -----------------------------------------------------------------------------

## Hace desaparecer al NPC de forma inmediata.
func despawn() -> void:
	# El efecto se reproduce antes de ocultar y liberar, en la escena actual,
	# para que no desaparezca junto con el NPC.
	_play_effect(&"play_despawn_effect")

	stop_movement()
	visible = false
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	queue_free()


## Llama a un método del emisor de efectos sin acoplar NPCBase a su clase.
func _play_effect(method_name: StringName) -> void:
	if effect_emitter == null or not is_instance_valid(effect_emitter):
		return

	if effect_emitter.has_method(method_name):
		effect_emitter.call(method_name, global_position)


# -----------------------------------------------------------------------------
# SPAWN
# -----------------------------------------------------------------------------

## Devuelve al NPC a su posición de aparición y reinicia su estado a Idle.
##
## Se usa al terminar una cinemática para que los NPC no capturados vuelvan a su
## spawn y puedan ser elegidos como nuevo objetivo. No hace nada si el NPC ya
## fue capturado o está en cola de liberación.
func return_to_spawn() -> void:
	if is_captured or is_queued_for_deletion():
		return

	stop_movement()
	velocity = Vector3.ZERO
	global_position = spawn_position

	# Evita que una ruta de navegación pendiente lo aleje del spawn.
	if navigation_agent != null:
		navigation_agent.target_position = spawn_position

	# Volver a Idle evita que un NPC en escape quede excluido como objetivo.
	request_state(&"idle")
	play_animation(idle_animation)


# -----------------------------------------------------------------------------
# EVENTS AND STATE MACHINE
# -----------------------------------------------------------------------------

## Envía un evento al comportamiento para que decida la reacción.
func notify_event(event: Dictionary) -> void:
	if behavior == null:
		return
	behavior.handle_event(event)


## Solicita un cambio de estado a la máquina de estados.
func request_state(state_name: StringName) -> bool:
	if state_machine == null:
		return false
	return state_machine.transition_to(state_name)


func has_perceived_threats() -> bool:
	return perception != null and perception.has_detected_bodies()


func _on_perception_body_detected(body: Node3D) -> void:
	notify_event({
		"name": NPCBehavior.EVENT_THREAT_DETECTED,
		"source": body,
	})


func _on_perception_body_lost(body: Node3D) -> void:
	notify_event({
		"name": NPCBehavior.EVENT_THREAT_LOST,
		"source": body,
	})


## Reenvía al comportamiento el descubrimiento global del jugador.
## El comportamiento decide si huye o no (por ejemplo, el objetivo de caza).
func _on_player_discovered() -> void:
	notify_event({
		"name": NPCBehavior.EVENT_PLAYER_DISCOVERED,
	})


# -----------------------------------------------------------------------------
# ANIMATIONS
# -----------------------------------------------------------------------------

## Reproduce una animación del modelo. Si no existe, se ignora sin errores.
func play_animation(animation_name: StringName, speed_scale: float = 1.0) -> void:
	if _animation_player == null:
		return

	if not _animation_player.has_animation(animation_name):
		if not _missing_animations.has(animation_name):
			_missing_animations[animation_name] = true
			push_warning(
				"NPC '%s' no tiene la animación '%s'." % [name, animation_name]
			)
		return

	if (
		_animation_player.current_animation == animation_name
		and _animation_player.is_playing()
	):
		_animation_player.speed_scale = speed_scale
		return

	_animation_player.play(animation_name, 0.1)
	_animation_player.speed_scale = speed_scale


# -----------------------------------------------------------------------------
# CINEMATIC
# -----------------------------------------------------------------------------

## Devuelve el AnimationPlayer del NPC para la cinemática.
func get_animation_player() -> AnimationPlayer:
	return _animation_player


## Detiene el NPC y reproduce el clip cinemático solicitado.
## Devuelve true si pudo reproducir algo. No cambia de cámara ni captura.
func begin_cinematic(animation_name: StringName) -> bool:
	stop_movement()
	velocity = Vector3.ZERO

	if _animation_player == null:
		return false

	var clip := animation_name

	if not _animation_player.has_animation(clip):
		push_warning(
			"NPC '%s' no tiene la animación '%s'; se usa 'idle'." % [name, clip]
		)
		clip = &"idle"

	if not _animation_player.has_animation(clip):
		push_warning(
			"NPC '%s' no tiene la animación de respaldo '%s'." % [name, clip]
		)
		return false

	_animation_player.speed_scale = 1.0
	_animation_player.play(clip)
	return true


## Restaura la animación base tras la cinemática. No reinicia la persecución
## ni elige destinos; la pausa del árbol detuvo la IA durante la secuencia.
func end_cinematic() -> void:
	play_animation(idle_animation)


# -----------------------------------------------------------------------------
# INITIALIZATION HELPERS
# -----------------------------------------------------------------------------

func _resolve_references() -> void:
	if navigation_agent == null:
		navigation_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D

	if model == null:
		model = get_node_or_null("Model") as Node3D

	if movement_modifier == null:
		movement_modifier = get_node_or_null("MovementModifier") as NPCMovementModifier

	behavior = get_node_or_null("Behavior") as NPCBehavior
	state_machine = get_node_or_null("StateMachine") as NPCStateMachine
	perception = get_node_or_null("PerceptionArea") as NPCPerception
	impact_receiver = get_node_or_null("ImpactReceiver")

	if effect_emitter == null:
		effect_emitter = get_node_or_null("EffectEmitter")

	_animation_player = _find_animation_player()

	if perception != null:
		perception.body_detected.connect(_on_perception_body_detected)
		perception.body_lost.connect(_on_perception_body_lost)


func _configure_perception() -> void:
	if perception == null:
		return
	perception.set_detection_range(detection_range)


## Aplica knockback al NPC delegando en el componente de impacto.
## No modifica estados ni decide reacciones: solo ejecuta la física.
func apply_knockback(direction_xz: Vector3, force: float) -> void:
	if impact_receiver == null:
		return
	impact_receiver.apply_knockback(direction_xz, force)


func _find_animation_player() -> AnimationPlayer:
	if model == null:
		return null

	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return null

	return players[0] as AnimationPlayer
