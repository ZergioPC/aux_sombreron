# AGENTS.md — Cámara de gameplay y cinemática de captura

> Este documento es la guía de implementación de la **cámara que sigue al jugador** y del **sistema cinemático de captura** de este proyecto.
>
> Convive con `GENERAL_AGENTS.md` y `NPCS_AGENTS.md`. En caso de conflicto:
>
> - `GENERAL_AGENTS.md` y `NPCS_AGENTS.md` siguen vigentes para el estado global, la caza, la percepción, los NPC y sus estados.
> - Este documento reemplaza únicamente el flujo del placeholder descrito en `GENERAL_AGENTS.md` §9 y el uso de `Game/CinematicPlaceholder.gd`.
> - `GameState` y `HuntManager` conservan su contrato actual: no se duplican la pausa ni la selección de objetivos.

## 1. Objetivo

Implementar dos sistemas independientes pero coordinados:

1. **Cámara de gameplay**: sigue al personaje activo del jugador, tanto en forma `SOMBRERON` como `PERRO`.
2. **Cinemática de captura**: se activa **solo cuando el jugador ataca y el objetivo de caza está dentro de `AttackArea3D`**. Cambia a una cámara cinemática, reproduce las animaciones de los personajes y ejecuta una animación de cámara que se authored más adelante.

La animación definitiva de cámara **no forma parte de esta tarea**. El sistema debe quedar preparado para recibirla sin cambiar código: durante esta fase se usa un placeholder claramente marcado.

## 2. Decisiones cerradas

- La camara es desde una perspectiva superior estilo top/down pero no completamente cenital, sino con una rotacion del 40%
- El único disparador de cinemática es el ataque del Sombreron.
- La condición exacta de disparo es la que ya existe: `_find_hunt_target_in_attack_area() != null`.
- No se añaden validaciones extra de distancia u orientación que puedan rechazar un ataque que el `AttackArea3D` ya aceptó.
- La cinemática solo se ejecuta si el objetivo es `NPCBase` y `is_hunt_target == true`.
- El jugador y el enemigo **permanecen en su posición mundial actual**. No se teletransporta a ninguno.
- La cámara de gameplay sigue la **forma activa real** (`player.gd → get_active_character()`), no solo `GameState.form`.
- La cámara cinemática se coloca a partir de un `CinematicMarker` que cuelga de `Pivote`, porque solo `model` y `Pivote` rotan hacia la dirección de mirada. El `CharacterBody3D` no rota.
- La animación de cámara se authored en **espacio local** respecto a un nodo animado (`CameraMotion`). El ancla global (`CameraRig`) no se anima.
- Se conserva la pausa del árbol mediante `GameState.begin_cinematic()` / `end_cinematic()`.
- No se usan temporizadores para decidir el final de la cinemática. La autoridad es la animación de cámara y sus eventos.
- La captura se ejecuta en el punto definido por una **pista de método** de la animación de cámara.
- La oclusión usa una capa de física dedicada para geometría oclusora. No se ocultan personajes ni se modifican materiales.
- No se usa `SpringArm3D` en la cámara cinemática.
- Los clips de personaje existentes se reutilizan. No se recrean animaciones importadas.

## 3. Estado actual relevante

### 3.1. Jugador

`Player/player.tscn`:

```text
Player (Node3D, grupo "player")
├── Sombreron (CharacterBody3D, sombreron.gd)
│   ├── Sombreron (escena GLB instanciada)
│   │   ├── SombreronV2
│   │   │   └── Skeleton3D
│   │   ├── AnimationPlayer
│   │   └── Pivote (Marker3D)
│   │       ├── Sprite3D
│   │       └── AttackArea3D
│   ├── CollisionShape3D
│   └── AnimationMarker3D (Marker3D existente)
└── Perro (CharacterBody3D, perro.gd)
	├── Perro (escena GLB instanciada)
	│   ├── Empty → PerroRIG
	│   └── AnimationPlayer
	└── CollisionShape3D2
```

Hechos importantes:

- `Player` es `Node3D` y permanece en su transform de aparición; quien se mueve es `Sombreron` o `Perro`.
- En `sombreron.gd`, solo rotan `model` y `pivote`. El cuerpo `Sombreron` no rota.
- `AttackArea3D` ya está bajo `Pivote` y se resuelve desde `pivote` si no está asignada.
- El nodo `AnimationMarker3D` existente cuelga del `CharacterBody3D`. **No se reutiliza** para la cinemática porque no hereda la rotación del pivote. No eliminarlo sin confirmar que está sin uso.
- `Player` no tiene cámara de gameplay. Solo existen cámaras estáticas en `Environment/map_testing.tscn` y `Scenes/testing.tscn`.

### 3.2. NPC

`NPCSystem/Base/NPCBase.gd`:

- Centraliza movimiento, navegación, percepción y animación.
- `_animation_player` es privado y se resuelve con `_find_animation_player()`.
- `play_animation()` no reproduce clips inexistentes y avisa con `push_warning`.
- `stop_movement()` detiene la navegación y anula la velocidad horizontal.
- `despawn()` oculta, desactiva colisiones y llama a `queue_free()`.
- No existe una API para forzar una animación cinemática ni para restaurar el estado tras ella.

### 3.3. Estado global y caza

- `Game/GameState.gd` es la autoridad de la pausa: `begin_cinematic()` pone `get_tree().paused = true`; `end_cinematic()` lo revierte.
- `Game/HuntManager.gd` es la autoridad de la captura: `complete_current_target()` quita la marca, hace desaparecer al NPC y emite `target_captured`; `continue_hunt()` elige un nuevo objetivo.
- `HuntManager` ya bloquea la selección mientras `GameState.is_cinematic_active` sea verdadero.
- `Game/CinematicPlaceholder.gd` es un placeholder temporal que usa `await` y temporizadores. Debe retirarse.

### 3.4. Animaciones disponibles

