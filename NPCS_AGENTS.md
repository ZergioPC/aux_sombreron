# AGENTS.md — Sistema de NPCs

## 1. Objetivo del sistema

Desarrollar un sistema modular de NPCs en Godot 4 (3D) que permita gestionar sus movimientos, comportamientos, estados, colisiones y reacciones ante eventos del entorno y acciones del jugador.

El sistema debe permitir crear diferentes tipos de NPC reutilizando una arquitectura común, evitando duplicar código y manteniendo independientes las responsabilidades de navegación, comportamiento y gestión de estados.

## 2. Principios de arquitectura

La arquitectura debe cumplir los siguientes principios:

- **Reutilización:** todos los NPC deben compartir una estructura base.
- **Modularidad:** cada sistema debe tener una responsabilidad específica.
- **Extensibilidad:** se deben poder agregar nuevos tipos de NPC, comportamientos y estados sin modificar innecesariamente los sistemas existentes.
- **Independencia:** la clasificación del NPC, su comportamiento y su estado actual deben ser independientes.
- **Configurabilidad:** las propiedades particulares de cada NPC deben poder configurarse desde el Inspector de Godot.
- **Bajo acoplamiento:** los comportamientos no deben implementar directamente los sistemas de navegación, movimiento o animaciones.

## 3. Clasificación de los NPC

Los NPC deben clasificarse al ser instanciados.

Se contemplan dos categorías iniciales:

- **NPC Normal:** personaje que no representa una amenaza directa para el jugador.
- **NPC Enemigo:** personaje que puede representar una amenaza y realizar acciones hostiles.

La clasificación no debe determinar directamente todos los comportamientos del NPC.

Por ejemplo, un NPC enemigo puede tener un comportamiento peleador o tramposo. La clasificación y el comportamiento deben poder configurarse independientemente.

## 4. Arquitectura general

El sistema debe dividirse en los siguientes módulos:

### 4.1. NPCBase

Escena y script principal de todos los NPC.

Debe heredar de `CharacterBody3D` y centralizar las funcionalidades compartidas:

- Movimiento del personaje.
- Navegación mediante `NavigationAgent3D`.
- Gestión de colisiones.
- Reproducción de animaciones.
- Detección de eventos y amenazas.
- Referencia a la zona segura asignada.
- Comunicación con la máquina de estados.
- Configuración de propiedades generales del NPC.

El script base no debe contener decisiones específicas de cada comportamiento.

### 4.2. NPCBehavior

Sistema encargado de determinar cómo reacciona un NPC ante los eventos del entorno y las acciones del jugador.

Se deben contemplar inicialmente los siguientes comportamientos:

- `NormalBehavior`
- `FighterBehavior`
- `TricksterBehavior`

Cada comportamiento debe definir sus propias reglas de reacción.

Ejemplos:

**NormalBehavior**
- Puede asustarse ante determinadas acciones del jugador.
- Puede escapar hacia su zona segura.
- Puede permanecer en reposo cuando no existen amenazas.

**FighterBehavior**
- Puede reaccionar agresivamente ante el jugador.
- Puede iniciar un ataque.
- Puede entrar en estado de aturdimiento.

**TricksterBehavior**
- Puede utilizar comportamientos evasivos.
- Puede escapar ante determinadas amenazas.
- Puede reaccionar de manera diferente a otros NPC.

Los comportamientos deben solicitar cambios de estado a la máquina de estados y delegar las acciones físicas al NPCBase.

### 4.3. NPCStateMachine

Sistema encargado de gestionar el estado actual del NPC.

Cada estado debe implementarse de forma independiente.

Estados iniciales:

- `Idle`: NPC en reposo.
- `Scared`: NPC asustado.
- `Escape`: NPC desplazándose hacia una zona segura.
- `Attack`: NPC realizando una acción ofensiva.
- `Stun`: NPC aturdido o incapacitado temporalmente.

Cada estado debe implementar, cuando corresponda, los siguientes métodos:

- `enter()`: inicialización al entrar en el estado.
- `update(delta)`: actualización de la lógica del estado.
- `exit()`: limpieza al abandonar el estado.

La máquina de estados debe garantizar que las transiciones sean controladas y evitar cambios incompatibles entre estados.

No todos los NPC necesitan utilizar todos los estados. Cada comportamiento debe determinar qué estados necesita.

### 4.4. NPCConfiguration

Cada instancia de NPC debe poder configurar sus propiedades particulares desde el Inspector.

Propiedades iniciales:

