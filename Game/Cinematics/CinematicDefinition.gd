class_name CinematicDefinition
extends Resource

## Definición de una cinemática de captura.
##
## [member id] es el identificador con el que el atacante solicita la
## cinemática. [member camera_animation] es el nombre de la animación dentro de
## la librería "cinematics" del AnimationPlayer del CinematicController.
## [member attacker_animation] y [member target_animation] son clips existentes
## de los personajes; si el clip del objetivo no existe se usa "idle".

## Identificador usado por el atacante al solicitar la cinemática.
@export var id: StringName = &""
## Nombre de la animación de cámara en la librería "cinematics".
@export var camera_animation: StringName = &""
## Clip del atacante. Si no existe, se usa "idle".
@export var attacker_animation: StringName = &"attack"
## Clip del objetivo. Si no existe, se usa "idle".
@export var target_animation: StringName = &"attack"
