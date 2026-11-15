
extends Node3D

# -------------------------
# REFERENCES
# -------------------------

@onready var sombreron = $Sombreron
@onready var perro = $Perro


# -------------------------
# CHARACTER CONTROL
# -------------------------

enum Character {
	SOMBRERON,
	PERRO
}

var current_character: Character = Character.SOMBRERON

# Saved position of Sombreron
var sombreron_saved_position: Vector3

# Save original dog collision settings
var perro_collision_layer: int
var perro_collision_mask: int


# -------------------------
# INITIALIZATION
# -------------------------
var sombreron_collision_layer: int
var sombreron_collision_mask: int

func _ready() -> void:
	sombreron_collision_layer = sombreron.collision_layer
	sombreron_collision_mask = sombreron.collision_mask
	
	sombreron_saved_position = sombreron.global_position

	perro_collision_layer = perro.collision_layer
	perro_collision_mask = perro.collision_mask

	# Initial state
	sombreron.set_controlled(true)

	perro.set_controlled(false)
	perro.visible = false
	perro.collision_layer = 0
	perro.collision_mask = 0
	perro.set_physics_process(false)

	# Sincroniza el estado global con la forma inicial (Sombreron).
	GameState.set_form(GameState.PlayerForm.SOMBRERON)


# -------------------------
# MAIN LOOP
# -------------------------

func _process(_delta: float) -> void:

	if Input.is_action_just_pressed("switch_character"):
		switch_character()


# -------------------------
# CHARACTER SWITCH
# -------------------------

func switch_character() -> void:

	# El cambio de forma se ignora mientras esté bloqueado (por ejemplo,
	# tras ser descubierto el Sombreron).
	if not GameState.can_change_form():
		return

	match current_character:

		Character.SOMBRERON:
			control_dog()

		Character.PERRO:
			control_sombreron()


# -------------------------
# CONTROL DOG
# -------------------------

func control_dog() -> void:
	# Save Sombreron position
	sombreron_saved_position = sombreron.global_position

	# Stop controlling Sombreron
	sombreron.set_controlled(false)

	# Place dog at Sombreron position
	perro.global_position = sombreron_saved_position
	perro.velocity = Vector3.ZERO

	# Restore dog's collisions and physics
	perro.collision_layer = perro_collision_layer
	perro.collision_mask = perro_collision_mask
	perro.visible = true
	perro.set_physics_process(true)

	# Give control to dog
	perro.set_controlled(true)
	sombreron.visible = false
	sombreron.collision_layer = 0
	sombreron.collision_mask = 0

	current_character = Character.PERRO
	GameState.set_form(GameState.PlayerForm.DOG)

# -------------------------
# CONTROL SOMBRERON
# -------------------------

func control_sombreron() -> void:
	# Stop controlling dog
	perro.set_controlled(false)

	# Hide dog and disable its collisions
	perro.visible = false
	perro.collision_layer = 0
	perro.collision_mask = 0
	perro.set_physics_process(false)

	# Return Sombreron to saved position
	sombreron.global_position = sombreron_saved_position
	sombreron.velocity = Vector3.ZERO

	# Restore control
	sombreron.set_controlled(true)
	sombreron.visible = true
	sombreron.collision_layer = sombreron_collision_layer
	sombreron.collision_mask = sombreron_collision_mask
	
	current_character = Character.SOMBRERON
	GameState.set_form(GameState.PlayerForm.SOMBRERON)
