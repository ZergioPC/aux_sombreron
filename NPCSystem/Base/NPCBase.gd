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

@export_group("Configuration")
## Clasificación del NPC. No determina por sí sola su comportamiento.
@export var classification: Classification = Classification.NORMAL
## Zona segura individual del NPC. Puede quedar vacía.
@export var safe_zone: Node3D

@export_group("Movement")
@export var move_speed: float = 2.0
@export var acceleration: float = 10.0
@export var rotation_speed: float = 8.0
@export var gravity: float = 20.0
@export var arrival_distance: float = 0.6

@export_group("Perception")
@export var detection_range: float = 6.0

@export_group("Animations")
@export var idle_animation: StringName = &"idle"
@export var escape_animation: StringName = &"run"

@export_group("References")
## Si se dejan vacías, se resuelven automáticamente por nombre de nodo.
@export var navigation_agent: NavigationAgent3D
@export var model: Node3D

var behavior: NPCBehavior
var state_machine: NPCStateMachine
var perception: NPCPerception

var _animation_player: AnimationPlayer
var _is_moving: bool = false
var _has_destination: bool = false
var _destination: Vector3 = Vector3.ZERO
var _movement_elapsed: float = 0.0
var _missing_animations: Dictionary = {}

## Tiempo mínimo antes de confiar en NavigationAgent3D.is_navigation_finished().
## Evita que un destino se considere alcanzado antes de que se calcule la ruta.
const DESTINATION_GRACE_TIME := 0.25


func _ready() -> void:
	add_to_group(&"npc")
	_resolve_references()
	_configure_perception()

	if behavior != null:
		behavior.setup(self)

	if state_machine != null:
		state_machine.setup(self)
		state_machine.start()


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)

	if state_machine != null:
		state_machine.update(delta)

	if _is_moving:
		_follow_navigation_path(delta)
	else:
		_decelerate(delta)

	move_and_slide()


# -----------------------------------------------------------------------------
# MOVEMENT AND NAVIGATION
# -----------------------------------------------------------------------------

## Inicia el desplazamiento hacia una posición usando el NavigationAgent3D.
func move_to_position(target_position: Vector3) -> void:
	if navigation_agent == null:
		push_warning("NPC '%s' no tiene un NavigationAgent3D asignado." % name)
		stop_movement()
		return

	_destination = target_position
	_has_destination = true
	_is_moving = true
	_movement_elapsed = 0.0
	navigation_agent.target_position = target_position


## Detiene el desplazamiento actual y anula la velocidad horizontal.
func stop_movement() -> void:
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

	velocity.x = move_toward(velocity.x, direction.x * move_speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * move_speed, acceleration * delta)

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
# INITIALIZATION HELPERS
# -----------------------------------------------------------------------------

func _resolve_references() -> void:
	if navigation_agent == null:
		navigation_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D

	if model == null:
		model = get_node_or_null("Model") as Node3D

	behavior = get_node_or_null("Behavior") as NPCBehavior
	state_machine = get_node_or_null("StateMachine") as NPCStateMachine
	perception = get_node_or_null("PerceptionArea") as NPCPerception

	_animation_player = _find_animation_player()

	if perception != null:
		perception.body_detected.connect(_on_perception_body_detected)
		perception.body_lost.connect(_on_perception_body_lost)


func _configure_perception() -> void:
	if perception == null:
		return
	perception.set_detection_range(detection_range)


func _find_animation_player() -> AnimationPlayer:
	if model == null:
		return null

	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return null

	return players[0] as AnimationPlayer
