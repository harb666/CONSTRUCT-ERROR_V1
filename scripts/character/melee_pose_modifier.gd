class_name MeleePoseModifier
extends SkeletonModifier3D
## Full-body pose for the melee punch-shot (PlayerMelee), procedural, on top
## of everything else (added after the ArmAimModifier). Clips and rig are not
## changed. From the move's timeline:
##  - WIND-UP: the right foot steps back (lifted, set down behind), knees
##    bend, the hips and chest coil away (right shoulder back), the right arm
##    cocks the cannon back by the cheek, the left arm comes up in front;
##  - STRIKE: hips and chest uncoil hard, the weight drives onto the front
##    foot, the right arm shoots out straight at the enemy (the cannon lands
##    like a fist and fires: it kicks up), the left arm pulls back;
##  - FOLLOW-THROUGH, then it eases back into whatever the clips are doing.
## Legs are placed with two-bone IK (feet keep their animated orientation,
## the back foot turned out and up on its toes). Skeleton space: +Z is the
## character's forward, +X its left.

var melee: PlayerMelee
## Tests / renders: force a weight (-1 = from the timeline).
var weight_override := -1.0
## Last applied weight (tests).
var last_weight := 0.0

var _b := {}
var _up_len := {}
var _low_len := {}
var _leg_len := 0.5


func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for n in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "RightArm", "RightForeArm", "LeftArm", "LeftForeArm",
			"LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]:
		_b[n] = sk.find_bone("mixamorig_" + n)
	for side in ["Left", "Right"]:
		var a := sk.get_bone_global_rest(_b[side + "UpLeg"]).origin
		var k := sk.get_bone_global_rest(_b[side + "Leg"]).origin
		var f := sk.get_bone_global_rest(_b[side + "Foot"]).origin
		_up_len[side] = a.distance_to(k)
		_low_len[side] = k.distance_to(f)
	_leg_len = _up_len.Left + _low_len.Left


## 0..1 strength of the pose at time `t` of the move.
func weight_at(t: float) -> float:
	if melee == null:
		return 0.0
	var end := melee.duration
	var hit := melee.strike_t if melee.strike_t >= 0.0 else melee.hit_time
	return smoothstep(0.0, 0.06, t) * (1.0 - smoothstep(hit + 0.17, end, t))


## 0 coiled (wind-up) -> 1 punched out.
func strike_at(t: float) -> float:
	if melee == null:
		return 0.0
	if melee.hit_done:
		return 1.0
	var k := clampf((t - melee.windup_time) / maxf(melee.hit_time - melee.windup_time, 0.01), 0.0, 1.0)
	return k * k  # accelerating into the hit


