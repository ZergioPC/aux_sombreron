class_name NPCPerception
extends Area3D

## Componente de percepción del NPC.
##
## Detecta cuerpos que pertenecen al grupo de amenaza (por defecto "player") y
## notifica a NPCBase mediante señales. No decide cómo debe reaccionar el NPC:
## esa decisión pertenece al comportamiento.

signal body_detected(body: Node3D)
signal body_lost(body: Node3D)

## Grupo cuyo cuerpo se considera una amenaza.
@export var threat_group: StringName = &"player"
## Si está activo, solo se aceptan cuerpos dentro de threat_group.
@export var use_group_filter: bool = true

var detected_bodies: Array[Node3D] = []


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Ajusta el radio del CollisionShape3D duplicando el recurso para que cada
## instancia de NPC tenga su propio rango de detección.
func set_detection_range(value: float) -> void:
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null:
		return

	var sphere := collision_shape.shape as SphereShape3D
	if sphere == null:
		return

	var own_sphere := sphere.duplicate() as SphereShape3D
	own_sphere.radius = value
	collision_shape.shape = own_sphere


func has_detected_bodies() -> bool:
	return not detected_bodies.is_empty()


## Devuelve la amenaza detectada más cercana, o null si no hay ninguna.
func get_nearest_body() -> Node3D:
	var nearest: Node3D = null
	var nearest_distance := INF

	for body in detected_bodies:
		if not is_instance_valid(body):
			continue

		var distance := global_position.distance_squared_to(body.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = body

	return nearest


func _on_body_entered(body: Node3D) -> void:
	if not _is_threat(body):
		return

	if detected_bodies.has(body):
		return

	detected_bodies.append(body)
	body_detected.emit(body)


func _on_body_exited(body: Node3D) -> void:
	if not detected_bodies.has(body):
		return

	detected_bodies.erase(body)
	body_lost.emit(body)


func _is_threat(body: Node3D) -> bool:
	if body == null or not is_instance_valid(body):
		return false

	# Evitar detectar el cuerpo del propio NPC.
	var node: Node = body
	while node != null:
		if node == get_parent():
			return false
		node = node.get_parent()

	if use_group_filter:
		return _belongs_to_group(body, threat_group)

	return true


func _belongs_to_group(node: Node, group_name: StringName) -> bool:
	var current: Node = node
	while current != null:
		if current.is_in_group(group_name):
			return true
		current = current.get_parent()

	return false
