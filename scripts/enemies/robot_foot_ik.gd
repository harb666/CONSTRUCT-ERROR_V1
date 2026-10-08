class_name RobotFootIK
extends SkeletonModifier3D
## Plants a walking robot's feet on top of its walk / run clip, so they
## never glide or skate:
##  * Stride warping: the clip's step length is stretched or shortened so
##    the planted foot moves back exactly as fast as the body moves forward
##    (whatever the clip's playback rate), along the body's real velocity.
##  * Foot locking: a foot that touches down stays put in the world until
##    it lifts again (small residual slips, turning on the spot).
##  * Flat feet: a planted foot lies flat on the floor under it (sole on
##    the ground, slopes / ramps followed via one ray per foot), easing in
##    at touch-down and out at lift-off; a swinging foot keeps the clip's
##    lift height above the floor under it.
##  * Two-bone leg IK (thigh / shin) reaches the foot targets, knees bending
##    in the clip's own plane, optionally turned towards the toes
##    (`knee_forward`); the hips drop a little if a leg can't reach.
## Only for clips listed in `gaits` (others fade it out: jumps, turns,
## deaths). The robot sets `body` (its RigidBody3D) and `enabled`.

## Clip -> {speed: planted foot ground speed at 1x (m/s), ankle_min: the
## clip's lowest ankle height (m, model space), stand: true = both feet
## always planted}. Measured by tools/measure_gait.gd.
var gaits := {}
var body: RigidBody3D
var enabled := true
## Knees turn this much (0..1) from the clip's bend plane towards the toes.
@export var knee_forward := 0.0
## A foot within `plant_band` (m) of its clip's lowest counts as planted;
## up to `stance_band` too while the clip carries it backwards (heel rising
## as it rolls off the toes - still on the ground).
@export var plant_band := 0.04
@export var stance_band := 0.09
## A locked foot lets go (slides to the clip's place) beyond this (m).
@export var max_slip := 0.22
## Most the stride is stretched / shortened.
@export var stride_limits := Vector2(0.5, 1.7)
## Most the hips drop (m) so a leg can reach the floor.
@export var max_hip_drop := 0.12
## Beyond this camera distance it does nothing (too small to see).
@export var max_camera_distance := 40.0
## Blend (0..1) the robot is driven at; eased in / out here.
var weight := 0.0

var _hips := -1
## Per leg: thigh, shin, foot, toe bone; state.
var _legs: Array[Leg] = []
var _hip_drop := 0.0
var _ray_frame := 0
var _ap: AnimationPlayer


class Leg:
	var thigh := -1
	var shin := -1
	var foot := -1
	var toe := -1
	var rest_ankle_y := 0.0
	var rest_foot := Basis()
	var toe_local := Vector3.FORWARD
	## Planted blend 0..1 and the world lock.
	var plant := 0.0
	var locked := false
	var lock_pos := Vector3.ZERO
	var floor_y := 0.0
	var floor_n := Vector3.UP
	var have_floor := false
	## World ankle target last frame (smooths unlocks).
	var last_target := Vector3.ZERO
	var have_last := false
	## Clip ankle position last frame (skeleton space).
	var prev_anim := Vector3.ZERO


func setup(skel: Skeleton3D, anim: AnimationPlayer, gait_table: Dictionary, rigid: RigidBody3D) -> void:
	gaits = gait_table
	body = rigid
	_ap = anim
	_hips = skel.find_bone(&"mixamorig_Hips")
	_legs.clear()
	for side in ["Left", "Right"]:
		var l := Leg.new()
		l.thigh = skel.find_bone("mixamorig_%sUpLeg" % side)
		l.shin = skel.find_bone("mixamorig_%sLeg" % side)
		l.foot = skel.find_bone("mixamorig_%sFoot" % side)
		l.toe = skel.find_bone("mixamorig_%sToeBase" % side)
		if l.thigh < 0 or l.shin < 0 or l.foot < 0:
			continue
		var r := skel.get_bone_global_rest(l.foot)
		l.rest_ankle_y = r.origin.y
		l.rest_foot = r.basis.orthonormalized()
		if l.toe >= 0:
			l.toe_local = skel.get_bone_rest(l.toe).origin
		_legs.append(l)


