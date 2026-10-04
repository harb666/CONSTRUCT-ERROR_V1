class_name BreakApart
extends Node
## Reusable dismemberment for skinned characters whose body is modelled as
## separate section meshes (see BreakSection). Nothing is cut: a detached
## section's meshes are moved, still skinned, onto a frozen copy of the
## skeleton inside a DebrisPiece, so they keep their exact current pose.
##
## `choose_level(info)` turns the killing hit into a destruction level (with
## controlled randomness); `plan(level, info)` picks which joints break;
## `detach(sections, info, base_velocity)` makes the pieces.

enum Level { NONE, LIGHT, MEDIUM, HEAVY, EXTREME }

@export var skeleton_path: NodePath
@export var section_set: BreakSectionSet

var sections: Array[BreakSection] = []

@export_group("Destruction level")
## Hit force (impact + explosive) that counts as full destructive power 1.0.
@export var reference_force := 35.0
## +/- random spread added to the power before picking a level.
@export var randomness := 0.18
## Power thresholds for LIGHT, MEDIUM, HEAVY, EXTREME.
@export var level_thresholds := Vector4(0.28, 0.45, 0.68, 0.92)
## Explosions break things more readily than direct hits of equal force.
@export var explosive_bonus := 0.12

@export_group("Breaks per level")
## [min, max] joints broken (LIGHT can be 0 = stays whole).
@export var light_breaks := Vector2i(0, 1)
@export var medium_breaks := Vector2i(1, 3)
@export var heavy_breaks := Vector2i(3, 5)
## EXTREME breaks everything except up to this many random joints.
@export var extreme_keep := 2

@export_group("Launch")
@export var base_launch_speed := 3.0
## Extra launch speed per 1.0 of destructive power.
@export var launch_per_power := 9.0
@export var max_launch_speed := 15.0
@export var max_spin := 12.0
## How much the attack's direction steers pieces (vs. flying out radially).
@export var direction_bias := 0.45
@export var upward_bias := 0.35
## Collision box = section bounds * this (smaller = no initial overlap).
@export var shape_shrink := 0.8
@export var density := 900.0
@export var piece_mass_range := Vector2(2.0, 30.0)

@export_group("Sparks")
@export var sparks_on_body := true
@export var sparks_on_piece := true

signal piece_detached(piece: DebrisPiece, section: BreakSection, joint_position: Vector3)

var skeleton: Skeleton3D
var _by_name := {}
## Section name -> Skeleton3D currently carrying it (original or a piece's).
var _carrier := {}
var _detached := {}


func _ready() -> void:
	if skeleton == null:
		skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if section_set:
		sections = section_set.sections
	for s in sections:
		_by_name[s.section_name] = s


## Destructive power 0..~1.5 of a hit.
func power_of(info: DamageInfo) -> float:
	var p := info.total_force() / maxf(reference_force, 0.01)
	if info.is_explosive():
		p += explosive_bonus
	return p


func choose_level(info: DamageInfo) -> Level:
	var p := power_of(info) + randf_range(-randomness, randomness)
	if p >= level_thresholds.w:
		return Level.EXTREME
	if p >= level_thresholds.z:
		return Level.HEAVY
	if p >= level_thresholds.y:
		return Level.MEDIUM
	if p >= level_thresholds.x:
		return Level.LIGHT
	return Level.NONE


