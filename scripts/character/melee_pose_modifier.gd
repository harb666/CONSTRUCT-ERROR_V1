class_name MeleePoseModifier
extends SkeletonModifier3D
## Full-body poses for the melee (PlayerMelee), procedural, on top of
## everything else (added after the ArmAimModifier). Clips and rig are not
## changed. From the move's timeline:
##  - GLIDE (flying in): leaning hard into the flight (more in the air),
##    the striking cannon cocked back by the shoulder, the other arm swept
##    back, the head up at the enemy; on the floor the feet slide in a
##    lunge, in the air they trail;
##  - JAB / HOOK (mirrored: the left arm): the back foot steps back, coil,
##    then the cannon shoots out (the hook swings round from the side with
##    the elbow out), the other arm pulls back, follow-through;
##  - UPPERCUT: deep crouch, fist low, then the body drives up and the
##    cannon comes up through the enemy, elbow bent;
##  - SPIN: the whole body spins a full turn (PlayerMelee.spin), the left
##    arm flung out straight, whipping round into a backfist;
##  - SLAM: both cannons raised together over the head (knees tucked on the hop),
##    then hammered down together, bent over, feet planted wide.
## Legs are placed with two-bone IK (feet keep their animated orientation).
## Skeleton space: +Z is the character's forward, +X its left.

var melee: PlayerMelee
## Tests / renders: force a weight (-1 = from the timeline).
var weight_override := -1.0
## Last applied weight (tests).
var last_weight := 0.0
## Last pose drawn ("glide" or the move's name; tests).
var last_pose := ""

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
	var into := 1.0 if melee.from_glide else smoothstep(0.0, 0.06, t)
	return into * (1.0 - smoothstep(hit + 0.17, end, t))


## 0 coiled (wind-up) -> 1 struck out.
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
	if melee.gliding:
		var g := weight_override if weight_override >= 0.0 else smoothstep(0.0, 0.06, melee.glide_t)
		if g > 0.001:
			last_weight = g
			last_pose = "glide"
			_glide(sk, g)
		return
	var t := melee.t
	var w := weight_override if weight_override >= 0.0 else weight_at(t)
	if w <= 0.001:
		return
	last_weight = w
	last_pose = melee.move_name()
	match melee.move:
		PlayerMelee.Move.HOOK:
			_punch(sk, w, t, -1.0, 1.0)
		PlayerMelee.Move.UPPERCUT:
			_uppercut(sk, w, t)
		PlayerMelee.Move.SPIN:
			_spin(sk, w, t)
		PlayerMelee.Move.SLAM:
			_slam(sk, w, t)
		_:
			_punch(sk, w, t, 1.0, 0.0)


## Follow-through after the hit (0..0.6) and the cannon's kick (1 -> 0).
func _after(t: float) -> Vector2:
	var since := t - melee.strike_t if melee.strike_t >= 0.0 else -1.0
	if since < 0.0:
		return Vector2.ZERO
	return Vector2(sin(clampf(since / 0.22, 0.0, 1.0) * PI) * 0.6, exp(-since * 14.0))


func _feet(sk: Skeleton3D) -> Array:
	var pos := {}
	var rot := {}
	for side in ["Left", "Right"]:
		var g := sk.get_bone_global_pose(_b[side + "Foot"])
		pos[side] = g.origin
		rot[side] = g.basis
	return [pos, rot]


func _set_feet(sk: Skeleton3D, rot: Dictionary, turn: Dictionary) -> void:
	for side in ["Left", "Right"]:
		var fp := sk.get_bone_global_pose(_b[side + "Foot"])
		fp.basis = (turn.get(side, Basis()) as Basis) * (rot[side] as Basis)
		sk.set_bone_global_pose(_b[side + "Foot"], fp)


func _hips(sk: Skeleton3D, offset: Vector3, b: Basis) -> void:
	var hp := sk.get_bone_global_pose(_b.Hips)
	hp.origin += offset
	hp.basis = b * hp.basis
	sk.set_bone_global_pose(_b.Hips, hp)


