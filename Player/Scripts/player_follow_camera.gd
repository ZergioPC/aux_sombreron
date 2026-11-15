extends Node3D

## Cámara de gameplay en perspectiva superior (top-down inclinada).
##
## Sigue al personaje activo real del jugador (`player.gd ->
## get_active_character()`) y no depende de `GameState.form`. Al cambiar de
## forma hace snap al nuevo personaje para evitar un desplazamiento largo.
## Se actualiza en `_physics_process` para ir sincronizada con los
## `CharacterBody3D`.
##
## El `offset` es mundial, no relativo a la rotación del personaje: mantiene
## una vista estable y evita desorientación sin control por ratón.

# Altura calculada para que la línea de visión quede a 40° por debajo de la
# horizontal: look_height + 9.0 * tan(40°). Ajustable desde el Inspector.
@export var offset: Vector3 = Vector3(0.0, 8.55, 9.0)
@export var look_height: float = 1.0
@export var follow_speed: float = 8.0
@export var snap_distance: float = 3.0

var _target: Node3D = null

@onready var _player: Node3D = get_parent() as Node3D
@onready var _camera: Camera3D = $GameplayCamera


func _ready() -> void:
	# La cámara de gameplay es la cámara activa en juego normal.
	_camera.current = true

	# El jugador emite la forma activa al terminar de inicializarse y en cada
	# cambio de forma. La conexión por nombre evita depender del tipo del
	# script del padre.
	if _player != null and _player.has_signal(&"active_character_changed"):
		_player.connect(&"active_character_changed", _on_active_character_changed)

	# Coloca la cámara sobre la forma inicial sin esperar al primer frame.
	_set_target(_resolve_active_character())


func _physics_process(delta: float) -> void:
	var active_character := _resolve_active_character()

	# Si la forma activa cambia sin señal (por seguridad), hace snap igualmente.
	if active_character != _target:
		_set_target(active_character)

	if not is_instance_valid(_target):
		return

	var desired_position := _target.global_position + offset

	# Si la cámara se queda demasiado atrás (por ejemplo, tras un dash),
	# recupera la posición de golpe en lugar de arrastrarse.
	if global_position.distance_to(desired_position) > snap_distance:
		global_position = desired_position
	else:
		# Suavizado independiente de los fps.
		var weight := 1.0 - exp(-follow_speed * delta)
		global_position = global_position.lerp(desired_position, weight)

	_look_at_target()


## Devuelve el personaje que controla el jugador en este momento.
func _resolve_active_character() -> Node3D:
	if _player != null and _player.has_method(&"get_active_character"):
		return _player.get_active_character() as Node3D
	return null


## Asigna el objetivo de seguimiento y, opcionalmente, hace snap inmediato.
func _set_target(character: Node3D) -> void:
	_target = character

	if not is_instance_valid(_target):
		# Sin objetivo válido se conserva la última posición conocida.
		return

	global_position = _target.global_position + offset
	_look_at_target()


## Orienta la cámara hacia el objetivo a la altura de mirada configurada.
func _look_at_target() -> void:
	if not is_instance_valid(_target):
		return

	var look_position := _target.global_position + Vector3.UP * look_height

	# Evita un `look_at` inválido si la cámara coincide con el punto de mira.
	if global_position.is_equal_approx(look_position):
		return

	look_at(look_position, Vector3.UP)


## Reacciona al cambio de forma activa haciendo snap sobre el nuevo personaje.
func _on_active_character_changed(character: Node3D) -> void:
	_set_target(character)