| Personaje | Clips |
|---|---|
| Sombreron | `idle`, `walk`, `run`, `dash`, `attack`, `stun` |
| Perro | `idle`, `walk`, `smell` |
| Peleador | `idle`, `walk`, `run`, `attack` |
| Tramposo | `idle`, `walk`, `run`, `attack` |
| NpcBoy | `idle`, `walk`, `run` |

No existen clips de fatality, reacción, ejecución ni captura. La primera cinemática usa `attack` para el jugador y `attack` (con fallback a `idle`) para el enemigo. Los clips animan huesos del esqueleto, no el `CharacterBody3D`; no se debe trasladar el cuerpo para compensar.

## 4. Arquitectura general

| Componente | Responsabilidad |
|---|---|
| `Player` / `player.gd` | Expone la forma activa y notifica cambios. No gestiona cámaras cinemáticas ni pausa. |
| `Sombreron` | Valida el ataque con `AttackArea3D` y **solicita** la cinemática. No cambia cámaras ni captura. |
| `NPCBase` | Ejecuta la animación cinemática asignada y se detiene durante la secuencia. |
| `CinematicMarker` | Proporciona la referencia espacial global para la cámara. |
| `CinematicController` | Gestiona el ciclo de vida completo, la pausa, las cámaras y los eventos. |
| `CameraRig` | Recibe el transform global del marcador. **No se anima.** |
| `CameraMotion` | Recibe las pistas locales de la animación de cámara. |
| `CinematicCamera` | Cámara que se activa solo durante la cinemática. |
| `CameraOcclusionController` | Detecta y oculta geometría que obstruye la vista. |
| `AnimationPlayer` del controller | Timeline de cámara y eventos sincronizados. |
| `GameState` | Autoridad única de la pausa global. |
| `HuntManager` | Autoridad única de la captura y la continuación de la caza. |

Regla central:

> El ataque solo **solicita** la cinemática. Toda transición, pausa, cambio de cámara, captura y restauración vive en `CinematicController`.

## 5. Cámara de gameplay

### 5.1. Estructura en `Player`

Añadir al final de `Player/player.tscn`:

```text
Player
└── GameplayCameraPivot (Node3D, player_follow_camera.gd)
	└── GameplayCamera (Camera3D)
```

- `GameplayCameraPivot` es el nodo que se mueve y orienta.
- `GameplayCamera` es la cámara hija, en transform local identidad.
- La cámara debe unirse al grupo `gameplay_camera` para que el controller pueda restaurarla como respaldo.
- La cámara se marca `current = true` en `_ready()`.

### 5.2. Comportamiento

`Player/Scripts/player_follow_camera.gd`, `extends Node3D`:

- Obtiene el personaje activo con `player.gd → get_active_character()`.
- Sigue su `global_position` con un desplazamiento configurable y suavizado.
- Mira hacia `target.global_position + Vector3.UP * look_height`.
- Se actualiza en `_physics_process(delta)` para ir sincronizada con el movimiento de los `CharacterBody3D`.
- Al cambiar de forma, **hace snap** al nuevo objetivo para evitar un viaje largo entre posiciones. Durante el movimiento normal, interpola.
- Si el objetivo no es válido, no hace nada y conserva la última posición.
- No depende de `GameState.form`; depende del nodo activo real.
- No usa `SpringArm3D` en esta fase. La colisión de la cámara de gameplay queda fuera de alcance.

Parámetros exportados sugeridos:

```gdscript
@export var offset: Vector3 = Vector3(0.0, 5.5, 9.0)
@export var look_height: float = 1.0
@export var follow_speed: float = 8.0
@export var snap_distance: float = 3.0
```

El `offset` es mundial, no relativo a la rotación del personaje. Esto conserva una vista estable y evita desorientación sin ratón. Los valores son ajustables desde el Inspector.

### 5.3. Forma activa en `player.gd`

Añadir:

```gdscript
signal active_character_changed(character: Node3D)

func get_active_character() -> Node3D:
	return sombreron if current_character == Character.SOMBRERON else perro
```

- Emitir `active_character_changed.emit(get_active_character())` al final de `control_dog()` y `control_sombreron()`, después de actualizar `current_character`.
- Emitir también una vez al final de `_ready()`, cuando la cámara ya está conectada.
- No cambiar la lógica de `GameState.set_form()` ni el bloqueo de cambio de forma.

### 5.4. Cámaras estáticas

- Eliminar la `Camera3D` estática de `Environment/map_testing.tscn`.
- Eliminar la `Camera3D` estática de `Scenes/testing.tscn`.
- Verificar antes que ningún script las referencia. Actualmente solo existen en esas escenas.
- Si se decide conservarlas por algún motivo, poner `current = false` y asegurarse de que `GameplayCamera` sea la cámara activa al iniciar.

## 6. `CinematicMarker`

### 6.1. Ubicación

Añadir un `Marker3D` llamado `CinematicMarker` en `Player/sombreron.tscn`, como hijo de `Pivote`, junto a `AttackArea3D`:

```text
Pivote (Marker3D)
├── Sprite3D
├── AttackArea3D
└── CinematicMarker (Marker3D)
```

Transform sugerido:

```text
position = (0.0, 1.2, 0.0)
rotation = (0.0, 0.0, 0.0)
```

- La altura de 1.2 m es una referencia de pecho; la animación de cámara se authored relativa a este punto.
- El eje local `+Z` del marcador coincide con la dirección de mirada del jugador, porque `Pivote` se rota con `basis.z` como frente.
- Una vez authored la animación definitiva, **no mover el marcador** sin revisar el encuadre.

### 6.2. Por qué no cuelga del cuerpo

- `Sombreron` es un `CharacterBody3D` que no rota.
- `model` y `Pivote` son los que rotan hacia la dirección de movimiento.
- Si el marcador cuelga del cuerpo, la cámara no hereda la orientación del jugador y el encuadre cambia según la última rotación del pivote.
- Por eso el marcador debe colgar de `Pivote`.