## Twist (yaw) and lean (forward, + = bent over) spread over the spine.
func _spine(sk: Skeleton3D, base_yaw: float, yaw: float, lean: float) -> void:
	for n in ["Spine", "Spine1", "Spine2"]:
		var gp := sk.get_bone_global_pose(_b[n])
		var y := yaw / 3.0
		var side_axis := Basis(Vector3.UP, base_yaw + y) * Vector3.RIGHT
		gp.basis = Basis(side_axis, lean / 3.0) * Basis(Vector3.UP, y) * gp.basis
		sk.set_bone_global_pose(_b[n], gp)


func _neck(sk: Skeleton3D, b: Basis) -> void:
	if _b.Neck >= 0:
		var np := sk.get_bone_global_pose(_b.Neck)
		np.basis = b * np.basis
		sk.set_bone_global_pose(_b.Neck, np)


func _arm(sk: Skeleton3D, side: String, up: Vector3, fore: Vector3, w: float) -> void:
	_aim_bone(sk, _b[side + "Arm"], up.normalized(), w)
	_aim_bone(sk, _b[side + "ForeArm"], fore.normalized(), w)


## Direction from `side`'s shoulder to the enemy (skeleton space), kept in
## front of the body.
func _punch_dir(sk: Skeleton3D, side: String) -> Vector3:
	var inv := sk.get_global_transform_interpolated().affine_inverse()
	var aim_local: Vector3 = inv * melee.aim_point
	var to_aim := aim_local - sk.get_bone_global_pose(_b[side + "Arm"]).origin
	var d := to_aim.normalized() if to_aim.length_squared() > 1e-4 else Vector3.BACK
	if d.z < 0.2:
		d = (d + Vector3(0, 0, 0.6)).normalized()
	return d


static func _mx(v: Vector3, m: float) -> Vector3:
	return Vector3(v.x * m, v.y, v.z)