## The gait entry for the clip playing now (or {}).
func _gait() -> Dictionary:
	if _ap == null or not _ap.is_playing():
		return {}
	return gaits.get(StringName(_ap.current_animation), {})


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or _legs.is_empty() or _hips < 0:
		return
	var dt := get_process_delta_time() if is_inside_tree() else 0.016
	var gait := _gait()
	var want := 1.0 if enabled and not gait.is_empty() else 0.0
	if want > 0.0 and is_inside_tree():
		var cam := get_viewport().get_camera_3d()
		if cam and cam.global_position.distance_to(skel.global_position) > max_camera_distance:
			want = 0.0
	weight = move_toward(weight, want, dt / 0.15)
	if weight <= 0.001:
		for l in _legs:
			l.locked = false
			l.plant = 0.0
			l.have_last = false
		_hip_drop = 0.0
		return
	var xf := skel.global_transform
	var inv := xf.affine_inverse()
	var stand: bool = gait.get("stand", false)
	# Stride: how much the clip's step must stretch to match the body.
	var vel := body.linear_velocity if body else Vector3.ZERO
	var vl := inv.basis * Vector3(vel.x, 0.0, vel.z)
	vl.y = 0.0
	var speed := vl.length()
	var k := 1.0
	var dir := Vector3.ZERO
	var rate := absf(_ap.get_playing_speed())
	var clip_speed: float = gait.get("speed", 0.0)
	if speed > 0.05 and clip_speed > 0.0 and rate > 0.01 and not stand:
		dir = vl / speed
		k = clampf(speed / (clip_speed * rate), stride_limits.x, stride_limits.y)
	var hips_g := skel.get_bone_global_pose(_hips)
	var pivot := hips_g.origin
	var ankle_min: float = gait.get("ankle_min", 0.0)
	# Floor under each foot: one ray every other frame per robot.
	_ray_frame += 1
	var cast := _ray_frame % 2 == 0 or not _legs[0].have_floor
	# 1) Targets (skeleton space).
	var targets: Array[Vector3] = []
	var bases: Array[Basis] = []
	var need_drop := 0.0
	for l in _legs:
		var fg := skel.get_bone_global_pose(l.foot)
		var a := fg.origin
		var lift := maxf(a.y - ankle_min, 0.0)
		var back := dir != Vector3.ZERO and l.have_last and (a - l.prev_anim).dot(dir) < 0.0
		var planted := stand or lift < plant_band or (back and lift < stance_band)
		l.prev_anim = a
		l.plant = move_toward(l.plant, 1.0 if planted else 0.0, dt / (0.06 if planted else 0.12))
		# Stride warp along the travel direction, about the hips.
		var t := a
		if dir != Vector3.ZERO:
			var along := (a - pivot).dot(dir)
			t += dir * along * (k - 1.0)
		var world_t := xf * t
		if cast or not l.have_floor:
			_cast_floor(l, world_t)
		# Height: the clip's lift over the floor under the foot, a planted
		# ankle at its flat-foot (rest) height.
		var floor_local := (inv * Vector3(world_t.x, l.floor_y, world_t.z)).y
		# (Planted: flat on the floor, the clip's heel rise left out.)
		t.y = floor_local + l.rest_ankle_y + (0.0 if stand else lift * (1.0 - l.plant))
		# Flat foot: the rest orientation (sole flat) turned to the clip's
		# heading, tilted to the floor.
		var flat := _flat_basis(l, fg.basis, inv)
		world_t = xf * t
		if planted:
			if not l.locked:
				l.locked = true
				l.lock_pos = world_t
			elif l.lock_pos.distance_to(world_t) > max_slip:
				l.locked = false  # slipped too far: let it catch up
		else:
			l.locked = false
		if l.locked:
			world_t = Vector3(l.lock_pos.x, world_t.y, l.lock_pos.z)
		# Ease out of a release instead of snapping.
		if l.have_last and not l.locked:
			world_t = l.last_target.lerp(world_t, clampf(dt * 25.0, 0.0, 1.0))
		l.last_target = world_t
		l.have_last = true
		t = inv * world_t
		var fb := fg.basis.orthonormalized()
		if l.plant > 0.001:
			fb = Basis(fb.get_rotation_quaternion().slerp(flat.get_rotation_quaternion(), l.plant))
		targets.append(fg.origin.lerp(t, weight))
		bases.append(Basis(fg.basis.orthonormalized().get_rotation_quaternion().slerp(fb.get_rotation_quaternion(), weight)))
		# Reach: lower the hips if this foot can't be reached.
		var thigh_o := skel.get_bone_global_pose(l.thigh).origin
		var reach := _len(skel, l) * 0.985
		var dv := targets[-1] - thigh_o
		var short := 0.0
		if dv.length() > reach:
			var horiz := Vector2(dv.x, dv.z).length()
			var vert_ok := sqrt(maxf(reach * reach - horiz * horiz, 0.0))
			short = -dv.y - vert_ok
		need_drop = maxf(need_drop, short)
	_hip_drop = move_toward(_hip_drop, clampf(need_drop, 0.0, max_hip_drop), dt * 0.6)
	if _hip_drop > 0.0005:
		hips_g.origin.y -= _hip_drop * weight
		skel.set_bone_global_pose(_hips, hips_g)
	# 2) Two-bone IK per leg.
	for i in _legs.size():
		_solve(skel, _legs[i], targets[i], bases[i])


