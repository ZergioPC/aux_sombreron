class_name NPCState
extends Node

## Clase base de los estados del NPC.
##
## Cada estado implementa su lógica en enter(), update() y exit(). El estado no
## accede directamente a la navegación ni al AnimationPlayer: solicita esas
## acciones a NPCBase.

## Referencia al NPC controlado por este estado.
var npc
## Referencia a la máquina de estados propietaria.
var state_machine
## Estados a los que se puede cambiar desde este estado.
@export var allowed_transitions: PackedStringArray = PackedStringArray()


## Identificador del estado. Se usa el nombre del nodo en minúsculas.
func get_state_name() -> StringName:
	return StringName(String(name).to_lower())


## Indica si el estado permite una transición hacia el estado indicado.
func can_transition_to(target_state: StringName) -> bool:
	if allowed_transitions.is_empty():
		return true
	return allowed_transitions.has(String(target_state))


## Se ejecuta al entrar al estado.
func enter() -> void:
	pass


## Se ejecuta en cada frame de física mientras el estado está activo.
func update(_delta: float) -> void:
	pass


## Se ejecuta al abandonar el estado.
func exit() -> void:
	pass


## Solicita una transición desde dentro del estado.
func request_transition(target_state: StringName) -> bool:
	if state_machine == null:
		return false
	return state_machine.transition_to(target_state)
