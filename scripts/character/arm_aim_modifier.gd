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

## Weapon recoil per arm (spring values from the CharacterAnimator: ~1 at
## peak kick, slightly negative on the rebound). Each arm kicks on its own
## (elbow driven back, muzzle climbs); the chest leans with the combined kick
## and twists towards the side that fired.
var recoil_side := {"Left": 0.0, "Right": 0.0}
@export var recoil_upper_arm_deg := 28.0
@export var recoil_forearm_deg := 16.0
@export var recoil_chest_lean_deg := 7.0
@export var recoil_chest_twist_deg := 5.0

## Independent target tracking per arm (dual wield). Each arm aims at its own
## `track_point[side]` (world space) with `track_weight[side]`; the spine
## twists towards the average of the tracked targets; hips and legs keep
## following the movement animation.
var track_weight := {"Left": 0.0, "Right": 0.0}
var track_point := {"Left": Vector3.ZERO, "Right": Vector3.ZERO}
## Half the distance kept between the two arms' aim lines (m): arms aim
## PARALLEL at a shared target instead of converging, so cannons never meet.
@export var aim_half_spacing := 0.2
## Most an arm may aim across the body (towards the other side), relative to
## the twisted chest, and how far the two arms' aim may cross (left arm aimed
## right of the right arm) before both are held back: within this the
## forearm cannons pass clear of each other.
@export var max_inward_yaw := 40.0
@export var max_cross_deg := 60.0
## When the arms cross (each slot's target on the other side), the right arm
## lifts and the left drops by up to this much (degrees) so the cannons pass
## over/under each other instead of colliding. Starts once they cross by
## `cross_stagger_start` (a shared target is aimed at almost in parallel),
## full at `cross_stagger_full`.
@export var cross_stagger_deg := 14.0
@export var cross_stagger_start := 6.0
@export var cross_stagger_full := 20.0
## Max total spine twist (degrees), shared over Spine/Spine1/Spine2.
@export var max_spine_twist := 60.0

@export_group("Weapon fit")
## Held weapons' bounds in their forearm frames (set by the weapon slots).
var weapon_fit := {"Left": AABB(), "Right": AABB()}
## Smallest gap kept between weapons / weapon and arm or body (m).
@export var fit_margin := 0.015
@export var arm_radius := 0.06
@export var torso_radius := 0.13
## Torso capsule starts this far above the hips bone.
@export var torso_bottom := 0.12
@export var fit_step_deg := 4.0
@export var fit_max_deg := 70.0
## Most extra upper-body turn for an aiming arm reaching across the chest.
@export var fit_max_spine_deg := 50.0
## Weapons taller than this (m) never cross over/under; arms stay apart.
@export var fit_bulky_height := 0.35
## Most extra over/under lift for crossed arms before spreading them instead.
@export var fit_max_stack_deg := 18.0
@export var fit_max_iterations := 12
## How fast corrections relax once no longer needed (degrees/second).
@export var fit_relax_deg_per_s := 40.0
var last_fit_iterations := 0
var _fix := {"yL": 0.0, "yR": 0.0, "pL": 0.0, "pR": 0.0, "sL": 0.0, "sR": 0.0}
@export_group("")
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
	_bones["hand"] = {"Left": sk.find_bone("mixamorig_LeftHand"), "Right": sk.find_bone("mixamorig_RightHand")}
	_bones["hips"] = sk.find_bone("mixamorig_Hips")
	_bones["neck"] = sk.find_bone("mixamorig_Neck")
	_bones["spine"] = [sk.find_bone("mixamorig_Spine"), sk.find_bone("mixamorig_Spine1"), sk.find_bone("mixamorig_Spine2")]


