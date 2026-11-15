extends Node

## Placeholder TEMPORAL de la cinemática de captura.
##
## NO es la cinemática final. Existe solo para poder probar el flujo completo de
## pausa, captura y reanudación mientras la cinemática real no está implementada:
##
##   1. Al iniciarse la cinemática espera un tiempo con el objetivo todavía visible.
##   2. En el punto definido captura al objetivo con
##      HuntManager.complete_current_target(), que lo hace desaparecer.
##   3. Espera otro momento y reanuda el juego continuando la caza.
##
## Debe estar configurado con PROCESS_MODE_ALWAYS para seguir ejecutándose con el
## árbol pausado durante la cinemática.

## Tiempo (segundos reales) que el objetivo permanece visible antes de capturarlo.
@export var capture_delay: float = 1.0
## Tiempo (segundos reales) tras la captura antes de reanudar el juego.
@export var resume_delay: float = 1.0

var _playing: bool = false


func _ready() -> void:
	GameState.cinematic_state_changed.connect(_on_cinematic_state_changed)


func _on_cinematic_state_changed(active: bool) -> void:
	if not active:
		return
	_play_placeholder()


## Reproduce el placeholder. La guarda [member _playing] evita reentradas si
## llegan varias notificaciones de inicio de cinemática.
func _play_placeholder() -> void:
	if _playing:
		return

	_playing = true

	# Tramo 1: el objetivo permanece visible.
	await _wait(capture_delay)

	# Punto definido de la cinemática: aquí desaparece el objetivo.
	HuntManager.complete_current_target()

	# Tramo 2: se muestra la captura antes de reanudar el juego.
	await _wait(resume_delay)

	GameState.end_cinematic()
	HuntManager.continue_hunt()

	_playing = false


## Espera en tiempo real aunque el árbol esté pausado. SceneTree.create_timer
## usa process_always = true por defecto.
func _wait(seconds: float) -> void:
	if seconds <= 0.0:
		return
	await get_tree().create_timer(seconds).timeout
