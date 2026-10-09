class_name RobotWalker
extends SkeletonModifier3D
## Procedural legs: the robot's thighs, shins and feet are posed here from a
## step cycle instead of the clip (the clip still moves the hips, torso and
## arms). For a model whose walk / run clips don't fit its legs.
##
##  * Step cycle: a phase runs at a cadence set by the body's speed; each
##    leg is planted for the first `duty` of its half of the cycle and
##    swings for the rest (legs half a cycle apart). Faster = quicker steps,
##    longer strides, a shorter planted share (a run has a flight phase).
##  * A planted foot is locked to its spot on the floor (never slides) and
##    lies flat on it; a swinging foot arcs to where it will be under the
##    hip half-way through its next stance (from the body's velocity, so it
##    follows turns, strafes, backpedals and stops), toes dipping as it lifts
##    and rising as it lands.
##  * Standing: the cycle stops with both feet down; a foot left out of
##    place (after a stop or turning on the spot) takes a settling step.
##  * Feet stay under the hips at `stance_width`, knees bend forward (a
##    little outward), hips crouch a bit with speed and bob with the steps,
##    and drop further if a leg couldn't reach.
## Active while the clip playing is one of `gaits` (else it fades out).

var gaits := {}
var body: RigidBody3D
var enabled := true
var weight := 0.0

## Feet this far (m) either side of the body's centre line.
@export var stance_width := 0.29
## Feet planted this far (m) ahead of the hips' rest point.
@export var stance_forward := 0.02
## Step cycles per second at standstill-walk and at `run_speed`.
@export var cadence := Vector2(1.0, 2.3)
@export var run_speed := 4.6
## Planted share of each leg's cycle at walking pace and at a full run.
@export var duty := Vector2(0.6, 0.34)
## Swing lift height (m), walking -> running.
@export var lift := Vector2(0.09, 0.2)
## Hips lowered (m) walking -> running, and their bob per step.
@export var crouch := Vector2(0.04, 0.14)
@export var bob := Vector2(0.015, 0.035)
## Toes dip at lift-off / rise before landing (radians).
@export var toe_swing := 0.45
## Knees point this far (radians) outward from straight ahead.
@export var knee_out := 0.25
## Standing: a foot further than this (m) from its place steps over.
@export var settle_distance := 0.1
@export var settle_yaw := 0.45
## Most the hips drop (m) beyond the crouch so a leg can reach.
@export var max_hip_drop := 0.18
@export var max_camera_distance := 40.0

var phase := 0.0
## Steps taken (tests).
var steps := 0
var _ap: AnimationPlayer
var _hips := -1
var _legs: Array[WLeg] = []
var _drop := 0.0
var _moving := false
## The model's scale (a scaled-up robot): world-space step sizes grow with
## it and its steps come slower, so a bigger robot strides like a big one.
var _k := 1.0


class WLeg:
	var thigh := -1
	var shin := -1
	var foot := -1
	var side := 1.0
	var rest_thigh := Basis()
	var rest_shin := Basis()
	var rest_foot := Basis()
	var thigh_dir := Vector3.DOWN
	var shin_dir := Vector3.DOWN
	var l1 := 0.25
	var l2 := 0.3
	var ankle_h := 0.1
	## World state.
	var pos := Vector3.ZERO
	var yaw := 0.0
	var planted := true
	var from := Vector3.ZERO
	var from_yaw := 0.0
	var t := 0.0
	var placed := false
	var floor_n := Vector3.UP


