class_name BossTorsoTwist
extends SkeletonModifier3D
## The boss's upper body turning ahead of its legs: the spine twists
## towards `target_yaw` (radians, relative to where the hips face, + = left)
## up to `max_deg`, at a heavy, limited rate, so the torso starts tracking
## the player while the legs step round (and small aiming corrections never
## need the feet). Applied at the lower spine (Spine).
##
## It turns about a vertical axis through the middle of the waist (`pivot`,
## skeleton space at rest, carried with the hips), not the Spine bone: the
## rig's spine runs along the front of the body, so turning about the bone
## swung the whole upper body sideways off the pelvis (owner asked to fix:
## it slid off its groin). About the waist's middle it turns in place.

@export var max_deg := 35.0
@export var rate_deg := 80.0
## The waist ring's middle (skeleton space, at rest; only x / z matter).
@export var pivot := Vector3.ZERO

var target_yaw := 0.0
var current := 0.0
var _spine := -1
var _hips := -1
var _pivot_in_hips := Vector3.ZERO


func setup(skel: Skeleton3D) -> void:
	_spine = skel.find_bone("mixamorig_Spine")
	_hips = skel.find_bone("mixamorig_Hips")
	if _spine < 0 or _hips < 0:
		return
	var at := Vector3(pivot.x, skel.get_bone_global_rest(_spine).origin.y, pivot.z)
	_pivot_in_hips = skel.get_bone_global_rest(_hips).affine_inverse() * at


## Where the twist turns about now (skeleton space).
func pivot_now(skel: Skeleton3D) -> Vector3:
	return skel.get_bone_global_pose(_hips) * _pivot_in_hips


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or _spine < 0 or _hips < 0:
		return
	var dt := get_process_delta_time() if is_inside_tree() else 0.016
	var want := clampf(target_yaw, -deg_to_rad(max_deg), deg_to_rad(max_deg))
	current = move_toward(current, want, deg_to_rad(rate_deg) * dt)
	if absf(current) < 1e-4:
		return
	var p := pivot_now(skel)
	var r := Basis(Vector3.UP, current)
	var g := skel.get_bone_global_pose(_spine)
	skel.set_bone_global_pose(_spine, Transform3D(r * g.basis, p + r * (g.origin - p)))
