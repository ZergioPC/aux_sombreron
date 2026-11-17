class_name NPCMovementModifier
extends Node

## Clase base de los modificadores de movimiento de NPC.
##
## Un modificador altera la dirección y la velocidad deseadas antes de que
## NPCBase las convierta en velocidad física. No decide estados, destinos ni
## navegación: solo transforma el movimiento solicitado por el estado activo.

## Reinicia el estado interno del modificador.
## NPCBase lo llama al empezar y al detener un desplazamiento.
func reset() -> void:
	pass


## Altera la dirección normalizada y la velocidad solicitadas.
## [param distance_to_destination] es la distancia horizontal al destino final.
## Devuelve un Dictionary con las claves "direction" y "speed". La dirección
## devuelta debe seguir siendo unitaria para no alterar la velocidad efectiva.
func modify_movement(
	direction: Vector3,
	speed: float,
	_delta: float,
	_distance_to_destination: float
) -> Dictionary:
	return {"direction": direction, "speed": speed}
