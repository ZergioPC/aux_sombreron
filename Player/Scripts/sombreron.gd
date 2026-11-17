
extends CharacterBody3D

# -------------------------
# CONFIGURATION
# -------------------------

@export_group("Movement")
@export var walk_speed: float = 3.0
@export var run_speed: float = 6.0
@export var gravity: float = 20.0

@export_group("Dash")
## Tiempo que el jugador permanece quieto antes de desplazarse con el dash.
@export var dash_windup: float = 0.15
@export var dash_speed: float = 12.0
@export var dash_duration: float = 0.25
@export var dash_cooldown: float = 0.8

@export_group("Actions")
@export var attack_duration: float = 0.7
@export var stun_duration: float = 1.0

@export_group("Knockback")
## Decaimiento del empuje recibido por ataques enemigos, en unidades por segundo.
@export var knockback_friction: float = 18.0

@export_group("References")
@export var animation_player: AnimationPlayer
@export var model: Node3D
@export var pivote: Marker3D
## Zona de detección del ataque. Si queda vacía, se resuelve desde [member pivote].
@export var attack_area: Area3D
## Marcador global usado por la cámara cinemática. Si queda vacío, se resuelve
## desde [member pivote].
@export var cinematic_marker: Marker3D

@export_group("Cinematic")
## Identificador de la definición de cinemática solicitada al atacar.
@export var cinematic_id: StringName = &"captura_sombreron"

# -------------------------
# STATES
# -------------------------

enum State {
	IDLE,
	WALK,
	RUN,
	DASH,
	ATTACK,
	STUN
}

var current_state: State = State.IDLE

var dash_windup_timer: float = 0.0
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var action_timer: float = 0.0

var movement_direction: Vector3 = Vector3.ZERO
var dash_direction: Vector3 = Vector3.ZERO
var knockback_velocity: Vector3 = Vector3.ZERO

var is_controlled: bool = false
var _was_controlled_before_cinematic: bool = false

# -------------------------
# INITIALIZATION
# -------------------------

func _ready() -> void:
	_resolve_attack_area()
	play_animation("idle", 1.0)


## Resuelve la referencia al AttackArea3D a partir del pivote si no está asignada.
func _resolve_attack_area() -> void:
	if attack_area != null or pivote == null:
		return
	attack_area = pivote.get_node_or_null("AttackArea3D") as Area3D


# -------------------------
# MAIN LOOP
# -------------------------

func _physics_process(delta: float) -> void:

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	
	if not is_controlled:
		velocity.x = 0.0
		velocity.z = 0.0
		_integrate_knockback(delta)
		move_and_slide()
		return
	
	# Cooldown
	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta

	# Temporary actions
	if current_state == State.DASH:
		update_dash(delta)
		_integrate_knockback(delta)
		move_and_slide()
		return

	if current_state == State.ATTACK or current_state == State.STUN:
		action_timer -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		_integrate_knockback(delta)

		if action_timer <= 0:
			change_state(State.IDLE)

		move_and_slide()
		return

	# Normal movement
	handle_movement(delta)
	_integrate_knockback(delta)
	move_and_slide()


# -------------------------
# MOVEMENT
# -------------------------

func handle_movement(delta) -> void:

	var input_direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	movement_direction = Vector3(
		input_direction.x,
		0,
		input_direction.y
	).normalized()

	# Dash input
	if Input.is_action_just_pressed("dash"):
		if dash_cooldown_timer <= 0:
			start_dash()
			return

	# Attack input
	if Input.is_action_just_pressed("attack"):
		start_attack()
		return

	# No movement
	if movement_direction == Vector3.ZERO:
		velocity.x = 0
		velocity.z = 0
		change_state(State.IDLE)
		return

	# Run or walk
	var is_running := Input.is_action_pressed("run")

	var speed := walk_speed

	if is_running:
		speed = run_speed
		change_state(State.RUN)
	else:
		change_state(State.WALK)

	velocity.x = movement_direction.x * speed
	velocity.z = movement_direction.z * speed

	# Rotate model towards movement direction
	if model:
		var target_direction = movement_direction
		var target_angle = atan2(
			target_direction.x,
			target_direction.z
		)
		model.rotation.y = lerp_angle(
			model.rotation.y,
			target_angle,
			8.0 * delta
		)

	# Rotate pivote
	if pivote:
		var target_direction = movement_direction
		var target_angle = atan2(
			target_direction.x,
			target_direction.z
		)
		pivote.rotation.y = lerp_angle(
			pivote.rotation.y,
			target_angle,
			8.0 * delta
		)

