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


# -----------------------------------------------------------------------------
# PLAYER IDENTIFICATION
# -----------------------------------------------------------------------------

## Indica si el cuerpo pertenece al jugador (nodo raíz o cualquiera de sus hijos).
func is_player_body(body: Node) -> bool:
	var current: Node = body
	while current != null:
		if current.is_in_group(&"player"):
			return true
		current = current.get_parent()
	return false


## Indica si el cuerpo corresponde a la forma Sombrerón del jugador.
func is_sombreron_body(body: Node) -> bool:
	var current: Node = body
	while current != null:
		if current.name == &"Sombreron":
			return true
		if (
			current.get_script() != null
			and String(current.get_script().resource_path).ends_with(
				"sombreron.gd"
			)
		):
			return true
		current = current.get_parent()
	return false


## El jugador válido para triggers de NPC es el Sombrerón (no el perro).
func is_valid_player_body(body: Node) -> bool:
	if body == null or not is_instance_valid(body):
		return false

	if not is_player_body(body):
		return false

	return is_sombreron_body(body)
