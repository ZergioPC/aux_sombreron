class_name TricksterBehavior
extends NPCBehavior

## Comportamiento del NPC tramposo.
##
## Por ahora solo utiliza los estados Idle y Escape: permanece en reposo cuando
## no hay amenazas y huye hacia su zona segura cuando detecta al jugador.
## Las reacciones evasivas propias del tramposo se agregarán en una etapa
## posterior.


func handle_event(event: Dictionary) -> void:
	var event_name := StringName(event.get("name", &""))

	match event_name:
		EVENT_THREAT_DETECTED:
			flee_from_threat()
		EVENT_PLAYER_DISCOVERED:
			flee_from_threat()

	# EVENT_THREAT_LOST no interrumpe Escape: el estado Escape comprueba las
	# amenazas al llegar a la zona segura y vuelve a Idle cuando desaparecen.
