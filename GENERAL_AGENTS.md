Aquí tienes el `AGENTS.md` específico para esta tarea. Está pensado como **complemento** del `NPC_AGENTS.md` existente, no como reemplazo.

---

# AGENTS.md — Tarea: estado global, caza y cinemática

> Este documento complementa el `AGENTS.md` existente del sistema de NPCs.
> Todas las reglas generales de arquitectura, modularidad y uso de GDScript/Godot 4 siguen vigentes.

## 1. Objetivo

Implementar el estado global del jugador, el descubrimiento por parte de los NPC, la selección aleatoria de un objetivo de caza, la huida y desaparición de los NPC y el flujo de ataque/captura con cinemática.

## 2. Decisiones cerradas

- El jugador tiene dos formas: `SOMBRERON` y `PERRO`.
- El perro es el mecanismo de sigilo: **siempre es ignorado por los NPC**.
- El Sombreron no tiene estado de “oculto”.
- Cualquier NPC que vea al Sombreron activa el estado `descubierto`.
- Al descubrirse al jugador:
  - se bloquea el cambio de forma;
  - todos los NPC son alertados;
  - todos huyen a su zona segura, excepto el objetivo de caza.
- El bloqueo de forma permanece hasta que un evento futuro lo libere.
- El objetivo de caza se elige aleatoriamente entre los NPC enemigos disponibles:
  - al iniciar la partida;
  - después de que el jugador cace al objetivo actual.
- El objetivo de caza:
  - no huye;
  - sí puede activar la alarma si ve al jugador;
  - no desaparece por llegar a una zona segura.
- Los demás NPC desaparecen instantáneamente al llegar a su zona segura.
- Si no quedan enemigos disponibles después de una captura, la caza termina sin objetivo.
- El ataque solo se ejecuta si el objetivo de caza está dentro del `AttackArea3D`.
- Si no hay objetivo dentro del área, no se reproduce la animación de ataque; se prepara el punto para la futura animación del rectángulo bajo el área.
- La cinemática aún no existe. Se debe dejar el flujo preparado y un placeholder temporal para probar pausa, captura y reanudación.
- Durante la cinemática el juego no debe volver a la normalidad hasta que termine.
- El objetivo debe permanecer visible hasta el punto de la cinemática definido por el diseñador; en ese punto se elimina.

## 3. Arquitectura global

### 3.1. `GameState` — autoload

Responsable únicamente del estado global del jugador y del bloqueo de cinemática. No debe contener lógica de movimiento, navegación ni decisiones de comportamiento de NPC.

```gdscript
enum PlayerForm {
	SOMBRERON,
	DOG,
}

signal form_changed(form)
signal player_discovered
signal form_lock_changed(locked)
signal cinematic_state_changed(active)

var form: PlayerForm = PlayerForm.SOMBRERON
var is_discovered: bool = false
var is_form_change_locked: bool = false
var is_cinematic_active: bool = false
```

Métodos previstos:

```gdscript
func is_player_detectable() -> bool
func can_change_form() -> bool
func set_form(new_form: PlayerForm) -> bool
func mark_player_discovered() -> void
func unlock_form_change() -> void
func clear_discovery() -> void
func begin_cinematic() -> void
func end_cinematic() -> void
func reset() -> void
```

Reglas:

- `is_player_detectable()` devuelve `true` solo si `form == SOMBRERON`.
- El perro nunca es detectable.
- `mark_player_discovered()` debe ser idempotente:
  - activa `is_discovered`;
  - bloquea el cambio de forma;
  - emite `player_discovered` una sola vez por descubrimiento.
- `set_form()` debe rechazar el cambio si `is_form_change_locked` es verdadero.
- `begin_cinematic()` debe pausar el árbol y marcar `is_cinematic_active`.
- `end_cinematic()` debe reanudar el árbol y limpiar el estado.
- El evento futuro que desbloquee la forma decidirá si usa `unlock_form_change()` o `clear_discovery()`.

### 3.2. `HuntManager` — autoload

Responsable de la selección y captura del objetivo de caza.

