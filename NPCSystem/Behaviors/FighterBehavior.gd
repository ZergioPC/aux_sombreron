class_name FighterBehavior
extends NPCBehavior

## Comportamiento del NPC peleador.
##
## Por ahora solo utiliza los estados Idle y Escape: permanece en reposo cuando
## no hay amenazas y huye hacia su zona segura cuando detecta al jugador.
## Los estados Attack y Stun se agregarán en una etapa posterior.


func handle_event(event: Dictionary) -> void:
	var event_name := StringName(event.get("name", &""))

	match event_name:
		EVENT_THREAT_DETECTED:
			flee_from_threat()
		EVENT_PLAYER_DISCOVERED:
			_on_player_discovered()

	# EVENT_THREAT_LOST no interrumpe Escape: el estado Escape comprueba las
	# amenazas al llegar a la zona segura y vuelve a Idle cuando desaparecen.


## Reacción al descubrimiento global del jugador.
##
## Por ahora el peleador huye igual que el resto. Punto de extensión previsto
## para que en el futuro reaccione de forma distinta (por ejemplo, perseguir).
func _on_player_discovered() -> void:
	flee_from_threat()
