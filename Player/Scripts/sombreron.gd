
extends CharacterBody3D

# -------------------------
# CONFIGURATION
# -------------------------

@export_group("Movement")
@export var walk_speed: float = 3.0
@export var run_speed: float = 6.0
@export var gravity: float = 20.0

@export_group("Dash")
@export var dash_speed: float = 12.0
@export var dash_duration: float = 0.25
@export var dash_cooldown: float = 0.8

@export_group("Actions")
@export var attack_duration: float = 0.7
@export var stun_duration: float = 1.0

@export_group("References")
@export var animation_player: AnimationPlayer
@export var model: Node3D
@export var pivote: Marker3D

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

var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var action_timer: float = 0.0

var movement_direction: Vector3 = Vector3.ZERO
var dash_direction: Vector3 = Vector3.ZERO

var is_controlled: bool = false
# -------------------------
# INITIALIZATION
# -------------------------

func _ready() -> void:
	play_animation("idle", 1.0)


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
		move_and_slide()
		return
	
	# Cooldown
	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta

	# Temporary actions
	if current_state == State.DASH:
		update_dash(delta)
		move_and_slide()
		return

	if current_state == State.ATTACK or current_state == State.STUN:
		action_timer -= delta
		velocity.x = 0.0
		velocity.z = 0.0

		if action_timer <= 0:
			change_state(State.IDLE)

		move_and_slide()
		return

	# Normal movement
	handle_movement(delta)
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

	if movement_direction != Vector3.ZERO:
		dash_direction = movement_direction
	else:
		dash_direction = -global_transform.basis.z

	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown

	change_state(State.DASH)


func update_dash(delta: float) -> void:

	dash_timer -= delta

	velocity.x = dash_direction.x * dash_speed
	velocity.z = dash_direction.z * dash_speed

	if dash_timer <= 0:
		change_state(State.IDLE)


# -------------------------
# ATTACK
# -------------------------

func start_attack() -> void:

	action_timer = attack_duration
	velocity.x = 0
	velocity.z = 0

	change_state(State.ATTACK)


# -------------------------
# STUN
# -------------------------

func apply_stun() -> void:

	action_timer = stun_duration
	velocity.x = 0
	velocity.z = 0

	change_state(State.STUN)


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
			play_animation("dash" , 1.0)

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