## Which sections break off (each at its joint) for a level. Sections nearer
## the impact are favoured; lower levels only break smaller parts.
func plan(level: Level, info: DamageInfo) -> Array[BreakSection]:
	var out: Array[BreakSection] = []
	if level == Level.NONE or skeleton == null:
		return out
	var candidates: Array[BreakSection] = []
	for s in sections:
		if _detached.has(s.section_name):
			continue
		match level:
			Level.LIGHT:
				if s.tier == 0 or (s.tier == 1 and s.parent != &"" and randf() < 0.15):
					candidates.append(s)
			Level.MEDIUM:
				if s.tier <= 1:
					candidates.append(s)
			Level.HEAVY:
				if s.parent != &"":  # everything but the root
					candidates.append(s)
			Level.EXTREME:
				candidates.append(s)
	if level == Level.EXTREME:
		candidates.shuffle()
		var keep := randi_range(0, extreme_keep)
		for i in candidates.size():
			# Keep a few random joints intact (never the small ends) for variety.
			if keep > 0 and candidates[i].tier > 0 and candidates[i].parent != &"":
				keep -= 1
				continue
			out.append(candidates[i])
		return _root_first(out)
	var range_v: Vector2i = light_breaks if level == Level.LIGHT else (medium_breaks if level == Level.MEDIUM else heavy_breaks)
	var count := randi_range(range_v.x, range_v.y)
	# Weighted pick: closer to the impact = more likely.
	var weighted: Array = []
	for s in candidates:
		var d := _section_center(s).distance_to(info.impact_position)
		weighted.append([s, 1.0 / (0.6 + d) * randf_range(0.6, 1.4)])
	weighted.sort_custom(func(a, b): return a[1] > b[1])
	for i in mini(count, weighted.size()):
		out.append(weighted[i][0])
	return _root_first(out)


func _root_first(list: Array[BreakSection]) -> Array[BreakSection]:
	list.sort_custom(func(a: BreakSection, b: BreakSection) -> bool: return _depth(a) < _depth(b))
	return list


func _depth(s: BreakSection) -> int:
	var d := 0
	var p := s.parent
	while p != &"" and _by_name.has(p) and d < 16:
		d += 1
		p = (_by_name[p] as BreakSection).parent
	return d


func is_detached(section_name: StringName) -> bool:
	return _detached.has(section_name)


func detached_count() -> int:
	return _detached.size()


## Detach `cuts` (each with its still-attached children) as flying pieces.
## `planned` = every section that will break in this death (when detaching
## in batches), so a piece never carries a part due to break off separately.
func detach(cuts: Array[BreakSection], info: DamageInfo, base_velocity := Vector3.ZERO, planned: Array[BreakSection] = []) -> Array[DebrisPiece]:
	var pieces: Array[DebrisPiece] = []
	if skeleton == null or not skeleton.is_inside_tree():
		return pieces
	var cut_names := {}
	for c in cuts + planned:
		cut_names[c.section_name] = true
	var power := power_of(info)
	for c in cuts:
		if _detached.has(c.section_name):
			continue
		var group := _collect(c, cut_names)
		var piece := _make_piece(group, info, power, base_velocity)
		if piece:
			pieces.append(piece)
	return pieces


## The section plus every attached descendant not being cut separately.
func _collect(root: BreakSection, cut_names: Dictionary) -> Array[BreakSection]:
	var out: Array[BreakSection] = [root]
	var i := 0
	while i < out.size():
		var cur := out[i]
		for s in sections:
			if s.parent == cur.section_name and not _detached.has(s.section_name) and not cut_names.has(s.section_name):
				out.append(s)
		i += 1
	return out


func _carrier_of(name: StringName) -> Skeleton3D:
	var c: Skeleton3D = _carrier.get(name, skeleton)
	return c if is_instance_valid(c) else null


func _section_center(s: BreakSection) -> Vector3:
	var info := _section_frame(s)
	return info[0] * (info[1] as AABB).get_center() if not info.is_empty() else skeleton.global_position


## [world transform of the section's rest mesh space, rest AABB] using its
## driving bone (sections are rigidly bound to one bone).
func _section_frame(s: BreakSection) -> Array:
	var sk := _carrier_of(s.section_name)
	if sk == null:
		return []
	var mi := sk.get_node_or_null(NodePath(s.mesh_names[0])) as MeshInstance3D
	if mi == null or mi.mesh == null:
		return []
	var b := sk.find_bone(s.bone)
	var bind := Transform3D.IDENTITY
	if mi.skin:
		for i in mi.skin.get_bind_count():
			if mi.skin.get_bind_name(i) == s.bone or mi.skin.get_bind_bone(i) == b:
				bind = mi.skin.get_bind_pose(i)
				break
	var xf := sk.global_transform * sk.get_bone_global_pose(b) * bind
	return [xf, mi.mesh.get_aabb()]


