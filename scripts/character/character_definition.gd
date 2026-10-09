class_name CharacterDefinition
extends Resource
## A playable character. The character select screen, its 3D preview, the
## HUD's portrait / name and the player that spawns all come from this, so
## adding a character = a new definition + adding it to the roster.

@export var id: StringName
@export var display_name := ""
## The player that spawns for this character (controller, visual, weapons).
@export var player_scene: PackedScene
## Optional: replaces the player scene's own visual (model + animator), so a
## character can share the Grinch's player (same movement, health,
## weapons) with only its look changed.
@export var visual_scene: PackedScene
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


## A new (not yet added) player for this character.
func instantiate_player() -> PlayerController:
	var p := player_scene.instantiate() as PlayerController
	if visual_scene:
		var root := p.get_node("Visual")
		for c in root.get_children():
			root.remove_child(c)
			c.free()
		var v := visual_scene.instantiate()
		root.add_child(v)
		var holder := p.get_node_or_null("WeaponHolder") as WeaponHolder
		if holder:
			holder.visual_path = NodePath("../Visual/" + String(v.name))
	p.character = self
	return p