func _process_modification_with_delta(_delta: float) -> void:
	var tracking: bool = track_weight.Left > 0.001 or track_weight.Right > 0.001
	var recoiling: bool = absf(recoil_side.Left) > 0.001 or absf(recoil_side.Right) > 0.001
	if weight <= 0.001 and armed_weight.Left <= 0.001 and armed_weight.Right <= 0.001 and not tracking and not recoiling:
		return
	var sk := get_skeleton()
	if sk == null or _bones.is_empty():
		return

	# Per-arm target direction in skeleton space (+Z = character forward,
	# +X = character's left), from a point beside the chest on that arm's
	# side so a shared target is aimed at in parallel.
	var inv := sk.get_global_transform_interpolated().affine_inverse()
	var chest_pos := sk.get_bone_global_pose(_bones.chest).origin
	var yaw := {"Left": 0.0, "Right": 0.0}
	var pitch := {"Left": 0.0, "Right": 0.0}
	var spine_yaw := 0.0
	var spine_pitch := 0.0
	var wsum := 0.0
	for side in ["Left", "Right"]:
		var tw: float = track_weight[side]
		if tw <= 0.001:
			continue
		var mirror := 1.0 if side == "Left" else -1.0
		var d: Vector3 = inv * (track_point[side] as Vector3) - (chest_pos + Vector3(aim_half_spacing * mirror, 0, 0))
		yaw[side] = atan2(d.x, d.z)
		pitch[side] = atan2(d.y, Vector2(d.x, d.z).length())
		spine_yaw += yaw[side] * tw
		spine_pitch += pitch[side] * tw
		wsum += tw
	if wsum > 0.001:
		# Upper body turns towards the average target; weight = strongest arm.
		var ws := maxf(track_weight.Left, track_weight.Right)
		_twist_spine(sk, spine_yaw / wsum * ws, spine_pitch / wsum * ws)
	var spine_turn := clampf(spine_yaw / maxf(wsum, 0.001), -deg_to_rad(max_spine_twist), deg_to_rad(max_spine_twist)) if wsum > 0.001 else 0.0
	# Never let an arm aim far across the body, and never let them cross.
	var inward := deg_to_rad(max_inward_yaw)
	yaw.Left = maxf(yaw.Left, spine_turn - inward) if track_weight.Left > 0.001 else yaw.Left
	yaw.Right = minf(yaw.Right, spine_turn + inward) if track_weight.Right > 0.001 else yaw.Right
	if track_weight.Left > 0.001 and track_weight.Right > 0.001:
		var cross := deg_to_rad(max_cross_deg)
		if yaw.Left < yaw.Right - cross:
			var mid: float = (yaw.Left + yaw.Right) * 0.5
			yaw.Left = mid - cross * 0.5
			yaw.Right = mid + cross * 0.5
		# Crossed: stagger vertically (right over, left under). Bulky weapons
		# don't cross at all (the fit resolver keeps them on their own sides).
		var crossing: float = clampf((yaw.Right - yaw.Left - deg_to_rad(cross_stagger_start)) / deg_to_rad(cross_stagger_full - cross_stagger_start), 0.0, 1.0)
		if crossing > 0.0 and not _bulky():
			var st := deg_to_rad(cross_stagger_deg) * crossing
			pitch.Right += st
			pitch.Left -= st
	if recoiling:
		_chest_recoil(sk)
	# Character frame: skeleton space faces +Z. Follow part of the chest's
	# yaw sway so the arms ride with the torso instead of looking bolted on.
	var chest := sk.get_bone_global_pose(_bones.chest).basis
	var chest_fwd := Vector3(chest.z.x, 0.0, chest.z.z).normalized()
	var frame := Basis.IDENTITY
	if chest_fwd.length_squared() > 0.5:
		var sway := atan2(chest_fwd.x, chest_fwd.z)
		frame = Basis(Vector3.UP, sway * chest_follow)

	var arm_frames := {}
	var up_dirs := {}
	var fore_dirs := {}
	var weights := {}
	for side in ["Left", "Right"]:
		var mirror := 1.0 if side == "Left" else -1.0
		var tw: float = track_weight[side]
		var arm_frame := frame
		if tw > 0.001:
			var y := clampf(yaw[side], -deg_to_rad(max_arm_yaw), deg_to_rad(max_arm_yaw))
			var p := clampf(pitch[side], -deg_to_rad(max_arm_pitch), deg_to_rad(max_arm_pitch))
			var aim := Basis(Vector3.UP, y) * Basis(Vector3.RIGHT, -p)
			arm_frame = Basis(frame.get_rotation_quaternion().slerp(aim.get_rotation_quaternion(), tw))
		var up_local := Vector3(upper_arm_dir.x * mirror, upper_arm_dir.y, upper_arm_dir.z).normalized()
		var fore_local := Vector3(forearm_dir.x * mirror, forearm_dir.y, forearm_dir.z).normalized()
		var r: float = recoil_side[side]
		if absf(r) > 0.001:
			# Kick: elbow driven back, forearm/muzzle climbs (in the arm's
			# own frame: pitch only, so it never swings into the other arm).
			up_local = Basis(Vector3.RIGHT, deg_to_rad(recoil_upper_arm_deg) * r) * up_local
			fore_local = Basis(Vector3.RIGHT, -deg_to_rad(recoil_forearm_deg) * r) * fore_local
		arm_frames[side] = arm_frame
		up_dirs[side] = up_local
		fore_dirs[side] = fore_local
		weights[side] = maxf(maxf(weight, armed_weight[side]), tw)
	_pose_arms_clear(sk, arm_frames, up_dirs, fore_dirs, weights, yaw.Right > yaw.Left and track_weight.Left > 0.001 and track_weight.Right > 0.001 and not _bulky())


