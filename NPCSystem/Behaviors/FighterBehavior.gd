class_name FighterBehavior
extends NPCBehavior

## Comportamiento del NPC peleador.
##
## Huye hacia su zona segura cuando detecta al jugador y, si el Sombrerón entra
## en su zona de carga durante la huida, interrumpe el escape para ejecutar un
## ataque en área antes de continuar escapando.

const EVENT_ATTACK_TRIGGER_ENTERED := &"attack_trigger_entered"
const EVENT_ATTACK_TRIGGER_EXITED := &"attack_trigger_exited"

## Área que inicia la carga del ataque cuando el jugador entra en ella.
@export var attack_trigger_area: Area3D

@export_group("Ataque Peleador")
## Fuerza del empuje aplicado al objetivo al impacto del ataque.
@export var attack_knockback_force: float = 8.0
## Duración del aturdimiento del Sombrerón tras el impacto (segundos).
@export var attack_player_stun_duration: float = 2.0

var _player_in_attack_trigger: bool = false


## NPCBase llama a este método durante su inicialización.
func setup(owner_npc) -> void:
	super.setup(owner_npc)
	_resolve_attack_trigger_area()
	_connect_attack_trigger()
	_set_attack_trigger_enabled(false)
	_player_in_attack_trigger = false
	_apply_attack_exports_to_state()
	set_physics_process(true)


## Aplica los exports del comportamiento a la configuración del estado Attack.
func _apply_attack_exports_to_state() -> void:
	var attack_state := _get_attack_state() as Node
	if attack_state == null:
		return
	if "knockback_force" in attack_state:
		attack_state.knockback_force = attack_knockback_force
	if "player_stun_duration" in attack_state:
		attack_state.player_stun_duration = attack_player_stun_duration


func _physics_process(_delta: float) -> void:
	_update_attack_trigger_state()

	# Reintenta el ataque cuando termina el cooldown si el jugador sigue en rango.
	if _player_in_attack_trigger:
		_try_start_attack()


## Activa o desactiva la zona de carga según si es objetivo y está escapando.
func _update_attack_trigger_state() -> void:
	var should_enable: bool = (
		npc != null
		and npc.is_hunt_target
		and _is_in_state(&"escape")
	)

	_set_attack_trigger_enabled(should_enable)

	if should_enable:
		_refresh_attack_trigger_state()
	else:
		_player_in_attack_trigger = false


func _set_attack_trigger_enabled(enabled: bool) -> void:
	if attack_trigger_area == null or not is_instance_valid(attack_trigger_area):
		return

	attack_trigger_area.monitoring = enabled
	attack_trigger_area.monitorable = enabled


func handle_event(event: Dictionary) -> void:
	var event_name := StringName(event.get("name", &""))

	match event_name:
		EVENT_THREAT_DETECTED:
			flee_from_threat()
		EVENT_PLAYER_DISCOVERED:
			_on_player_discovered()
		EVENT_ATTACK_TRIGGER_ENTERED:
			_on_attack_trigger_entered(event.get("source"))
		EVENT_ATTACK_TRIGGER_EXITED:
			_on_attack_trigger_exited(event.get("source"))

	# EVENT_THREAT_LOST no interrumpe Escape: el estado Escape gestiona la
	# llegada a la zona segura.


## Reacción al descubrimiento global del jugador.
func _on_player_discovered() -> void:
	flee_from_threat()


## Huye hacia la zona segura. Si es el objetivo de caza, puede interrumpir la
## huida para atacar cuando el jugador entra en la zona de carga.
func flee_from_threat() -> void:
	if npc == null:
		return

	if not npc.has_safe_zone():
		push_warning("NPC '%s' sin zona segura asignada." % npc.name)
		return

	request_state(&"escape")

	# Solo el objetivo de caza puede atacar mientras huye.
	if npc.is_hunt_target and _is_in_state(&"escape") and _can_start_attack():
		request_state(&"attack")


func _on_attack_trigger_entered(body: Node) -> void:
	if not is_valid_player_body(body):
		return

	_player_in_attack_trigger = true
	_try_start_attack()


func _on_attack_trigger_exited(body: Node) -> void:
	if not is_valid_player_body(body):
		return

	_player_in_attack_trigger = _is_player_still_in_trigger()


## Intenta iniciar el ataque si el peleador objetivo está huyendo y el cooldown lo permite.
func _try_start_attack() -> void:
	if npc == null or not npc.is_hunt_target:
		return

	if not _is_in_state(&"escape"):
		return

	if not _can_start_attack():
		return

	request_state(&"attack")


func _can_start_attack() -> bool:
	if npc == null:
		return false

	# Solo el objetivo de caza tiene la posibilidad de atacar.
	if not npc.is_hunt_target:
		return false

	if not _player_in_attack_trigger:
		return false

	if not _is_player_still_in_trigger():
		_player_in_attack_trigger = false
		return false

	var attack_state := _get_attack_state()
	if attack_state == null:
		return false

	if not attack_state.is_ready():
		return false

	return true


func _get_attack_state() -> Node:
	if npc == null or npc.state_machine == null:
		return null
	return npc.state_machine.states.get(&"attack", null)


func _is_in_state(state_name: StringName) -> bool:
	if npc == null or npc.state_machine == null:
		return false
	return npc.state_machine.current_state_name == state_name


func _connect_attack_trigger() -> void:
	if attack_trigger_area == null or not is_instance_valid(attack_trigger_area):
		return

	if not attack_trigger_area.body_entered.is_connected(_on_trigger_body_entered):
		attack_trigger_area.body_entered.connect(_on_trigger_body_entered)
	if not attack_trigger_area.body_exited.is_connected(_on_trigger_body_exited):
		attack_trigger_area.body_exited.connect(_on_trigger_body_exited)


## Resuelve el área de carga desde el NPC si no se asignó en el Inspector.
func _resolve_attack_trigger_area() -> void:
	if attack_trigger_area != null and is_instance_valid(attack_trigger_area):
		return
	if npc == null:
		return

	attack_trigger_area = npc.get_node_or_null("AttackTriggerArea") as Area3D


func _refresh_attack_trigger_state() -> void:
	_player_in_attack_trigger = _is_player_still_in_trigger()


func _is_player_still_in_trigger() -> bool:
	if attack_trigger_area == null or not is_instance_valid(attack_trigger_area):
		return false

	for body in attack_trigger_area.get_overlapping_bodies():
		if is_valid_player_body(body):
			return true

	return false


func _on_trigger_body_entered(body: Node3D) -> void:
	if not is_valid_player_body(body):
		return
	if npc == null:
		return

	npc.notify_event({
		"name": EVENT_ATTACK_TRIGGER_ENTERED,
		"source": body,
	})


## El trigger de ataque reutiliza los helpers de NPCBehavior.
func _on_trigger_body_exited(body: Node3D) -> void:
	if not is_valid_player_body(body):
		return
	if npc == null:
		return

	npc.notify_event({
		"name": EVENT_ATTACK_TRIGGER_EXITED,
		"source": body,
	})
