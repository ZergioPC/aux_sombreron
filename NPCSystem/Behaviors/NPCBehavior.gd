class_name NPCBehavior
extends Node

## Clase base de los comportamientos de NPC.
##
## Un comportamiento recibe los eventos del entorno y decide qué estado
## solicitar. Las acciones físicas las ejecuta NPCBase a través de su máquina
## de estados.

const EVENT_THREAT_DETECTED := &"threat_detected"
const EVENT_THREAT_LOST := &"threat_lost"
const EVENT_PLAYER_DISCOVERED := &"player_discovered"

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


## Huye hacia la zona segura del NPC.
##
## Reacción común ante una amenaza o ante el descubrimiento del jugador. El
## objetivo de caza nunca huye y un NPC sin zona segura solo registra una
## advertencia.
func flee_from_threat() -> void:
	if npc == null:
		return

	if npc.is_hunt_target:
		return

	if not npc.has_safe_zone():
		push_warning("NPC sin zona segura asignada.")
		return

	request_state(&"escape")
