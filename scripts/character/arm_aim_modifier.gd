class_name ArmAimModifier
extends SkeletonModifier3D
## Procedural upper-body layer: raises both arms so the forearms (arm cannons)
## point forward, on top of whatever the AnimationTree produced. Only the
## existing UpperArm/ForeArm bones are re-posed at runtime; shoulders, spine,
## hands and the source clips are untouched. Each bone is turned by the
## smallest rotation onto its aim direction, so the animated twist and the
## natural running sway of the torso are kept.

## 0..1, driven by the CharacterAnimator (smoothed there).
var weight := 0.0
## Per-arm minimum weight while that arm holds a weapon (smoothed by animator).
var armed_weight := {"Left": 0.0, "Right": 0.0}

## Weapon recoil (spring value from the CharacterAnimator: ~1 at peak kick,
## slightly negative on the rebound). Applied to the armed arm (elbow driven
## back, muzzle climbs) and, smaller, to the chest (lean back + twist).
var recoil := 0.0
@export var recoil_upper_arm_deg := 28.0
@export var recoil_forearm_deg := 16.0
@export var recoil_chest_lean_deg := 7.0
@export var recoil_chest_twist_deg := 5.0

## Target tracking (locked enemy). When track_weight > 0 the spine twists
## towards `track_point` (world space) and the armed arm aims straight at it;
## hips and legs keep following the movement animation.
var track_weight := 0.0
var track_point := Vector3.ZERO
var track_side := "Right"
## Max total spine twist (degrees), shared over Spine/Spine1/Spine2.
@export var max_spine_twist := 60.0
@export var max_spine_pitch := 25.0
## Max arm yaw/pitch relative to the body (degrees).
@export var max_arm_yaw := 110.0
@export var max_arm_pitch := 60.0

## Aim directions in character space (x = character's left, y = up, z = forward).
## Upper arm reaches forward-down; forearm points straight ahead, slightly inward.
@export var upper_arm_dir := Vector3(0.12, -0.55, 0.83)
@export var forearm_dir := Vector3(-0.06, 0.04, 1.0)
## How much of the chest's animated yaw/roll sway the aim follows (0 = locked to
## the body's facing, 1 = rigidly attached to the chest).
@export var chest_follow := 0.35
## Fraction of the original upper-arm swing that is kept.
@export var keep_upper_swing := 0.12

var _bones := {}


func _ready() -> void:
	var sk := get_skeleton()
	for side in ["Left", "Right"]:
		_bones[side] = [sk.find_bone("mixamorig_%sArm" % side), sk.find_bone("mixamorig_%sForeArm" % side)]
	_bones["chest"] = sk.find_bone("mixamorig_Spine2")
	_bones["spine"] = [sk.find_bone("mixamorig_Spine"), sk.find_bone("mixamorig_Spine1"), sk.find_bone("mixamorig_Spine2")]