### 6.3. Acceso

Añadir a `sombreron.gd`:

```gdscript
@export var cinematic_marker: Marker3D

func get_cinematic_marker() -> Marker3D:
	if cinematic_marker != null:
		return cinematic_marker
	if pivote != null:
		cinematic_marker = pivote.get_node_or_null("CinematicMarker") as Marker3D
	return cinematic_marker
```

- Si el export queda vacío, se resuelve desde `Pivote`.
- Si no existe, el controller rechaza la cinemática y el ataque cae al flujo normal.
- No usar una ruta absoluta desde `Player`; la referencia se resuelve dentro de la escena del personaje.

## 7. `CinematicController`

### 7.1. Escena

Crear `Game/Cinematics/CinematicController.tscn`:

```text
CinematicController (Node3D)
├── CameraRig (Node3D)
│   └── CameraMotion (Node3D)
│       └── CinematicCamera (Camera3D)
├── AnimationPlayer
└── CameraOcclusionController (Node)
```

Requisitos de la escena:

- `CinematicController.process_mode = PROCESS_MODE_ALWAYS` (valor `3`).
- Grupo `cinematic_controller`.
- `CameraRig.top_level = true` para que su transform global no dependa del transform del controller.
- `CameraRig` **no se anima**.
- `CameraMotion` contiene un transform local de referencia ("home"), por ejemplo:

  ```text
  position = (0.0, 2.2, -3.8)
  rotation = (0.0, PI, 0.0)
  ```

  Este transform es solo una vista previa y un respaldo. La animación debe escribir sus propias claves desde `t = 0`.
- `CinematicCamera.current = false` por defecto y `fov = 70.0`.
- `AnimationPlayer.process_mode = PROCESS_MODE_ALWAYS`, `root_node = ".."` (el propio controller). No cambiar `root_node` sin actualizar las rutas de las pistas.
- `CameraOcclusionController.process_mode = PROCESS_MODE_ALWAYS`.

Instanciar el controller en `Environment/map_testing.tscn` como nodo hermano de `Player` y de `Npcs`. No registrarlo como autoload: es un nodo 3D con cámara y transform mundial; debe vivir en la escena del mapa.

### 7.2. Separación `CameraRig` / `CameraMotion`

Es obligatoria. Las pistas de un `AnimationPlayer` escriben valores **locales absolutos**, no valores relativos al transform actual del nodo.

Ejemplo del problema:

- El marcador está en el mundo en `(10, 0, 5)`.
- Se asigna `CameraRig.global_transform = marker.global_transform`.
- La animación escribe `CameraRig:position = (0, 2, -4)`.
- Resultado: el rig salta a `(0, 2, -4)`, no a `(10, 2, 1)`.

Solución:

- `CameraRig` recibe `marker.global_transform` y no se anima.
- `CameraMotion` es hijo de `CameraRig` y recibe las pistas locales de posición, rotación y FOV.
- El resultado final es `marker.global_transform * animación_local`, lo que permite reutilizar el mismo clip en cualquier lugar del mapa.

### 7.3. Máquina de estados

```gdscript
enum State {
	IDLE,
	PREPARING,
	PLAYING,
	RESTORING,
}
```

| Estado | Responsabilidad |
|---|---|
| `IDLE` | Juego normal. Se puede solicitar una cinemática. |
| `PREPARING` | Valida participantes, guarda cámara y estados, detiene movimiento, coloca el rig y activa la cámara cinemática. |
| `PLAYING` | Reproduce la animación de cámara y las animaciones de personaje; espera el evento de captura y el final. |
| `RESTORING` | Restaura oclusión, cámara, `process_mode`, control, estados de personaje y pausa. |

Reglas:

- Solo puede haber una cinemática a la vez.
- Si `_state != IDLE` o `GameState.is_cinematic_active`, `play_cinematic()` devuelve `false`.
- Las solicitudes recibidas durante `PREPARING`, `PLAYING` o `RESTORING` se rechazan.
- `finish_cinematic()` solo es válido desde `PLAYING`. Si se llama en `PREPARING`, se trata como cancelación.
- `cancel_cinematic()` restaura sin capturar y sin elegir un nuevo objetivo.

### 7.4. API

```gdscript
class_name CinematicController
extends Node3D

signal cinematic_started(id: StringName, attacker: Node3D, target: Node3D)
signal cinematic_finished(id: StringName, captured: bool)
signal cinematic_cancelled(id: StringName)

func play_cinematic(
	attacker: Node3D,
	target: Node3D,
	cinematic_id: StringName
) -> bool

func finish_cinematic() -> void
func cancel_cinematic() -> void
func is_playing() -> bool
```

`play_cinematic()` devuelve `true` solo si la secuencia quedó iniciada. Si falta el controller, el marcador, la definición o la animación, devuelve `false` y registra un aviso; el atacante decide el fallback.

### 7.5. Flujo detallado

1. `Sombreron.start_attack()` detecta el objetivo en `AttackArea3D`.
2. Solicita `controller.play_cinematic(self, target, cinematic_id)`.
3. `play_cinematic()` valida:
   - que no haya otra cinemática;
   - que `GameState.is_cinematic_active` sea `false`;
   - que `target` sea `NPCBase`, `is_hunt_target` y `HuntManager.current_target`;
   - que exista la definición `cinematic_id`;
   - que `attacker.get_cinematic_marker()` devuelva un marcador válido;
   - que exista la animación de cámara (o se pueda generar el placeholder).
4. `PREPARING`:
   - guarda `get_viewport().get_camera_3d()` como cámara de gameplay;
   - guarda `process_mode` y `speed_scale` de los `AnimationPlayer` de los participantes;
   - detiene el movimiento del atacante y del objetivo;
   - asigna `CameraRig.global_transform = marker.global_transform`;
   - aplica el transform "home" a `CameraMotion`;
   - activa `CinematicCamera.current = true`;
   - activa la oclusión;
   - llama a `GameState.begin_cinematic()` (pausa el árbol);
   - reproduce la animación de cámara y las animaciones de personaje;
   - pasa a `PLAYING` y emite `cinematic_started`.
