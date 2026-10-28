class_name WarmUpLibrary
extends Resource
## One material of every kind the game draws during play (effects, debris,
## hit flashes, pick-ups ...), recorded by tools/collect_warm_up_materials.gd
## while `?fxsoak` sets off every effect in each level. `Vfx.warm_up` draws
## them all (tiny, hidden) so a phone makes their shaders before play, and
## keeps them: Godot drops a material kind's shader when the last material
## of that kind goes, so an effect's shaders would be made again - a freeze
## - each time it came back after a lull.

## The recorded materials (one per kind).
@export var materials: Array[Material] = []
## Each one's kind (what makes its shader differ) and where it was seen.
@export var keys: PackedStringArray = []
@export var seen: PackedStringArray = []
## Sprite3D / Label3D set-ups (their materials are made inside the engine):
## {"label": bool, "billboard", "transparent", "shaded", "double_sided",
## "no_depth_test", "fixed_size", "alpha_cut", "texture_filter"}.
@export var sprites: Array[Dictionary] = []


## What makes a material's shader differ: its shader (ShaderMaterial), or
## its feature flags / modes and which texture slots are used (built-in
## materials); colours and amounts don't.
static func key_of(m: Material) -> String:
	if m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		if sh == null:
			return "S:none"
		return "S:" + (sh.resource_path if sh.resource_path != "" and not sh.resource_path.contains("::") else str(sh.code.hash()))
	var k := m.get_class()
	for p in m.get_property_list():
		if not (int(p.usage) & PROPERTY_USAGE_STORAGE):
			continue
		var n: String = p.name
		if n == "render_priority" or n.begins_with("resource_") or n == "script" or n == "next_pass":
			continue
		match int(p.type):
			TYPE_BOOL, TYPE_INT:
				k += "|%s=%s" % [n, m.get(n)]
			TYPE_OBJECT:
				if m.get(n) != null:
					k += "|%s" % n
	return k


static func sprite_key(s: GeometryInstance3D) -> Dictionary:
	var d := {"label": s is Label3D, "billboard": int(s.get("billboard")), "shaded": bool(s.get("shaded")),
		"double_sided": bool(s.get("double_sided")), "no_depth_test": bool(s.get("no_depth_test")),
		"fixed_size": bool(s.get("fixed_size")), "alpha_cut": int(s.get("alpha_cut")), "texture_filter": int(s.get("texture_filter"))}
	if s is SpriteBase3D:
		d["transparent"] = (s as SpriteBase3D).transparent
	return d
