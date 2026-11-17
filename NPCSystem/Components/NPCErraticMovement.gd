class_name NPCErraticMovement
extends NPCMovementModifier

## Modificador de movimiento errático.
##
## Cambia la velocidad de forma aleatoria y hace oscilar la dirección alrededor
## de la ruta hacia el objetivo. Está pensado para el caminar del Borracho, pero
## puede usarse en cualquier NPC. No decide estados: solo transforma la
## dirección y la velocidad que solicita NPCBase.

@export_group("Velocidad errática")
## Factor mínimo aplicado a la velocidad solicitada por el estado.
@export var speed_factor_min: float = 0.45
## Factor máximo aplicado a la velocidad solicitada por el estado.
@export var speed_factor_max: float = 1.2
## Intervalo mínimo entre cambios de velocidad, amplitud y frecuencia.
@export var change_interval_min: float = 0.45
## Intervalo máximo entre cambios de velocidad, amplitud y frecuencia.
@export var change_interval_max: float = 1.6

@export_group("Oscilación")
## Desviación angular mínima respecto a la dirección de la ruta.
@export var weave_angle_min_deg: float = 8.0
## Desviación angular máxima respecto a la dirección de la ruta.
@export var weave_angle_max_deg: float = 28.0
## Frecuencia mínima de la oscilación en hercios.
@export var weave_frequency_min: float = 0.25
## Frecuencia máxima de la oscilación en hercios.
@export var weave_frequency_max: float = 0.8
## Distancia al destino en la que la oscilación y la velocidad se normalizan.
## Evita que el NPC orbite alrededor del punto de llegada.
@export var weave_fade_distance: float = 1.75

var _rng := RandomNumberGenerator.new()
var _elapsed: float = 0.0
var _change_timer: float = 0.0
var _speed_factor: float = 1.0
var _speed_factor_target: float = 1.0
var _weave_angle_deg: float = 0.0
var _weave_frequency: float = 0.5
var _phase: float = 0.0


func _ready() -> void:
	# La semilla incluye el id de instancia para que varios NPC creados en el
	# mismo frame no compartan exactamente la misma secuencia aleatoria.
	_rng.seed = hash(get_instance_id()) ^ int(Time.get_ticks_usec())
	reset()


## Reinicia la oscilación y sortea un patrón nuevo.
func reset() -> void:
	_elapsed = 0.0
	_change_timer = 0.0
	_phase = _rng.randf_range(0.0, TAU)
	_speed_factor = 1.0
	_pick_new_pattern()


## Aplica la variación de velocidad y la oscilación angular a la dirección.
func modify_movement(
	direction: Vector3,
	speed: float,
	delta: float,
	distance_to_destination: float
) -> Dictionary:
	if speed <= 0.0 or direction.length_squared() <= 0.0001:
		return {"direction": direction, "speed": speed}

	_elapsed += delta
	_change_timer -= delta

	if _change_timer <= 0.0:
		_pick_new_pattern()

	# Suaviza el factor para que NPCBase no reciba saltos bruscos.
	_speed_factor = move_toward(_speed_factor, _speed_factor_target, 3.0 * delta)

	var fade := 1.0
	if weave_fade_distance > 0.0:
		fade = clampf(distance_to_destination / weave_fade_distance, 0.0, 1.0)

	var angle := deg_to_rad(_weave_angle_deg) \
		* sin(_elapsed * TAU * _weave_frequency + _phase) * fade
	var final_direction := direction.rotated(Vector3.UP, angle)
	var final_speed := speed * lerpf(1.0, _speed_factor, fade)

	return {"direction": final_direction, "speed": final_speed}


## Sortea un patrón nuevo de velocidad, amplitud y frecuencia.
func _pick_new_pattern() -> void:
	var min_interval := maxf(change_interval_min, 0.05)
	var max_interval := maxf(change_interval_max, min_interval)
	_change_timer = _rng.randf_range(min_interval, max_interval)

	var min_factor := minf(speed_factor_min, speed_factor_max)
	var max_factor := maxf(speed_factor_min, speed_factor_max)
	_speed_factor_target = _rng.randf_range(min_factor, max_factor)

	var min_angle := minf(weave_angle_min_deg, weave_angle_max_deg)
	var max_angle := maxf(weave_angle_min_deg, weave_angle_max_deg)
	_weave_angle_deg = _rng.randf_range(min_angle, max_angle)

	var min_frequency := minf(weave_frequency_min, weave_frequency_max)
	var max_frequency := maxf(weave_frequency_min, weave_frequency_max)
	_weave_frequency = _rng.randf_range(min_frequency, max_frequency)