5. `PLAYING`:
   - la animación de cámara avanza con el árbol pausado;
   - la pista de método en el punto de captura llama a `_on_cinematic_capture()`;
   - la pista de método final o `animation_finished` llama a `finish_cinematic()`;
   - no se usan temporizadores.
6. `RESTORING`:
   - detiene la animación de cámara;
   - detiene y restaura la oclusión;
   - restaura `process_mode` y `speed_scale` de los `AnimationPlayer`;
   - llama a `attacker.end_cinematic()` y, si sigue vivo, a `target.end_cinematic()`;
   - desactiva `CinematicCamera` y reactiva la cámara guardada;
   - llama a `GameState.end_cinematic()`;
   - llama a `HuntManager.continue_hunt()`;
   - emite `cinematic_finished`;
   - vuelve a `IDLE` y limpia referencias.

### 7.6. Pausa y `process_mode`

- `GameState` sigue siendo la única autoridad de la pausa.
- `CinematicController`, su `AnimationPlayer` y `CameraOcclusionController` deben ser `PROCESS_MODE_ALWAYS`.
- Los `AnimationPlayer` de los personajes se cambian temporalmente a `PROCESS_MODE_ALWAYS` durante la cinemática y se restauran al terminar. Guardar el valor original.
- **No** poner `Player`, `Sombreron`, `Perro` ni `NPCBase` completos en `PROCESS_MODE_ALWAYS`: eso permitiría que su lógica de movimiento o IA siguiera ejecutándose.
- No desactivar `_physics_process` indiscriminadamente. La pausa del árbol ya detiene el movimiento y la IA; solo se necesita `ALWAYS` en animaciones, cámara y oclusión.
- El `AnimationPlayer` de cámara debe tener el loop desactivado para que `animation_finished` o el evento final se disparen.

### 7.7. Restauración y cancelación

`finish_cinematic()`:

- Restaura todo y luego reanuda la caza.
- Si el objetivo fue capturado, `_target` puede haber quedado libre por `queue_free()`. Usar `is_instance_valid()` antes de restaurar su animación o estado.
- Si la cámara guardada ya no es válida, buscar una cámara en el grupo `gameplay_camera`; si tampoco existe, registrar un aviso.
- Llamar a `GameState.end_cinematic()` antes de `HuntManager.continue_hunt()`, porque `continue_hunt()` comprueba `is_cinematic_active`.

`cancel_cinematic()`:

- Restaura cámara, visibilidad, `process_mode`, control y estados.
- No captura.
- No llama a `HuntManager.continue_hunt()`: el objetivo actual sigue siendo válido y el jugador puede volver a atacar.
- Emite `cinematic_cancelled`.
- Debe ser seguro llamarlo desde `_exit_tree()` si la escena se cierra durante una cinemática.

### 7.8. Señales

- `cinematic_started`: para HUD, audio o efectos futuros.
- `cinematic_finished`: incluye si hubo captura.
- `cinematic_cancelled`: para limpiar estado temporal.

Los listeners deben ser de solo lectura. Ningún otro sistema debe iniciar su propia captura, cambiar cámaras o llamar a `GameState.begin_cinematic()`.

## 8. Definiciones de cinemática

Crear `Game/Cinematics/CinematicDefinition.gd`:

```gdscript
class_name CinematicDefinition
extends Resource

@export var id: StringName = &""
@export var camera_animation: StringName = &""
@export var attacker_animation: StringName = &"attack"
@export var target_animation: StringName = &"attack"
```

- `id`: identificador que usa el atacante al solicitar la cinemática.
- `camera_animation`: nombre del `Animation` dentro de la librería `cinematics` del controller.
- `attacker_animation`: clip existente del jugador.
- `target_animation`: clip existente del enemigo; si no existe, se usa `idle`.

Crear `Game/Cinematics/Definitions/captura_sombreron.tres` con:

```text
id = "captura_sombreron"
camera_animation = "captura_sombreron"
attacker_animation = "attack"
target_animation = "attack"
```

El controller expone:

```gdscript
@export var definitions: Array[CinematicDefinition] = []
```

y construye un diccionario `id → definición` en `_ready()`. Si un `id` se repite, conservar el primero y registrar un aviso.

En `sombreron.gd`, exponer el id para poder cambiarlo desde el Inspector:

```gdscript
@export var cinematic_id: StringName = &"captura_sombreron"
```

No hardcodear el id dentro de la lógica del ataque más allá de este valor por defecto.

## 9. Animación de cámara

### 9.1. Contrato para la animación definitiva

La animación que se authored más adelante debe cumplir:

- Nombre: el definido en `CinematicDefinition.camera_animation`.
- Librería: `cinematics` en el `AnimationPlayer` del controller.
- `root_node`: el controller (`".."` respecto al `AnimationPlayer`).
- Loop: desactivado.
- Pistas relativas a `CameraMotion`:

  ```text
  CameraRig/CameraMotion:position
  CameraRig/CameraMotion:rotation   (o rotation_quaternion)
  CameraRig/CameraMotion/CinematicCamera:fov   (opcional)
  ```

- Claves en `t = 0` y en el final. No confiar en el transform previo del nodo.
- Pista de método en el instante de captura:

  ```text
  Ruta: "."
  Método: _on_cinematic_capture
  Argumentos: []
  ```

- Pista de método al final, o confiar en `animation_finished`:

  ```text
  Ruta: "."
  Método: _on_cinematic_animation_end
  Argumentos: []
  ```

- La duración de la animación de cámara es la duración de la cinemática. No usar `attack_duration` para esto.
- La animación debe encuadrar a ambos personajes en sus posiciones actuales. No debe asumir coordenadas mundiales fijas.

### 9.2. Placeholder temporal

