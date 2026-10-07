extends SceneTree
## Authors the robot boss's heavy mechanical walk on its existing skeleton
## and writes it for tools/build_robot_boss.py:
##   godot --headless --path . -s tools/author_boss_walk.gd [-- out.json]
##
## Heavy_Walk: deliberate steps at an in-place speed of `clip_speed()`
## (model units / s): each foot lifts quickly, carries forward, stomps down
## and then stays planted, sliding back under the body at exactly the walk
## speed (so with the body moving at that speed the feet don't slide).
## The legs are solved with two-bone IK from those foot paths. The weight
## drops after every plant, shifts over the standing leg (sway + lean) and
## the arms and weapons stay nearly rigid, sagging a little after each stomp.
## Heavy_Step: the same steps without stride (turning on the spot).

const GLB := "res://assets/enemies/robot_boss/robot_boss.glb"
const FPS := 30.0
## Two steps (s, at playback speed 1).
const CYCLE := 1.8
## Body travel per step (model units).
const STEP := 0.3
## Share of the cycle each foot is in the air.
const SWING := 0.38
const LIFT := 0.1
## Walks a little lower than it stands (heavier, and the legs keep reach).
const CROUCH := 0.015
## Weight drop after a plant, sideways sway, lean (deg), twist (deg).
const DROP := 0.035
const SWAY := 0.035
const LEAN := 3.0
const TWIST := 2.5
## Turning on the spot: each Heavy_Turn_L/R clip turns the robot TURN_DEG
## (+ = left) in TURN_TIME with two heavy steps; it ends in the rest pose
## rotated by TURN_DEG about the hips, so the game adds the angle to the
## body's yaw and carries on seamlessly (more steps for bigger turns).
const TURN_DEG := 45.0
const TURN_TIME := 1.0
## Left foot leaves the ground at phase 0, the right half a cycle later.
const SIDES := {"Left": 0.0, "Right": 0.5}

var sk: Skeleton3D
var base_rot: Array[Quaternion] = []
var base_pos: Array[Vector3] = []
var base_global: Array[Transform3D] = []


static func clip_speed() -> float:
	return 2.0 * STEP / CYCLE


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_path: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ProjectSettings.globalize_path("res://tools/robot_boss_walk.json")
	var model: Node3D = load(GLB).instantiate()
	root.add_child(model)
	sk = model.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	ap.play(&"Idle")
	ap.seek(0.0, true)
	ap.active = false
	for b in sk.get_bone_count():
		base_rot.append(sk.get_bone_pose_rotation(b))
		base_pos.append(sk.get_bone_pose_position(b))
	sk.force_update_all_bone_transforms()
	for b in sk.get_bone_count():
		base_global.append(sk.get_bone_global_pose(b))
	var clips := []
	for spec in [["Heavy_Walk", STEP], ["Heavy_Step", 0.0]]:
		clips.append(_author(spec[0], spec[1]))
	clips.append(_author_turn("Heavy_Turn_L", TURN_DEG))
	clips.append(_author_turn("Heavy_Turn_R", -TURN_DEG))
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"clips": clips}))
	f.close()
	print("wrote %s; walk speed %.3f model units/s at playback 1" % [out_path, clip_speed()])
	quit()


