class_name TricksterBehavior
extends NPCBehavior

## Comportamiento del NPC tramposo.
##
## Huye hacia su zona segura cuando es amenazado, incluso si es el objetivo de
## caza. Si el Sombrerón se acerca mientras huye, ejecuta una vez por huida su
## habilidad de duplicación: ataque, aparición del clon y huida de ambos.
##
## El clon es un NPCBase marcado como señuelo (ver TramposoClone.tscn). No huye
## del jugador ni se duplica: su comportamiento base ignora los eventos.

## Área que detecta al Sombrerón durante la huida.
@export var clone_trigger_area: Area3D


## NPCBase llama a este método durante su inicialización.
func setup(owner_npc) -> void:
	super.setup(owner_npc)
	_resolve_clone_trigger_area()
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	_try_start_clone_attack()


func handle_event(event: Dictionary) -> void:
	var event_name := StringName(event.get("name", &""))

	match event_name:
		EVENT_THREAT_DETECTED:
			flee_from_threat()
		EVENT_PLAYER_DISCOVERED:
			flee_from_threat()

	# EVENT_THREAT_LOST no interrumpe Escape: una vez iniciada la huida, el NPC
	# continúa hasta su zona segura y desaparece.


## Huye hacia la zona segura aunque sea el objetivo de caza.
##
## Es una excepción deliberada al helper base, igual que en el Peleador: el
## tramposo usa su huida para activar la duplicación antes de desaparecer. No
## interrumpe una huida ni una secuencia de ataque en curso.
func flee_from_threat() -> void:
	if npc == null:
		return

	if not npc.has_safe_zone():
		push_warning("NPC '%s' sin zona segura asignada." % npc.name)
		return

	if _is_in_state(&"attack") or _is_in_state(&"escape"):
		return

	# Cada huida nueva rearma la habilidad de duplicación.
	_reset_clone_ability()
	request_state(&"escape")


## Intenta iniciar la secuencia de ataque/duplicación si se cumplen todas las
## condiciones. Se consulta cada frame en lugar de usar body_entered para evitar
## perder el disparo cuando el jugador ya está dentro del área.
func _try_start_clone_attack() -> void:
	if npc == null or not npc.is_hunt_target:
		return

	if not GameState.is_discovered:
		return

	if not _is_in_state(&"escape"):
		return

	var attack_state := _get_attack_state()
	if attack_state == null or not attack_state.is_available():
		return

	if not _is_sombreron_in_trigger():
		return

	request_state(&"attack")


func _reset_clone_ability() -> void:
	var attack_state := _get_attack_state()
	if attack_state == null:
		return
	if attack_state.has_method("reset_for_new_escape"):
		attack_state.reset_for_new_escape()


func _get_attack_state() -> Node:
	if npc == null or npc.state_machine == null:
		return null
	return npc.state_machine.states.get(&"attack", null)


func _is_in_state(state_name: StringName) -> bool:
	if npc == null or npc.state_machine == null:
		return false
	return npc.state_machine.current_state_name == state_name


func _is_sombreron_in_trigger() -> bool:
	if clone_trigger_area == null or not is_instance_valid(clone_trigger_area):
		return false

	for body in clone_trigger_area.get_overlapping_bodies():
		if is_valid_player_body(body):
			return true

	return false


## Resuelve el área de disparo desde el NPC si no se asignó en el Inspector.
func _resolve_clone_trigger_area() -> void:
	if clone_trigger_area != null and is_instance_valid(clone_trigger_area):
		return
	if npc == null:
		return

	clone_trigger_area = npc.get_node_or_null("CloneTriggerArea") as Area3D