Mientras la animación definitiva no exista, el controller debe generar un placeholder para no bloquear la implementación:

- `@export var generate_placeholder_if_missing: bool = true`.
- `@export var placeholder_duration: float = 3.0`.
- `@export var placeholder_capture_time: float = 1.5`.
- Si la librería `cinematics` no existe, crearla con `AnimationLibrary.new()`.
- Si la animación no existe y el flag está activo, crear un `Animation` con:
  - `length = placeholder_duration`;
  - `loop_mode = Animation.LOOP_NONE`;
  - una pista de posición con un arco simple alrededor del marcador;
  - una pista de rotación en cuaterniones;
  - una pista de FOV opcional;
  - una pista de método en `placeholder_capture_time` que llame a `_on_cinematic_capture`;
  - una pista de método en `placeholder_duration` que llame a `_on_cinematic_animation_end`.
- Añadir la animación a la librería `cinematics` con el nombre de la definición.
- Marcar el bloque con un comentario `# PLACEHOLDER TEMPORAL`.
- Si la animación definitiva ya existe en la librería, **no generar nada**: la definitiva tiene prioridad.
- El placeholder debe ser reemplazable sin cambiar el código. Cuando se authored la animación real, basta con crearla en el editor con el mismo nombre; el generador deja de actuar.

El placeholder no es la cinemática final. No debe considerarse contenido definitivo ni usarse para evaluar el encuadre final.

### 9.3. Final de la cinemática

- La animación de cámara es la autoridad del final.
- Preferir la pista de método final `_on_cinematic_animation_end`.
- Conectar también `AnimationPlayer.animation_finished` como respaldo, normalizando el nombre si incluye el prefijo de la librería.
- Proteger contra doble finalización comprobando `_state == PLAYING`.
- No usar `await get_tree().create_timer()` ni `Timer` para terminar la cinemática.
- Si la animación no tiene evento de captura, registrar un aviso. No capturar por temporizador.

### 9.4. Flujo de authoring futuro

1. Verificar los clips de personaje disponibles.
2. Crear el `Animation` en la librería `cinematics`.
3. Animar `CameraMotion` en local, no `CameraRig`.
4. Encuadrar a jugador y enemigo en sus posiciones actuales.
5. Añadir la pista de método de captura en el punto elegido.
6. Añadir el evento final.
7. Probar el mismo clip en dos ubicaciones distintas del mapa.
8. Probar la oclusión.
9. Verificar que el juego se restaura correctamente.

## 10. Animaciones de personaje

### 10.1. Reglas generales

- Usar los `AnimationPlayer` existentes de cada personaje.
- No recrear animaciones que ya existen en los GLTF importados.
- No modificar los recursos importados ni los `.import` sin necesidad.
- Reproducir el clip con `speed_scale = 1.0` durante la cinemática.
- Desactivar el loop en los clips cinemáticos; los clips actuales `attack` ya son no loop.
- No mover el `CharacterBody3D` para compensar el root motion. Los clips actuales animan el hueso `Base`, no el cuerpo.
- Si un clip provoca un desplazamiento visible no deseado, usar una variante in-place o neutralizar la pista del hueso raíz. No teletransportar al personaje.
- Si el clip solicitado no existe, usar `idle` como fallback y registrar un aviso.

### 10.2. API del jugador (`sombreron.gd`)

Añadir:

```gdscript
func get_animation_player() -> AnimationPlayer
func begin_cinematic(animation_name: StringName) -> void
func end_cinematic() -> void
```

`begin_cinematic()`:

- Guarda si el personaje estaba controlado.
- Llama a `set_controlled(false)` y anula la velocidad horizontal.
- Anula `action_timer`.
- Reproduce el clip solicitado si existe; si no, `idle`.
- No cambia de cámara ni captura.

`end_cinematic()`:

- Anula `action_timer`.
- Fuerza el estado local a `IDLE` y reproduce `idle` (no confiar en el early-return de `change_state()`).
- Restaura el control solo si estaba controlado antes de la cinemática.

El ataque con objetivo **no** debe entrar en el estado local `ATTACK` con `action_timer = attack_duration`. La duración la define la animación de cámara. El estado `ATTACK` y `attack_duration` quedan solo para el fallback sin controller.

### 10.3. API del NPC (`NPCBase.gd`)

Añadir:

```gdscript
func get_animation_player() -> AnimationPlayer
func begin_cinematic(animation_name: StringName) -> bool
func end_cinematic() -> void
```

`begin_cinematic()`:

- Llama a `stop_movement()` y anula `velocity`.
- Reproduce el clip solicitado si existe.
- Si no existe, intenta `idle`.
- Devuelve `true` si pudo reproducir algo; `false` si no hay `AnimationPlayer`.

`end_cinematic()`:

- Reproduce `idle_animation`.
- No reinicia la persecución ni elige destinos.
- Si el NPC fue capturado y liberado, el controller no debe llamarlo; comprobar `is_instance_valid()`.

No cambiar la lógica de la máquina de estados ni de los comportamientos. La pausa del árbol detiene la IA durante la cinemática.

## 11. Oclusión de cámara

### 11.1. Nodo y API

`Game/Cinematics/CinematicOcclusionController.gd`, `extends Node`:

```gdscript
func setup(camera: Camera3D, attacker: Node3D, target: Node3D) -> void
func start() -> void
func stop() -> void
func clear_target() -> void
```

- `start()` activa las consultas.
- `stop()` restaura toda la geometría modificada y limpia el estado.
- `clear_target()` se llama cuando el objetivo es capturado y liberado; a partir de ese momento solo se ocluye respecto al jugador.
- `process_mode = PROCESS_MODE_ALWAYS`.

### 11.2. Capa de oclusión

- Añadir en `project.godot`:

  ```ini
  [layer_names]
  3d_physics/layer_1="world"
  3d_physics/layer_2="camera_occluder"
  ```

