extends Node

## Estado global del jugador.
##
## Responsable únicamente de la forma actual del jugador, del descubrimiento por
## parte de los NPC y del bloqueo durante la cinemática. No contiene lógica de
## movimiento, navegación ni decisiones de comportamiento de NPC.

enum PlayerForm {
	SOMBRERON,
	DOG,
}

## Se emite cuando la forma del jugador cambia. [param form] es el nuevo valor.
signal form_changed(form)
## Se emite una sola vez por descubrimiento del Sombreron.
signal player_discovered
## Se emite cuando cambia el bloqueo del cambio de forma. [param locked] es el nuevo valor.
signal form_lock_changed(locked)
## Se emite cuando la cinemática empieza o termina. [param active] es el nuevo valor.
signal cinematic_state_changed(active)

## Forma actual del jugador.
var form: PlayerForm = PlayerForm.SOMBRERON
## Indica si el Sombreron ya fue descubierto por algún NPC.
var is_discovered: bool = false
## Mientras es verdadero, el jugador no puede cambiar de forma.
var is_form_change_locked: bool = false
## Mientras es verdadero, el juego está dentro de una cinemática.
var is_cinematic_active: bool = false


# -----------------------------------------------------------------------------
# FORMA DEL JUGADOR
# -----------------------------------------------------------------------------

## Devuelve true solo si el jugador puede ser detectado por los NPC.
## El perro es el mecanismo de sigilo y siempre es ignorado.
func is_player_detectable() -> bool:
	return form == PlayerForm.SOMBRERON


## Indica si el jugador puede cambiar de forma en este momento.
func can_change_form() -> bool:
	return not is_form_change_locked


## Intenta cambiar la forma del jugador.
## Rechaza el cambio si está bloqueado. Devuelve true si la forma quedó aplicada.
func set_form(new_form: PlayerForm) -> bool:
	if is_form_change_locked:
		return false

	if form == new_form:
		return true

	form = new_form
	form_changed.emit(form)
	return true


# -----------------------------------------------------------------------------
# DESCUBRIMIENTO
# -----------------------------------------------------------------------------

## Marca al jugador como descubierto. Es idempotente: la señal
## [signal player_discovered] se emite una sola vez por descubrimiento.
func mark_player_discovered() -> void:
	if is_discovered:
		return

	is_discovered = true
	lock_form_change()
	player_discovered.emit()


## Bloquea el cambio de forma. Emite [signal form_lock_changed] si hubo cambio.
func lock_form_change() -> void:
	if is_form_change_locked:
		return

	is_form_change_locked = true
	form_lock_changed.emit(true)


## Desbloquea el cambio de forma sin limpiar el descubrimiento.
## Es el punto de extensión previsto para el evento futuro que libera la forma.
func unlock_form_change() -> void:
	if not is_form_change_locked:
		return

	is_form_change_locked = false
	form_lock_changed.emit(false)


## Limpia el descubrimiento y desbloquea el cambio de forma.
func clear_discovery() -> void:
	is_discovered = false
	unlock_form_change()


# -----------------------------------------------------------------------------
# CINEMÁTICA
# -----------------------------------------------------------------------------

## Inicia la cinemática: pausa el árbol y marca el estado. Es idempotente.
func begin_cinematic() -> void:
	if is_cinematic_active:
		return

	is_cinematic_active = true
	get_tree().paused = true
	cinematic_state_changed.emit(true)


## Termina la cinemática: reanuda el árbol y limpia el estado. Es idempotente.
func end_cinematic() -> void:
	if not is_cinematic_active:
		return

	is_cinematic_active = false
	get_tree().paused = false
	cinematic_state_changed.emit(false)


# -----------------------------------------------------------------------------
# REINICIO
# -----------------------------------------------------------------------------

## Devuelve el estado global a sus valores iniciales.
func reset() -> void:
	if is_cinematic_active:
		is_cinematic_active = false
		get_tree().paused = false
		cinematic_state_changed.emit(false)

	is_discovered = false

	if is_form_change_locked:
		is_form_change_locked = false
		form_lock_changed.emit(false)

	if form != PlayerForm.SOMBRERON:
		form = PlayerForm.SOMBRERON
		form_changed.emit(form)
