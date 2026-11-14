extends NPCState

## Estado de escape del NPC.
##
## Solicita a NPCBase el desplazamiento hacia la zona segura asignada y vuelve
## a Idle cuando la amenaza desaparece o al llegar sin amenazas pendientes.

var _arrived: bool = false


func enter() -> void:
	_arrived = false

	if npc == null:
		return

	if not npc.has_safe_zone():
		push_warning(
			"NPC '%s' intentó escapar sin una zona segura asignada." % npc.name
		)
		npc.stop_movement()
		npc.play_animation(npc.idle_animation)
		return

	npc.move_to_position(npc.get_safe_zone_position())
	npc.play_animation(npc.escape_animation)


func update(_delta: float) -> void:
	if npc == null:
		return

	if not npc.has_safe_zone():
		request_transition(&"idle")
		return

	if _arrived:
		if not npc.has_perceived_threats():
			request_transition(&"idle")
		return

	if npc.has_reached_destination():
		_arrived = true
		npc.stop_movement()
		npc.play_animation(npc.idle_animation)

		if not npc.has_perceived_threats():
			request_transition(&"idle")


func exit() -> void:
	if npc == null:
		return
	npc.stop_movement()
