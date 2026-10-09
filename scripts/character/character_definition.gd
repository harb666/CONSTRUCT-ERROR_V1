class_name CharacterDefinition
extends Resource
## A playable character. The character select screen, its 3D preview, the
## HUD's portrait / name and the player that spawns all come from this, so
## adding a character = a new definition + adding it to the roster.

@export var id: StringName
@export var display_name := ""
## The player that spawns for this character (controller, visual, weapons).
@export var player_scene: PackedScene
## Head-and-shoulders picture (HUD, character select, squad slots).
@export var portrait: Texture2D
@export var accent_color := Color(0.27, 0.86, 0.96)

@export_group("Preview")
## The character's model (with its AnimationPlayer) for the select screen.
@export var preview_model: PackedScene
## Caps sealing open holes in the model, as on the player.
@export var preview_caps: MeshCaps
@export var preview_animation := ""
## Model yaw that faces the viewer (+Z).
@export var preview_yaw_degrees := 0.0
