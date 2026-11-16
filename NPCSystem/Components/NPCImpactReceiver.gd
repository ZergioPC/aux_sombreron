class_name NPCImpactReceiver
extends Node

## Componente que gestiona el knockback recibido por un CharacterBody3D.
##
## Mantiene una velocidad externa en el plano XZ que se aplica y decae en cada
## frame de física. No decide cuándo se recibe el impacto: solo ejecuta la
## respuesta física.

## Cuerpo que recibe el empuje. Si se deja vacío se resuelve con el padre.
@export var body: CharacterBody3D

## Velocidad de decaimiento del knockback en unidades por segundo.
@export var knockback_friction: float = 18.0

## Velocidad externa actual en XZ.
var knockback_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	if body == null:
		body = get_parent() as CharacterBody3D


## Aplica un impulso de knockback en el plano XZ.
func apply_knockback(direction_xz: Vector3, force: float) -> void:
	if body == null or not is_instance_valid(body):
		return

	var direction := direction_xz
	direction.y = 0.0

	if direction.length_squared() <= 0.0001:
		return

	direction = direction.normalized()
	knockback_velocity += direction * maxf(force, 0.0)


## Integra y decae el knockback sobre el cuerpo. Debe llamarse en física
## después de calcular la velocidad base y antes de move_and_slide().
func integrate(delta: float) -> void:
	if body == null or not is_instance_valid(body):
		knockback_velocity = Vector3.ZERO
		return

	if knockback_velocity.length_squared() <= 0.0001:
		knockback_velocity = Vector3.ZERO
		return

	# Aplica el empuje residual sin afectar la velocidad vertical.
	body.velocity.x += knockback_velocity.x
	body.velocity.z += knockback_velocity.z

	# Decae el empuje para que no desplace al cuerpo indefinidamente.
	var current_speed := knockback_velocity.length()
	var new_speed := move_toward(current_speed, 0.0, knockback_friction * delta)
	knockback_velocity = knockback_velocity.normalized() * new_speed

	if new_speed <= 0.01:
		knockback_velocity = Vector3.ZERO


## Indica si queda knockback residual significativo.
func is_active() -> bool:
	return knockback_velocity.length_squared() > 0.0001


## Limpia cualquier knockback pendiente.
func clear() -> void:
	knockback_velocity = Vector3.ZERO
