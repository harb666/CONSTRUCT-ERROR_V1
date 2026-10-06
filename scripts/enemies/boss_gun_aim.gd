class_name BossGunAim
extends SkeletonModifier3D
## Points the robot boss's chaingun at `target_point` on top of whatever
## body clip is playing: the whole arm turns rigidly at the shoulder joint
## (no bending or twisting of the mesh) until the barrel's own axis - the
## muzzle's +Z - points at the target, within `max_angle_deg` of the
## animated pose. `weight` eases in and out.

var target_point := Vector3.ZERO
var weight := 0.0
var target_weight := 0.0
@export var blend_speed := 2.5
@export var max_angle_deg := 55.0
## Turning speed of the arm (deg/s): heavy, mechanical tracking.
@export var track_speed_deg := 70.0

## How far the barrel is from pointing at the target (deg), as drawn.
var aim_error_deg := 180.0

var _arm := -1
var _fore := -1
## Muzzle transform in the forearm bone's space.
var _muzzle_local := Transform3D()
## Current correction (eased towards the wanted one).
var _current := Quaternion()


func setup(skel: Skeleton3D, side: String, muzzle_in_forearm: Transform3D) -> void:
	_arm = skel.find_bone("mixamorig_%sArm" % side)
	_fore = skel.find_bone("mixamorig_%sForeArm" % side)
	_muzzle_local = muzzle_in_forearm


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or _arm < 0:
		return
	var dt := get_process_delta_time() if is_inside_tree() else 0.016
	weight = move_toward(weight, target_weight, blend_speed * dt)
	var target_local := skel.global_transform.affine_inverse() * target_point
	# Wanted correction: turn the arm (about the shoulder) until the barrel
	# points at the target. A few passes (turning moves the muzzle, which is
	# well out from the shoulder; each pass removes most of what's left).
	var arm_g := skel.get_bone_global_pose(_arm)
	var fore_rel := arm_g.affine_inverse() * skel.get_bone_global_pose(_fore)
	var want := Quaternion()
	for i in 6:
		var g := Transform3D(Basis(want) * arm_g.basis, arm_g.origin) * fore_rel * _muzzle_local
		var cur := g.basis.z.normalized()
		var to := (target_local - g.origin).normalized()
		var axis := cur.cross(to)
		if axis.length() > 1e-6:
			want = Quaternion(axis.normalized(), cur.angle_to(to)) * want
	var ang := want.get_angle()
	var limit := deg_to_rad(max_angle_deg)
	if ang > limit:
		want = Quaternion().slerp(want, limit / ang)
	# Heavy arm: turns towards it at a limited rate.
	var step := deg_to_rad(track_speed_deg) * dt
	var goal := Quaternion().slerp(want, weight)
	var gap := _current.angle_to(goal)
	_current = _current.slerp(goal, 1.0 if gap <= step else step / gap)
	if weight > 0.001 or _current.get_angle() > 1e-4:
		skel.set_bone_global_pose(_arm, Transform3D(Basis(_current) * arm_g.basis, arm_g.origin))
	var m := skel.get_bone_global_pose(_fore) * _muzzle_local
	aim_error_deg = rad_to_deg(m.basis.z.normalized().angle_to((target_local - m.origin).normalized()))
