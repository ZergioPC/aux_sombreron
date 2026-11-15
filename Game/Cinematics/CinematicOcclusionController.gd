class_name CinematicOcclusionController
extends Node

## Controlador de oclusión de la cámara cinemática.
##
## Lanza varios rayos desde la cámara hacia el pecho y la cabeza del jugador y
## del objetivo. Si un rayo impacta geometría de la capa 2
## ("camera_occluder"), oculta esa geometría y la restaura cuando deja de
## ocluir. No mueve la cámara, no usa SpringArm3D y no modifica materiales.
##
## Solo se oculta la geometría que el rayo puede detectar (capa 2). Los
## personajes permanecen en la capa 1 y además se excluyen explícitamente.
##
## Debe tener PROCESS_MODE_ALWAYS para actualizarse con el árbol pausado.

## Máscara de física reservada para geometría que puede ocultar la cámara.
const OCCLUDER_COLLISION_MASK: int = 2

## Intervalo entre actualizaciones, en segundos. Evita raycasts por frame.
@export_range(0.01, 1.0, 0.01) var refresh_interval: float = 0.08

@export_group("Ray Points")
## Altura del pecho del jugador sobre su posición global.
@export var player_chest_height: float = 1.0
## Altura de la cabeza del jugador sobre su posición global.
@export var player_head_height: float = 1.8
## Altura del pecho del enemigo sobre su posición global.
@export var enemy_chest_height: float = 1.0
## Altura de la cabeza del enemigo sobre su posición global.
@export var enemy_head_height: float = 1.7

var _camera: Camera3D = null
var _attacker: Node3D = null
var _target: Node3D = null
var _active: bool = false
var _elapsed: float = 0.0
var _excluded_rids: Array[RID] = []

## Oclusores activos: instance_id -> {ref, visible, transparency}.
## Se guarda un WeakRef para no conservar viva geometría liberable.
var _occluders: Dictionary = {}


# -----------------------------------------------------------------------------
# API PÚBLICA
# -----------------------------------------------------------------------------

## Configura la cámara y los participantes de la cinemática actual.
func setup(camera: Camera3D, attacker: Node3D, target: Node3D) -> void:
	if _active:
		stop()

	_camera = camera
	_attacker = attacker
	_target = target


## Activa las consultas y hace una primera actualización inmediata.
func start() -> void:
	_active = true
	_elapsed = 0.0
	_refresh_occluders()


## Detiene las consultas y restaura toda la geometría modificada.
func stop() -> void:
	_restore_all()
	_active = false
	_elapsed = 0.0
	_camera = null
	_attacker = null
	_target = null
	_excluded_rids.clear()


## Deja de ocluir respecto al objetivo (por ejemplo, tras la captura).
## A partir de este momento solo se ocluye respecto al jugador.
func clear_target() -> void:
	_target = null


## Indica si el controlador está activo.
func is_active() -> bool:
	return _active


# -----------------------------------------------------------------------------
# ACTUALIZACIÓN
# -----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _active:
		return

	_elapsed += delta

	if _elapsed < refresh_interval:
		return

	_elapsed = 0.0
	_refresh_occluders()


## Construye el conjunto de oclusores actual, oculta los nuevos y restaura los
## que ya no ocluyen o que fueron liberados.
func _refresh_occluders() -> void:
	if not is_instance_valid(_camera):
		return

	var space_state := _camera.get_world_3d().direct_space_state
	if space_state == null:
		return

	# Se reconstruyen en cada pasada para descartar cuerpos liberados.
	_refresh_excluded_rids()

	var from := _camera.global_position
	var current: Dictionary = {}

	for point in _collect_ray_points():
		if from.is_equal_approx(point):
			continue

		var query := PhysicsRayQueryParameters3D.create(
			from, point, OCCLUDER_COLLISION_MASK
		)
		query.collide_with_bodies = true
		query.collide_with_areas = false
		query.exclude = _excluded_rids

		var hit := space_state.intersect_ray(query)
		if hit.is_empty():
			continue

		var geometry := _resolve_geometry(hit.get("collider"))
		if geometry == null or _is_ignored(geometry):
			continue

		current[geometry.get_instance_id()] = geometry

	# Solo se toca la visibilidad cuando el conjunto cambia: evita parpadeos.
	for id in current:
		if not _occluders.has(id):
			_hide_occluder(current[id])

	for id in _occluders.keys():
		if not current.has(id):
			_restore_occluder(id)


