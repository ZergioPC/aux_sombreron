extends CharacterBody3D

# -------------------------
# CONFIGURATION
# -------------------------

@export_group("Movement")
@export var walk_speed: float = 3.0
@export var gravity: float = 20.0

@export_group("Sniff")
@export var sniff_duration: float = 2.0

@export_group("References")
@export var animation_player: AnimationPlayer
@export var model: Node3D


# -------------------------
# STATES
# -------------------------

enum State {
	IDLE,
	WALK,
	SNIFF
}

var is_controlled: bool = false

var current_state: State = State.IDLE

var action_timer: float = 0.0
var movement_direction: Vector3 = Vector3.ZERO


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

	# Sniff action
	if current_state == State.SNIFF:

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

	# Sniff input
	if Input.is_action_just_pressed("sniff"):
		start_sniff()
		return

	# No movement
	if movement_direction == Vector3.ZERO:

		velocity.x = 0.0
		velocity.z = 0.0

		change_state(State.IDLE)
		return

	# Walking
	velocity.x = movement_direction.x * walk_speed
	velocity.z = movement_direction.z * walk_speed

	change_state(State.WALK)

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


# -------------------------
# SNIFF
# -------------------------

func start_sniff() -> void:

	action_timer = sniff_duration

	velocity.x = 0.0
	velocity.z = 0.0

	change_state(State.SNIFF)


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
			play_animation("walk", 1.8)

		State.SNIFF:
			play_animation("smell", 1.0)

func set_controlled(value: bool) -> void:
	is_controlled = value

	if not is_controlled:
		velocity.x = 0.0
		velocity.z = 0.0


func play_animation(animation_name: String, speed: float) -> void:

	if animation_player:
		animation_player.speed_scale = speed
		animation_player.play(animation_name)