```gdscript
signal target_changed(target)
signal target_captured(target)
signal hunt_finished

var current_target: NPCBase
```

Métodos previstos:

```gdscript
func select_random_target() -> void
func complete_current_target() -> void
func continue_hunt() -> void
func is_available_for_hunt(npc) -> bool
func reset() -> void
```

Reglas de selección:

- Solo puede elegir NPC con `classification == NPCBase.Classification.ENEMY`.
- Debe esperar a que los NPC estén registrados en el árbol; no asumir que el grupo `npc` está listo en el `_ready` del autoload.
- Debe excluir:
  - NPCs que se están eliminando;
  - NPCs en estado `escape`;
  - NPCs ya capturados;
  - el objetivo actual.
- Debe marcar exactamente un objetivo mediante `NPCBase.set_hunt_target(true)`.
- Si no hay candidatos:
  - `current_target = null`;
  - emitir `hunt_finished`.
- `complete_current_target()`:
  - valida que el objetivo siga siendo válido;
  - quita la marca de objetivo;
  - elimina/desaparece al NPC;
  - emite `target_captured`.
  - **No selecciona un nuevo objetivo durante la cinemática.**
- `continue_hunt()` se llama al terminar la cinemática:
  - elige un nuevo objetivo aleatorio si hay enemigos disponibles;
  - o emite `hunt_finished`.

## 4. Jugador

Archivo: `Player/Scripts/player.gd`.

- `control_dog()` debe actualizar `GameState.form = DOG`.
- `control_sombreron()` debe actualizar `GameState.form = SOMBRERON`.
- Antes de cambiar de personaje se debe comprobar `GameState.can_change_form()`.
- Si el cambio está bloqueado, la entrada debe ignorarse.
- No se debe implementar un estado “oculto” para el Sombreron.
- El perro debe seguir siendo la única forma de moverse sin activar NPCs.

## 5. Percepción y descubrimiento

Archivo: `NPCSystem/Components/NPCPerception.gd`.

- El perro debe ignorarse siempre.
- El Sombreron debe detectarse normalmente.
- Si el jugador cambia de forma, se deben revalidar los cuerpos detectados y emitir `body_lost` para los que dejen de ser amenaza.
- Cualquier NPC que detecte al Sombreron debe llamar a:

```gdscript
GameState.mark_player_discovered()
```

- El objetivo de caza también puede activar la alarma, pero luego no debe huir.
- La detección debe seguir separada de la reacción: la percepción detecta, el comportamiento decide.

## 6. Comportamientos y huida

Archivo base: `NPCSystem/Behaviors/NPCBehavior.gd`.

Añadir:

```gdscript
const EVENT_PLAYER_DISCOVERED := &"player_discovered"
```

Añadir un helper común:

```gdscript
func flee_from_threat() -> void:
	if npc == null:
		return
	if npc.is_hunt_target:
		return
	if not npc.has_safe_zone():
		push_warning("NPC sin zona segura asignada.")
		return
	request_state(&"escape")
```

- `NormalBehavior`, `FighterBehavior` y `TricksterBehavior` deben usar este helper para:
  - `EVENT_THREAT_DETECTED`;
  - `EVENT_PLAYER_DISCOVERED`.
- El objetivo de caza no debe entrar en `Escape` por ninguna de estas dos vías.
- En el futuro, `FighterBehavior` podrá reaccionar de forma distinta al evento de descubrimiento.

`NPCBase` debe conectar la señal `GameState.player_discovered` y reenviar el evento al comportamiento:

```gdscript
notify_event({
	"name": EVENT_PLAYER_DISCOVERED,
})
```

También debe consultar el estado al inicializarse, para NPCs que aparezcan después de la alarma.

## 7. Desaparición en zona segura

Archivo: `NPCSystem/States/Escape.gd`.

- Al llegar a la zona segura:
  - detener el movimiento;
  - llamar a `npc.despawn()`;
  - no volver a `Idle`.
- `NPCBase.despawn()` debe:
  - ocultar el NPC;
  - desactivar colisiones;
  - llamar a `queue_free()`.