# -------------------------
# DASH
# -------------------------

func start_dash() -> void:

	# Con entrada se usa la dirección de movimiento; sin entrada se usa hacia
	# dónde está mirando el jugador (el pivote/modelo), no el eje del cuerpo.
	if movement_direction != Vector3.ZERO:
		dash_direction = movement_direction.normalized()
	else:
		dash_direction = _get_facing_direction()

	# Fase de preparación: el personaje se queda quieto antes de desplazarse.
	dash_windup_timer = dash_windup
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown

	velocity.x = 0.0
	velocity.z = 0.0

	change_state(State.DASH)


## Devuelve la dirección horizontal hacia la que mira el jugador. El cuerpo no
## rota, así que la orientación real vive en el pivote (o en el modelo).
func _get_facing_direction() -> Vector3:
	var reference: Node3D = pivote if pivote != null else model

	if reference == null:
		var fallback := -global_transform.basis.z
		fallback.y = 0.0
		return fallback.normalized()

	var facing := reference.global_transform.basis.z
	facing.y = 0.0

	if facing.length_squared() < 0.0001:
		facing = -global_transform.basis.z
		facing.y = 0.0

	return facing.normalized()


func update_dash(delta: float) -> void:

	# Mientras dura la preparación el jugador no se mueve.
	if dash_windup_timer > 0.0:
		dash_windup_timer -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		return

	dash_timer -= delta

	velocity.x = dash_direction.x * dash_speed
	velocity.z = dash_direction.z * dash_speed

	if dash_timer <= 0:
		change_state(State.IDLE)


# -------------------------
# ATTACK
# -------------------------

func start_attack() -> void:
	var target := _find_hunt_target_in_attack_area()

	# 1. Objetivo de caza en el área: cinemática de captura.
	if target != null:
		# El ataque solo solicita la cinemática. Toda transición, pausa, cámara,
		# captura y restauración vive en el CinematicController.
		var controller := get_tree().get_first_node_in_group(
			&"cinematic_controller"
		) as CinematicController

		if controller != null and controller.play_cinematic(self, target, cinematic_id):
			return

		# Fallback: no hay controller o la cinemática no pudo iniciarse.
		push_warning("Ataque sin cinemática: se ejecuta el ataque normal sin captura.")
		_play_normal_attack()
		return

	# 2. Señuelo en el área: desaparece sin cinemática ni pausa.
	var decoy := _find_decoy_in_attack_area()

	if decoy != null:
		decoy.break_decoy()
		_play_normal_attack()
		return

	# 3. Sin objetivo ni señuelo no hay ataque ni cinemática.
	_prepare_attack_miss_effect()


## Ejecuta el ataque normal del Sombrerón, sin captura ni pausa del árbol.
func _play_normal_attack() -> void:
	action_timer = attack_duration
	velocity.x = 0.0
	velocity.z = 0.0
	change_state(State.ATTACK)


## Busca un NPC que sea el objetivo de caza dentro del AttackArea3D.
func _find_hunt_target_in_attack_area() -> NPCBase:
	if attack_area == null:
		return null

	for body in attack_area.get_overlapping_bodies():
		if body is NPCBase and body.is_hunt_target:
			return body

	return null


## Busca un señuelo del tramposo dentro del AttackArea3D.
func _find_decoy_in_attack_area() -> NPCBase:
	if attack_area == null:
		return null

	for body in attack_area.get_overlapping_bodies():
		if body is NPCBase and body.is_decoy:
			return body

	return null


