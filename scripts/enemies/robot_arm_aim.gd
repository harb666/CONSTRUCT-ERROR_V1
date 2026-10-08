class_name RobotArmAim
extends SkeletonModifier3D
## Points the robot's arm-mounted cannons at `target_point` on top of
## whatever clip is playing, arms held out straight like the player's: the
## collarbone, forearm and hand take their rest pose (a straight arm; the
## clip's swing no longer moves them) and the upper arm is set so the
## cannon's muzzle lies on the line from the shoulder to the target, its
## rest "up" side kept up (no rolling). Each arm stays within `arm_cone_deg`
## of where the chest faces (never swung back across the body); outside it
## the cannon is off target (`on_target()` false - the robot holds fire).
## `weight` fades it in/out.

## Emitted every frame once the arms are posed (muzzle_position() is then
## exactly where the cannons are drawn this frame).
signal posed

## World point to aim at.
var target_point := Vector3.ZERO
## Upper-body twist (radians, about the body's up axis) so the chest faces
## the target while the legs face where it's walking; spread over the spine.
var twist := 0.0
var _spine: Array[int] = []
## 0..1 blend (set by the robot; eased here).
var weight := 0.0
var target_weight := 0.0
@export var blend_speed := 6.0
## How much the forearm / hand / collarbone take their rest pose (straight,
## outstretched arm) while aiming.
@export var forearm_straighten := 1.0
## Most an arm points away from the chest's facing (degrees, sideways) and
## up / down.
@export var arm_cone_deg := 50.0
@export var arm_pitch_deg := 60.0
## Off target beyond this (degrees past the cone edge).
@export var on_target_slack_deg := 4.0

## Per side: [upper arm bone, forearm bone, hand bone, muzzle offset in hand
## space, collarbone bone (or -1)]
var _sides: Array = []
## Per side: the target lies outside the arm's reach cone.
var _off: Array[bool] = [false, false]
## Muzzle positions (skeleton space) as last drawn, i.e. AFTER aiming (bone
## poses read outside this modifier don't include its changes).
var _muzzles_local: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _elbows_local: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _have_muzzles := false
## Per cannon (0 = left, 1 = right): firing kick 0..1 that jerks the muzzle
## up and the arm back (set by the robot, decays here). 0 = none.
var kick: Array[float] = [0.0, 0.0]
@export var kick_decay := 14.0
@export var kick_climb := 0.16


func setup(skel: Skeleton3D, muzzles: Dictionary) -> void:
	_sides.clear()
	_spine.clear()
	for b in ["mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2"]:
		var i := skel.find_bone(b)
		if i >= 0:
			_spine.append(i)
	for side in ["Left", "Right"]:
		var arm := skel.find_bone("mixamorig_%sArm" % side)
		var fore := skel.find_bone("mixamorig_%sForeArm" % side)
		var hand := skel.find_bone("mixamorig_%sHand" % side)
		if arm >= 0 and fore >= 0 and hand >= 0:
			_sides.append([arm, fore, hand, muzzles[side], skel.find_bone("mixamorig_%sShoulder" % side)])


## Current world position of a cannon muzzle (0 = left, 1 = right), as
## drawn on screen (including the aiming).
func muzzle_position(i: int) -> Vector3:
	var skel := get_skeleton()
	if skel == null or i >= _sides.size():
		return Vector3.ZERO
	if not _have_muzzles:
		var s: Array = _sides[i]
		return skel.global_transform * (skel.get_bone_global_pose(s[2]) * (s[3] as Vector3))
	return skel.global_transform * _muzzles_local[i]


## Current world position of a cannon's elbow (forearm joint): with the
## muzzle it gives the line a forearm-mounted cannon points along.
func elbow_position(i: int) -> Vector3:
	var skel := get_skeleton()
	if skel == null or i >= _sides.size():
		return Vector3.ZERO
	if not _have_muzzles:
		return skel.global_transform * skel.get_bone_global_pose((_sides[i] as Array)[1]).origin
	return skel.global_transform * _elbows_local[i]


## Both cannons (or `side`: 0 left, 1 right) can point at the target.
func on_target(side := -1) -> bool:
	if weight < 0.6:
		return false
	if side >= 0:
		return side < _off.size() and not _off[side]
	return not (_off[0] or _off[1])


