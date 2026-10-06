class_name ToxicArena
extends Node3D
## Toxic Arena (made by image-to-level): the imported level.glb as is, plus
## what it needs to be played in:
##   - collision: one StaticBody3D of simple shapes built from the level's own
##     named meshes (a box per platform / walkway / bridge / wall / cover /
##     tower part / pipe from the mesh's bounds and transform; a simplified
##     convex hull per ramp, staircase and the chamfered central platform).
##     Decoration (panels, glow strips, banners, trims, toxic falls,
##     background blocks) gets none.
##   - HazardFluid: no collision; an Area3D over it sends a player who
##     touches it back to their spawn and kills robots. A hidden basin floor
##     under the fluid catches props and debris.
##   - an out-of-bounds Area3D below the whole level (same as the fluid).
## Nothing in the level itself is moved, rescaled or re-materialed.

const LEVEL := preload("res://assets/levels/toxic_arena/level.glb")

## Meshes whose names contain any of these get no collision.
const NO_COLLISION := ["HazardFluid", "_Fall", "Banner", "_Light_", "_Glow_", "_Trim", "Background_Block"]
## Meshes whose names start with these get a convex hull (slopes, and the
## chamfered central platform).
const HULLS := ["Ramp_", "Stairs_", "Central_Platform_"]
const HAZARD := "HazardFluid"
## How far above the fluid surface touching it counts.
const HAZARD_SKIN := 0.15
## Top of the out-of-bounds volume (below everything playable).
const OUT_OF_BOUNDS_Y := -6.0

var level: Node3D
var collision: StaticBody3D
var hazard: Area3D
var out_of_bounds: Area3D


func _ready() -> void:
	level = LEVEL.instantiate()
	level.name = "Level"
	add_child(level)
	collision = StaticBody3D.new()
	collision.name = "Collision"
	add_child(collision)
	var fluid: MeshInstance3D = null
	for mi: MeshInstance3D in level.find_children("*", "MeshInstance3D", true, false):
		if mi.name == HAZARD:
			fluid = mi
		if NO_COLLISION.any(func(s: String) -> bool: return mi.name.contains(s)):
			continue
		if HULLS.any(func(s: String) -> bool: return mi.name.begins_with(s)):
			_add_hull(mi)
		else:
			_add_box(mi)
	if fluid:
		var box := _world_aabb(fluid)
		hazard = _add_kill_volume("HazardVolume", AABB(Vector3(box.position.x, box.position.y - 2.0, box.position.z), Vector3(box.size.x, box.size.y + 2.0 + HAZARD_SKIN, box.size.z)))
		# Hidden basin floor at the bottom of the fluid.
		var basin := CollisionShape3D.new()
		basin.name = "Basin"
		var bs := BoxShape3D.new()
		bs.size = Vector3(box.size.x, 1.0, box.size.z)
		basin.shape = bs
		basin.position = Vector3(box.get_center().x, box.position.y - 0.5, box.get_center().z)
		collision.add_child(basin)
	out_of_bounds = _add_kill_volume("OutOfBounds", AABB(Vector3(-400, OUT_OF_BOUNDS_Y - 200.0, -400), Vector3(800, 200, 800)))


