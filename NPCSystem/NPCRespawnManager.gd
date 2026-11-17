extends Node

## Controlador global de reaparición de NPC.
##
## Guarda un plano de cada NPC colocado en la escena: escena de origen, padre,
## transform de aparición y sobreescrituras de instancia (zona segura y spawn).
##
## Cuando un NPC desaparece sin ser capturado (por ejemplo, al llegar a su zona
## segura huyendo), [HuntManager] solicita [method respawn_missing] durante el
## reset para recrearlo en su spawn. El NPC capturado se elimina del registro
## con [method mark_captured] y nunca reaparece.
##
## Es un autoload porque la reaparición debe sobrevivir a los NPC liberados y no
## depende de un nodo concreto del mapa.

## Metadato que identifica las instancias recreadas por este controlador.
const RESPAWN_META := &"npc_respawn_key"

## Planos registrados, indexados por la ruta original del NPC en la escena.
var _blueprints: Dictionary = {}


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


# -----------------------------------------------------------------------------
# REGISTRO
# -----------------------------------------------------------------------------

## Registra un NPC cuando entra al árbol, después de su `_ready`.
func _on_node_added(node: Node) -> void:
	if not (node is NPCBase):
		return

	var npc := node as NPCBase

	# Una instancia recreada ya tiene un plano asociado.
	if npc.has_meta(RESPAWN_META):
		return

	if not npc.is_node_ready():
		await npc.ready

	if not is_instance_valid(npc):
		return

	# Los señuelos y cualquier NPC marcado como no registrable (clones,
	# invocaciones temporales) no deben reaparecer en el reset.
	if npc.is_decoy or not npc.register_for_respawn:
		return

	_register(npc)


func _register(npc: NPCBase) -> void:
	var key := StringName(npc.get_path())
	var existing: Variant = _blueprints.get(key)

	if existing is Dictionary:
		var existing_parent: Variant = (existing as Dictionary).get("parent")

		# Mismo padre: el NPC ya estaba registrado.
		if existing_parent == npc.get_parent():
			return

		# Escena recargada: el padre anterior ya no sirve, se reemplaza el plano.
		_blueprints.erase(key)

	var scene_path := npc.scene_file_path
	if scene_path.is_empty():
		push_warning(
			"NPCRespawnManager: '%s' no tiene una escena de origen." % npc.name
		)
		return

	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_warning(
			"NPCRespawnManager: no se pudo cargar la escena '%s' de '%s'."
			% [scene_path, npc.name]
		)
		return

	_blueprints[key] = {
		"scene": packed,
		"parent": npc.get_parent(),
		"name": npc.name,
		"transform": npc.global_transform,
		"spawn_position": npc.spawn_position,
		"use_scene_position_as_spawn": npc.use_scene_position_as_spawn,
		"safe_zone": npc.safe_zone,
		"instance": npc,
	}

	npc.set_meta(RESPAWN_META, key)


## Elimina del registro al NPC capturado para que no vuelva a aparecer.
func mark_captured(npc: NPCBase) -> void:
	if npc == null or not is_instance_valid(npc):
		return

	var key: Variant = npc.get_meta(RESPAWN_META, &"")
	if key == &"":
		return

	_blueprints.erase(key)


# -----------------------------------------------------------------------------
# REAPARICIÓN
# -----------------------------------------------------------------------------

## Recrea en su spawn a todos los NPC registrados cuya instancia ya no exista.
func respawn_missing() -> void:
	_prune_invalid_blueprints()

	for key in _blueprints.keys():
		var blueprint: Dictionary = _blueprints[key]
		var instance: Variant = blueprint.get("instance")

		if is_instance_valid(instance) and not instance.is_queued_for_deletion():
			continue

		_respawn(key, blueprint)


func _respawn(key: StringName, blueprint: Dictionary) -> void:
	var parent: Variant = blueprint.get("parent")

	if not is_instance_valid(parent):
		_blueprints.erase(key)
		return

	var packed: Variant = blueprint.get("scene")
	if not (packed is PackedScene):
		_blueprints.erase(key)
		return

	var npc := (packed as PackedScene).instantiate() as NPCBase
	if npc == null:
		push_warning("NPCRespawnManager: la escena registrada no es un NPCBase.")
		return

	var spawn_transform: Transform3D = blueprint.get(
		"transform", Transform3D.IDENTITY
	)

	npc.name = StringName(blueprint.get("name", npc.name))
	npc.use_scene_position_as_spawn = bool(
		blueprint.get("use_scene_position_as_spawn", true)
	)
	npc.spawn_position = blueprint.get("spawn_position", Vector3.ZERO)

	var safe_zone: Variant = blueprint.get("safe_zone")
	if safe_zone is Node3D and is_instance_valid(safe_zone):
		npc.safe_zone = safe_zone

	# El transform local se calcula antes de añadirlo para que `_ready` capture
	# la posición de spawn correcta aunque el padre tenga transform.
	if parent is Node3D:
		npc.transform = (parent as Node3D).global_transform.affine_inverse() * spawn_transform
	else:
		npc.transform = spawn_transform

	# Evita un segundo registro si `node_added` ocurre después del await.
	npc.set_meta(RESPAWN_META, key)

	parent.add_child(npc)

	# Refuerza el transform global por si el padre cambió entre el registro y
	# la reaparición.
	npc.global_transform = spawn_transform

	blueprint["instance"] = npc
	_blueprints[key] = blueprint


func _prune_invalid_blueprints() -> void:
	for key in _blueprints.keys():
		var blueprint: Dictionary = _blueprints[key]
		var parent: Variant = blueprint.get("parent")

		if not is_instance_valid(parent):
			_blueprints.erase(key)
