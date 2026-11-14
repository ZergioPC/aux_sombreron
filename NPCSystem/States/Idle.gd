extends NPCState

## Estado de reposo del NPC.
##
## Permanece quieto hasta que el comportamiento solicite otro estado.

func enter() -> void:
	if npc == null:
		return

	npc.stop_movement()
	npc.play_animation(npc.idle_animation)
