class_name NormalBehavior
extends NPCBehavior

## Comportamiento del NPC normal.
##
## Permanece en reposo cuando no existen amenazas y huye hacia su zona segura
## cuando el sistema de percepción detecta al jugador. No realiza acciones
## ofensivas: eso corresponde a otros comportamientos.


func handle_event(event: Dictionary) -> void:
	var event_name := StringName(event.get("name", &""))

	match event_name:
		EVENT_THREAT_DETECTED:
			flee_from_threat()
		EVENT_PLAYER_DISCOVERED:
			flee_from_threat()

	# EVENT_THREAT_LOST no interrumpe Escape: el estado Escape comprueba las
	# amenazas al llegar a la zona segura y vuelve a Idle cuando desaparecen.