func setup(skel: Skeleton3D, anim: AnimationPlayer, gait_table: Dictionary, rigid: RigidBody3D) -> void:
	gaits = gait_table
	body = rigid
	_ap = anim
	_hips = skel.find_bone(&"mixamorig_Hips")
	_legs.clear()
	for side in ["Left", "Right"]:
		var l := WLeg.new()
		l.thigh = skel.find_bone("mixamorig_%sUpLeg" % side)
		l.shin = skel.find_bone("mixamorig_%sLeg" % side)
		l.foot = skel.find_bone("mixamorig_%sFoot" % side)
		if l.thigh < 0 or l.shin < 0 or l.foot < 0:
			continue
		var rt := skel.get_bone_global_rest(l.thigh)
		var rs := skel.get_bone_global_rest(l.shin)
		var rf := skel.get_bone_global_rest(l.foot)
		l.side = signf(rf.origin.x) if absf(rf.origin.x) > 0.001 else (1.0 if side == "Left" else -1.0)
		l.rest_thigh = rt.basis
		l.rest_shin = rs.basis
		l.rest_foot = rf.basis
		l.thigh_dir = (rs.origin - rt.origin).normalized()
		l.shin_dir = (rf.origin - rs.origin).normalized()
		l.l1 = rt.origin.distance_to(rs.origin)
		l.l2 = rs.origin.distance_to(rf.origin)
		l.ankle_h = rf.origin.y
		_legs.append(l)
	phase = randf()


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or _legs.size() != 2 or _hips < 0:
		return
	var dt := get_process_delta_time() if is_inside_tree() else 0.016
	dt = minf(dt, 0.05)
	var active := enabled and _ap != null and _ap.is_playing() and gaits.has(StringName(_ap.current_animation))
	if active and is_inside_tree():
		var cam := get_viewport().get_camera_3d()
		if cam and cam.global_position.distance_to(skel.global_position) > max_camera_distance:
			active = false
	weight = move_toward(weight, 1.0 if active else 0.0, dt / 0.15)
	if weight <= 0.001:
		for l in _legs:
			l.placed = false
		return
	var xf := skel.global_transform
	var inv := xf.affine_inverse()
	_k = maxf(xf.basis.get_scale().y, 0.01)
	var fwd := xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.BACK
	var body_yaw := atan2(fwd.x, fwd.z)
	var vel := body.linear_velocity if body else Vector3.ZERO
	vel.y = 0.0
	var speed := vel.length()
	var s := clampf(speed / run_speed, 0.0, 1.0)
	var hips_rest := skel.get_bone_global_rest(_hips).origin
	# Where each foot belongs now (world), under the hips.
	var home: Array[Vector3] = []
	for l in _legs:
		home.append(xf * Vector3(stance_width * l.side, 0.0, hips_rest.z + stance_forward))
	for i in 2:
		var l := _legs[i]
		if not l.placed:
			l.pos = _on_floor(l, home[i])
			l.yaw = body_yaw
			l.planted = true
			l.placed = true
	# Cycle: runs while moving; standing, it runs only to finish a step or
	# to settle a foot that's out of place.
	var f := lerpf(cadence.x, cadence.y, s) / _k
	var d := lerpf(duty.x, duty.y, s)
	_moving = speed > (0.12 if _moving else 0.25)
	var settle := false
	if not _moving:
		for i in 2:
			var l := _legs[i]
			var off := Vector2(l.pos.x - home[i].x, l.pos.z - home[i].z).length()
			if off > settle_distance * _k or absf(wrapf(l.yaw - body_yaw, -PI, PI)) > settle_yaw:
				settle = true
	var any_swing := not _legs[0].planted or not _legs[1].planted
	if _moving or settle or any_swing:
		phase = fposmod(phase + dt * maxf(f, 1.1 if not _moving else f), 1.0)
	var stance_time := d / maxf(f, 0.1)
	for i in 2:
		var l := _legs[i]
		var q := fposmod(phase + 0.5 * i, 1.0)
		var swing := q >= d
		if swing and l.planted:
			# Standing and in place: stay down (the other foot settles).
			if not _moving and not any_swing and not settle:
				continue
			if not _moving and Vector2(l.pos.x - home[i].x, l.pos.z - home[i].z).length() < settle_distance * _k * 0.5 \
					and absf(wrapf(l.yaw - body_yaw, -PI, PI)) < settle_yaw * 0.5:
				continue
			l.planted = false
			l.from = l.pos
			l.from_yaw = l.yaw
		if not l.planted:
			var t := clampf((q - d) / (1.0 - d), 0.0, 1.0) if swing else 1.0
			l.t = t
			# Land where it will be under the hip half-way through its next
			# stance.
			var left := (1.0 - t) * (1.0 - d) / maxf(f, 0.1)
			var lead := vel * (left + stance_time * 0.5) if _moving else Vector3.ZERO
			var to := _on_floor(l, home[i] + lead)
			var e := t * t * (3.0 - 2.0 * t)
			var p := l.from.lerp(to, e)
			p.y = lerpf(l.from.y, to.y, e) + sin(PI * t) * lerpf(lift.x, lift.y, s) * _k
			l.pos = p
			l.yaw = lerp_angle(l.from_yaw, body_yaw, e)
			if not swing or t >= 1.0:
				l.planted = true
				l.pos = to
				l.yaw = body_yaw
				steps += 1
	# Hips: crouch with speed, bob (lowest as each foot lands), and drop
	# further if a foot is out of reach.
	var hips_g := skel.get_bone_global_pose(_hips)
	var low := lerpf(crouch.x, crouch.y, s) if _moving else crouch.x
	if _moving:
		low += lerpf(bob.x, bob.y, s) * (0.5 + 0.5 * cos(TAU * 2.0 * (phase - d * 0.25)))
	var need := 0.0
	for l in _legs:
		var a := hips_g.origin + (skel.get_bone_global_pose(l.thigh).origin - hips_g.origin)
		a.y -= low
		var tgt := inv * l.pos
		var dv := tgt - a
		var reach := (l.l1 + l.l2) * 0.97
		var horiz := Vector2(dv.x, dv.z).length()
		if horiz < reach:
			need = maxf(need, -dv.y - sqrt(reach * reach - horiz * horiz))
	_drop = move_toward(_drop, clampf(need, 0.0, max_hip_drop), dt * 3.0)
	hips_g.origin.y -= (low + _drop) * weight
	skel.set_bone_global_pose(_hips, hips_g)
	# Legs.
	for l in _legs:
		_solve(skel, l, inv, body_yaw)