## Either held weapon too tall to pass over/under the other one.
func _bulky() -> bool:
	return weapon_fit.Left.size.y > fit_bulky_height or weapon_fit.Right.size.y > fit_bulky_height


## Aim both arms, then make sure the held weapons stay clear of each other,
## of the other arm and of the body: the weapons' boxes (in the forearm
## frame, from the weapon slots) are predicted from the posed bones and,
## while anything would touch, the arms are spread apart (or, when crossed,
## stacked over/under) a little more and re-posed. Corrections appear at
## once and relax slowly, so nothing ever visibly passes through.
func _pose_arms_clear(sk: Skeleton3D, frames: Dictionary, ups: Dictionary, fores: Dictionary, weights: Dictionary, crossed: bool) -> void:
	# Local poses (restoring locals keeps the hierarchy when the spine is
	# re-twisted below).
	var saved := {}
	var restore: Array[int] = []
	restore.append_array(_bones.spine)
	restore.append_array(_bones.Left)
	restore.append_array(_bones.Right)
	for b: int in restore:
		saved[b] = sk.get_bone_pose(b)
	var have_fit: bool = weapon_fit.Left.size != Vector3.ZERO or weapon_fit.Right.size != Vector3.ZERO
	var dt := get_process_delta_time() if is_inside_tree() else 0.016
	var relax := deg_to_rad(fit_relax_deg_per_s) * dt
	var need := {"yL": 0.0, "yR": 0.0, "pL": 0.0, "pR": 0.0, "sL": 0.0, "sR": 0.0}
	var applied := {}
	for k in need:
		applied[k] = maxf(_fix[k] - relax, 0.0)
	last_fit_iterations = 0
	for it in fit_max_iterations:
		for b: int in restore:
			sk.set_bone_pose(b, saved[b])
		# Extra upper-body turn towards an aiming arm that reaches across the
		# chest (its shoulder comes forward, so the weapon clears the body).
		var extra: float = applied.sR - applied.sL
		if absf(extra) > 0.0001:
			_twist_spine(sk, extra, 0.0, false)
		for side in ["Left", "Right"]:
			var ids: Array = _bones[side]
			var w: float = weights[side]
			if w <= 0.001:
				continue
			# Outward yaw (left arm +, right arm -) and lift (right over when
			# crossed, left under).
			var fy: float = applied["y" + side[0]] * (1.0 if side == "Left" else -1.0)
			var fp: float = applied["p" + side[0]] * (1.0 if side == "Right" else -1.0)
			var f: Basis = Basis(Vector3.UP, fy) * (frames[side] as Basis) * Basis(Vector3.RIGHT, -fp)
			_aim_bone(sk, ids[0], f * (ups[side] as Vector3), w * (1.0 - keep_upper_swing))
			_aim_bone(sk, ids[1], f * (fores[side] as Vector3), w)
		if not have_fit:
			break
		last_fit_iterations = it + 1
		var hits := _fit_contacts(sk)
		if hits.is_empty():
			break
		for h: String in hits:
			match h:
				"weapons", "arm":
					# Crossed arms stack over/under, up to a point; bulky weapons
					# that need more than that spread apart (uncross) instead.
					if crossed and applied.pR < deg_to_rad(fit_max_stack_deg):
						need.pR = applied.pR + deg_to_rad(fit_step_deg)
						need.pL = applied.pL + deg_to_rad(fit_step_deg)
					else:
						# Only one arm aiming: the idle arm moves out of its way
						# (the aiming arm stays on target); otherwise both spread.
						var aim_r: bool = track_weight.Right > 0.5
						var aim_l: bool = track_weight.Left > 0.5
						if not aim_r or aim_l:
							need.yR = applied.yR + deg_to_rad(fit_step_deg)
						if not aim_l or aim_r:
							need.yL = applied.yL + deg_to_rad(fit_step_deg)
				"torso_Left", "torso_Right":
					var sd := h.substr(6)
					var k := sd[0]
					if track_weight[sd] > 0.5 and applied["s" + k] < deg_to_rad(fit_max_spine_deg):
						# Aiming: the body turns further instead of pulling the
						# weapon off target.
						need["s" + k] = applied["s" + k] + deg_to_rad(fit_step_deg)
					else:
						need["y" + k] = applied["y" + k] + deg_to_rad(fit_step_deg)
		for k in need:
			applied[k] = minf(maxf(applied[k], need[k]), deg_to_rad(fit_max_deg))
	for k in applied:
		_fix[k] = applied[k]


