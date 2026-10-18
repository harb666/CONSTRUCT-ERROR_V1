extends SceneTree
## Bakes the Toxic Works' FlightGraph (the open air flying robots route
## through, FlightNav) from the level's collision and saves it:
## levels/slime_arena/gameplay/flight_graph.res. Run after the level's
## collision changes:
##   godot --headless --path . -s tools/bake_flight_graph.gd

const SCENE := "res://scenes/toxic_works.tscn"
const OUT := "res://levels/slime_arena/gameplay/flight_graph.res"
const GATES := "res://levels/slime_arena/mobile/collision.json"
const SPACING := 4.0
## Room a point needs round it, and the body flown between two (a Neon
## Sentinel's sphere is 0.68 m at 1.3x: 0.9 m, plus its wings).
const ROOM := 1.3
const BODY := 1.1
const MASK := 1 | ShaftBarrier.LAYER
const Y_RANGE := Vector2(2.0, 26.0)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RobotEnemy.ai_enabled = false
	var main: Node = load(SCENE).instantiate()
	root.add_child(main)
	for i in 5:
		await physics_frame
	var tw := main.get_node("ToxicWorks") as ToxicWorks
	# Baked with the laser gates open: their links are kept apart.
	for g in get_nodes_in_group(&"laser_gate"):
		g.free()
	for r in get_nodes_in_group(&"enemies"):
		r.free()
	await physics_frame
	await physics_frame
	var box := AABB()
	var first := true
	for cs: CollisionShape3D in tw.collision.find_children("*", "CollisionShape3D", true, false):
		if cs.shape == null:
			continue
		var b := cs.global_transform * cs.shape.get_debug_mesh().get_aabb()
		box = b if first else box.merge(b)
		first = false
	var g := FlightGraph.new()
	g.spacing = SPACING
	g.origin = Vector3(snappedf(box.position.x, SPACING), Y_RANGE.x, snappedf(box.position.z, SPACING))
	g.dims = Vector3i(int((box.end.x - g.origin.x) / SPACING) + 1, int((Y_RANGE.y - Y_RANGE.x) / SPACING) + 1, int((box.end.z - g.origin.z) / SPACING) + 1)
	var space := main.get_viewport().world_3d.direct_space_state
	var n := g.dims.x * g.dims.y * g.dims.z
	var free := PackedByteArray()
	free.resize(n)
	var room := SphereShape3D.new()
	room.radius = ROOM
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = room
	q.collision_mask = MASK
	var open := 0
	for i in n:
		q.transform = Transform3D(Basis(), g.cell_position(g.cell_of(i)))
		free[i] = 1 if space.intersect_shape(q, 1).is_empty() else 0
		open += free[i]
	var gates := []
	for gd in (JSON.parse_string(FileAccess.get_file_as_string(GATES)) as Dictionary).get("gates", []):
		var c: Array = gd["center"]
		var sz: Array = gd["size"]
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(gd.get("yaw_deg", 0.0)))), Vector3(c[0], c[1], c[2]))
		var half := Vector3(sz[0], sz[1], sz[2]) * 0.5 + Vector3(0.5, 0.5, 1.5)
		gates.append([String(gd["id"]), xf.affine_inverse(), AABB(-half, half * 2.0)])
		g.gate_links[String(gd["id"])] = PackedInt32Array()
	var body := SphereShape3D.new()
	body.radius = BODY
	var mq := PhysicsShapeQueryParameters3D.new()
	mq.shape = body
	mq.collision_mask = MASK
	g.links.resize(n)
	var count := 0
	for i in n:
		if not free[i]:
			g.links[i] = -1
			continue
		var c := g.cell_of(i)
		var a := g.cell_position(c)
		var bits := 0
		for s in FlightGraph.STEPS.size():
			var j := g.cell_index(c + FlightGraph.STEPS[s])
			if j < 0 or not free[j]:
				continue
			var b := g.cell_position(c + FlightGraph.STEPS[s])
			mq.transform = Transform3D(Basis(), a)
			mq.motion = b - a
			var m := space.cast_motion(mq)
			if m.is_empty() or m[0] < 1.0:
				continue
			var through := ""
			for gt in gates:
				var la: Vector3 = gt[1] * a
				var lb: Vector3 = gt[1] * b
				if (gt[2] as AABB).intersects_segment(la, lb):
					through = gt[0]
			if through != "":
				var l: PackedInt32Array = g.gate_links[through]
				l.append(i)
				l.append(s)
				g.gate_links[through] = l
			else:
				bits |= 1 << s
			count += 1
		g.links[i] = bits
	var e := ResourceSaver.save(g, OUT)
	print("FLIGHT GRAPH %s cells, %d open, %d links, gates %s -> %s (%s)" % [g.dims, open, count,
		g.gate_links.keys().map(func(k: String) -> String: return "%s %d" % [k, g.gate_links[k].size() / 2]), OUT, error_string(e)])
	quit()