func _len(skel: Skeleton3D, l: Leg) -> float:
	return skel.get_bone_rest(l.shin).origin.length() + skel.get_bone_rest(l.foot).origin.length()


func _flat_basis(l: Leg, anim: Basis, inv: Transform3D) -> Basis:
	var a := (anim * l.toe_local)
	var r := (l.rest_foot * l.toe_local)
	var yaw := atan2(a.x, a.z) - atan2(r.x, r.z)
	var b := Basis(Vector3.UP, yaw) * l.rest_foot
	if l.floor_n.dot(Vector3.UP) < 0.999:
		var n := (inv.basis * l.floor_n).normalized()
		var ax := Vector3.UP.cross(n)
		if ax.length_squared() > 1e-6:
			b = Basis(ax.normalized(), Vector3.UP.angle_to(n)) * b
	return b


func _cast_floor(l: Leg, at: Vector3) -> void:
	if body == null or not body.is_inside_tree():
		return
	var base_y := body.global_position.y
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, base_y + 0.6, at.z), Vector3(at.x, base_y - 1.4, at.z))
	q.collision_mask = 1
	q.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		if not l.have_floor:
			l.floor_y = (get_skeleton().global_transform * Vector3.ZERO).y
			l.floor_n = Vector3.UP
		return
	# Other robots / players are not floors.
	var c: Object = hit.collider
	if c is RigidBody3D or c is CharacterBody3D:
		return
	l.floor_y = hit.position.y
	var n: Vector3 = hit.normal
	l.floor_n = n if n.dot(Vector3.UP) > 0.7 else Vector3.UP
	l.have_floor = true


## Thigh and shin turned so the ankle reaches `target`, knee in the clip's
## bend plane (eased towards the toes), then the foot set to `foot_basis`.
func _solve(skel: Skeleton3D, l: Leg, target: Vector3, foot_basis: Basis) -> void:
	var tg := skel.get_bone_global_pose(l.thigh)
	var sg := skel.get_bone_global_pose(l.shin)
	var fg := skel.get_bone_global_pose(l.foot)
	var a := tg.origin
	var b := sg.origin
	var c := fg.origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var to := target - a
	var d := clampf(to.length(), absf(l1 - l2) + 0.01, (l1 + l2) * 0.999)
	if to.length_squared() < 1e-8:
		return
	var u := to.normalized()
	# Pole: the clip's knee direction, optionally towards the toes.
	var pole := (b - a) - u * (b - a).dot(u)
	if knee_forward > 0.0:
		var toes := foot_basis * l.toe_local
		toes.y = 0.0
		if toes.length_squared() > 1e-6:
			var fwd := toes.normalized() - u * toes.normalized().dot(u)
			if fwd.length_squared() > 1e-6:
				pole = pole.normalized().lerp(fwd.normalized(), knee_forward) if pole.length_squared() > 1e-8 else fwd
	if pole.length_squared() < 1e-8:
		return
	pole = pole.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var knee := a + u * (l1 * cos_a) + pole * (l1 * sqrt(1.0 - cos_a * cos_a))
	var ankle := a + u * d
	# Thigh.
	var r1 := Quaternion((b - a).normalized(), (knee - a).normalized())
	var tg2 := Transform3D(Basis(r1) * tg.basis, a)
	skel.set_bone_global_pose(l.thigh, tg2)
	# Shin (its origin follows the thigh).
	var sg2 := skel.get_bone_global_pose(l.shin)
	var c_now := sg2 * (sg.affine_inverse() * c)
	var r2 := Quaternion((c_now - sg2.origin).normalized(), (ankle - sg2.origin).normalized())
	skel.set_bone_global_pose(l.shin, Transform3D(Basis(r2) * sg2.basis, sg2.origin))
	# Foot: the wanted orientation.
	var fg2 := skel.get_bone_global_pose(l.foot)
	skel.set_bone_global_pose(l.foot, Transform3D(foot_basis, fg2.origin))
