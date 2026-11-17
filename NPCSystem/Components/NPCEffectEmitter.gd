class_name NPCEffectEmitter
extends Node

## Hook de efectos visuales para la aparición y desaparición de un NPC.
##
## Las escenas quedan vacías por defecto: cuando existan partículas o efectos,
## se asignan desde el Inspector sin cambiar código. El efecto se instancia en
## la escena actual para que sobreviva al NPC que lo originó.

@export_group("Effects")
## Efecto que se reproduce cuando el NPC aparece (por ejemplo, un clon).
@export var spawn_effect: PackedScene
## Efecto que se reproduce cuando el NPC desaparece.
@export var despawn_effect: PackedScene
## Tiempo de vida del efecto instanciado antes de liberarlo.
@export var effect_lifetime: float = 2.0


## Reproduce el efecto de aparición en una posición mundial.
func play_spawn_effect(world_position: Vector3) -> void:
	_play(spawn_effect, world_position)


## Reproduce el efecto de desaparición en una posición mundial.
func play_despawn_effect(world_position: Vector3) -> void:
	_play(despawn_effect, world_position)


func _play(effect_scene: PackedScene, world_position: Vector3) -> void:
	if effect_scene == null:
		return

	var effect := effect_scene.instantiate()
	if effect == null:
		return

	var parent := _resolve_effect_parent()
	if parent == null:
		effect.queue_free()
		return

	parent.add_child(effect)

	if effect is Node3D:
		(effect as Node3D).global_position = world_position

	_schedule_free(effect)


## Los efectos viven en la escena actual, no dentro del NPC que los origina.
func _resolve_effect_parent() -> Node:
	if not is_inside_tree():
		return null

	var current_scene := get_tree().current_scene
	if current_scene != null:
		return current_scene

	return get_tree().root


## Libera el efecto tras su tiempo de vida. Es cosmético, así que el timer
## sigue corriendo aunque el árbol esté pausado.
func _schedule_free(effect: Node) -> void:
	var lifetime := maxf(effect_lifetime, 0.0)

	if lifetime <= 0.0:
		effect.queue_free()
		return

	var timer := get_tree().create_timer(lifetime, true, false, true)
	timer.timeout.connect(effect.queue_free)