## Which contacts the current pose has: "weapons", "arm" (a weapon against
## the other arm), "torso_<side>".
func _fit_contacts(sk: Skeleton3D) -> Array[String]:
	var out: Array[String] = []
	var boxes := {}
	var segs := {}
	for side in ["Left", "Right"]:
		var ids: Array = _bones[side]
		var fore := sk.get_bone_global_pose(ids[1])
		segs[side] = [sk.get_bone_global_pose(ids[0]).origin, fore.origin, sk.get_bone_global_pose(_bones.hand[side]).origin]
		var box: AABB = weapon_fit[side]
		if box.size != Vector3.ZERO:
			var xf := WeaponSlot.forearm_frame(fore)
			boxes[side] = [xf * box.get_center(), [xf.basis.x * box.size.x * 0.5, xf.basis.y * box.size.y * 0.5, xf.basis.z * box.size.z * 0.5]]
	if boxes.has("Left") and boxes.has("Right") and WeaponBounds.gap(boxes.Left, boxes.Right) < fit_margin:
		out.append("weapons")
	var torso_a := sk.get_bone_global_pose(_bones.hips).origin + Vector3(0, torso_bottom, 0)
	var torso_b := sk.get_bone_global_pose(_bones.neck).origin
	for side in boxes:
		var other: Array = segs["Left" if side == "Right" else "Right"]
		if WeaponBounds.capsule_gap(boxes[side], other[0], other[1], arm_radius) < fit_margin \
				or WeaponBounds.capsule_gap(boxes[side], other[1], other[2], arm_radius) < fit_margin:
			if not out.has("arm"):
				out.append("arm")
		if WeaponBounds.capsule_gap(boxes[side], torso_a, torso_b, torso_radius) < fit_margin:
			out.append("torso_" + side)
	return out


## Turn the upper body towards the target: the twist is shared over the three
## spine bones (hips/legs untouched) and clamped to a natural range.
func _twist_spine(sk: Skeleton3D, yaw: float, pitch: float, clamp_twist := true) -> void:
	var lim := deg_to_rad(max_spine_twist) if clamp_twist else PI
	var y := clampf(yaw, -lim, lim) / 3.0
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
	# Both firing: stronger lean, twists cancel out.
	var lean: float = clampf(recoil_side.Left + recoil_side.Right, -1.5, 1.5)
	var twist: float = recoil_side.Right - recoil_side.Left
	var r := Basis(Vector3.UP, deg_to_rad(recoil_chest_twist_deg) * twist) * Basis(Vector3.RIGHT, -deg_to_rad(recoil_chest_lean_deg) * lean)
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
