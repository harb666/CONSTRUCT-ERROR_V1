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
## Each one's levels (scene names, comma separated) and how it was drawn
## there ("mesh" - one object, "multi" - a batch: particles / multimesh,
## both differ in their shaders): a level warms up only its own (owner's
## iPhone lost its graphics preparing the Toxic Works - every level's
## effects in both forms there, ~250 shaders it never uses).
@export var levels: PackedStringArray = []
@export var drawn: PackedStringArray = []
## Sprite3D / Label3D set-ups (their materials are made inside the engine):
## {"label": bool, "billboard", "transparent", "shaded", "double_sided",
## "no_depth_test", "fixed_size", "alpha_cut", "texture_filter",
## "levels": "a,b"}.
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


## Whether material `i` is warmed up in `level` (all levels when the
## library has no level records).
func used_in(i: int, level: String) -> bool:
	if levels.size() != materials.size() or level == "":
		return true
	return level in levels[i].split(",", false)


## How material `i` was drawn: "mesh", "multi" or "mesh,multi".
func drawn_as(i: int) -> String:
	return drawn[i] if drawn.size() == materials.size() and drawn[i] != "" else "mesh,multi"
