class_name CharacterDefinition
extends Resource
## A playable character. The character select screen, its 3D preview, the
## HUD's portrait / name and the player that spawns all come from this, so
## adding a character = a new definition + adding it to the roster.

@export var id: StringName
@export var display_name := ""
## The player that spawns for this character (controller, weapons; every
## character shares scenes/player.tscn, so they all play the same).
@export var player_scene: PackedScene
## The character's look (model + animator), added to the player's Visual.
## A path, loaded only when this character spawns: the characters nobody
## picked never take up memory.
@export_file("*.tscn") var visual_scene_path := ""
## Face picture (HUD corner ring, squad slots).
@export var portrait: Texture2D
## Character select card art (slanted, transparent outside the slant).
@export var banner: Texture2D
@export var accent_color := Color(0.27, 0.86, 0.96)

@export_group("Preview")
## The character's model (with its AnimationPlayer) for the select screen
## (a path: loaded only while it's shown).
@export_file("*.glb", "*.tscn") var preview_model_path := ""
## Caps sealing open holes in the model, as on the player.
@export var preview_caps: MeshCaps
@export var preview_animation := ""
## Model yaw that faces the viewer (+Z).
@export var preview_yaw_degrees := 0.0


## A new (not yet added) player for this character.
func instantiate_player() -> PlayerController:
	var p := player_scene.instantiate() as PlayerController
	if visual_scene_path != "":
		var root := p.get_node("Visual")
		for c in root.get_children():
			root.remove_child(c)
			c.free()
		var v := (load(visual_scene_path) as PackedScene).instantiate()
		root.add_child(v)
		var holder := p.get_node_or_null("WeaponHolder") as WeaponHolder
		if holder:
			holder.visual_path = NodePath("../Visual/" + String(v.name))
	p.character = self
	return p