## Robot spots for the stress test: on the four big platforms (clear of
## their cover blocks) and the corner platforms.
func stress_spawn_points(n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var spots := [Vector2(0, 0), Vector2(-3.5, 0), Vector2(3.5, 0), Vector2(0, -3.5), Vector2(0, 3.5), Vector2(-3.5, 3.5), Vector2(3.5, -3.5)]
	var platforms := [Vector3(0, 6, -26), Vector3(0, 6, 26), Vector3(-26, 6, 0), Vector3(26, 6, 0)]
	for s: Vector2 in spots:
		for p: Vector3 in platforms:
			out.append(p + Vector3(s.x, 0, s.y))
	for c in [Vector3(18, 4, -15.5), Vector3(-18, 4, -15.5), Vector3(18, 4, 15.5), Vector3(-18, 4, 15.5)]:
		out.append(c)
	out.resize(mini(n, out.size()))
	return out


func _world_aabb(mi: MeshInstance3D) -> AABB:
	return mi.global_transform * mi.mesh.get_aabb()


## Box from the mesh's local bounds, placed with its transform (scale baked
## into the size: no scaled shapes).
func _add_box(mi: MeshInstance3D) -> void:
	var ab := mi.mesh.get_aabb()
	if ab.size.length() < 0.01:
		return
	var xf := mi.global_transform
	var sc := xf.basis.get_scale()
	var cs := CollisionShape3D.new()
	cs.name = String(mi.name)
	var shape := BoxShape3D.new()
	shape.size = (ab.size * sc).max(Vector3.ONE * 0.05)
	cs.shape = shape
	cs.transform = Transform3D(xf.basis.orthonormalized(), xf * ab.get_center())
	collision.add_child(cs)


func _add_hull(mi: MeshInstance3D) -> void:
	var cs := CollisionShape3D.new()
	cs.name = String(mi.name)
	var shape := mi.mesh.create_convex_shape(true, false)
	if mi.name.begins_with("Stairs_"):
		shape.points = _stair_ramp(shape.points)
	cs.shape = shape
	cs.transform = mi.global_transform
	collision.add_child(cs)


## A staircase's hull keeps its first step as a small wall (the character
## doesn't step up ledges): carry the slope of the step edges on down to
## the floor in front of the bottom step, so the stairs walk like a ramp.
func _stair_ramp(pts: PackedVector3Array) -> PackedVector3Array:
	var ab := AABB(pts[0], Vector3.ZERO)
	for q in pts:
		ab = ab.expand(q)
	var axis := 0 if ab.size.x > ab.size.z else 2
	# Top height at each end of the run.
	var lo := ab.position[axis]
	var hi := ab.end[axis]
	var top_lo := ab.position.y
	var top_hi := ab.position.y
	for q in pts:
		if absf(q[axis] - lo) < 0.01:
			top_lo = maxf(top_lo, q.y)
		if absf(q[axis] - hi) < 0.01:
			top_hi = maxf(top_hi, q.y)
	var low_end := lo if top_lo < top_hi else hi
	var out := -1.0 if low_end == lo else 1.0
	var lip := minf(top_lo, top_hi) - ab.position.y
	if lip < 0.01:
		return pts
	# Where the top first reaches full height, measured from the low end.
	var reach := ab.size[axis]
	for q in pts:
		if q.y > ab.end.y - 0.01:
			reach = minf(reach, absf(q[axis] - low_end))
	var rise := ab.end.y - (ab.position.y + lip)
	if reach < 0.01 or rise < 0.01:
		return pts
	var ext := lip * reach / rise
	var res := pts.duplicate()
	for q in pts:
		if absf(q[axis] - low_end) < 0.01 and q.y < ab.position.y + 0.01:
			var e := q
			e[axis] += out * ext
			res.append(e)
	return res


func _add_kill_volume(n: String, box: AABB) -> Area3D:
	var a := Area3D.new()
	a.name = n
	a.monitorable = false
	a.collision_mask = 0xFFFFFFFF
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	cs.shape = shape
	cs.position = box.get_center()
	a.add_child(cs)
	add_child(a)
	a.body_entered.connect(_on_kill_volume)
	return a


## A player is sent back to their spawn; a robot dies (and respawns as usual).
func _on_kill_volume(body: Node3D) -> void:
	if body is PlayerController:
		(body as PlayerController).respawn()
	elif body is RobotEnemy and (body as RobotEnemy).alive:
		body.apply_damage(DamageInfo.make(1.0e6, DamageInfo.Type.ENERGY, body.global_position, Vector3.DOWN, 0.0))