## `d` limited to the arm's cone around the chest's facing (sideways and
## up / down); notes when the target lies outside it.
func _in_cone(d: Vector3, chest: Vector3, side: int) -> Vector3:
	var flat := Vector3(d.x, 0.0, d.z)
	var pitch := atan2(d.y, flat.length())
	var yaw := atan2(flat.x, flat.z) if flat.length_squared() > 1e-8 else atan2(chest.x, chest.z)
	var cy := atan2(chest.x, chest.z)
	var off := wrapf(yaw - cy, -PI, PI)
	var lim := deg_to_rad(arm_cone_deg)
	var plim := deg_to_rad(arm_pitch_deg)
	var slack := deg_to_rad(on_target_slack_deg)
	if side < _off.size():
		_off[side] = absf(off) > lim + slack or absf(pitch) > plim + slack
	yaw = cy + clampf(off, -lim, lim)
	pitch = clampf(pitch, -plim, plim)
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))


## Orthonormal basis with columns (x = `dir`, y = `up` made perpendicular,
## z = x cross y).
static func _frame(dir: Vector3, up: Vector3) -> Basis:
	var x := dir.normalized()
	var y := up - x * up.dot(x)
	if y.length_squared() < 1e-8:
		y = Vector3.BACK - x * Vector3.BACK.dot(x)
	y = y.normalized()
	return Basis(x, y, x.cross(y))


func _store_muzzles(skel: Skeleton3D) -> void:
	for i in _sides.size():
		var s: Array = _sides[i]
		_muzzles_local[i] = skel.get_bone_global_pose(s[2]) * (s[3] as Vector3)
		_elbows_local[i] = skel.get_bone_global_pose(s[1]).origin
	_have_muzzles = true


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	var dt := get_process_delta_time() if is_inside_tree() else 0.016
	weight = move_toward(weight, target_weight, blend_speed * dt)
	for i in kick.size():
		kick[i] = maxf(kick[i] - kick_decay * dt * maxf(kick[i], 0.25), 0.0)
	if weight <= 0.001:
		_store_muzzles(skel)
		posed.emit()
		return
	# Twist the spine first (parents before the arms).
	if absf(twist) > 0.001 and not _spine.is_empty():
		var part := twist * weight / _spine.size()
		for b in _spine:
			var g := skel.get_bone_global_pose(b)
			skel.set_bone_global_pose(b, Transform3D(Basis(Vector3.UP, part) * g.basis, g.origin))
	var target_local := skel.global_transform.affine_inverse() * target_point
	# Where the chest faces (skeleton space: +Z forward), after the twist.
	var chest := Basis(Vector3.UP, twist * weight) * Vector3.BACK
	for si in _sides.size():
		var s: Array = _sides[si]
		var arm: int = s[0]
		var fore: int = s[1]
		var hand: int = s[2]
		var clav: int = s[4]
		# Straight, outstretched arm: collarbone, forearm and hand at rest.
		var k_rest := forearm_straighten * weight
		for b in ([clav, fore, hand] if clav >= 0 else [fore, hand]):
			var q := skel.get_bone_pose_rotation(b).slerp(skel.get_bone_rest(b).basis.get_rotation_quaternion(), k_rest)
			skel.set_bone_pose_rotation(b, q)
		var g_arm := skel.get_bone_global_pose(arm)
		var a := g_arm.origin
		# The muzzle in the upper arm's own space (straight arm below it).
		var m_local := (skel.get_bone_rest(fore) * skel.get_bone_rest(hand)) * (s[3] as Vector3)
		if m_local.length_squared() < 1e-6:
			continue
		# The upper arm's "up" side (as in its rest pose) stays up.
		var up_local := skel.get_bone_global_rest(arm).basis.inverse() * Vector3.UP
		var d := target_local - a
		if d.length_squared() < 1e-6:
			continue
		d = _in_cone(d.normalized(), chest, si)
		var g := _frame(d, Vector3.UP) * _frame(m_local.normalized(), up_local).inverse()
		# Firing kick: the shoulder jerks the muzzle up (rigid, no wobble).
		var k: float = kick[si] if si < kick.size() else 0.0
		if k > 0.001:
			var axis := d.cross(Vector3.UP)
			if axis.length_squared() > 1e-4:
				g = Basis(axis.normalized(), k * kick_climb) * g
		var sc := g_arm.basis.get_scale()
		var q_from := g_arm.basis.get_rotation_quaternion()
		var q_to := g.orthonormalized().get_rotation_quaternion()
		skel.set_bone_global_pose(arm, Transform3D(Basis(q_from.slerp(q_to, weight)).scaled(sc), a))
	_store_muzzles(skel)
	posed.emit()