## Jab (m = 1, right arm) / hook (m = -1, left arm, `hook` = 1).
func _punch(sk: Skeleton3D, w: float, t: float, m: float, hook: float) -> void:
	var s := strike_at(t)
	var af := _after(t)
	var follow := af.x
	var kick := af.y
	var wind := smoothstep(0.0, melee.windup_time, t)
	var L := _leg_len
	var hit_side := "Right" if m > 0.0 else "Left"
	var guard := "Left" if m > 0.0 else "Right"
	var feet := _feet(sk)
	var foot0: Dictionary = feet[0]

	var hip_yaw := deg_to_rad(lerpf(-22.0, 24.0 + 10.0 * hook, s) + 6.0 * follow) * m
	var crouch := L * lerpf(0.13, 0.2, s) * wind
	var fwd := L * lerpf(-0.06, 0.24, s)
	_hips(sk, Vector3(0.0, -crouch, fwd) * w, Basis(Vector3.UP, hip_yaw * w))
	var spine_yaw := deg_to_rad(lerpf(-30.0 - 12.0 * hook, 26.0 + 12.0 * hook, s) + 10.0 * follow) * m
	var lean := deg_to_rad(lerpf(4.0, 17.0, s) + 4.0 * follow)
	_spine(sk, hip_yaw * w, spine_yaw * w, lean * w)
	# The head keeps looking at the enemy (undo most of the twist).
	_neck(sk, Basis(Vector3.UP, -(hip_yaw + spine_yaw) * 0.7 * w))

	var torso := Basis(Vector3.UP, (hip_yaw + spine_yaw) * w)
	var punch_dir := _punch_dir(sk, hit_side)
	# Striking arm: cocked by the cheek -> straight out at the enemy; the
	# hook comes round from the side, elbow out, upper arm level.
	var up0 := torso * _mx(Vector3(-0.32, -0.3, -0.9).lerp(Vector3(-0.92, -0.12, -0.35), hook).normalized(), m)
	var fore0 := torso * _mx(Vector3(0.08, 0.32, 0.94).lerp(Vector3(0.55, 0.12, 0.82), hook).normalized(), m)
	var flat := Vector3(punch_dir.x, punch_dir.y * 0.4, punch_dir.z).normalized()
	var up1 := punch_dir.lerp((Basis(Vector3.UP, -0.95 * m) * flat), hook).normalized()
	var r_up := _slerp_dir(up0, up1, s)
	var r_fore := _slerp_dir(fore0, punch_dir, s)
	if kick > 0.0:
		var axis := punch_dir.cross(Vector3.UP).normalized()
		if axis.length_squared() > 0.5:
			r_fore = Basis(axis, -deg_to_rad(16.0) * kick) * r_fore
			r_up = Basis(axis, -deg_to_rad(6.0) * kick) * r_up
	_arm(sk, hit_side, r_up, r_fore, w)
	# Other arm: guard out in front -> pulled back to the hip.
	var l_up := _slerp_dir(torso * _mx(Vector3(0.22, -0.38, 0.9).normalized(), m), torso * _mx(Vector3(0.32, -0.82, -0.48).normalized(), m), s)
	var l_fore := _slerp_dir(torso * _mx(Vector3(-0.18, 0.34, 0.92).normalized(), m), torso * _mx(Vector3(-0.12, 0.02, 1.0).normalized(), m), s)
	_arm(sk, guard, l_up, l_fore, w)

	# Legs: front foot planted ahead, back foot stepped back.
	var lift := sin(clampf(t / maxf(melee.windup_time, 0.01), 0.0, 1.0) * PI) * L * 0.16
	var targets := {}
	targets[guard] = (foot0[guard] as Vector3) + _mx(Vector3(L * 0.05, 0.0, L * lerpf(0.28, 0.42, s)), m) * w
	targets[hit_side] = (foot0[hit_side] as Vector3) + _mx(Vector3(-L * 0.08, lift + L * 0.07 * s, -L * lerpf(0.85, 0.95, s)), m) * w
	for side in ["Left", "Right"]:
		_leg_ik(sk, side, targets[side], hip_yaw * w, w)
	# Feet keep their animated orientation; the back one turns out and
	# rolls up onto its toes as the hips drive through.
	var turn := {}
	turn[hit_side] = Basis(Vector3.RIGHT, deg_to_rad(28.0) * s * w) * Basis(Vector3.UP, deg_to_rad(-35.0) * m * w)
	turn[guard] = Basis(Vector3.UP, deg_to_rad(12.0) * m * w)
	_set_feet(sk, feet[1], turn)


