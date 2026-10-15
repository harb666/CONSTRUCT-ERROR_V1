extends Node
## image-to-level art style runtime starter for Godot 4 (UNTESTED in Godot here - treat as a starting point).
## Reads environment.json "style" (written from the level's art_style preset, e.g. alien_cartoon) and applies:
##   toon  -> every StandardMaterial3D of the level: diffuse_mode TOON, specular off, metallic 0 (works in Mobile +
##            Compatibility renderers, no post-processing). The "ink" material (outline shells) is left unlit-black.
## Outlines need NO script: they are inverted-hull meshes already inside level.glb / level_mobile.glb (nodes "*__ol"
## or merged "M_ink_*"), drawn with ordinary back-face culling. Keep them out of collision (they have no colliders).

@export_file("*.json") var environment_path: String = "res://levels/skyforge_arena/environment.json"
@export var level_root: Node3D


func _ready() -> void:
	var env = JSON.parse_string(FileAccess.get_file_as_string(environment_path))
	if env == null or env.get("style") == null or level_root == null:
		return
	var style: Dictionary = env["style"]
	if style.has("toon"):
		_toon(level_root, {})


func _toon(n: Node, seen: Dictionary) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in range(mi.get_surface_override_material_count()):
			var m := mi.get_active_material(i) as StandardMaterial3D
			if m == null or seen.has(m):
				continue
			seen[m] = true
			if m.resource_name == "ink":
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.disable_fog = false
				continue
			m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			m.metallic = 0.0
			m.roughness = 1.0
	for c in n.get_children():
		_toon(c, seen)