func _author(clip_name: String, step: float) -> Dictionary:
	var frames := int(round(CYCLE * FPS))
	var times := []
	var rot := {}
	var hips_pos := []
	var reach_err := 0.0
	var slide := 0.0
	var prev_plant := {}
	for fi in frames + 1:
		var t := fi / FPS
		var ph := fposmod(t / CYCLE, 1.0)
		_reset()
		var hips := sk.find_bone("mixamorig_Hips")
		# Weight over the standing leg: sway towards it, lean onto it.
		var s := -cos(TAU * (ph - SWING * 0.5))  # +1: weight on the left foot
		var drop := DROP * (_impact(ph, SWING) + _impact(ph, 0.5 + SWING))
		var hp := base_pos[hips] + Vector3(SWAY * s, -drop - CROUCH, 0.0)
		var lean := Basis(Vector3.BACK, deg_to_rad(-LEAN * s))
		var twist := Basis(Vector3.UP, deg_to_rad(TWIST * sin(TAU * (ph - SWING * 0.5))))
		sk.set_bone_pose_position(hips, hp)
		sk.set_bone_pose_rotation(hips, (lean * twist * Basis(base_rot[hips])).get_rotation_quaternion())
		# Torso stiff, a short forward nod on each stomp; head steadier.
		var nod := 1.6 * (_impact(ph, SWING) + _impact(ph, 0.5 + SWING))
		_delta("mixamorig_Spine2", Basis(Vector3.RIGHT, deg_to_rad(nod)) * Basis(Vector3.UP, deg_to_rad(-TWIST * 0.6 * sin(TAU * (ph - SWING * 0.5)))))
		_delta("mixamorig_Neck", Basis(Vector3.BACK, deg_to_rad(LEAN * 0.6 * s)) * Basis(Vector3.RIGHT, deg_to_rad(-nod * 0.7)))
		# Heavy weapons: they lag the lean and sag after each stomp.
		var lag := -cos(TAU * (ph - SWING * 0.5 - 0.08))
		var sag := 2.5 * (_impact(ph - 0.04, SWING) + _impact(ph - 0.04, 0.5 + SWING))
		_delta("mixamorig_LeftArm", Basis(Vector3.BACK, deg_to_rad(1.5 * lag)) * Basis(Vector3.RIGHT, deg_to_rad(sag)))
		_delta("mixamorig_RightArm", Basis(Vector3.BACK, deg_to_rad(1.5 * lag)) * Basis(Vector3.RIGHT, deg_to_rad(sag)))
		sk.force_update_all_bone_transforms()
		# Legs: feet on their paths, solved with two-bone IK.
		for side in SIDES:
			var fp := fposmod(ph - SIDES[side], 1.0)
			var off := _foot_path(fp, step)
			var foot := sk.find_bone("mixamorig_%sFoot" % side)
			var target: Vector3 = base_global[foot].origin + off
			reach_err = maxf(reach_err, _solve_leg(side, target, _toe_pitch(fp)))
			if fp >= SWING:
				# Planted: in the world (body moving forward at the clip speed)
				# the foot must not move.
				var world_z := target.z + clip_speed() * (step / STEP if STEP > 0.0 else 0.0) * t
				if prev_plant.has(side) and prev_plant[side][0] == int(floor((t / CYCLE) - SIDES[side])):
					slide = maxf(slide, absf(world_z - prev_plant[side][1]))
				else:
					prev_plant[side] = [int(floor((t / CYCLE) - SIDES[side])), world_z]
			else:
				prev_plant.erase(side)
		times.append(t)
		var h := sk.get_bone_pose_position(hips)
		hips_pos.append([h.x, h.y, h.z])
		for b in sk.get_bone_count():
			var q := sk.get_bone_pose_rotation(b)
			if not rot.has(b):
				rot[b] = []
			rot[b].append([q.x, q.y, q.z, q.w])
	print("%s: %d frames, foot IK error %.4f, planted foot slide %.4f" % [clip_name, frames + 1, reach_err, slide])
	var tracks := []
	for b in rot:
		tracks.append({"node": sk.get_bone_name(b).replace("mixamorig_", "mixamorig:"), "path": "rotation", "times": times, "values": rot[b]})
	tracks.append({"node": "mixamorig:Hips", "path": "translation", "times": times, "values": hips_pos})
	return {"name": clip_name, "tracks": tracks}


