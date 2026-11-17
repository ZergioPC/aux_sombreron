extends NPCState

## Estado de huida hacia un punto aleatorio del mapa.
##
## Se usa en el clon del tramposo: corre hacia un punto de navegación aleatorio y,
## al llegar, se queda en Idle. No usa la zona segura ni desaparece, porque el
## clon debe seguir existiendo hasta que lo destruyan o termine la caza.

@export_group("Flee")
## Animación de carrera usada durante la huida.
@export var flee_animation: StringName = &"run"
## Distancia mínima del punto de destino respecto al NPC.
@export var min_distance: float = 6.0
## Distancia máxima del punto de destino respecto al NPC.
@export var max_distance: float = 18.0
## Intentos para encontrar un punto de navegación aleatorio válido.
@export var search_attempts: int = 12
## Tiempo máximo corriendo antes de detenerse (salvaguarda).
@export var max_flee_time: float = 15.0

var _elapsed: float = 0.0
var _has_destination: bool = false


func enter() -> void:
	_elapsed = 0.0
	_has_destination = false

	if npc == null:
		return

	var search: Dictionary = npc.get_random_navigation_position(
		min_distance, max_distance, search_attempts
	)

	if not bool(search.get("found", false)):
		_finish_flee()
		return

	_has_destination = true
	npc.move_to_position(search["position"], npc.run_speed)
	npc.play_animation(flee_animation)


func update(delta: float) -> void:
	if npc == null or not _has_destination:
		return

	_elapsed += delta

	if npc.has_reached_destination() or _elapsed >= max_flee_time:
		_finish_flee()


func exit() -> void:
	if npc == null:
		return
	npc.stop_movement()


func _finish_flee() -> void:
	if npc == null:
		return

	_has_destination = false
	npc.stop_movement()
	npc.play_animation(npc.idle_animation)
	request_transition(&"idle")
