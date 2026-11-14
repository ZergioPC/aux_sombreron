extends NPCState

## Estado de reposo del NPC.
##
## Alterna entre pausas quietas y caminatas hacia puntos aleatorios del mapa de
## navegación. Este estado solo decide cuándo caminar y cuándo detenerse: el
## movimiento, la navegación y las animaciones se solicitan a NPCBase.

@export_group("Wandering")
## Si está desactivado, el NPC permanece quieto durante todo el estado.
@export var wandering_enabled: bool = true
## Tiempo mínimo que el NPC permanece quieto entre caminatas.
@export var min_idle_time: float = 2.0
## Tiempo máximo que el NPC permanece quieto entre caminatas.
@export var max_idle_time: float = 5.0
## Distancia mínima del punto de destino respecto al NPC.
@export var min_walk_distance: float = 2.0
## Distancia máxima del punto de destino respecto al NPC.
@export var max_walk_distance: float = 12.0
## Tiempo máximo caminando antes de detenerse y volver a esperar.
## Sirve como salvaguarda si un destino no se alcanza nunca.
@export var max_walk_time: float = 12.0
## Intentos para encontrar un punto de navegación aleatorio válido.
@export var target_search_attempts: int = 10

var _rng := RandomNumberGenerator.new()
var _waiting: bool = true
var _wait_time_left: float = 0.0
var _walk_time: float = 0.0


func enter() -> void:
	if npc == null:
		return

	_seed_random_generator()
	npc.stop_movement()
	npc.play_animation(npc.idle_animation)
	_start_waiting()


func update(delta: float) -> void:
	if npc == null:
		return

	if _waiting:
		_update_waiting(delta)
	else:
		_update_walking(delta)


func exit() -> void:
	if npc == null:
		return

	npc.stop_movement()


func _update_waiting(delta: float) -> void:
	_wait_time_left -= delta

	if _wait_time_left > 0.0:
		return

	if not wandering_enabled or not _try_start_walking():
		_start_waiting()


func _update_walking(delta: float) -> void:
	_walk_time += delta

	if not npc.has_reached_destination() and _walk_time < max_walk_time:
		return

	npc.stop_movement()
	npc.play_animation(npc.idle_animation)
	_start_waiting()


## Intenta iniciar una caminata hacia un punto aleatorio. Devuelve true si el
## NPC comenzó a moverse.
func _try_start_walking() -> bool:
	var search: Dictionary = npc.get_random_navigation_position(
		min_walk_distance, max_walk_distance, target_search_attempts
	)

	if not bool(search.get("found", false)):
		return false

	var target: Vector3 = search["position"]
	_waiting = false
	_walk_time = 0.0
	npc.move_to_position(target, npc.walk_speed)
	npc.play_animation(npc.walk_animation)
	return true


func _start_waiting() -> void:
	_waiting = true
	_walk_time = 0.0

	var minimum := maxf(min_idle_time, 0.0)
	var maximum := maxf(max_idle_time, minimum)
	_wait_time_left = _rng.randf_range(minimum, maximum)


func _seed_random_generator() -> void:
	# Incluir el id de instancia evita que varios NPC que entran al estado en el
	# mismo frame generen exactamente la misma secuencia aleatoria.
	_rng.seed = int(Time.get_ticks_usec()) ^ int(npc.get_instance_id())