## Rising uppercut (right arm): sink low, then drive up through it.
func _uppercut(sk: Skeleton3D, w: float, t: float) -> void:
	var s := strike_at(t)
	var af := _after(t)
	var wind := smoothstep(0.0, melee.windup_time, t)
	var L := _leg_len
	var feet := _feet(sk)
	var foot0: Dictionary = feet[0]
	var hip_yaw := deg_to_rad(lerpf(-24.0, 16.0, s) + 4.0 * af.x)
	var crouch := L * (0.24 * wind * (1.0 - s) - 0.04 * s)
	_hips(sk, Vector3(0.0, -crouch, L * lerpf(0.0, 0.14, s)) * w, Basis(Vector3.UP, hip_yaw * w))
	var spine_yaw := deg_to_rad(lerpf(-24.0, 20.0, s))
	var lean := deg_to_rad(lerpf(20.0 * wind, -12.0, s) - 4.0 * af.x)
	_spine(sk, hip_yaw * w, spine_yaw * w, lean * w)
	_neck(sk, Basis(Vector3.UP, -(hip_yaw + spine_yaw) * 0.6 * w) * Basis(Vector3.RIGHT, -lean * 0.4 * w))
	var torso := Basis(Vector3.UP, (hip_yaw + spine_yaw) * w)
	var pd := _punch_dir(sk, "Right")
	var fwd := Vector3(pd.x, 0.0, pd.z).normalized()
	# Fist low by the hip -> elbow up in front, forearm straight up.
	var up0 := torso * Vector3(-0.3, -0.92, -0.25).normalized()
	var fore0 := torso * Vector3(-0.05, -0.15, 1.0).normalized()
	var up1 := (fwd + Vector3.UP * 0.35 + pd * 0.3).normalized()
	var fore1 := (fwd * 0.3 + Vector3.UP).normalized()
	var r_up := _slerp_dir(up0, up1, s)
	var r_fore := _slerp_dir(fore0, fore1, s)
	if af.y > 0.0:
		var axis := fwd.cross(Vector3.UP).normalized()
		r_fore = Basis(axis, deg_to_rad(14.0) * af.y) * r_fore
	_arm(sk, "Right", r_up, r_fore, w)
	_arm(sk, "Left", _slerp_dir(torso * Vector3(0.25, -0.3, 0.9).normalized(), torso * Vector3(0.35, -0.8, -0.45).normalized(), s),
		_slerp_dir(torso * Vector3(-0.2, 0.45, 0.85).normalized(), torso * Vector3(-0.1, 0.0, 1.0).normalized(), s), w)
	var targets := {
		"Left": (foot0.Left as Vector3) + Vector3(L * 0.06, 0.0, L * 0.14) * w,
		"Right": (foot0.Right as Vector3) + Vector3(-L * 0.06, L * 0.05 * s, -L * 0.12) * w,
	}
	for side in ["Left", "Right"]:
		_leg_ik(sk, side, targets[side], hip_yaw * w, w)
	_set_feet(sk, feet[1], {"Right": Basis(Vector3.RIGHT, deg_to_rad(24.0) * s * w)})


## Glitch spin: a full turn of the whole body, left arm flung out straight,
## whipping round into a backfist at the enemy.
func _spin(sk: Skeleton3D, w: float, t: float) -> void:
	var s := strike_at(t)
	var a := melee.spin
	var L := _leg_len
	var turn := Basis(Vector3.UP, a * w)
	var tuck := sin(clampf(t / maxf(melee.hit_time, 0.01), 0.0, 1.0) * PI)
	_hips(sk, Vector3(0.0, -L * 0.06 * w, 0.0), turn)
	_spine(sk, a * w, 0.0, deg_to_rad(8.0) * w)
	var torso := turn
	var pd := _punch_dir(sk, "Left")
	var out := torso * Vector3(1.0, 0.12, 0.15).normalized()
	var whip := smoothstep(0.7, 1.0, a / TAU) if not melee.hit_done else 1.0
	var dir := _slerp_dir(out, pd, whip)
	var af := _after(t)
	if af.y > 0.0:
		var axis := pd.cross(Vector3.UP).normalized()
		dir = Basis(axis, -deg_to_rad(12.0) * af.y) * dir
	_arm(sk, "Left", dir, dir, w)
	# Right arm tucked across the chest.
	_arm(sk, "Right", torso * Vector3(-0.15, -0.55, 0.8), torso * Vector3(0.6, 0.55, 0.55), w)
	# Knees come up through the hop.
	var feet := _feet(sk)
	var foot0: Dictionary = feet[0]
	for side in ["Left", "Right"]:
		var target := (foot0[side] as Vector3) + Vector3(0.0, L * 0.28 * tuck * (1.0 - s * 0.5), L * 0.08 * tuck) * w
		_leg_ik(sk, side, target, a * w, w)