- La desaparición debe ser instantánea.
- El objetivo de caza no debe pasar por `Escape`, por lo que no debe desaparecer por esta vía.
- Si un NPC no tiene zona segura, no debe entrar en `Escape`; se debe registrar una advertencia.

## 8. Ataque, objetivo y captura

Archivo: `Player/Scripts/sombreron.gd`.

El `AttackArea3D` existente en `Player/sombreron.tscn` será la zona de detección del ataque.

- Añadir una referencia exportada o resuelta al `AttackArea3D`.
- Al pulsar atacar:
  1. consultar `AttackArea3D.get_overlapping_bodies()`;
  2. buscar un cuerpo que sea `NPCBase` y tenga `is_hunt_target == true`;
  3. si no hay objetivo:
	 - no reproducir la animación de ataque;
	 - llamar a un método placeholder para la futura animación del rectángulo;
	 - no iniciar cinemática;
  4. si hay objetivo:
	 - reproducir la animación de ataque;
	 - iniciar el flujo de captura y cinemática.

Método placeholder previsto:

```gdscript
func _prepare_attack_miss_effect() -> void:
	# Punto de extensión para la futura animación del Sprite3D.
	pass
```

No se debe implementar todavía la animación visual del rectángulo.

## 9. Cinemática de captura

La cinemática real no existe en el proyecto. Se debe preparar el flujo sin dejarlo bloqueado permanentemente.

Flujo previsto:

1. El ataque detecta el objetivo.
2. Se llama a `GameState.begin_cinematic()`.
3. La cinemática/placeholder muestra al objetivo.
4. En el punto definido de la cinemática se llama:

```gdscript
HuntManager.complete_current_target()
```

5. El objetivo desaparece en ese punto.
6. Al terminar la cinemática:

```gdscript
GameState.end_cinematic()
HuntManager.continue_hunt()
```

Reglas:

- La cinemática debe tener `PROCESS_MODE_ALWAYS` si se pausa el árbol.
- El objetivo debe permanecer visible hasta el punto de captura definido.
- No se debe seleccionar un nuevo objetivo mientras la cinemática esté activa.
- El jugador no debe poder moverse ni cambiar de forma durante la cinemática.
- Mientras no exista la cinemática real, implementar un placeholder temporal y claramente documentado que permita probar pausa, captura y reanudación.
- El placeholder no debe considerarse la cinemática final.

## 10. Flujo completo

1. Inicia la partida.
2. `HuntManager` elige un enemigo aleatorio.
3. El jugador se mueve como Sombreron o Perro.
4. Si un NPC ve al Sombreron:
   - se marca descubierto;
   - se bloquea el cambio de forma;
   - se emite la alarma global.
5. Todos los NPC salvo el objetivo huyen a su zona segura y desaparecen.
6. El objetivo permanece y puede ser atacado.
7. Si el jugador ataca con el objetivo dentro del área:
   - se inicia la cinemática;
   - el objetivo permanece visible hasta el punto definido;
   - se captura y elimina;
   - se reanuda el juego;
   - se elige un nuevo objetivo o termina la caza.
8. Si no hay objetivo dentro del área:
   - no hay ataque;
   - se prepara la futura animación del rectángulo.
9. Si no quedan enemigos disponibles:
   - `HuntManager` emite `hunt_finished`;
   - no se produce ningún error.

## 11. Archivos previstos

Nuevos:

- `Game/GameState.gd` + autoload en `project.godot`.
- `Game/HuntManager.gd` + autoload en `project.godot`.
- Placeholder temporal de cinemática, si se decide necesario para probar el flujo.

Existentes a modificar:

- `Player/Scripts/player.gd`
- `Player/Scripts/sombreron.gd`
- `Player/sombreron.tscn` o `Player/player.tscn` para la referencia al `AttackArea3D`
- `NPCSystem/Components/NPCPerception.gd`
- `NPCSystem/Base/NPCBase.gd`
- `NPCSystem/States/Escape.gd`
- `NPCSystem/Behaviors/NPCBehavior.gd`
- `NPCSystem/Behaviors/NormalBehavior.gd`
- `NPCSystem/Behaviors/FighterBehavior.gd`
- `NPCSystem/Behaviors/TricksterBehavior.gd`
- `project.godot`