## Punto de extensión para la futura animación del rectángulo (Sprite3D) bajo el
## área de ataque. Todavía no implementa ningún efecto visual.
func _prepare_attack_miss_effect() -> void:
	pass


# -------------------------
# STUN
# -------------------------

## Aplica aturdimiento al Sombrerón. Si no se indica duración, usa la del export.
func apply_stun(duration: float = -1.0) -> void:
	action_timer = stun_duration if duration <= 0.0 else duration
	velocity.x = 0.0
	velocity.z = 0.0
	change_state(State.STUN)


# -------------------------
# KNOCKBACK
# -------------------------

## Aplica un empuje externo en el plano XZ con decaimiento progresivo.
func apply_knockback(direction_xz: Vector3, force: float) -> void:
	var direction := direction_xz
	direction.y = 0.0

	if direction.length_squared() <= 0.0001:
		return

	direction = direction.normalized()
	knockback_velocity += direction * maxf(force, 0.0)


## Integra y decae el knockback sin afectar la velocidad vertical.
func _integrate_knockback(delta: float) -> void:
	if knockback_velocity.length_squared() <= 0.0001:
		knockback_velocity = Vector3.ZERO
		return

	velocity.x += knockback_velocity.x
	velocity.z += knockback_velocity.z

	var current_speed := knockback_velocity.length()
	var new_speed := move_toward(current_speed, 0.0, knockback_friction * delta)
	knockback_velocity = knockback_velocity.normalized() * new_speed

	if new_speed <= 0.01:
		knockback_velocity = Vector3.ZERO


# -------------------------
# CINEMATIC
# -------------------------

## Devuelve el marcador global usado por la cámara cinemática.
## Si el export está vacío, se resuelve desde el pivote.
func get_cinematic_marker() -> Marker3D:
	if cinematic_marker != null:
		return cinematic_marker
	if pivote != null:
		cinematic_marker = pivote.get_node_or_null("CinematicMarker") as Marker3D
	return cinematic_marker


## Devuelve el AnimationPlayer del personaje para la cinemática.
func get_animation_player() -> AnimationPlayer:
	return animation_player


## Detiene al personaje y reproduce el clip cinemático solicitado.
## No cambia de cámara ni captura: eso pertenece al CinematicController.
func begin_cinematic(animation_name: StringName) -> void:
	_was_controlled_before_cinematic = is_controlled

	set_controlled(false)
	action_timer = 0.0
	velocity.x = 0.0
	velocity.z = 0.0

	if animation_player == null:
		return

	var clip := animation_name

	if not animation_player.has_animation(clip):
		push_warning(
			"Sombreron no tiene la animación '%s'; se usa 'idle'." % clip
		)
		clip = &"idle"

	if animation_player.has_animation(clip):
		animation_player.speed_scale = 1.0
		animation_player.play(clip)


## Restaura el estado tras la cinemática: idle, temporizadores y control.
func end_cinematic() -> void:
	action_timer = 0.0
	current_state = State.IDLE
	play_animation("idle", 1.0)

	if _was_controlled_before_cinematic:
		set_controlled(true)

	_was_controlled_before_cinematic = false


# -------------------------
# ANIMATIONS
# -------------------------

func change_state(new_state: State) -> void:

	if current_state == new_state:
		return

	current_state = new_state

	match current_state:
		State.IDLE:
			play_animation("idle", 1.0)

		State.WALK:
			play_animation("walk", 1.5)

		State.RUN:
			play_animation("run", 1.0)

		State.DASH:
			play_animation("dash", 1.0)

		State.ATTACK:
			play_animation("attack", 1.0)

		State.STUN:
			play_animation("stun", 1.0)

func set_controlled(value: bool) -> void:
	is_controlled = value

	if not is_controlled:
		velocity.x = 0.0
		velocity.z = 0.0

func play_animation(animation_name: String, speed: float) -> void:
	if animation_player:
		animation_player.play(animation_name)
		animation_player.speed_scale = speed
