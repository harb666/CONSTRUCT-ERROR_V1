extends SceneTree
## Picks spots for a level's holographic health pick-ups (HealthPickup),
## spread out over its walkable floor, and prints them as scene nodes to
## paste under the level's "HealthPickups" node:
##   godot --headless --path . -s tools/place_health_pickups.gd -- --level=ascent --count=8
## Candidates: the navigation mesh's polygons (levels with one), else a grid
## of floor hits (the test arena). Kept only on still, flat, open floor:
## not a moving platform / belt / lift, not in slime or a hazard, head room
## over it, away from the players' spawn and weapon pads. Then the spot
## farthest from everything picked so far, `count` times.

const LEVELS := {
	"battle": "res://scenes/battle_arena.tscn",
	"skyforge": "res://scenes/skyforge_arena.tscn",
	"works": "res://scenes/toxic_works.tscn",
	"ascent": "res://scenes/assembly_ascent.tscn",
}
const MOVING := ["Belt", "Lift", "Float", "Arena_", "Riser", "Spinner", "Saw", "Press", "Car", "Elevator",
	"Conveyor", "Pad_", "Pillars", "Crusher", "Jet", "Rig", "Shotgun", "Turbine", "Fan"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var which := "ascent"
	var count := 8
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			which = a.substr(8)
		elif a.begins_with("--count="):
			count = a.substr(8).to_int()
	RobotEnemy.ai_enabled = false
	var main: Node = load(LEVELS[which]).instantiate()
	main.set(&"front_end_mode", 0)
	root.add_child(main)
	for i in 40:
		await physics_frame
	var space := main.get_viewport().world_3d.direct_space_state
	var cands: Array[Vector3] = []
	var nav := main.get_node_or_null("Navigation") as NavigationRegion3D
	if nav and nav.navigation_mesh:
		var nm := nav.navigation_mesh
		var v := nm.get_vertices()
		for i in nm.get_polygon_count():
			var poly := nm.get_polygon(i)
			var c := Vector3.ZERO
			for k in poly:
				c += v[k]
			cands.append(nav.global_transform * (c / poly.size()))
	else:
		for x in range(-60, 61, 2):
			for z in range(-60, 61, 2):
				var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 40, z), Vector3(x, -10, z), 1))
				if not h.is_empty():
					cands.append(h["position"])
	var avoid: Array[Vector3] = []
	for sp in main.get_node("SpawnPoints").get_children():
		avoid.append((sp as Node3D).global_position)
	for pad in main.find_children("*", "WeaponSpawnPad", true, false):
		avoid.append((pad as Node3D).global_position)
	# Only where play goes: linked over the navigation mesh to where the
	# players or the robots start (spawn points, wave spawn markers, placed
	# robots) - not ground far below the level or a roof top.
	var seeds: Array[Vector3] = avoid.duplicate()
	for m in main.find_children("*", "Marker3D", true, false):
		seeds.append((m as Node3D).global_position)
	for r in main.get_tree().get_nodes_in_group(&"enemies"):
		seeds.append((r as Node3D).global_position)
	var map := nav.get_navigation_map() if nav else RID()
	if map.is_valid():
		for i in 30:
			await physics_frame
		var snapped: Array[Vector3] = []
		for sd in seeds:
			var q := NavigationServer3D.map_get_closest_point(map, sd)
			if q.distance_to(sd) < 3.0:
				snapped.append(q)
		seeds = snapped
		print("seeds on the mesh %d" % seeds.size())
	var ok: Array[Vector3] = []
	for c in cands:
		var p := _floor_spot(space, c)
		if p == Vector3.INF or not avoid.all(func(a: Vector3) -> bool: return a.distance_to(p) > 5.0):
			continue
		if map.is_valid():
			var on := NavigationServer3D.map_get_closest_point(map, p)
			var linked := false
			for sd in seeds:
				var path := NavigationServer3D.map_get_path(map, sd, on, true)
				if path.size() > 0 and path[path.size() - 1].distance_to(on) < 1.0:
					linked = true
					break
			if not linked:
				continue
		ok.append(p)
	print("candidates %d, on still open floor %d" % [cands.size(), ok.size()])
	var picked: Array[Vector3] = []
	var near: Array[Vector3] = avoid.duplicate()
	for n in count:
		var best := Vector3.INF
		var bd := -1.0
		for p in ok:
			var d := INF
			for q in near + picked:
				# (Height counts double: decks above one another are far apart.)
				d = minf(d, Vector3(p.x - q.x, (p.y - q.y) * 2.0, p.z - q.z).length())
			if d > bd:
				bd = d
				best = p
		if best == Vector3.INF:
			break
		picked.append(best)
	for i in picked.size():
		var p := picked[i]
		print("[node name=\"Health%d\" type=\"Node3D\" parent=\"HealthPickups\"]\nscript = ExtResource(\"healthpickup\")\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.2f, %.2f, %.2f)\n" % [i + 1, p.x, p.y, p.z])
	quit()


## `c` dropped onto still, flat floor with room over it, or INF.
func _floor_spot(space: PhysicsDirectSpaceState3D, c: Vector3) -> Vector3:
	var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(c + Vector3.UP * 1.0, c + Vector3.DOWN * 2.0, 1))
	if h.is_empty() or (h["normal"] as Vector3).y < 0.92:
		return Vector3.INF
	var col := h["collider"] as Node
	if not (col is StaticBody3D):
		return Vector3.INF
	var n := String(col.name) + "/" + String(col.get_parent().name if col.get_parent() else "")
	for m in MOVING:
		if n.contains(m):
			return Vector3.INF
	var p: Vector3 = h["position"]
	# Room for the projector and its cross (and a player) over it.
	var room := SphereShape3D.new()
	room.radius = 0.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = room
	q.collision_mask = 1
	for y in [0.9, 1.7]:
		q.transform = Transform3D(Basis(), p + Vector3.UP * y)
		if not space.intersect_shape(q, 1).is_empty():
			return Vector3.INF
	# Not in slime, a hazard, the exit or a trigger.
	var pq := PhysicsPointQueryParameters3D.new()
	pq.collide_with_areas = true
	pq.collide_with_bodies = false
	for y in [0.3, 1.0]:
		pq.position = p + Vector3.UP * y
		for r in space.intersect_point(pq, 8):
			var a := r["collider"] as Node
			if a and (a.is_in_group(&"hazard") or a.is_in_group(&"level_exit") or String(a.name).contains("Kill")
					or String(a.name).contains("Slime") or String(a.name).contains("Hazard")):
				return Vector3.INF
	# Solid ground all round (not the edge of a walkway).
	for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var e := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + d * 1.3 + Vector3.UP * 0.5, p + d * 1.3 + Vector3.DOWN * 0.6, 1))
		if e.is_empty():
			return Vector3.INF
	return p