## 12. Orden de implementación

1. Crear `GameState` y registrarlo como autoload.
2. Integrar bloqueo de forma y actualización de forma en `player.gd`.
3. Filtrar la percepción del perro y disparar el descubrimiento.
4. Crear `HuntManager`, selección aleatoria y flag de objetivo.
5. Añadir el helper de huida y la excepción del objetivo.
6. Implementar la desaparición en zona segura.
7. Integrar el ataque con `AttackArea3D`.
8. Añadir el flujo de cinemática y el placeholder temporal.
9. Ejecutar pruebas headless con varios NPC.

## 13. Criterios de aceptación

- [ ] El perro nunca activa la percepción de los NPC.
- [ ] El Sombreron es detectado normalmente.
- [ ] Cualquier NPC que vea al Sombreron activa el descubrimiento una sola vez.
- [ ] Al descubrirse, el cambio de forma queda bloqueado.
- [ ] El bloqueo se mantiene hasta el evento futuro.
- [ ] Todos los NPC salvo el objetivo huyen al ser descubiertos.
- [ ] Los NPC que huyen desaparecen instantáneamente al llegar a su zona segura.
- [ ] El objetivo de caza no huye.
- [ ] El objetivo de caza sí puede activar la alarma.
- [ ] El objetivo se elige aleatoriamente entre enemigos disponibles.
- [ ] Tras capturar al objetivo se elige otro enemigo disponible.
- [ ] Si no quedan enemigos, la caza termina sin objetivo.
- [ ] El ataque sin objetivo no reproduce la animación de ataque y usa el placeholder.
- [ ] El ataque con objetivo inicia la cinemática.
- [ ] El juego permanece bloqueado hasta terminar la cinemática.
- [ ] El objetivo permanece visible hasta el punto definido de la cinemática.
- [ ] Al terminar la cinemática se reanuda el juego y se actualiza la caza.
- [ ] Varios NPC funcionan simultáneamente sin compartir estado.
- [ ] No hay errores si un NPC no tiene zona segura.
- [ ] No hay errores si no quedan enemigos disponibles.

## 14. Pruebas mínimas

- Iniciar el mapa y verificar que solo un enemigo es objetivo.
- Acercar al perro a un NPC y comprobar que no hay detección ni huida.
- Acercar al Sombreron y comprobar descubrimiento, bloqueo de forma y alarma.
- Verificar que todos los NPC salvo el objetivo entran en `Escape`.
- Verificar que los NPC que escapan desaparecen al llegar a su zona segura.
- Atacar sin objetivo dentro del área y comprobar que no hay ataque ni cinemática.
- Atacar con el objetivo dentro y comprobar pausa, captura, reanudación y nuevo objetivo.
- Repetir hasta que no queden enemigos y comprobar `hunt_finished`.
- Ejecutar la comprobación headless del proyecto sin errores de script.

## 15. Fuera de alcance

- Implementar la cinemática final.
- Implementar la animación visual del rectángulo de ataque.
- Implementar el evento futuro que desbloquea el cambio de forma.
- Implementar un sistema de reaparición de NPCs.
- Implementar daño o combate contra NPCs que no sean el objetivo.
- Añadir mecánicas de ocultamiento para el Sombreron.

## 16. Reglas para el agente implementador

1. Mantener la navegación y el movimiento centralizados en `NPCBase`.
2. No implementar navegación dentro de estados o comportamientos.
3. No poner decisiones de comportamiento dentro de `GameState` ni `HuntManager`.
4. Usar señales globales para la alarma y el estado del jugador.
5. Comprobar referencias antes de usarlas.
6. Evitar estados o destinos compartidos entre NPCs.
7. Mantener los nombres y comentarios en español, coherentes con el proyecto.
8. No modificar sistemas ajenos a la tarea sin necesidad.
9. Verificar el proyecto en modo headless antes de finalizar.
10. Documentar las funciones públicas nuevas y los puntos de extensión.

---

Este es el contenido que debe usarse como guía de implementación.
