extends Node

## Gestor de la caza.
##
## Elige aleatoriamente un objetivo entre los NPC enemigos disponibles, gestiona
## su captura y decide si la caza continúa. No contiene decisiones de
## comportamiento de NPC: solo selecciona y comunica mediante señales.

## Se emite cuando cambia el objetivo de caza. [param target] puede ser null.
signal target_changed(target)
## Se emite cuando un objetivo ha sido capturado. [param target] es el NPC capturado.
signal target_captured(target)
## Se emite cuando no quedan enemigos disponibles para la caza.
signal hunt_finished

## Nombre del estado que excluye a un NPC como candidato de caza.
const ESCAPE_STATE := &"escape"

## Objetivo de caza actual, o null si no hay ninguno.
var current_target: NPCBase = null


func _ready() -> void:
	# Los NPC pueden añadirse más tarde; reaccionamos a su registro en el árbol.
	get_tree().node_added.connect(_on_node_added)
	_start_hunt.call_deferred()


# -----------------------------------------------------------------------------
# SELECCIÓN DE OBJETIVO
# -----------------------------------------------------------------------------

## Elige aleatoriamente un enemigo disponible como objetivo de caza.
## Si no hay candidatos, deja el objetivo en null y emite [signal hunt_finished].
func select_random_target() -> void:
	if GameState.is_cinematic_active:
		return

	var candidates := _get_available_enemies()

	if candidates.is_empty():
		_set_current_target(null)
		hunt_finished.emit()
		return

	var index := randi() % candidates.size()
	_set_current_target(candidates[index])
	print(candidates[index].name)


## Completa la captura del objetivo actual: le quita la marca, lo hace
## desaparecer y emite [signal target_captured]. No elige un nuevo objetivo.
func complete_current_target() -> void:
	var target := current_target
	_set_current_target(null)

	if target == null or not is_instance_valid(target):
		return

	target.is_captured = true
	target.despawn()
	target_captured.emit(target)


## Reanuda la caza tras una captura o una cinemática, eligiendo un nuevo objetivo.
func continue_hunt() -> void:
	if GameState.is_cinematic_active:
		return
	select_random_target()


## Indica si un NPC puede convertirse en objetivo de caza.
func is_available_for_hunt(npc: Node) -> bool:
	if not (npc is NPCBase) or not is_instance_valid(npc):
		return false

	if npc.classification != NPCBase.Classification.ENEMY:
		return false

	if npc.is_queued_for_deletion() or npc.is_captured:
		return false

	if npc == current_target:
		return false

	if _is_escaping(npc):
		return false

	return true


## Restablece el gestor a su estado inicial.
func reset() -> void:
	if current_target != null and is_instance_valid(current_target):
		current_target.set_hunt_target(false)
	current_target = null


# -----------------------------------------------------------------------------
# ARRANQUE DIFERIDO
# -----------------------------------------------------------------------------

## Espera un frame para dar tiempo a que la escena y sus NPC se registren.
func _start_hunt() -> void:
	await get_tree().process_frame

	if current_target != null or GameState.is_cinematic_active:
		return

	# Si la escena todavía no ha cargado sus NPC, _on_node_added se encargará.
	if get_tree().get_nodes_in_group(&"npc").is_empty():
		return

	select_random_target()


## Selecciona objetivo cuando aparece un NPC y aún no hay ninguno elegido.
func _on_node_added(node: Node) -> void:
	if not (node is NPCBase):
		return

	if GameState.is_cinematic_active or current_target != null:
		return

	# node_added se emite antes del _ready del NPC, donde se une al grupo "npc".
	if not node.is_node_ready():
		await node.ready

	if not is_instance_valid(node):
		return

	if current_target == null and not GameState.is_cinematic_active:
		select_random_target()


# -----------------------------------------------------------------------------
# HELPERS
# -----------------------------------------------------------------------------

func _set_current_target(target: NPCBase) -> void:
	if current_target == target:
		return

	if current_target != null and is_instance_valid(current_target):
		current_target.set_hunt_target(false)

	current_target = target

	if current_target != null:
		current_target.set_hunt_target(true)

	target_changed.emit(current_target)


func _get_available_enemies() -> Array[NPCBase]:
	var result: Array[NPCBase] = []

	for node in get_tree().get_nodes_in_group(&"npc"):
		if is_available_for_hunt(node):
			result.append(node as NPCBase)

	return result


func _is_escaping(npc: NPCBase) -> bool:
	if npc.state_machine == null:
		return false
	return npc.state_machine.current_state_name == ESCAPE_STATE
