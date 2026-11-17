extends NPCState

## Estado de ataque y duplicación del tramposo.
##
## Detiene al NPC, reproduce la animación de ataque y ejecuta una secuencia
## temporal propia del estado:
##
##     t = 0.0 s  → ataque desde el inicio
##     t = 2.5 s  → aparece el clon quieto
##     t = 3.5 s  → el original vuelve a Escape y el clon inicia Flee
##
## La secuencia se mide con delta acumulado: no usa Timer ni animation_finished,
## porque el clip de ataque puede terminar antes que la secuencia.

## Se emite cuando el clon aparece en la escena.
signal clone_spawned(clone: NPCBase)
## Se emite cuando el clon se libera hacia su huida.
signal clone_released(clone: NPCBase)

@export_group("Attack")
## Animación que se reproduce al iniciar la secuencia.
@export var attack_animation: StringName = &"attack"
## Estado al que vuelve el original cuando empieza la huida final.
@export var exit_state: StringName = &"escape"

@export_group("Clone")
## Escena del clon. Si queda vacía se usa la ruta por defecto del proyecto.
@export var clone_scene: PackedScene
## Tiempo en segundos hasta que aparece el clon.
@export var clone_spawn_time: float = 2.5
## Tiempo en segundos hasta que original y clon salen corriendo.
@export var flee_start_time: float = 3.5
## Separación lateral del clon respecto al original, en metros.
@export var clone_spawn_distance: float = 1.4

## Ruta de respaldo para no depender de una asignación manual en el Inspector.
const DEFAULT_CLONE_SCENE := "res://Entities/Tramposo/TramposoClone.tscn"

var _elapsed: float = 0.0
var _clone_spawned: bool = false
var _flee_started: bool = false
var _used_in_current_escape: bool = false
var _clone: NPCBase = null


func enter() -> void:
	_elapsed = 0.0
	_clone_spawned = false
	_flee_started = false
	_clone = null
	_used_in_current_escape = true

	if npc == null:
		return

	# Prioridad del ataque: detiene la huida y permanece en su posición.
	npc.stop_movement()
	npc.velocity.x = 0.0
	npc.velocity.z = 0.0

	_play_attack_from_start()


func update(delta: float) -> void:
	if npc == null:
		return

	_elapsed += delta

	if not _clone_spawned and _elapsed >= clone_spawn_time:
		_spawn_clone()
		_clone_spawned = true

	if not _flee_started and _elapsed >= flee_start_time:
		_start_flee()


func exit() -> void:
	# Si la secuencia se interrumpió antes de liberar al clon, no dejarlo
	# huérfano en la escena.
	if _clone_spawned and not _flee_started:
		_despawn_clone()

	_flee_started = false
	_clone_spawned = false
	_clone = null

	if npc != null:
		npc.stop_movement()


## Indica si la habilidad puede usarse en la huida actual.
func is_available() -> bool:
	return not _used_in_current_escape


## Rearma la habilidad al iniciar una huida nueva desde Idle.
func reset_for_new_escape() -> void:
	_used_in_current_escape = false


func _play_attack_from_start() -> void:
	var animation_player: AnimationPlayer = npc.get_animation_player()

	if (
		animation_player != null
		and animation_player.has_animation(attack_animation)
	):
		animation_player.speed_scale = 1.0
		animation_player.play(attack_animation)
		return

	npc.play_animation(attack_animation)


func _spawn_clone() -> void:
	var scene := clone_scene

	if scene == null:
		scene = load(DEFAULT_CLONE_SCENE) as PackedScene

	if scene == null:
		push_warning(
			"Tramposo '%s' no pudo cargar la escena del clon." % npc.name
		)
		return

	var clone := scene.instantiate() as NPCBase
	if clone == null:
		push_warning("La escena del clon no es un NPCBase.")
		return

	var spawn_position := _get_clone_spawn_position()
	var yaw := 0.0

	if npc.model != null:
		yaw = npc.model.global_rotation.y

	var spawn_transform := Transform3D(Basis(Vector3.UP, yaw), spawn_position)
	var parent: Node = npc.get_parent()

	if parent is Node3D:
		clone.transform = (
			(parent as Node3D).global_transform.affine_inverse()
			* spawn_transform
		)
	else:
		clone.transform = spawn_transform

	parent.add_child(clone)
	clone.global_transform = spawn_transform

	clone.stop_movement()
	clone.play_animation(clone.idle_animation)

	_clone = clone
	clone_spawned.emit(clone)


func _start_flee() -> void:
	_flee_started = true

	if is_instance_valid(_clone):
		_clone.request_state(&"flee")
		clone_released.emit(_clone)

	request_transition(exit_state)


func _despawn_clone() -> void:
	if not is_instance_valid(_clone):
		return

	_clone.despawn()
	_clone = null


## Coloca al clon a un lado del original para que no se solapen.
func _get_clone_spawn_position() -> Vector3:
	var side: Vector3 = npc.global_transform.basis.x
	side.y = 0.0

	if side.length_squared() <= 0.0001:
		side = Vector3.RIGHT

	return npc.global_position + side.normalized() * clone_spawn_distance
