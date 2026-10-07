class_name BossTorsoTwist
extends SkeletonModifier3D
## The boss's upper body turning ahead of its legs: the spine twists
## towards `target_yaw` (radians, relative to where the hips face, + = left)
## up to `max_deg`, at a heavy, limited rate, so the torso starts tracking
## the player while the legs step round (and small aiming corrections never
## need the feet). Applied at the lower spine (Spine).

@export var max_deg := 35.0
@export var rate_deg := 80.0

var target_yaw := 0.0
var current := 0.0
var _spine := -1


func setup(skel: Skeleton3D) -> void:
	_spine = skel.find_bone("mixamorig_Spine")


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or _spine < 0:
		return
	var dt := get_process_delta_time() if is_inside_tree() else 0.016
	var want := clampf(target_yaw, -deg_to_rad(max_deg), deg_to_rad(max_deg))
	current = move_toward(current, want, deg_to_rad(rate_deg) * dt)
	if absf(current) < 1e-4:
		return
	var g := skel.get_bone_global_pose(_spine)
	skel.set_bone_global_pose(_spine, Transform3D(Basis(Vector3.UP, current) * g.basis, g.origin))
