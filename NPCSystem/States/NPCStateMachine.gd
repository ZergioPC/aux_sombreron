class_name NPCStateMachine
extends Node

## Máquina de estados del NPC.
##
## Registra los nodos NPCState que contiene, delega la actualización al estado
## activo y valida las transiciones antes de ejecutarlas.

signal state_changed(previous_state: StringName, current_state: StringName)

## Estado con el que arranca el NPC.
@export var initial_state: StringName = &"idle"

var npc
var states: Dictionary = {}
var current_state: NPCState
var current_state_name: StringName = &""


## NPCBase llama a este método durante su inicialización.
func setup(owner_npc) -> void:
	npc = owner_npc
	states.clear()

	for child in get_children():
		if child is NPCState:
			var state := child as NPCState
			state.npc = npc
			state.state_machine = self
			states[state.get_state_name()] = state


## Activa el estado inicial del NPC.
func start() -> void:
	if current_state == null:
		transition_to(initial_state)


## Solicita un cambio de estado validando que el estado exista y que la
## transición esté permitida por el estado actual.
func transition_to(target_state: StringName) -> bool:
	var target := StringName(target_state)

	if not states.has(target):
		push_warning("NPCStateMachine: el estado '%s' no existe." % target)
		return false

	if current_state == states[target]:
		return false

	if current_state != null and not current_state.can_transition_to(target):
		push_warning(
			"NPCStateMachine: transición no permitida '%s' -> '%s'."
			% [current_state_name, target]
		)
		return false

	var previous_state := current_state_name

	if current_state != null:
		current_state.exit()

	current_state = states[target] as NPCState
	current_state_name = target
	current_state.enter()

	state_changed.emit(previous_state, current_state_name)
	return true


## Actualiza el estado activo. NPCBase lo llama desde su _physics_process.
func update(delta: float) -> void:
	if current_state != null:
		current_state.update(delta)
