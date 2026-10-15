extends Node3D
## image-to-level Stage 5 starter for Godot 4 (UNTESTED in Godot here).
## Applies mobile_manifest.json to an instanced level_mobile.glb: visibility ranges (distance culling of merged props),
## shadow casting flags, and Area3D hazards from collision.json (put the level in group "hazard" handling in your game).
## Setup: copy levels/<name>/ to res://levels/<name>/, instance mobile/level_mobile.glb (+ background_mobile.glb and
## collision.glb), add a Node3D with this script at the world origin and assign level_root.

@export_file("*.json") var manifest_path: String = "res://levels/toxic_arena/mobile/mobile_manifest.json"
@export var level_root: Node3D
@export var hazard_group: StringName = &"hazard"
## emitted when a body enters a level exit (e.g. falls into the elevator shaft): load `target` in your game
signal level_exit_entered(target: String, body: Node)
## emitted when an arriving elevator car (collision.json "entrances") reaches its rest position
signal arrival_finished(entrance_id: String)

var _entrances := {}  # id -> {"data": entrance dict, "pivot": Node3D holding the car's merged nodes}


func _ready() -> void:
	var m = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if m == null or level_root == null:
		push_error("manifest or level_root missing")
		return
	for n in m["nodes"]:
		var gi := level_root.find_child(n["node"], true, false) as GeometryInstance3D
		if gi == null:
			continue
		gi.visibility_range_end = float(n["visibility_range_end"])
		gi.visibility_range_begin = float(n.get("visibility_range_begin", 0.0))  # Stage 9 terrain LOD1/LOD2 start further out
		if gi.visibility_range_end > 0.0 or gi.visibility_range_begin > 0.0:
			gi.visibility_range_end_margin = 5.0
			gi.visibility_range_begin_margin = 5.0
			gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if n["cast_shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var col = JSON.parse_string(FileAccess.get_file_as_string(manifest_path.get_base_dir() + "/collision.json"))
	if col == null:
		return
	_setup_entrances.call_deferred(m, col)  # deferred: reparenting while the level tree is still being set up fails
	for tr in col.get("triggers", []):  # level exits (elevator shafts ...): Area3D in group "level_exit", meta "target"
		var ta := Area3D.new()
		ta.name = String(tr["id"])
		var tcs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = float(tr["radius"])
		cyl.height = float(tr["height"])
		tcs.shape = cyl
		ta.add_child(tcs)
		ta.position = Vector3(tr["center"][0], tr["center"][1], tr["center"][2])
		ta.set_meta("target", tr["target"])
		ta.add_to_group(&"level_exit")
		ta.body_entered.connect(func(b): level_exit_entered.emit(String(tr["target"]), b))
		add_child(ta)
	for h in col["hazards"]:
		var area := Area3D.new()
		area.name = String(h["name"]) + "_Area"
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(h["size"][0], h["size"][1], h["size"][2])
		cs.shape = box
		area.add_child(cs)
		area.position = Vector3(h["center"][0], h["center"][1], h["center"][2])
		area.add_to_group(hazard_group)
		add_child(area)


func _setup_entrances(m: Dictionary, col: Dictionary) -> void:
	for en in col.get("entrances", []):  # arriving elevator cars: their merged nodes ("<car>__<material>") go under one movable pivot
		var pivot := Node3D.new()
		pivot.name = String(en["car"]) + "_Pivot"
		level_root.add_child(pivot)
		for n in m["nodes"]:
			if String(n.get("group", "")) == String(en["mobile_group"]):
				var gi := level_root.find_child(n["node"], true, false) as Node3D
				if gi != null:
					gi.reparent(pivot, true)
		_entrances[String(en["id"])] = {"data": en, "pivot": pivot}


## Play an elevator arrival: the car starts start_offset_y above its rest position and comes down over duration_s.
## `player` (optional) rides along: it is kept standing on the car floor (call before enabling player control).
## The car's colliders in collision.glb sit at the rest position, so keep the player's physics paused until arrival_finished.
func play_arrival(entrance_id: String, player: Node3D = null) -> void:
	var e = _entrances.get(entrance_id)
	if e == null:
		push_error("no entrance " + entrance_id)
		return
	var en: Dictionary = e["data"]
	var pivot: Node3D = e["pivot"]
	var off := float(en["start_offset_y"])
	var sp := Vector3(en["spawn"][0], en["spawn"][1], en["spawn"][2])
	var step := func(y: float) -> void:
		pivot.position.y = y
		if player != null:
			player.global_position = Vector3(player.global_position.x, sp.y + y, player.global_position.z)
	step.call(off)
	var tw := create_tween()
	tw.tween_method(step, off, 0.0, float(en["duration_s"])).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.finished.connect(func(): arrival_finished.emit(entrance_id))