- La capa 2 (`valor de bit 2`) es exclusiva para geometría que puede ocultar la cámara.
- En `Environment/map_testing.tscn`, poner `collision_layer = 3` en cada `CSGBox3D` con `use_collision = true`. El valor 3 significa capas 1 y 2:
  - sigue colisionando con los personajes, que están en la capa 1;
  - el rayo de oclusión, con máscara 2, lo detecta.
- Los personajes permanecen en la capa 1. No es necesario cambiar sus capas.
- Los props futuros que deban ocluir se configuran con la capa 2 incluida.
- El rayo usa `collision_mask = 2` y `collide_with_bodies = true`, `collide_with_areas = false`.
- Excluir además los RID del atacante y del objetivo, y todos los cuerpos de los grupos `player` y `npc`, como defensa adicional.

### 11.3. Rayos y puntos

Lanzar varios rayos desde la cámara hacia puntos relevantes:

- pecho del jugador;
- cabeza del jugador;
- pecho del enemigo;
- cabeza del enemigo.

Los puntos se calculan con alturas exportadas:

```gdscript
@export var player_chest_height: float = 1.0
@export var player_head_height: float = 1.8
@export var enemy_chest_height: float = 1.0
@export var enemy_head_height: float = 1.7
```

- Usar `attacker.global_position + Vector3.UP * altura`.
- Si el enemigo ya no es válido, no lanzar sus rayos.
- No usar un solo rayo. Varios rayos evitan que una esquina o un prop pequeño deje la vista bloqueada.

### 11.4. Detección y ocultamiento

Para cada impacto:

1. Resolver el `GeometryInstance3D` más cercano subiendo por los padres del `collider`. Un `CSGBox3D` es un `GeometryInstance3D`; si el collider es un cuerpo interno, su padre puede ser el CSG.
2. Ignorar el jugador, el enemigo y la cámara.
3. Guardar el estado original del oclusor.
4. Ocultarlo.

Implementación inicial:

- `visible = false` y guardar `visible` original.
- Verificar que el CSG conserva su colisión al ocultarse. La colisión de CSG es independiente de la visibilidad, pero debe comprobarse en el mapa.
- Si se detecta que el CSG pierde colisión, usar `GeometryInstance3D.transparency = 1.0` y guardar/restaurar `transparency`. Esta propiedad no modifica materiales ni colisión.
- No modificar `material_override`, `material_overlay` ni los recursos de material.
- No ocultar el jugador ni el enemigo.

### 11.5. Restauración y objetos liberados

- Mantener un diccionario de oclusores activos.
- Usar `instance_id` como clave y `WeakRef` o `is_instance_valid()` para el nodo. No conservar referencias fuertes a objetos que pueden ser liberados.
- En cada actualización:
  - construir el conjunto de oclusores actuales;
  - ocultar los nuevos;
  - restaurar los que ya no ocluyen;
  - eliminar del diccionario los objetos liberados.
- Al terminar o cancelar, restaurar **todos** los oclusores.
- Si un objeto se libera mientras está oculto, no intentar restaurarlo; simplemente eliminarlo del diccionario.

### 11.6. Frecuencia

- No hacer raycasts ni toggles cada frame.
- Usar un intervalo exportado, por ejemplo `refresh_interval = 0.08` segundos, acumulando `delta` en `_physics_process`.
- Solo cambiar la visibilidad cuando el conjunto de oclusores cambie.
- Evitar parpadeos: no ocultar y restaurar el mismo objeto en frames consecutivos si sigue ocluyendo.

### 11.7. Límites

- No mover la cámara para evitar obstáculos.
- No usar `SpringArm3D`.
- No alterar la animación authored.
- No ocultar objetos que no estén en la capa de oclusión.
- No usar transparencia gradual en la primera versión; queda como mejora opcional.

## 12. Integración con ataque, `GameState` y `HuntManager`

### 12.1. `sombreron.gd`

`start_attack()` debe quedar así:

```gdscript
func start_attack() -> void:
	var target := _find_hunt_target_in_attack_area()

	if target == null:
		_prepare_attack_miss_effect()
		return

	var controller := get_tree().get_first_node_in_group(&"cinematic_controller")

	if controller != null and controller.play_cinematic(self, target, cinematic_id):
		return

	# Fallback: no hay controller o la cinemática no pudo iniciarse.
	push_warning("Ataque sin cinemática: se ejecuta el ataque normal sin captura.")
	action_timer = attack_duration
	velocity.x = 0.0
	velocity.z = 0.0
	change_state(State.ATTACK)
```

- Eliminar la llamada directa a `GameState.begin_cinematic()`.
- No cambiar `_find_hunt_target_in_attack_area()`.
- No añadir validaciones que dupliquen el `AttackArea3D`.
- El fallback existe para escenas sin controller y para errores de configuración; no debe capturar.

### 12.2. `GameState`

No cambiar su contrato:

- `begin_cinematic()` pausa y marca el estado.
- `end_cinematic()` reanuda y limpia el estado.
- `is_cinematic_active` sigue siendo la bandera global.

El controller es el único que llama a estos métodos durante una cinemática. No añadir una segunda bandera de pausa en el controller.

### 12.3. `HuntManager`

No cambiar su contrato. El controller:

- llama a `HuntManager.complete_current_target()` en el evento de captura;
- verifica antes que `target == HuntManager.current_target` y que el objetivo sigue siendo válido;
- llama a `HuntManager.continue_hunt()` al finalizar, después de `GameState.end_cinematic()`;
- no elige objetivos por su cuenta.

`complete_current_target()` hace `queue_free()` del NPC. A partir de ese momento, el controller y la oclusión deben comprobar `is_instance_valid()` antes de usar la referencia.

### 12.4. Retirar el placeholder anterior

- Eliminar el nodo `CinematicPlaceholder` de `Environment/map_testing.tscn`.
- Eliminar `Game/CinematicPlaceholder.gd`.
- Verificar que no quede ninguna conexión a `GameState.cinematic_state_changed` que inicie una captura.
- `GameState.cinematic_state_changed` puede seguir existiendo para HUD/audio futuros, pero ningún sistema debe iniciar su propia cinemática al recibirlo.

