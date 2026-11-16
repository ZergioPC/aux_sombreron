extends NPCState

## Estado de ataque en área del NPC.
##
## Detiene el movimiento, reproduce la animación de ataque, ejecuta un impacto
## diferido sobre un Area3D y, al terminar la animación, vuelve al estado de
## salida configurado. La decisión de cuándo atacar pertenece al comportamiento.

@export_group("Attack")
## Animación que se reproduce al iniciar el ataque.
@export var attack_animation: StringName = &"attack"
## Tiempo en segundos desde el inicio de la animación hasta el impacto.
@export var impact_delay: float = 1.7
## Estado al que se vuelve cuando termina la animación.
@export var exit_state: StringName = &"escape"
## Tiempo mínimo entre ataques, en segundos.
@export var cooldown_duration: float = 7.0

@export_group("Impact")
## Área que define el radio afectado por el impacto.
@export var impact_area: Area3D
## Fuerza del empuje aplicado a los cuerpos afectados.
@export var knockback_force: float = 8.0
## Duración del aturdimiento aplicado al jugador (Sombrerón).
@export var player_stun_duration: float = 2.0

var _elapsed: float = 0.0
var _impact_done: bool = false
var _attack_finished: bool = false
var _cooldown_left: float = 0.0


func _ready() -> void:
	# El cooldown corre aunque el estado no esté activo.
	set_physics_process(true)


func enter() -> void:
	_elapsed = 0.0
	_impact_done = false
	_attack_finished = false

	if npc == null:
		return

	_resolve_impact_area()

	# Prioridad del ataque: detiene la huida y permanece en su posición.
	npc.stop_movement()
	npc.velocity.x = 0.0
	npc.velocity.z = 0.0

	_connect_animation_finished()

	# Reproduce la animación de ataque desde el inicio.
	var animation_player: AnimationPlayer = npc.get_animation_player()
	if animation_player != null and animation_player.has_animation(attack_animation):
		animation_player.speed_scale = 1.0
		animation_player.play(attack_animation)
	else:
		npc.play_animation(attack_animation)
		push_warning(
			"NPC '%s' no pudo iniciar la animación de ataque '%s'."
			% [npc.name, attack_animation]
		)
		# Sin animación fiable se completa el ataque tras el impacto.
		_attack_finished = true

	# Inicia el cooldown al comenzar la carga.
	_cooldown_left = maxf(cooldown_duration, 0.0)


func update(delta: float) -> void:
	if npc == null:
		return

	_elapsed += delta

	if not _impact_done and _elapsed >= impact_delay:
		_perform_impact()
		_impact_done = true

	# La salida se produce al terminar la animación.
	if _attack_finished:
		request_transition(exit_state)
		return

	# Salvaguarda: si la animación no emite finished, termina al alcanzar su duración.
	if _is_animation_done() and _impact_done:
		_attack_finished = true
		request_transition(exit_state)


func exit() -> void:
	_attack_finished = false
	_disconnect_animation_finished()

	if npc != null:
		npc.stop_movement()


func _physics_process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left -= delta


## Indica si el ataque está disponible según el cooldown.
func is_ready() -> bool:
	return _cooldown_left <= 0.0


func _perform_impact() -> void:
	if npc == null or impact_area == null or not is_instance_valid(impact_area):
		return

	for body in impact_area.get_overlapping_bodies():
		if body == null or not is_instance_valid(body):
			continue

		# El atacante se excluye del impacto.
		if body == npc:
			continue

		var push_direction: Vector3 = body.global_position - npc.global_position
		push_direction.y = 0.0

		if push_direction.length_squared() <= 0.0001:
			push_direction = -npc.global_transform.basis.z
			push_direction.y = 0.0

		if push_direction.length_squared() <= 0.0001:
			push_direction = Vector3.FORWARD

		push_direction = push_direction.normalized()

		# Solo el Sombrerón recibe knockback y stun.
		if _is_sombreron(body):
			_apply_player_impact(body, push_direction)
			continue

		# Los demás NPCs reciben solo knockback.
		if body.is_in_group(&"npc"):
			_apply_npc_knockback(body, push_direction)


func _apply_player_impact(body: Node3D, direction: Vector3) -> void:
	var target := _resolve_sombreron(body)
	if target == null:
		return

	if target.has_method("apply_knockback"):
		target.apply_knockback(direction, knockback_force)

	if target.has_method("apply_stun"):
		target.apply_stun(player_stun_duration)


func _apply_npc_knockback(body: Node3D, direction: Vector3) -> void:
	if body.has_method("apply_knockback"):
		body.apply_knockback(direction, knockback_force)
	elif body is NPCBase:
		(body as NPCBase).apply_knockback(direction, knockback_force)


func _is_sombreron(body: Node) -> bool:
	var current: Node = body
	while current != null:
		if current.name == &"Sombreron" or current.is_in_group(&"sombreron"):
			return true
		# El script del Sombrerón identifica al personaje controlable principal.
		if current.get_script() != null and String(current.get_script().resource_path).ends_with("sombreron.gd"):
			return true
		current = current.get_parent()
	return false


func _resolve_sombreron(body: Node) -> Node:
	var current: Node = body
	while current != null:
		if current.name == &"Sombreron":
			return current
		if current.get_script() != null and String(current.get_script().resource_path).ends_with("sombreron.gd"):
			return current
		current = current.get_parent()
	return body as Node


func _connect_animation_finished() -> void:
	if npc == null:
		return
	var animation_player: AnimationPlayer = npc.get_animation_player()
	if animation_player == null:
		return
	if not animation_player.animation_finished.is_connected(_on_animation_finished):
		animation_player.animation_finished.connect(_on_animation_finished)


func _disconnect_animation_finished() -> void:
	if npc == null:
		return
	var animation_player: AnimationPlayer = npc.get_animation_player()
	if animation_player == null:
		return
	if animation_player.animation_finished.is_connected(_on_animation_finished):
		animation_player.animation_finished.disconnect(_on_animation_finished)


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == attack_animation:
		_attack_finished = true


## Indica si la animación de ataque ya terminó o no puede reproducirse.
func _is_animation_done() -> bool:
	if npc == null:
		return true

	var animation_player: AnimationPlayer = npc.get_animation_player()
	if animation_player == null:
		return true

	if not animation_player.has_animation(attack_animation):
		return true

	# Si el AnimationPlayer ya no reproduce esta animación, se considera terminada.
	if animation_player.current_animation != String(attack_animation):
		return _elapsed >= impact_delay

	var animation: Animation = animation_player.get_animation(attack_animation)
	if animation == null:
		return true

	return _elapsed >= animation.length


## Resuelve el área de impacto desde el NPC si no se asignó en el Inspector.
func _resolve_impact_area() -> void:
	if impact_area != null and is_instance_valid(impact_area):
		return
	if npc == null:
		return

	impact_area = npc.get_node_or_null("AttackImpactArea") as Area3D