func _process_modification_with_delta(_delta: float) -> void:
	last_weight = 0.0
	if melee == null or (not melee.active and weight_override < 0.0):
		return
	var sk := get_skeleton()
	if sk == null or _b.is_empty() or _b.Hips < 0:
		return
	var t := melee.t
	var w := weight_override if weight_override >= 0.0 else weight_at(t)
	if w <= 0.001:
		return
	last_weight = w
	var s := strike_at(t)
	# Follow-through after the hit, and the cannon's kick.
	var since := t - melee.strike_t if melee.strike_t >= 0.0 else -1.0
	var follow := 0.0
	var kick := 0.0
	if since >= 0.0:
		follow = sin(clampf(since / 0.22, 0.0, 1.0) * PI) * 0.6
		kick = exp(-since * 14.0)
	var wind := smoothstep(0.0, melee.windup_time, t)
	var L := _leg_len

	# Animated feet (before anything moves), the targets are relative to them.
	var foot0 := {}
	var foot_basis := {}
	for side in ["Left", "Right"]:
		var g := sk.get_bone_global_pose(_b[side + "Foot"])
		foot0[side] = g.origin
		foot_basis[side] = g.basis

	# --- hips: drop, drive forward, coil / uncoil ---
	var hip_yaw := deg_to_rad(lerpf(-22.0, 24.0, s) + 6.0 * follow)
	var crouch := L * lerpf(0.13, 0.2, s) * wind
	var fwd := L * lerpf(-0.06, 0.24, s)
	var hp := sk.get_bone_global_pose(_b.Hips)
	hp.origin += Vector3(0.0, -crouch, fwd) * w
	hp.basis = Basis(Vector3.UP, hip_yaw * w) * hp.basis
	sk.set_bone_global_pose(_b.Hips, hp)

	# --- spine: twist further and lean into the punch ---
	var spine_yaw := deg_to_rad(lerpf(-30.0, 26.0, s) + 10.0 * follow)
	var lean := deg_to_rad(lerpf(4.0, 17.0, s) + 4.0 * follow)
	for n in ["Spine", "Spine1", "Spine2"]:
		var gp := sk.get_bone_global_pose(_b[n])
		var y := spine_yaw / 3.0 * w
		var side_axis := Basis(Vector3.UP, hip_yaw * w + y) * Vector3.RIGHT
		gp.basis = Basis(side_axis, lean / 3.0 * w) * Basis(Vector3.UP, y) * gp.basis
		sk.set_bone_global_pose(_b[n], gp)
	# The head keeps looking at the enemy (undo most of the twist).
	if _b.Neck >= 0:
		var np := sk.get_bone_global_pose(_b.Neck)
		np.basis = Basis(Vector3.UP, -(hip_yaw + spine_yaw) * 0.7 * w) * np.basis
		sk.set_bone_global_pose(_b.Neck, np)

	# --- arms ---
	var torso := Basis(Vector3.UP, (hip_yaw + spine_yaw) * w)
	var inv := sk.get_global_transform_interpolated().affine_inverse()
	var aim_local: Vector3 = inv * melee.aim_point
	var shoulder := sk.get_bone_global_pose(_b.RightArm).origin
	var to_aim := aim_local - shoulder
	var punch_dir := to_aim.normalized() if to_aim.length_squared() > 1e-4 else Vector3.FORWARD * -1.0
	if punch_dir.z < 0.2:
		punch_dir = (punch_dir + Vector3(0, 0, 0.6)).normalized()
	# Right: cocked by the cheek -> straight out at the enemy (kicks up).
	var r_up := _slerp_dir(torso * Vector3(-0.32, -0.3, -0.9).normalized(), punch_dir, s)
	var r_fore := _slerp_dir(torso * Vector3(0.08, 0.32, 0.94).normalized(), punch_dir, s)
	if kick > 0.0:
		var axis := punch_dir.cross(Vector3.UP).normalized()
		if axis.length_squared() > 0.5:
			r_fore = Basis(axis, -deg_to_rad(16.0) * kick) * r_fore
			r_up = Basis(axis, -deg_to_rad(6.0) * kick) * r_up
	_aim_bone(sk, _b.RightArm, r_up.normalized(), w)
	_aim_bone(sk, _b.RightForeArm, r_fore.normalized(), w)
	# Left: guard out in front -> pulled back to the hip.
	var l_up := _slerp_dir(torso * Vector3(0.22, -0.38, 0.9).normalized(), torso * Vector3(0.32, -0.82, -0.48).normalized(), s)
	var l_fore := _slerp_dir(torso * Vector3(-0.18, 0.34, 0.92).normalized(), torso * Vector3(-0.12, 0.02, 1.0).normalized(), s)
	_aim_bone(sk, _b.LeftArm, l_up, w)
	_aim_bone(sk, _b.LeftForeArm, l_fore, w)

	# --- legs: front foot planted ahead, back foot stepped back ---
	var lift := sin(clampf(t / maxf(melee.windup_time, 0.01), 0.0, 1.0) * PI) * L * 0.16
	var targets := {
		"Left": (foot0.Left as Vector3) + Vector3(L * 0.05, 0.0, L * lerpf(0.28, 0.42, s)) * w,
		"Right": (foot0.Right as Vector3) + Vector3(-L * 0.08, lift + L * 0.07 * s, -L * lerpf(0.85, 0.95, s)) * w,
	}
	for side in ["Left", "Right"]:
		_leg_ik(sk, side, targets[side], hip_yaw * w, w)
	# Feet keep their animated orientation; the back one turns out and
	# rolls up onto its toes as the hips drive through.
	for side in ["Left", "Right"]:
		var fp := sk.get_bone_global_pose(_b[side + "Foot"])
		var b: Basis = foot_basis[side]
		if side == "Right":
			b = Basis(Vector3.UP, deg_to_rad(-35.0) * w) * b
			b = Basis(Vector3.RIGHT, deg_to_rad(28.0) * s * w) * b
		else:
			b = Basis(Vector3.UP, deg_to_rad(12.0) * w) * b
		fp.basis = b
		sk.set_bone_global_pose(_b[side + "Foot"], fp)


## Two-bone IK: thigh and shin aimed so the ankle reaches `target`, knee
## pointing forward (turned with the hips), blended in by `amount`.
func _leg_ik(sk: Skeleton3D, side: String, target: Vector3, yaw: float, amount: float) -> void:
	var hip := sk.get_bone_global_pose(_b[side + "UpLeg"]).origin
	var a: float = _up_len[side]
	var c: float = _low_len[side]
	var to := target - hip
	var d := clampf(to.length(), 0.05, (a + c) * 0.999)
	var dir := to.normalized()
	var out := 0.25 if side == "Left" else -0.25
	var pole := Basis(Vector3.UP, yaw) * Vector3(out, 0.0, 1.0).normalized()
	var perp := (pole - dir * pole.dot(dir))
	perp = perp.normalized() if perp.length_squared() > 1e-5 else Vector3.FORWARD
	var cos_a := clampf((a * a + d * d - c * c) / (2.0 * a * d), -1.0, 1.0)
	var knee := hip + dir * a * cos_a + perp * a * sqrt(1.0 - cos_a * cos_a)
	_aim_bone(sk, _b[side + "UpLeg"], (knee - hip).normalized(), amount)
	var k2 := sk.get_bone_global_pose(_b[side + "Leg"]).origin
	_aim_bone(sk, _b[side + "Leg"], (hip + dir * d - k2).normalized(), amount)


static func _slerp_dir(a: Vector3, b: Vector3, k: float) -> Vector3:
	var q := Quaternion(a.normalized(), b.normalized()) if a.normalized().dot(b.normalized()) > -0.999 else Quaternion(Vector3.UP, PI)
	return (Quaternion.IDENTITY.slerp(q, k) * a).normalized()


## Rotate a bone (globally) so its +Y axis points along `dir`, by `amount`.
func _aim_bone(sk: Skeleton3D, bone: int, dir: Vector3, amount: float) -> void:
	if bone < 0:
		return
	var gp := sk.get_bone_global_pose(bone)
	var cur := gp.basis.y.normalized()
	var axis := cur.cross(dir)
	var sl := axis.length()
	var angle := atan2(sl, cur.dot(dir))
	if sl < 1e-5 or angle < 1e-4:
		return
	gp.basis = Basis(axis / sl, angle * amount) * gp.basis
	sk.set_bone_global_pose(bone, gp)