func _make_piece(group: Array[BreakSection], info: DamageInfo, power: float, base_velocity: Vector3) -> DebrisPiece:
	var root := group[0]
	var src := _carrier_of(root.section_name)
	var frame := _section_frame(root)
	if src == null or frame.is_empty():
		return null
	var world := skeleton.get_tree().current_scene
	if world == null:
		world = skeleton.get_tree().root
	var s_xf: Transform3D = frame[0]
	var s_box: AABB = frame[1]
	var body_xf := Transform3D(s_xf.basis.orthonormalized(), s_xf * s_box.get_center())
	var piece := DebrisPiece.new()
	piece.name = "Debris_%s" % root.section_name
	piece.section = root.section_name
	# Frozen copy of the skeleton in its current pose.
	var pose := Skeleton3D.new()
	pose.name = "Pose"
	for i in src.get_bone_count():
		pose.add_bone(src.get_bone_name(i))
	for i in src.get_bone_count():
		pose.set_bone_parent(i, src.get_bone_parent(i))
		pose.set_bone_rest(i, src.get_bone_rest(i))
		pose.set_bone_pose(i, src.get_bone_pose(i))
	piece.add_child(pose)
	pose.transform = body_xf.affine_inverse() * src.global_transform
	piece.pose = pose
	var mass := 0.0
	var joint_world := _joint_position(root, src)
	for s in group:
		var f := _section_frame(s)
		if f.is_empty():
			continue
		var xf: Transform3D = f[0]
		var box: AABB = f[1]
		var sc := xf.basis.get_scale()
		var size := (box.size * sc * shape_shrink).max(Vector3.ONE * 0.05)
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		shape.shape = bs
		shape.transform = body_xf.affine_inverse() * Transform3D(xf.basis.orthonormalized(), xf * box.get_center())
		piece.add_child(shape)
		mass += size.x * size.y * size.z * density
		# Move the section's meshes (still skinned) onto the frozen pose.
		for mn in s.mesh_names:
			var mi := src.get_node_or_null(NodePath(mn)) as MeshInstance3D
			if mi == null:
				continue
			var local := mi.transform
			src.remove_child(mi)
			pose.add_child(mi)
			mi.transform = local
			mi.skeleton = NodePath("..")
		_detached[s.section_name] = true
	for s in group:
		_carrier[s.section_name] = pose
	piece.mass = clampf(mass, piece_mass_range.x, piece_mass_range.y)
	world.add_child(piece)
	piece.global_transform = body_xf
	piece.reset_physics_interpolation()
	# Launch: away from the blast/impact, steered by the attack direction.
	var center := body_xf.origin
	var radial := center - info.impact_position
	radial = radial.normalized() if radial.length_squared() > 1e-4 else info.impact_direction
	var dir := (radial * (1.0 - direction_bias) + info.impact_direction * direction_bias + Vector3.UP * upward_bias).normalized()
	var speed := minf(base_launch_speed + power * launch_per_power, max_launch_speed) * randf_range(0.7, 1.1) * info.launch_scale
	speed /= clampf(sqrt(piece.mass / 6.0), 1.0, 2.5)
	var spin := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * minf(3.0 + power * 8.0, max_spin) * randf_range(0.5, 1.0)
	piece.launch(base_velocity * 0.6 + dir * speed, spin)
	# Small electrical failure at the broken connection, on both sides.
	var jb := pose.find_bone(root.joint_bone)
	if sparks_on_piece and jb >= 0:
		JointSparks.play_on_bone(pose, jb, 1.0)
	var parent_carrier := _carrier_of(root.parent) if root.parent != &"" else null
	if sparks_on_body and parent_carrier and jb >= 0:
		JointSparks.play_on_bone(parent_carrier, parent_carrier.find_bone(root.joint_bone), 0.85)
	piece_detached.emit(piece, root, joint_world)
	return piece


func _joint_position(s: BreakSection, sk: Skeleton3D) -> Vector3:
	var b := sk.find_bone(s.joint_bone)
	return (sk.global_transform * sk.get_bone_global_pose(b)).origin if b >= 0 else sk.global_position
