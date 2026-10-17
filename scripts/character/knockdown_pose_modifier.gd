class_name KnockdownPoseModifier
extends SkeletonModifier3D
## Full-body pose for being knocked flying (PlayerKnockdown), procedural, on
## top of everything (clips and rig unchanged):
##  - FLYING: the body tips over backwards about the hips, legs swinging up
##    (hips and knees bent), arms flung up and out, flailing; blasted by a
##    missile it turns a backward somersault first, balled up (knees to the
##    chest, arms in), opening out to land;
##  - DOWN: flat on the back on the floor (a bounce as it lands), knees up a
##    little, arms out;
##  - GETUP: a kip-up - rolls back with the knees tucked to the chest, then
##    snaps up onto its feet (the controller hops) and eases back into the
##    clips.
## Skeleton space: +Z the character's forward, +X its left; tipping
## backwards is a negative turn about +X.

var knockdown: PlayerKnockdown
var last_weight := 0.0
## Current backwards tip (rad) and lie amount (0 standing hips height ->
## 1 hips on the floor), for tests.
var cur_pitch := 0.0
var cur_lie := 0.0

var _b := {}
var _leg_len := 0.5


func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for n in ["Hips", "LeftArm", "LeftForeArm", "RightArm", "RightForeArm", "LeftUpLeg", "LeftLeg", "RightUpLeg", "RightLeg"]:
		_b[n] = sk.find_bone("mixamorig_" + n)
	var a := sk.get_bone_global_rest(_b.LeftUpLeg).origin
	var f := sk.get_bone_global_rest(sk.find_bone("mixamorig_LeftFoot")).origin
	_leg_len = a.distance_to(f)


func _process_modification_with_delta(_delta: float) -> void:
	last_weight = 0.0
	if knockdown == null or not knockdown.active or _b.is_empty() or _b.Hips < 0:
		cur_pitch = 0.0
		cur_lie = 0.0
		return
	var sk := get_skeleton()
	var L := _leg_len
	var t := knockdown.phase_t
	var pitch := knockdown.pitch
	var lie := 0.0
	var flex := 0.0  # hips (+ = thighs up towards the chest)
	var knee := 0.0
	var w := 1.0
	var bounce := 0.0
	var flail := sin(knockdown.flight_t * 22.0)
	var arm_mode := 0  # 0 flail, 1 out flat, 2 tucked
	match knockdown.phase:
		PlayerKnockdown.Phase.FLYING:
			w = smoothstep(0.0, 0.08, t)
			flex = deg_to_rad(50.0)
			knee = deg_to_rad(70.0)
			if knockdown.somersaults > 0:
				# Head over heels: balled up (knees to the chest, arms in)
				# through the turn, opening out to land on the back.
				var left := pitch - (-deg_to_rad(80.0) - TAU * knockdown.somersaults)
				var ball := smoothstep(0.35, 1.2, left) * smoothstep(0.0, 0.1, t)
				flex = lerpf(flex, deg_to_rad(110.0), ball)
				knee = lerpf(knee, deg_to_rad(130.0), ball)
				if ball > 0.5:
					arm_mode = 2
		PlayerKnockdown.Phase.DOWN:
			lie = smoothstep(0.0, 0.07, t)
			bounce = sin(clampf(t / 0.16, 0.0, 1.0) * PI) * L * 0.06
			flex = deg_to_rad(lerpf(50.0, 30.0, clampf(t / 0.12, 0.0, 1.0)))
			knee = deg_to_rad(lerpf(70.0, 45.0, clampf(t / 0.12, 0.0, 1.0)))
			arm_mode = 1
		PlayerKnockdown.Phase.GETUP:
			var tuck_t := knockdown.getup_hop_at
			var total := knockdown.getup_time
			if t < tuck_t:
				var k := smoothstep(0.0, tuck_t, t)
				pitch = lerpf(-PI * 0.5, -deg_to_rad(112.0), k)
				lie = 1.0
				flex = deg_to_rad(lerpf(30.0, 115.0, k))
				knee = deg_to_rad(lerpf(45.0, 125.0, k))
				arm_mode = 2
			else:
				var k := clampf((t - tuck_t) / (total - tuck_t), 0.0, 1.0)
				var e := 1.0 - pow(1.0 - k, 3.0)
				# Snaps up past upright (a little forward) and settles.
				pitch = lerpf(-deg_to_rad(112.0), 0.0, e) + deg_to_rad(10.0) * sin(k * PI) * k
				lie = 1.0 - smoothstep(0.0, 0.55, k)
				flex = deg_to_rad(115.0) * (1.0 - smoothstep(0.1, 0.8, k))
				knee = deg_to_rad(125.0) * (1.0 - smoothstep(0.15, 0.85, k))
				arm_mode = 2
				w = 1.0 - smoothstep(0.75, 1.0, k)
	if w <= 0.001:
		return
	last_weight = w
	cur_pitch = pitch * w
	cur_lie = lie * w
	var tip := Basis(Vector3.RIGHT, pitch * w)
	# Hips: tipped back about themselves, lowered onto the floor when lying
	# (and a little behind where the feet were).
	var hp := sk.get_bone_global_pose(_b.Hips)
	var lie_y := L * 0.22 + bounce
	hp.origin = hp.origin.lerp(Vector3(hp.origin.x, lie_y, hp.origin.z - L * 0.35), lie * w)
	hp.basis = tip * hp.basis
	sk.set_bone_global_pose(_b.Hips, hp)
	# Legs: hips and knees bend about the body's sideways axis.
	for side in ["Left", "Right"]:
		var ul := sk.get_bone_global_pose(_b[side + "UpLeg"])
		ul.basis = Basis(Vector3.RIGHT, -flex * w) * ul.basis
		sk.set_bone_global_pose(_b[side + "UpLeg"], ul)
		var lg := sk.get_bone_global_pose(_b[side + "Leg"])
		lg.basis = Basis(Vector3.RIGHT, knee * w) * lg.basis
		sk.set_bone_global_pose(_b[side + "Leg"], lg)
	# Arms (in the tipped body's frame).
	for side in ["Left", "Right"]:
		var m := 1.0 if side == "Left" else -1.0
		var up_dir: Vector3
		var fore_dir: Vector3
		match arm_mode:
			0:
				var f := flail * (1.0 if side == "Left" else -1.0)
				up_dir = Vector3(0.75 * m, 0.5 + 0.2 * f, -0.35 + 0.25 * f)
				fore_dir = Vector3(0.45 * m, 0.85, 0.15 - 0.3 * f)
			1:
				up_dir = Vector3(0.95 * m, 0.25, 0.1)
				fore_dir = Vector3(0.85 * m, 0.45, 0.3)
			_:
				up_dir = Vector3(0.3 * m, -0.35, 0.88)
				fore_dir = Vector3(-0.1 * m, 0.45, 0.88)
		_aim(sk, _b[side + "Arm"], (tip * up_dir).normalized(), w)
		_aim(sk, _b[side + "ForeArm"], (tip * fore_dir).normalized(), w)


func _aim(sk: Skeleton3D, bone: int, dir: Vector3, amount: float) -> void:
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