## 13. Archivos

### Nuevos

- `Game/Cinematics/CinematicController.gd`
- `Game/Cinematics/CinematicController.tscn`
- `Game/Cinematics/CinematicDefinition.gd`
- `Game/Cinematics/CinematicOcclusionController.gd`
- `Game/Cinematics/Definitions/captura_sombreron.tres`
- `Player/Scripts/player_follow_camera.gd`

### Modificados

- `Player/player.tscn`: añadir `GameplayCameraPivot` + `GameplayCamera`; conservar `AnimationMarker3D`.
- `Player/Scripts/player.gd`: señal `active_character_changed` y `get_active_character()`.
- `Player/sombreron.tscn`: añadir `CinematicMarker` bajo `Pivote`; conservar `AttackArea3D` y `Sprite3D`.
- `Player/Scripts/sombreron.gd`: `cinematic_id`, `get_cinematic_marker()`, `get_animation_player()`, `begin_cinematic()`, `end_cinematic()` y nuevo flujo de `start_attack()`.
- `NPCSystem/Base/NPCBase.gd`: API pública de animación y cinemática.
- `Environment/map_testing.tscn`: quitar cámara estática y placeholder; instanciar `CinematicController`; poner `collision_layer = 3` en los CSG.
- `Scenes/testing.tscn`: quitar la cámara estática o dejarla con `current = false`.
- `project.godot`: nombres de capas 3D.

### Eliminados

- `Game/CinematicPlaceholder.gd`
- Nodo `CinematicPlaceholder` en `Environment/map_testing.tscn`

### Sin cambios

- `Game/GameState.gd` (salvo que se detecte un bug real).
- `Game/HuntManager.gd`.
- `NPCSystem/Components/NPCPerception.gd`.
- `NPCSystem/States/*`.
- `NPCSystem/Behaviors/*`.
- Recursos `.glb`, `.import`, materiales y texturas.

## 14. Orden de implementación

### Fase 0 — Verificación base

- Ejecutar el proyecto en headless y confirmar que arranca sin errores de script.
- Confirmar que el aviso del renderer dummy por CSG es preexistente y no un error nuevo.

### Fase 1 — Cámara de gameplay

- Añadir `GameplayCameraPivot` + `GameplayCamera` a `player.tscn`.
- Implementar `player_follow_camera.gd`.
- Añadir la señal y el getter en `player.gd`.
- Eliminar o desactivar las cámaras estáticas.
- Probar el seguimiento en Sombreron y Perro, y el snap al cambiar de forma.

### Fase 2 — Ciclo de vida de la cinemática

- Crear `CinematicMarker` bajo `Pivote`.
- Crear `CinematicDefinition` y `CinematicController` con la máquina de estados.
- Implementar la guarda y restauración de cámara, `process_mode`, control y pausa.
- Integrar `sombreron.gd` con el controller.
- Retirar `CinematicPlaceholder`.
- Probar una cinemática sin animación real, con una duración mínima.

### Fase 3 — Animaciones y captura

- Implementar el placeholder de animación de cámara.
- Reproducir `attack`/`idle` en jugador y enemigo.
- Añadir la pista de método de captura y el evento final.
- Integrar `HuntManager.complete_current_target()` y `continue_hunt()`.
- Verificar que los personajes no se mueven de su posición mundial.

### Fase 4 — Oclusión

- Añadir la capa de oclusión y configurar los CSG.
- Implementar rayos múltiples, ocultamiento y restauración.
- Probar muros, props y objetos liberados.
- Verificar que no se ocultan personajes ni se modifican materiales.

### Fase 5 — Reutilización y robustez

- Probar el mismo clip de cámara en dos ubicaciones distintas.
- Probar ejecuciones repetidas.
- Probar rechazos por controller ausente, marcador ausente y animación ausente.
- Probar cancelación y cierre de escena durante la cinemática.
- Verificar que no queda estado residual.

## 15. Pruebas

### 15.1. Smoke test headless

```bash
/home/sergiopc2/Apps/godot/Godot_v4.3-stable_linux.x86_64 --headless --path . --quit
```

Criterios:

- Código de salida `0`.
- Sin errores de script.
- El aviso del renderer dummy sobre CSG es aceptable y preexistente; no debe aparecer un error nuevo de GDScript.

### 15.2. Pruebas manuales

1. Iniciar `Environment/map_testing.tscn`.
2. Confirmar que la cámara de gameplay es la activa y sigue al Sombreron al caminar, correr y hacer dash.
3. Cambiar a Perro y confirmar que la cámara lo sigue y hace snap.
4. Volver a Sombreron y confirmar que la cámara vuelve a seguirlo.
5. Atacar sin objetivo de caza en `AttackArea3D`:
   - no se reproduce `attack`;
   - no se pausa el juego;
   - se llama a `_prepare_attack_miss_effect()`.
6. Atacar con el objetivo de caza dentro del área:
   - se activa la cámara cinemática;
   - el árbol queda pausado;
   - el jugador y el enemigo no se mueven de su posición mundial;
   - ambos reproducen sus clips;
   - la captura ocurre en el punto de la pista de método;
   - el objetivo desaparece en ese punto;
   - la cámara vuelve a la de gameplay;
   - el control y la IA se restauran;
   - se elige un nuevo objetivo o se emite `hunt_finished`.
7. Repetir la cinemática en otra ubicación del mapa y confirmar que el mismo clip local funciona.
8. Colocar un muro entre la cámara y los personajes:
   - la geometría se oculta;
   - se restaura al dejar de ocluir;
   - no se modifican materiales;
   - no se ocultan los personajes.
9. Cancelar una cinemática en curso:
   - se restaura la cámara, la visibilidad y el control;
   - no hay captura;
   - el objetivo actual sigue válido.