## Twin cannon slam: both cannons high overhead (knees tucked on the hop),
## then hammered down together, bent over, feet planted wide.
func _slam(sk: Skeleton3D, w: float, t: float) -> void:
	var s := strike_at(t)
	var af := _after(t)
	var wind := smoothstep(0.0, melee.windup_time, t)
	var L := _leg_len
	var feet := _feet(sk)
	var foot0: Dictionary = feet[0]
	var crouch := L * (0.3 * s + 0.08 * af.x)
	_hips(sk, Vector3(0.0, -crouch, L * 0.1 * s) * w, Basis())
	var lean := deg_to_rad(lerpf(-16.0 * wind, 36.0, s) + 6.0 * af.x)
	_spine(sk, 0.0, 0.0, lean * w)
	_neck(sk, Basis(Vector3.RIGHT, -lean * 0.5 * w))
	var pd := (_punch_dir(sk, "Right") + _punch_dir(sk, "Left")) * 0.5
	var fwd := Vector3(pd.x, 0.0, pd.z).normalized()
	for side in ["Left", "Right"]:
		var m := 1.0 if side == "Right" else -1.0
		# Raised together over the head (cannons crossed above it).
		var up0 := _mx(Vector3(0.22, 0.95, -0.12).normalized(), m)
		var fore0 := _mx(Vector3(0.5, 0.55, -0.65).normalized(), m)
		var down := (fwd * 0.8 + Vector3.DOWN * 0.55 + _mx(Vector3(-0.12, 0, 0), m)).normalized()
		var up := _slerp_dir(up0, down, s)
		var fore := _slerp_dir(fore0, down, s)
		if af.y > 0.0:
			var axis := fwd.cross(Vector3.UP).normalized()
			fore = Basis(axis, -deg_to_rad(10.0) * af.y) * fore
		_arm(sk, side, up, fore, w)
	for side in ["Left", "Right"]:
		var m := 1.0 if side == "Right" else -1.0
		var target := (foot0[side] as Vector3) + _mx(Vector3(-L * 0.14 * s, L * 0.3 * wind * (1.0 - s), L * 0.04), m) * w
		_leg_ik(sk, side, target, 0.0, w)


## Flying in: leaning into the flight, the striking cannon cocked back by the
## shoulder, the other arm swept back, the head up at the enemy; feet in a
## sliding lunge on the floor, trailing in the air.
func _glide(sk: Skeleton3D, g: float) -> void:
	var air := not melee._player.is_on_floor() if melee._player else true
	var L := _leg_len
	var arms: Array = PlayerMelee.MOVES[melee.move].arms
	var feet := _feet(sk)
	var foot0: Dictionary = feet[0]
	var lean := deg_to_rad(40.0 if air else 24.0)
	var tilt := Basis(Vector3.RIGHT, lean * g)
	_hips(sk, Vector3(0.0, -L * (0.0 if air else 0.16), 0.0) * g, tilt)
	_spine(sk, 0.0, 0.0, deg_to_rad(8.0) * g)
	_neck(sk, Basis(Vector3.RIGHT, -lean * 0.75 * g))
	for side in ["Left", "Right"]:
		var m := 1.0 if side == "Right" else -1.0
		if arms.has(side):
			# Cannon cocked back by the shoulder, ready.
			_arm(sk, side, tilt * _mx(Vector3(-0.3, -0.2, -0.93), m), tilt * _mx(Vector3(0.1, 0.55, 0.83), m), g)
		else:
			# Swept back along the body.
			_arm(sk, side, tilt * _mx(Vector3(-0.28, -0.55, -0.79), m), tilt * _mx(Vector3(-0.1, -0.45, -0.89), m), g)
	if air:
		# Legs trailing, a little bent.
		for side in ["Left", "Right"]:
			var f := sk.get_bone_global_pose(_b[side + "Foot"]).origin
			_leg_ik(sk, side, f + Vector3(0.0, L * 0.12, -L * 0.1) * g, 0.0, g)
	else:
		# Sliding lunge: lead foot ahead, the other trailing behind.
		var lead := "Left" if arms.has("Right") else "Right"
		var trail := "Right" if lead == "Left" else "Left"
		_leg_ik(sk, lead, (foot0[lead] as Vector3) + Vector3(0.0, 0.0, L * 0.38) * g, 0.0, g)
		_leg_ik(sk, trail, (foot0[trail] as Vector3) + Vector3(0.0, L * 0.06, -L * 0.62) * g, 0.0, g)


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
