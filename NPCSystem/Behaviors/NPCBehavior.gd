class_name NPCBehavior
extends Node

## Clase base de los comportamientos de NPC.
##
## Un comportamiento recibe los eventos del entorno y decide qué estado
## solicitar. Las acciones físicas las ejecuta NPCBase a través de su máquina
## de estados.

const EVENT_THREAT_DETECTED := &"threat_detected"
const EVENT_THREAT_LOST := &"threat_lost"

## Referencia al NPC que utiliza este comportamiento.
var npc


## NPCBase llama a este método durante su inicialización.
func setup(owner_npc) -> void:
	npc = owner_npc


## Punto de entrada para los eventos del entorno o del jugador.
func handle_event(_event: Dictionary) -> void:
	pass


## Solicita un cambio de estado delegando en la máquina de estados del NPC.
func request_state(state_name: StringName) -> bool:
	if npc == null:
		return false
	return npc.request_state(state_name)
