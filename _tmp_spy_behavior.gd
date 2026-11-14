extends NPCBehavior

## Comportamiento espía temporal (fase 5): registra los eventos recibidos.

var eventos: Array = []


func handle_event(event: Dictionary) -> void:
	eventos.append(event)