## Puntos relevantes hacia los que lanzar los rayos.
func _collect_ray_points() -> Array[Vector3]:
	var points: Array[Vector3] = []

	if is_instance_valid(_attacker):
		points.append(
			_attacker.global_position + Vector3.UP * player_chest_height
		)
		points.append(
			_attacker.global_position + Vector3.UP * player_head_height
		)

	if is_instance_valid(_target):
		points.append(
			_target.global_position + Vector3.UP * enemy_chest_height
		)
		points.append(
			_target.global_position + Vector3.UP * enemy_head_height
		)

	return points


## Resuelve el GeometryInstance3D más cercano subiendo por los padres del
## collider. Un CSGBox3D es GeometryInstance3D; si el impacto es en un cuerpo
## interno, su padre puede ser el CSG.
func _resolve_geometry(collider: Variant) -> GeometryInstance3D:
	var node := collider as Node

	while node != null:
		if node is GeometryInstance3D:
			return node as GeometryInstance3D
		node = node.get_parent()

	return null


## Ignora la cámara y los personajes, como defensa adicional a la máscara.
func _is_ignored(geometry: GeometryInstance3D) -> bool:
	if not is_instance_valid(geometry):
		return true

	if is_instance_valid(_camera):
		if _camera == geometry or _camera.is_ancestor_of(geometry):
			return true

	if is_instance_valid(_attacker):
		if _attacker == geometry or _attacker.is_ancestor_of(geometry):
			return true

	if is_instance_valid(_target):
		if _target == geometry or _target.is_ancestor_of(geometry):
			return true

	return false


# -----------------------------------------------------------------------------
# EXCLUSIONES DE FÍSICA
# -----------------------------------------------------------------------------

func _refresh_excluded_rids() -> void:
	_excluded_rids.clear()

	_add_excluded_node(_attacker)
	_add_excluded_node(_target)
	_add_group_bodies(&"player")
	_add_group_bodies(&"npc")


func _add_group_bodies(group: StringName) -> void:
	for node in get_tree().get_nodes_in_group(group):
		_add_excluded_node(node)


## Excluye el RID del nodo y el de todos sus CollisionObject3D descendientes.
func _add_excluded_node(node: Node) -> void:
	if not is_instance_valid(node):
		return

	if node is CollisionObject3D:
		_append_excluded_rid((node as CollisionObject3D).get_rid())

	for child in node.find_children("*", "CollisionObject3D", true, false):
		_append_excluded_rid((child as CollisionObject3D).get_rid())


func _append_excluded_rid(rid: RID) -> void:
	if not rid.is_valid():
		return

	if _excluded_rids.has(rid):
		return

	_excluded_rids.append(rid)


# -----------------------------------------------------------------------------
# OCULTAMIENTO Y RESTAURACIÓN
# -----------------------------------------------------------------------------

func _hide_occluder(geometry: GeometryInstance3D) -> void:
	var id := geometry.get_instance_id()

	if _occluders.has(id):
		return

	_occluders[id] = {
		"ref": weakref(geometry),
		"visible": geometry.visible,
		"transparency": geometry.transparency,
	}

	# La colisión de CSG es independiente de la visibilidad; solo se oculta el
	# render. No se tocan materiales ni se mueve la cámara.
	geometry.visible = false


func _restore_occluder(id: int) -> void:
	var entry: Dictionary = _occluders.get(id, {})

	if entry.is_empty():
		return

	var reference: Variant = entry.get("ref")

	if reference is WeakRef:
		var geometry_object: Variant = reference.get_ref()

		if is_instance_valid(geometry_object) and geometry_object is GeometryInstance3D:
			var geometry := geometry_object as GeometryInstance3D
			geometry.visible = bool(entry.get("visible", true))
			geometry.transparency = float(entry.get("transparency", 0.0))

	_occluders.erase(id)


func _restore_all() -> void:
	for id in _occluders.keys():
		_restore_occluder(id)

	_occluders.clear()