## One heavy turn step: the lead foot (on the turning side) lifts and plants
## rotated about the hips, then the other foot follows; the body yaws
## progressively, weight shifts onto the standing foot, each plant drops the
## weight. Planted feet stay exactly where they are (IK).
func _author_turn(clip_name: String, deg: float) -> Dictionary:
	var frames := int(round(TURN_TIME * FPS))
	var th := deg_to_rad(deg)
	var lead := "Left" if deg > 0.0 else "Right"
	var hips := sk.find_bone("mixamorig_Hips")
	var pivot := Vector3(base_global[hips].origin.x, 0.0, base_global[hips].origin.z)
	var times := []
	var rot := {}
	var hips_pos := []
	var reach_err := 0.0
	var plants := {}  # side -> [planted position, moved since?]
	var slide := 0.0
	var spans := {lead: Vector2(0.06, 0.46), ("Right" if lead == "Left" else "Left"): Vector2(0.54, 0.88)}
	for fi in frames + 1:
		var t := fi / FPS
		var u := float(fi) / frames
		_reset()
		var a := th * smoothstep(0.06, 0.92, u)
		var R := Basis(Vector3.UP, a)
		var env := 1.0 - smoothstep(0.9, 1.0, u)
		# Weight: on the trailing foot while the lead steps, then on the lead.
		var w := sin(TAU * u) * env  # + = on the trailing foot
		var on_left := w if lead == "Right" else -w
		var drop := DROP * (_impact_t(u, 0.46) + _impact_t(u, 0.88)) * env
		var hp := base_pos[hips]
		var sway := R * Vector3(SWAY * on_left, 0.0, 0.0)
		# (the crouch eases in and out: starts and ends exactly at Idle height)
		sk.set_bone_pose_position(hips, pivot + R * (Vector3(hp.x, 0.0, hp.z) - pivot) + Vector3(0.0, hp.y - drop - CROUCH * sin(PI * u), 0.0) + sway)
		var lean := Basis(R * Vector3.BACK, deg_to_rad(-LEAN * on_left))
		sk.set_bone_pose_rotation(hips, (lean * R * Basis(base_rot[hips])).get_rotation_quaternion())
		var nod := 1.6 * (_impact_t(u, 0.46) + _impact_t(u, 0.88)) * env
		_delta_rot("mixamorig_Spine2", R, Basis(Vector3.RIGHT, deg_to_rad(nod)))
		var sag := 2.5 * (_impact_t(u - 0.03, 0.46) + _impact_t(u - 0.03, 0.88)) * env
		_delta_rot("mixamorig_LeftArm", R, Basis(Vector3.RIGHT, deg_to_rad(sag)))
		_delta_rot("mixamorig_RightArm", R, Basis(Vector3.RIGHT, deg_to_rad(sag)))
		sk.force_update_all_bone_transforms()
		for side in [lead, "Right" if lead == "Left" else "Left"]:
			var foot := sk.find_bone("mixamorig_%sFoot" % side)
			var rest := base_global[foot].origin
			var span: Vector2 = spans[side]
			var k := clampf((u - span.x) / (span.y - span.x), 0.0, 1.0)
			var f := smoothstep(0.1, 0.85, k)
			var target := pivot + Basis(Vector3.UP, th * f) * (rest - pivot)
			var up := 0.0
			if k > 0.0 and k < 1.0:
				up = sin(k / 0.3 * PI * 0.5) if k < 0.3 else (1.0 if k < 0.8 else cos((k - 0.8) / 0.2 * PI * 0.5))
			target.y += LIFT * 0.8 * up
			var toe := -10.0 * sin(k * PI) if k > 0.0 and k < 1.0 else 0.0
			reach_err = maxf(reach_err, _solve_leg(side, target, toe, th * f, (th * f + a) * 0.5))
			# Planted (not between lift-off and touch-down): must not move.
			if k <= 0.0 or k >= 1.0:
				var key := "%s%d" % [side, 0 if k <= 0.0 else 1]
				if plants.has(key):
					slide = maxf(slide, (plants[key] as Vector3).distance_to(target))
				else:
					plants[key] = target
		times.append(t)
		var h := sk.get_bone_pose_position(hips)
		hips_pos.append([h.x, h.y, h.z])
		for b in sk.get_bone_count():
			var q := sk.get_bone_pose_rotation(b)
			if not rot.has(b):
				rot[b] = []
			rot[b].append([q.x, q.y, q.z, q.w])
	# The last frame must be the rest pose turned by `deg` about the hips.
	var end_err := 0.0
	for b in sk.get_bone_count():
		var want := Transform3D(Basis(Vector3.UP, th), Vector3.ZERO).translated(-pivot)
		want = Transform3D(Basis.IDENTITY, pivot) * Transform3D(Basis(Vector3.UP, th), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot) * base_global[b]
		end_err = maxf(end_err, sk.get_bone_global_pose(b).origin.distance_to(want.origin))
	print("%s: %d frames, %.0f deg, foot IK error %.4f, planted foot slide %.4f, end pose error %.4f, pivot %s" % [clip_name, frames + 1, deg, reach_err, slide, end_err, pivot])
	var tracks := []
	for b in rot:
		tracks.append({"node": sk.get_bone_name(b).replace("mixamorig_", "mixamorig:"), "path": "rotation", "times": times, "values": rot[b]})
	tracks.append({"node": "mixamorig:Hips", "path": "translation", "times": times, "values": hips_pos})
	return {"name": clip_name, "tracks": tracks}


## 0..1 bump right after a plant at clip fraction `at` (turn clips).
func _impact_t(u: float, at: float) -> float:
	var d := (u - at) * TURN_TIME
	if d < 0.0 or d > 0.5:
		return 0.0
	return clampf(d / 0.06, 0.0, 1.0) * exp(-maxf(d - 0.06, 0.0) / 0.12)


## Rotation `d` on a bone, in the frame turned by `R` (the turning body).
func _delta_rot(bone: String, R: Basis, d: Basis) -> void:
	var b := sk.find_bone(bone)
	var p := sk.get_bone_parent(b)
	var pg := R * base_global[p].basis
	var dg := R * d * R.inverse()
	sk.set_bone_pose_rotation(b, (pg.inverse() * dg * pg * Basis(base_rot[b])).get_rotation_quaternion())


