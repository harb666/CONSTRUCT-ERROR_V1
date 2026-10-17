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
## Stage 59: emitted when a laser gate (collision.json "gates") has opened (call open_gate(id) when its encounter is cleared)
signal gate_opened(gate_id: String)

## Stage 80: emitted when a control terminal (collision.json "terminals") is used - after its gates were told to open
signal terminal_activated(terminal_id: String)

var _gates := {}  # id -> {"data": gate dict, "blocker": StaticBody3D}
var _terminals := {}  # id -> terminal dict (Stage 80)
## Stage 89: emitted once when a player reaches a pickup (collision.json "pickups", e.g. the shotgun on its platform) -
## the game gives / spawns the item. A pickup on a riser is live only once its platform is up (apply_effects.gd).
signal pickup_reached(pickup_id: String, item: String)

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
	for gt in col.get("gates", []):  # Stage 59: laser gates - a solid blocker while closed (group "laser_gate", meta "gate_id")
		var sb := StaticBody3D.new()
		sb.name = String(gt["id"]) + "_Blocker"
		var gcs := CollisionShape3D.new()
		var gbox := BoxShape3D.new()
		gbox.size = Vector3(gt["size"][0], gt["size"][1], gt["size"][2])
		gcs.shape = gbox
		sb.add_child(gcs)
		sb.position = Vector3(gt["center"][0], gt["center"][1], gt["center"][2])
		sb.rotation_degrees.y = float(gt.get("yaw_deg", 0.0))
		sb.set_meta("gate_id", gt["id"])
		sb.add_to_group(&"laser_gate")
		add_child(sb)
		_gates[String(gt["id"])] = {"data": gt, "blocker": sb}
		if not bool(gt.get("closed_at_start", true)):
			open_gate.call_deferred(String(gt["id"]), 0.0)
	for tm in col.get("terminals", []):  # Stage 80: control terminals - an interaction area (group "terminal", meta "terminal_id")
		var ia := Area3D.new()
		ia.name = String(tm["id"]) + "_Use"
		var ics := CollisionShape3D.new()
		var isp := SphereShape3D.new()
		isp.radius = float(tm.get("radius", 1.8))
		ics.shape = isp
		ia.add_child(ics)
		ia.position = Vector3(tm["center"][0], tm["center"][1], tm["center"][2])
		ia.set_meta("terminal_id", tm["id"])
		ia.add_to_group(&"terminal")
		add_child(ia)
		_terminals[String(tm["id"])] = tm
	for pk in col.get("pickups", []):  # Stage 89: item pickups - an area (group "pickup", meta "pickup_id" / "item")
		var pa := Area3D.new()
		pa.name = String(pk["id"]) + "_Pickup"
		var pcs := CollisionShape3D.new()
		var psp := SphereShape3D.new()
		psp.radius = float(pk.get("radius", 1.4))
		pcs.shape = psp
		pa.add_child(pcs)
		pa.position = Vector3(pk["center"][0], pk["center"][1], pk["center"][2])
		pa.set_meta("pickup_id", pk["id"])
		pa.set_meta("item", pk.get("item", ""))
		pa.add_to_group(&"pickup")
		pa.monitoring = not pk.has("riser")
		var pid := String(pk["id"])
		var item := String(pk.get("item", ""))
		pa.body_entered.connect(func(b: Node3D) -> void:
			if b is CharacterBody3D and pa.has_meta("pickup_id"):
				pa.remove_meta("pickup_id")
				pickup_reached.emit(pid, item))
		add_child(pa)
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


## Stage 59: open a laser gate - its beams (merged nodes "<group>__<material>") stutter out over `fade` seconds, the
## blocker is removed, then gate_opened(id) is emitted. Call it when the gate's encounter (level.json "encounters") is cleared.
## Stage 80: use a control terminal (call it when the player presses interact inside its "terminal" area): every gate in
## its "activates" list opens (open_gate), then terminal_activated(id) is emitted. Used once.
func activate_terminal(terminal_id: String) -> void:
	if not _terminals.has(terminal_id):
		return
	var tm: Dictionary = _terminals[terminal_id]
	_terminals.erase(terminal_id)
	for gid in tm.get("activates", []):
		if _gates.has(String(gid)):
			open_gate(String(gid))
	terminal_activated.emit(terminal_id)


func open_gate(gate_id: String, fade: float = 0.6) -> void:
	if not _gates.has(gate_id):
		push_warning("unknown gate " + gate_id)
		return
	var g: Dictionary = _gates[gate_id]
	var nodes: Array = []
	for c in level_root.find_children(String(g["data"]["group"]) + "__*", "Node3D", true, false):
		nodes.append(c)
	if is_instance_valid(g["blocker"]):
		g["blocker"].queue_free()
	if fade > 0.0 and not nodes.is_empty():  # beams stutter out (merged meshes sit at the origin: no scaling)
		for i in 6:
			for nd in nodes:
				(nd as Node3D).visible = i % 2 == 1
			await get_tree().create_timer(fade / 6.0).timeout
	for nd in nodes:
		(nd as Node3D).visible = false
	_gates.erase(gate_id)
	gate_opened.emit(gate_id)