func _process_modification_with_delta(_delta: float) -> void:
	if weight <= 0.001 and armed_weight.Left <= 0.001 and armed_weight.Right <= 0.001 and track_weight <= 0.001 and absf(recoil) < 0.001:
		return
	var sk := get_skeleton()
	if sk == null or _bones.is_empty():
		return

	# Target direction in skeleton space (+Z = character forward).
	var track_yaw := 0.0
	var track_pitch := 0.0
	if track_weight > 0.001:
		var to_sk := sk.get_global_transform_interpolated().affine_inverse() * track_point
		var chest_pos := sk.get_bone_global_pose(_bones.chest).origin
		var d := to_sk - chest_pos
		track_yaw = atan2(d.x, d.z)
		track_pitch = atan2(d.y, Vector2(d.x, d.z).length())
		_twist_spine(sk, track_yaw * track_weight, track_pitch * track_weight)
	if absf(recoil) > 0.001:
		_chest_recoil(sk)
	# Character frame: skeleton space faces +Z. Follow part of the chest's
	# yaw sway so the arms ride with the torso instead of looking bolted on.
	var chest := sk.get_bone_global_pose(_bones.chest).basis
	var chest_fwd := Vector3(chest.z.x, 0.0, chest.z.z).normalized()
	var frame := Basis.IDENTITY
	if chest_fwd.length_squared() > 0.5:
		var sway := atan2(chest_fwd.x, chest_fwd.z)
		frame = Basis(Vector3.UP, sway * chest_follow)

	for side in ["Left", "Right"]:
		var mirror := 1.0 if side == "Left" else -1.0
		var ids: Array = _bones[side]
		var arm_frame := frame
		if side == track_side and track_weight > 0.001:
			var yaw := clampf(track_yaw, -deg_to_rad(max_arm_yaw), deg_to_rad(max_arm_yaw))
			var pitch := clampf(track_pitch, -deg_to_rad(max_arm_pitch), deg_to_rad(max_arm_pitch))
			var aim := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch)
			arm_frame = Basis(frame.get_rotation_quaternion().slerp(aim.get_rotation_quaternion(), track_weight))
		var up_local := Vector3(upper_arm_dir.x * mirror, upper_arm_dir.y, upper_arm_dir.z).normalized()
		var fore_local := Vector3(forearm_dir.x * mirror, forearm_dir.y, forearm_dir.z).normalized()
		if side == track_side and absf(recoil) > 0.001:
			# Kick: elbow driven back, forearm/muzzle climbs (in the arm's frame).
			up_local = Basis(Vector3.RIGHT, deg_to_rad(recoil_upper_arm_deg) * recoil) * up_local
			fore_local = Basis(Vector3.RIGHT, -deg_to_rad(recoil_forearm_deg) * recoil) * fore_local
		var up_dir := arm_frame * up_local
		var fore_dir := arm_frame * fore_local
		var w := maxf(weight, armed_weight[side])
		if side == track_side:
			w = maxf(w, track_weight)
		if w <= 0.001:
			continue
		_aim_bone(sk, ids[0], up_dir, w * (1.0 - keep_upper_swing))
		_aim_bone(sk, ids[1], fore_dir, w)


## Turn the upper body towards the target: the twist is shared over the three
## spine bones (hips/legs untouched) and clamped to a natural range.
func _twist_spine(sk: Skeleton3D, yaw: float, pitch: float) -> void:
	var y := clampf(yaw, -deg_to_rad(max_spine_twist), deg_to_rad(max_spine_twist)) / 3.0
	var p := clampf(pitch, -deg_to_rad(max_spine_pitch), deg_to_rad(max_spine_pitch)) / 3.0
	for b: int in _bones.spine:
		var gp := sk.get_bone_global_pose(b)
		# Pitch around the character's sideways axis, after the yaw twist.
		var side_axis := Basis(Vector3.UP, y) * Vector3.RIGHT
		gp.basis = Basis(side_axis, -p) * Basis(Vector3.UP, y) * gp.basis
		sk.set_bone_global_pose(b, gp)


## Secondary recoil through the upper body: the chest leans back and twists
## towards the firing side (Spine2 only, so hips/legs are untouched).
func _chest_recoil(sk: Skeleton3D) -> void:
	var b: int = _bones.chest
	var gp := sk.get_bone_global_pose(b)
	var twist_sign := 1.0 if track_side == "Right" else -1.0
	var r := Basis(Vector3.UP, deg_to_rad(recoil_chest_twist_deg) * recoil * twist_sign) * Basis(Vector3.RIGHT, -deg_to_rad(recoil_chest_lean_deg) * recoil)
	gp.basis = r * gp.basis
	sk.set_bone_global_pose(b, gp)


## Rotate a bone (globally) so its +Y axis points along `dir`, by `amount`.
func _aim_bone(sk: Skeleton3D, bone: int, dir: Vector3, amount: float) -> void:
	var gp := sk.get_bone_global_pose(bone)
	var cur := gp.basis.y.normalized()
	var axis := cur.cross(dir)
	var s := axis.length()
	var angle := atan2(s, cur.dot(dir))
	if s < 1e-5 or angle < 1e-4:
		return
	var rot := Basis(axis / s, angle * amount)
	gp.basis = rot * gp.basis
	sk.set_bone_global_pose(bone, gp)