func _on_floor(l: WLeg, p: Vector3) -> Vector3:
	var y := body.global_position.y if body else p.y
	if body and body.is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, y + 0.6 * _k, p.z), Vector3(p.x, y - 1.4 * _k, p.z))
		q.collision_mask = 1
		q.exclude = [body.get_rid()]
		var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and not (hit.collider is RigidBody3D or hit.collider is CharacterBody3D):
			var n: Vector3 = hit.normal
			l.floor_n = n if n.dot(Vector3.UP) > 0.7 else Vector3.UP
			return Vector3(p.x, hit.position.y + l.ankle_h * _k, p.z)
	l.floor_n = Vector3.UP
	var base := (get_skeleton().global_transform * Vector3.ZERO).y
	return Vector3(p.x, base + l.ankle_h * _k, p.z)


## Orthonormal frame with x along `dir` and y along `pole` (made
## perpendicular).
static func _frame(dir: Vector3, pole: Vector3) -> Basis:
	var x := dir.normalized()
	var y := (pole - x * pole.dot(x))
	if y.length_squared() < 1e-8:
		y = Vector3.UP.cross(x) if absf(x.y) < 0.99 else Vector3.RIGHT
	y = y.normalized()
	return Basis(x, y, x.cross(y))


func _solve(skel: Skeleton3D, l: WLeg, inv: Transform3D, body_yaw: float) -> void:
	var anim_t := skel.get_bone_global_pose(l.thigh)
	var anim_s := skel.get_bone_global_pose(l.shin)
	var anim_f := skel.get_bone_global_pose(l.foot)
	var a := anim_t.origin
	var target := inv * l.pos
	var to := target - a
	var dist := clampf(to.length(), absf(l.l1 - l.l2) + 0.01, (l.l1 + l.l2) * 0.999)
	var u := to.normalized() if to.length_squared() > 1e-8 else Vector3.DOWN
	# Knee forward along the foot's heading, a little outward.
	var yd := wrapf(l.yaw - body_yaw, -PI, PI)
	var pole := Basis(Vector3.UP, yd) * Vector3(sin(knee_out) * l.side, 0.0, cos(knee_out))
	pole = (pole - u * pole.dot(u))
	if pole.length_squared() < 1e-8:
		pole = Vector3.BACK
	pole = pole.normalized()
	var cos_a := clampf((l.l1 * l.l1 + dist * dist - l.l2 * l.l2) / (2.0 * l.l1 * dist), -1.0, 1.0)
	var knee := a + u * (l.l1 * cos_a) + pole * (l.l1 * sqrt(1.0 - cos_a * cos_a))
	var ankle := a + u * dist
	var rest_pole := Vector3.BACK
	var tb := _frame(knee - a, pole) * _frame(l.thigh_dir, rest_pole).transposed() * l.rest_thigh
	var sb := _frame(ankle - knee, pole) * _frame(l.shin_dir, rest_pole).transposed() * l.rest_shin
	# Foot: flat (rest), turned to its heading, toes dipping / rising in
	# the swing, tilted to the floor when planted.
	var pitch := 0.0 if l.planted else toe_swing * sin(TAU * l.t) * 0.5 * (1.0 - absf(1.0 - 2.0 * l.t) * 0.3)
	var fb := Basis(Vector3.UP, yd) * Basis(Vector3.RIGHT, pitch) * l.rest_foot
	if l.planted and l.floor_n.dot(Vector3.UP) < 0.999:
		var n := (inv.basis * l.floor_n).normalized()
		var ax := Vector3.UP.cross(n)
		if ax.length_squared() > 1e-6:
			fb = Basis(ax.normalized(), Vector3.UP.angle_to(n)) * fb
	var w := weight
	skel.set_bone_global_pose(l.thigh, Transform3D(_blend(anim_t.basis, tb, w), a))
	var s_now := skel.get_bone_global_pose(l.shin)
	skel.set_bone_global_pose(l.shin, Transform3D(_blend(anim_s.basis, sb, w), s_now.origin))
	var f_now := skel.get_bone_global_pose(l.foot)
	skel.set_bone_global_pose(l.foot, Transform3D(_blend(anim_f.basis, fb, w), f_now.origin))


static func _blend(a: Basis, b: Basis, w: float) -> Basis:
	if w >= 0.999:
		return b
	var sc := a.get_scale()
	return Basis(a.get_rotation_quaternion().slerp(b.get_rotation_quaternion(), w)).scaled(sc)
