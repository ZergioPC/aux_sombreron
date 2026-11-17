extends NPCState

## Estado de escape del NPC.
##
## Solicita a NPCBase el desplazamiento hacia la zona segura asignada. Al
## llegar, el NPC desaparece de forma instantánea mediante NPCBase.despawn().

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

	npc.move_to_position(npc.get_safe_zone_position(), npc.run_speed)
	npc.play_animation(npc.escape_animation)


func update(_delta: float) -> void:
	if npc == null:
		return

	# Salvaguarda: sin zona segura no tiene sentido escapar.
	if not npc.has_safe_zone():
		request_transition(&"idle")
		return

	# Ya se ordenó la desaparición; se espera a que queue_free la aplique.
	if _arrived:
		return

	if npc.has_reached_destination():
		_arrived = true
		npc.stop_movement()
		# Avisa antes de desaparecer para que HuntManager suelte el objetivo.
		npc.notify_escaped()
		npc.despawn()


func exit() -> void:
	if npc == null:
		return
	npc.stop_movement()
