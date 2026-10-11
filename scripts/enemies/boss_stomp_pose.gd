class_name BossStompPose
extends SkeletonModifier3D
## The robot boss's foot stomp, procedural, on top of its clips (after the
## torso twist): the weight shifts onto the left leg and the right knee
## comes up high (`lift`), the body leaning back - then the foot slams down
## in front, the hips drop and the body pitches into it; a jolt on impact,
## then it settles back into its stance. Legs by two-bone IK from the foot's
## path; the left foot stays planted. Driven by `t` (seconds into the stomp)
## from RobotBoss. Skeleton space: +Z forward, +X the boss's left.

## Seconds: knee up / slam down (impact) / back to normal.
var raise_time := 0.55
var slam_time := 0.12
var recover_time := 0.55
## Seconds into the stomp; < 0 = not stomping.
var t := -1.0
var last_weight := 0.0

var _b := {}
var _up := 0.38
var _low := 0.28


func impact_time() -> float:
	return raise_time + slam_time


func total_time() -> float:
	return impact_time() + recover_time


func setup(sk: Skeleton3D) -> void:
	for n in ["Hips", "Spine", "Spine1", "Spine2", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]:
		_b[n] = sk.find_bone("mixamorig_" + n)
	if _b.RightUpLeg >= 0:
		var a := sk.get_bone_global_rest(_b.RightUpLeg).origin
		var k := sk.get_bone_global_rest(_b.RightLeg).origin
		var f := sk.get_bone_global_rest(_b.RightFoot).origin
		_up = a.distance_to(k)
		_low = k.distance_to(f)


func _process_modification_with_delta(_delta: float) -> void:
	last_weight = 0.0
	if t < 0.0 or _b.is_empty() or _b.Hips < 0:
		return
	var sk := get_skeleton()
	var L := _up + _low
	var hit := impact_time()
	# Phases: 0..1 knee up, then the slam, then recover.
	var up := smoothstep(0.0, raise_time, t)
	var slam := clampf((t - raise_time) / slam_time, 0.0, 1.0)
	slam = slam * slam
	var rec := clampf((t - hit) / recover_time, 0.0, 1.0)
	var w := smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.25, 1.0, rec))
	if w <= 0.001:
		return
	last_weight = w
	var jolt := exp(-maxf(t - hit, 0.0) * 12.0) if t >= hit else 0.0
	var foot0 := sk.get_bone_global_pose(_b.RightFoot)
	var lfoot := sk.get_bone_global_pose(_b.LeftFoot)
	# Hips: over the left leg as the knee rises, dropping into the stomp.
	var shift := L * 0.16 * up * (1.0 - slam * 0.6)
	var drop := L * (0.03 * up + 0.1 * slam) + L * 0.05 * jolt
	var hp := sk.get_bone_global_pose(_b.Hips)
	hp.origin += Vector3(shift, -drop, L * 0.06 * slam) * w
	var lean := deg_to_rad(-7.0 * up * (1.0 - slam) + 12.0 * slam + 5.0 * jolt)
	hp.basis = Basis(Vector3.RIGHT, lean * w * 0.5) * Basis(Vector3.FORWARD, deg_to_rad(5.0) * up * (1.0 - slam) * w) * hp.basis
	sk.set_bone_global_pose(_b.Hips, hp)
	for n in ["Spine", "Spine1", "Spine2"]:
		if _b[n] < 0:
			continue
		var gp := sk.get_bone_global_pose(_b[n])
		gp.basis = Basis(Vector3.RIGHT, lean / 6.0 * w) * gp.basis
		sk.set_bone_global_pose(_b[n], gp)
	# Right foot: up high and a little forward, then slammed down in front.
	var raised := foot0.origin + Vector3(-L * 0.05, L * 0.72, L * 0.3)
	var planted := foot0.origin + Vector3(0.0, 0.0, L * 0.18)
	var target := raised.lerp(planted, slam) if t < hit else planted
	target = foot0.origin.lerp(target, w)
	_leg_ik(sk, "Right", target, Vector3(-0.35, 0.0, 1.0).normalized(), w)
	# Left foot stays where it is (the hips moved over it).
	_leg_ik(sk, "Left", lfoot.origin, Vector3(0.35, 0.0, 1.0).normalized(), w)
	# Feet keep their orientation; the raised one tips its toes down a bit.
	var fr := sk.get_bone_global_pose(_b.RightFoot)
	fr.basis = Basis(Vector3.RIGHT, deg_to_rad(20.0) * up * (1.0 - slam) * w) * foot0.basis
	sk.set_bone_global_pose(_b.RightFoot, fr)
	var fl := sk.get_bone_global_pose(_b.LeftFoot)
	fl.basis = lfoot.basis
	sk.set_bone_global_pose(_b.LeftFoot, fl)


func _leg_ik(sk: Skeleton3D, side: String, target: Vector3, pole: Vector3, amount: float) -> void:
	var hip := sk.get_bone_global_pose(_b[side + "UpLeg"]).origin
	var a := _up
	var c := _low
	var to := target - hip
	var d := clampf(to.length(), 0.05, (a + c) * 0.999)
	var dir := to.normalized()
	var perp := pole - dir * pole.dot(dir)
	perp = perp.normalized() if perp.length_squared() > 1e-5 else Vector3.FORWARD
	var cos_a := clampf((a * a + d * d - c * c) / (2.0 * a * d), -1.0, 1.0)
	var knee := hip + dir * a * cos_a + perp * a * sqrt(1.0 - cos_a * cos_a)
	_aim(sk, _b[side + "UpLeg"], (knee - hip).normalized(), amount)
	var k2 := sk.get_bone_global_pose(_b[side + "Leg"]).origin
	_aim(sk, _b[side + "Leg"], (hip + dir * d - k2).normalized(), amount)


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