- Clasificación del NPC.
- Comportamiento asignado.
- Zona segura asignada.
- Velocidad de movimiento.
- Rango de detección.
- Parámetros particulares del comportamiento.

Evitar establecer valores específicos de cada NPC directamente en el código compartido.

## 5. Estructura de escenas

La escena base debe utilizar la siguiente estructura como referencia:

```text
NPCBase (CharacterBody3D)
│
├── Model (Node3D)
│   └── AnimationPlayer
│
├── CollisionShape3D
│
├── NavigationAgent3D
│
├── AudioTrigger (Area3D)
│   └── CollisionShape3D
│
├── PerceptionArea (Area3D)
│   └── CollisionShape3D
│
├── SafeZoneFinder (Node3D)
│
└── StateMachine (Node)
	├── Idle
	├── Scared
	├── Escape
	├── Attack
	└── Stun
```

Esta estructura puede ampliarse según las necesidades del proyecto, pero debe mantenerse la separación de responsabilidades.

## 6. Sistema de navegación

Todos los NPC deben compartir el sistema de navegación.

Se utilizará `NavigationAgent3D` para calcular las rutas dentro del mapa.

El movimiento físico debe gestionarse desde NPCBase utilizando `CharacterBody3D` y `move_and_slide()`.

El sistema debe permitir:

- Establecer un destino.
- Calcular rutas hacia el destino.
- Seguir las rutas calculadas.
- Detectar cuándo se ha alcanzado el destino.
- Detener el movimiento al finalizar la navegación.
- Actualizar la orientación del modelo según la dirección de desplazamiento.

Los comportamientos y estados no deben implementar sistemas de navegación independientes.

## 7. Sistema de zonas seguras

Cada NPC debe tener una referencia individual a una zona segura.

Las zonas seguras se representarán inicialmente mediante nodos `Marker3D` ubicados en el mapa.

Ejemplo:

```text
World
│
├── NavigationRegion3D
│
├── SafeZones
│   ├── SafeZone_A (Marker3D)
│   ├── SafeZone_B (Marker3D)
│   └── SafeZone_C (Marker3D)
│
├── NPCs
│   ├── NPC_01
│   ├── NPC_02
│   └── NPC_03
│
└── Player
```

Cada instancia debe poder recibir su propia referencia mediante una propiedad exportada:

```gdscript
@export var safe_zone: Node3D
```

El comportamiento será responsable de decidir cuándo utilizar la zona segura.

El NPCBase será responsable de ejecutar el desplazamiento hacia ella.

### Flujo de escape

1. El NPC recibe un evento que requiere escapar.
2. El comportamiento determina que debe huir.
3. Se solicita la transición al estado `Escape`.
4. El estado solicita al NPCBase desplazarse hacia su zona segura.
5. NPCBase configura el destino del `NavigationAgent3D`.
6. El NPC sigue la ruta calculada.
7. Al llegar, se detiene y cambia al estado correspondiente.

El sistema debe contemplar la ausencia de una zona segura asignada y evitar errores por referencias nulas.

## 8. Sistema de eventos y percepción

Los NPC deben poder reaccionar a eventos del entorno y acciones del jugador.

La detección debe estar separada de la decisión de comportamiento.

Se utilizarán nodos como:

- `Area3D` para detectar cuerpos y áreas.
- `AudioTrigger` para gestionar eventos relacionados con sonido.
- `PerceptionArea` para detectar elementos cercanos.

El sistema de percepción debe comunicar los eventos al comportamiento correspondiente.

Ejemplo de flujo:

```text
Evento del jugador
	   |
	   v
NPC Perception
	   |
	   v
NPC Behavior
	   |
	   v
State Machine
	   |
	   v
NPCBase
	   |
	   v
Ejecución de la acción
```

Los NPC no deben reaccionar automáticamente de la misma manera ante todos los eventos. Cada comportamiento debe definir su respuesta.

## 9. Animaciones

La reproducción de animaciones debe centralizarse en NPCBase mediante un controlador de animaciones.

Los estados deben solicitar la animación correspondiente sin acceder directamente a la implementación interna del `AnimationPlayer`.

Ejemplo:

```gdscript
npc.play_animation("run")
```

Los nombres de las animaciones deben configurarse de acuerdo con las animaciones disponibles en cada modelo.

No asumir que todos los NPC tienen exactamente las mismas animaciones.

## 10. Flujo general de funcionamiento

El sistema debe seguir este flujo:

1. Se instancia un NPC.
2. Se configura su clasificación.
3. Se asigna su comportamiento.
4. Se asigna su zona segura.
5. El NPC inicializa sus sistemas.
6. El NPC permanece en su estado inicial.
7. Recibe eventos del entorno o del jugador.
8. Su comportamiento evalúa la situación.
9. Solicita una transición de estado.
10. La máquina de estados ejecuta la transición.
11. NPCBase ejecuta las acciones correspondientes.
12. El NPC continúa funcionando hasta recibir otro evento o alcanzar una condición de finalización.

## 11. Organización de archivos

Utilizar una organización modular similar a la siguiente:

```text
NPCSystem/
│
├── Base/
│   ├── NPCBase.tscn
│   └── NPCBase.gd
│
├── Behaviors/
│   ├── NPCBehavior.gd
│   ├── NormalBehavior.gd
│   ├── FighterBehavior.gd
│   └── TricksterBehavior.gd
│
├── States/
│   ├── NPCState.gd
│   ├── NPCStateMachine.gd
│   ├── Idle.gd
│   ├── Scared.gd
│   ├── Escape.gd
│   ├── Attack.gd
│   └── Stun.gd
│
├── Components/
│   ├── NPCMovement.gd
│   ├── NPCNavigation.gd
│   ├── NPCPerception.gd
│   ├── NPCAnimation.gd
│   └── NPCCollision.gd
│
└── Configuration/
	└── NPCConfiguration.gd
```

La estructura puede adaptarse a la organización existente del proyecto. No crear carpetas o archivos duplicados si ya existen sistemas equivalentes.

## 12. Reglas de desarrollo para el agente

Al implementar o modificar el sistema, seguir estas directrices:

1. Utilizar GDScript y las funcionalidades nativas de Godot 4.
2. Mantener NPCBase como la clase compartida de los NPC.
3. No duplicar código de movimiento o navegación en los comportamientos.
4. No introducir decisiones específicas de comportamiento dentro de NPCBase.
5. Mantener los estados independientes y reutilizables.
6. Utilizar propiedades exportadas para las configuraciones particulares de cada NPC.
7. Comprobar las referencias a nodos antes de utilizarlas.
8. Evitar dependencias innecesarias entre comportamientos y estados.
9. Utilizar nombres descriptivos para variables, métodos y nodos.
10. No modificar sistemas ajenos al NPC sin que sea necesario.
11. Antes de crear nuevos scripts, revisar los existentes para evitar duplicaciones.
12. No implementar funcionalidades que no hayan sido solicitadas o que no sean necesarias para cumplir los requisitos.
13. Priorizar soluciones modulares y fáciles de mantener.
14. Documentar las funciones públicas y las responsabilidades de cada componente.
15. Verificar que varios NPC puedan funcionar simultáneamente sin compartir accidentalmente estados, destinos o configuraciones individuales.

## 13. Criterios de aceptación

El sistema se considerará funcional cuando cumpla las siguientes condiciones:

- Se pueden instanciar NPC normales y enemigos.
- Cada NPC puede tener un comportamiento independiente.
- Cada NPC puede tener una zona segura individual.
- Los NPC comparten el sistema de movimiento y navegación.
- Los NPC pueden detectar eventos del entorno y del jugador.
- Los comportamientos pueden solicitar cambios de estado.
- La máquina de estados gestiona correctamente las transiciones.
- Los NPC pueden desplazarse hacia sus zonas seguras.
- Las animaciones corresponden al estado actual.
- Se pueden agregar nuevos comportamientos sin modificar el sistema base.
- Se pueden agregar nuevos estados sin duplicar la lógica de navegación.
- Varios NPC pueden funcionar simultáneamente de manera independiente.

## 14. Prioridad de implementación

Desarrollar el sistema progresivamente en este orden:

1. Crear NPCBase y configurar su estructura.
2. Implementar movimiento y colisiones.
3. Integrar NavigationAgent3D.
4. Implementar referencias a zonas seguras.
5. Crear NPCState y NPCStateMachine.
6. Implementar Idle, Scared y Escape.
7. Implementar el sistema de percepción y eventos.
8. Crear NormalBehavior.
9. Crear FighterBehavior.
10. Crear TricksterBehavior.
11. Implementar Attack y Stun.
12. Realizar pruebas con múltiples NPC simultáneamente.

**Objetivo final:** disponer de un sistema de NPCs modular, reutilizable y extensible, donde la navegación, el movimiento y las funcionalidades comunes estén centralizadas, mientras que las decisiones y reacciones particulares estén determinadas por comportamientos independientes y gestionadas mediante una máquina de estados.