func _reset() -> void:
	for b in sk.get_bone_count():
		sk.set_bone_pose_rotation(b, base_rot[b])
		sk.set_bone_pose_position(b, base_pos[b])


## Rotation `d` (model axes) applied to a bone on top of its parent.
func _delta(bone: String, d: Basis) -> void:
	var b := sk.find_bone(bone)
	var p := sk.get_bone_parent(b)
	var pg := base_global[p].basis
	sk.set_bone_pose_rotation(b, (pg.inverse() * d * pg * Basis(base_rot[b])).get_rotation_quaternion())


## 0..1 bump right after a foot plants at phase `at`: hits fast, settles.
func _impact(ph: float, at: float) -> float:
	var d := fposmod(ph - at, 1.0) * CYCLE
	if d > 0.5:
		return 0.0
	return clampf(d / 0.06, 0.0, 1.0) * exp(-maxf(d - 0.06, 0.0) / 0.12)


## Foot offset from its standing spot at foot phase fp (0 = leaves ground).
## Stance: slides back at the walk speed; swing: up fast, forward, stomp.
func _foot_path(fp: float, step: float) -> Vector3:
	var reach := step * (1.0 - SWING)
	if fp >= SWING:
		var k := (fp - SWING) / (1.0 - SWING)
		return Vector3(0, 0, lerpf(reach, -reach, k))
	var u := fp / SWING
	# Mechanical: most of the forward travel mid-swing, a quick drop at the end.
	var fwd := smoothstep(0.1, 0.85, u)
	var up := 0.0
	if u < 0.3:
		up = sin(u / 0.3 * PI * 0.5)
	elif u < 0.8:
		up = 1.0
	else:
		up = cos((u - 0.8) / 0.2 * PI * 0.5)
	return Vector3(0, LIFT * up, lerpf(-reach, reach, fwd))


## Toe pitch (deg): heel-down stomp, toes lifted in the air.
func _toe_pitch(fp: float) -> float:
	if fp >= SWING:
		return 0.0
	var u := fp / SWING
	return -12.0 * sin(u * PI)


## Two-bone IK: thigh and shin reach `target` with the knee bending the way
## it does at rest; the foot keeps its rest orientation (+ toe pitch).
## Returns how far the ankle ends up from the target.
func _solve_leg(side: String, target: Vector3, toe_deg: float, foot_yaw := 0.0, knee_yaw := 0.0) -> float:
	var up := sk.find_bone("mixamorig_%sUpLeg" % side)
	var lo := sk.find_bone("mixamorig_%sLeg" % side)
	var ft := sk.find_bone("mixamorig_%sFoot" % side)
	var hip := sk.get_bone_global_pose(up).origin
	var l1 := base_global[up].origin.distance_to(base_global[lo].origin)
	var l2 := base_global[lo].origin.distance_to(base_global[ft].origin)
	var to := target - hip
	var d := clampf(to.length(), absf(l1 - l2) + 1e-3, l1 + l2 - 1e-3)
	var dir := to.normalized()
	# Knee plane from the rest pose.
	var rest_knee := Basis(Vector3.UP, knee_yaw) * (base_global[lo].origin - base_global[up].origin)
	var pole := (rest_knee - dir * rest_knee.dot(dir)).normalized()
	var a := acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))
	var knee := hip + (dir * cos(a) + pole * sin(a)) * l1
	# Thigh.
	var g_up := sk.get_bone_global_pose(up)
	var cur_knee := sk.get_bone_global_pose(lo).origin
	sk.set_bone_global_pose(up, Transform3D(_arc(cur_knee - hip, knee - hip) * g_up.basis, hip))
	sk.force_update_all_bone_transforms()
	# Shin.
	var g_lo := sk.get_bone_global_pose(lo)
	var cur_ankle := sk.get_bone_global_pose(ft).origin
	sk.set_bone_global_pose(lo, Transform3D(_arc(cur_ankle - g_lo.origin, hip + dir * d - g_lo.origin) * g_lo.basis, g_lo.origin))
	sk.force_update_all_bone_transforms()
	# Foot: flat as at rest, toes pitched.
	var g_ft := sk.get_bone_global_pose(ft)
	var yb := Basis(Vector3.UP, foot_yaw)
	sk.set_bone_global_pose(ft, Transform3D(yb * Basis(Vector3.RIGHT, deg_to_rad(toe_deg)) * base_global[ft].basis, g_ft.origin))
	sk.force_update_all_bone_transforms()
	return sk.get_bone_global_pose(ft).origin.distance_to(target)


func _arc(from: Vector3, to: Vector3) -> Basis:
	var axis := from.cross(to)
	if axis.length() < 1e-8:
		return Basis()
	return Basis(axis.normalized(), from.angle_to(to))
