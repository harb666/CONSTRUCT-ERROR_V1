class_name RobotArmAim
extends SkeletonModifier3D
## Points the robot's arm-mounted cannons at `target_point` on top of
## whatever clip is playing: the forearm is eased towards its (straight,
## forward) rest pose and the shoulder is turned so the cannon's muzzle lies
## on the line from the shoulder to the target. `weight` fades it in/out.

## World point to aim at.
var target_point := Vector3.ZERO
## 0..1 blend (set by the robot; eased here).
var weight := 0.0
var target_weight := 0.0
@export var blend_speed := 6.0
## How much the forearm straightens towards its rest pose while aiming.
@export var forearm_straighten := 0.75

## Per side: [shoulder bone, forearm bone, hand bone, muzzle offset in hand space]
var _sides: Array = []
## Muzzle positions (skeleton space) as last drawn, i.e. AFTER aiming (bone
## poses read outside this modifier don't include its changes).
var _muzzles_local: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _have_muzzles := false


func setup(skel: Skeleton3D, muzzles: Dictionary) -> void:
	_sides.clear()
	for side in ["Left", "Right"]:
		var arm := skel.find_bone("mixamorig_%sArm" % side)
		var fore := skel.find_bone("mixamorig_%sForeArm" % side)
		var hand := skel.find_bone("mixamorig_%sHand" % side)
		if arm >= 0 and fore >= 0 and hand >= 0:
			_sides.append([arm, fore, hand, muzzles[side]])


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


func _store_muzzles(skel: Skeleton3D) -> void:
	for i in _sides.size():
		var s: Array = _sides[i]
		_muzzles_local[i] = skel.get_bone_global_pose(s[2]) * (s[3] as Vector3)
	_have_muzzles = true


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	var dt := get_process_delta_time() if is_inside_tree() else 0.016
	weight = move_toward(weight, target_weight, blend_speed * dt)
	if weight <= 0.001:
		_store_muzzles(skel)
		return
	var target_local := skel.global_transform.affine_inverse() * target_point
	for s in _sides:
		var arm: int = s[0]
		var fore: int = s[1]
		var hand: int = s[2]
		# Straighten the forearm towards its rest (cannon held forward).
		var fp := skel.get_bone_pose(fore)
		var rest := skel.get_bone_rest(fore)
		var q := fp.basis.get_rotation_quaternion().slerp(rest.basis.get_rotation_quaternion(), forearm_straighten * weight)
		skel.set_bone_pose_rotation(fore, q)
		# Turn the shoulder so the muzzle lines up with the target.
		var g_arm := skel.get_bone_global_pose(arm)
		var muzzle := skel.get_bone_global_pose(hand) * (s[3] as Vector3)
		var from := (muzzle - g_arm.origin)
		var to := (target_local - g_arm.origin)
		if from.length_squared() < 1e-6 or to.length_squared() < 1e-6:
			continue
		var rot := Quaternion(from.normalized(), to.normalized())
		rot = Quaternion.IDENTITY.slerp(rot, weight)
		var new_global := Transform3D(Basis(rot) * g_arm.basis, g_arm.origin)
		skel.set_bone_global_pose(arm, new_global)
	_store_muzzles(skel)