10. Ejecutar la cinemática varias veces y confirmar que no hay controladores duplicados ni pausa residual.

### 15.3. Comprobaciones de estado

- `get_viewport().get_camera_3d()` es la cámara de gameplay antes y después de la cinemática.
- `get_tree().paused == false` después de terminar o cancelar.
- `GameState.is_cinematic_active == false` después de terminar o cancelar.
- `HuntManager.current_target` es el objetivo esperado después de `continue_hunt()`.
- Los `AnimationPlayer` de los personajes recuperan su `process_mode` original.
- La visibilidad de todos los oclusores coincide con la original.

## 16. Criterios de aceptación

- [ ] La cámara de gameplay sigue al Sombreron en juego normal.
- [ ] La cámara de gameplay sigue al Perro al cambiar de forma.
- [ ] Al volver a Sombreron, la cámara lo sigue sin errores.
- [ ] La cámara de gameplay es la única cámara activa en juego normal.
- [ ] El ataque sin objetivo en `AttackArea3D` no inicia cinemática ni reproduce el ataque.
- [ ] El ataque con objetivo de caza en `AttackArea3D` inicia la cinemática.
- [ ] La cinemática solo se puede iniciar una vez a la vez.
- [ ] El jugador y el enemigo permanecen en su posición mundial.
- [ ] La cámara cinemática se coloca usando `CinematicMarker`.
- [ ] `CameraRig` no se anima; `CameraMotion` recibe las pistas locales.
- [ ] El mismo clip de cámara funciona en distintas ubicaciones del mapa.
- [ ] Las animaciones de personaje usan los clips existentes.
- [ ] La captura ocurre en la pista de método definida.
- [ ] La animación de cámara o su evento final determina el final.
- [ ] No se usan temporizadores para la duración de la cinemática.
- [ ] La geometría oclusora se oculta y se restaura.
- [ ] No se ocultan el jugador ni el enemigo.
- [ ] No se modifican materiales para la oclusión.
- [ ] La cámara de gameplay se restaura al terminar.
- [ ] El control del jugador y la IA del enemigo se restauran.
- [ ] `GameState` y `HuntManager` conservan su flujo actual.
- [ ] La caza continúa o termina correctamente tras la captura.
- [ ] Cancelar una cinemática deja el juego en un estado seguro.
- [ ] Varias ejecuciones no dejan estado residual.
- [ ] El proyecto arranca en headless sin errores de script.

## 17. Fuera de alcance

- Authoring de la animación definitiva de cámara. Se implementa el placeholder y el contrato.
- Creación de clips GLTF de fatality, reacción, ejecución o captura.
- Combate, daño o muerte de NPCs que no sean el objetivo.
- Cámara de gameplay con colisión, órbita o control por ratón.
- Oclusión de la cámara de gameplay.
- Transparencia gradual de oclusores; la primera versión usa visibilidad.
- Evento futuro que desbloquee el cambio de forma.
- Reaparición de NPCs.
- Nuevos objetivos de caza o cambios en `HuntManager`.
- Multijugador.
- Cambios en la percepción o en los comportamientos de NPC.

## 18. Reglas para el agente implementador

1. Leer `GENERAL_AGENTS.md`, `NPCS_AGENTS.md` y este documento antes de modificar código.
2. Mantener la pausa centralizada en `GameState` y la captura centralizada en `HuntManager`.
3. No duplicar la lógica de selección de objetivos ni la de pausa.
4. No teletransportar al jugador ni al enemigo.
5. No animar `CameraRig`; animar `CameraMotion`.
6. No usar `SpringArm3D` en la cámara cinemática.
7. No usar temporizadores para el final de la cinemática.
8. No modificar recursos importados ni materiales para la oclusión.
9. Usar GDScript tipado y comentarios en español.
10. Preferir señales para comunicación entre sistemas y referencias exportadas para nodos locales.
11. Para el controller entre escenas, usar el grupo `cinematic_controller`; no usar rutas absolutas.
12. Comprobar `is_instance_valid()` antes de usar referencias a NPCs que pueden ser liberados.
13. Restaurar siempre cámara, visibilidad, `process_mode`, `speed_scale`, control y pausa.
14. Verificar el proyecto en headless antes de finalizar.
15. No eliminar el `AnimationMarker3D` existente ni otros cambios del árbol de trabajo sin confirmarlo.
16. Documentar las funciones públicas nuevas y los puntos de extensión.
17. Mantener el alcance: no implementar la animación definitiva ni clips nuevos en esta tarea.

## 19. Diferencias con el documento de referencia

| Documento de referencia | Adaptación a este proyecto |
|---|---|
| La cinemática se activa con un ataque especial genérico. | Solo se activa con el ataque del Sombreron y solo si el objetivo de caza está en `AttackArea3D`. |
| El `CinematicMarker` cuelga del jugador. | Cuelga de `Pivote`, porque el `CharacterBody3D` no rota. |
| El `CameraRig` recibe el transform del marcador y se anima directamente. | Se separa en `CameraRig` (ancla global, no animada) y `CameraMotion` (animación local). |
| La pausa se gestiona dentro del sistema cinemático. | Se conserva `GameState.begin_cinematic()` / `end_cinematic()` como autoridad única. |
| Se asumen animaciones de fatality y reacción. | Se usan los clips existentes `attack`/`idle`; la animación definitiva de cámara se authored después. |
| La oclusión puede usar cualquier geometría. | Se usa una capa de física dedicada (`camera_occluder`) para no ocultar personajes ni props no configurados. |
| No se menciona cámara de gameplay. | Se añade una cámara de seguimiento para Sombreron y Perro, separada de la cinemática. |
| El controller puede ser un autoload o un nodo de escena. | Se instancia en el mapa como nodo 3D y se localiza por grupo. |
| Se permiten temporizadores como respaldo. | No se usan temporizadores; la animación de cámara y sus eventos son la autoridad. |
