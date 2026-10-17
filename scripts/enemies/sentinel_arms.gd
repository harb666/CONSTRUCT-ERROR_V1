class_name SentinelArms
extends SkeletonModifier3D
## The Neon Sentinel's arms (owner asked: "I don't want it flying around in
## T-pose ... give its arms some life"; its flight clips hold them straight
## out). Each arm is posed on its own two joints - the shoulder (Cannon_*, a
## ball joint) and the elbow (Elbow_*, a hinge) - so the upper arm angles
## out, down and forward and the elbow bends to point the forearm (and the
## cannon on its end) where it's aiming: at the player once it's fighting,
## forwards and a little down otherwise. Exact two-joint solve: the shoulder
## turns so the elbow's hinge plane holds the forearm's direction, and the
## elbow bends by the angle between them.
##
## Life: both arms spring towards their pose (a little overshoot), lag
## behind the body's acceleration (swing back on a surge, out on a dash),
## sway gently out of step with each other, and kick back and up when their
## cannon fires (`recoil`). Startled: they fling out wide and down.
## Dying: they go limp and dangle towards the ground as the wreck tumbles.
## Frozen: they hold still.
##
## Clear of the wings (owner asked: the arms mustn't merge into the wings):
## when a red wing cover swings down over the shoulder (`flex.hinge_down`),
## that arm tucks down and a little back under it, and its forearm keeps
## below it - it moves out of the way before the cover gets there. (The
## startle clip's own arm fling went up through the wing backs, so the
## arms no longer follow it.)

## Upper arm and forearm directions at rest (left arm; mirrored for the
## right; model space: +Z forward, +Y up, the left arm out along -X).
@export var relaxed_upper := Vector3(-0.72, -0.52, 0.42)
@export var relaxed_fore := Vector3(-0.08, -0.32, 1.0)
@export var stiffness := 110.0
@export var damping := 13.0
@export var lag := 0.012
@export var sway := 0.07
@export var recoil_kick := 0.75
## Startled: upper arm / forearm flung out wide and down (left arm).
@export var startle_upper := Vector3(-0.75, -0.6, 0.1)
@export var startle_fore := Vector3(-0.6, -0.25, 0.75)
## Tucked under a lowered wing cover (left arm), and the cover's swing
## (deg, all told) where it starts / finishes tucking.
@export var tuck_upper := Vector3(-0.25, -0.8, -0.25)
@export var tuck_from := 30.0
@export var tuck_to := 62.0
## The highest the upper arm ever lifts (its direction's height): the wing
## sits right over the shoulder, so a raised arm would go into it.
@export var max_raise := -0.25

## World point to aim the forearms at (INF: no target).
var aim := Vector3.INF
## Body acceleration (model frame), set every tick by RobotSentinel.
var accel := Vector3.ZERO
var startled := false
var dying := false
var frozen := false
## Its wings (where their covers are; RobotSentinel).
var flex: SentinelFlex

var _sh: Array[int] = []
var _el: Array[int] = []
var _u: Array[Vector3] = []
var _uv: Array[Vector3] = []
var _f: Array[Vector3] = []
var _fv: Array[Vector3] = []
var _kick: Array[float] = [0.0, 0.0]
var _t := 0.0


func setup(skel: Skeleton3D) -> void:
	_sh = [skel.find_bone(&"Cannon_L"), skel.find_bone(&"Cannon_R")]
	_el = [skel.find_bone(&"Elbow_L"), skel.find_bone(&"Elbow_R")]
	_u = [_side(relaxed_upper, 0).normalized(), _side(relaxed_upper, 1).normalized()]
	_f = [_side(relaxed_fore, 0).normalized(), _side(relaxed_fore, 1).normalized()]
	_uv = [Vector3.ZERO, Vector3.ZERO]
	_fv = [Vector3.ZERO, Vector3.ZERO]
	_t = randf() * 10.0


## Mirrors a left-arm vector for arm `i` (0 left, 1 right).
func _side(v: Vector3, i: int) -> Vector3:
	return v if i == 0 else Vector3(-v.x, v.y, v.z)


## Cannon `i` just fired: its arm kicks back and up.
func recoil(i: int) -> void:
	if i >= 0 and i < 2:
		_kick[i] = 1.0


## The current upper-arm / forearm directions (model frame; tests).
func arm_dirs(i: int) -> Array:
	return [_u[i], _f[i]]


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or _sh.size() < 2 or _sh[0] < 0:
		return
	var dt := clampf(get_process_delta_time() if is_inside_tree() else 0.016, 0.0, 0.05)
	if not frozen:
		_t += dt
	var inv := skel.global_basis.inverse()
	var down := (inv * Vector3.DOWN).normalized()
	for i in 2:
		var s := 1.0 if i == 0 else -1.0
		var shoulder := skel.get_bone_global_pose(_sh[i]).origin
		var want_u: Vector3
		var want_f: Vector3
		var k := stiffness
		var d := damping
		if dying:
			# Limp: dangling towards the ground, floppy.
			want_u = (down + Vector3(-0.35 * s, 0.0, 0.1)).normalized()
			want_f = (down + Vector3(-0.1 * s, 0.0, 0.25)).normalized()
			k = 45.0
			d = 4.0
		else:
			want_u = _side(relaxed_upper, i).normalized()
			want_f = _side(relaxed_fore, i).normalized()
			if startled:
				want_u = _side(startle_upper, i).normalized()
				want_f = _side(startle_fore, i).normalized()
			elif aim != Vector3.INF:
				var elbow_at := shoulder + _u[i] * 0.24
				var to := skel.global_transform.affine_inverse() * aim - elbow_at
				if to.length_squared() > 0.01:
					to = to.normalized()
					# Never back into the body, nor across in front of it.
					to.z = maxf(to.z, 0.2)
					if to.x * s > 0.35:  # (inwards is +X for the left arm)
						to.x = 0.35 * s
					want_f = to.normalized()
					want_u = (want_u + want_f * 0.35).normalized()
			# Gentle sway, out of step; lag behind the body's acceleration.
			var ph := _t * 1.3 + i * 2.1
			var drag := (accel * lag).limit_length(0.35)
			want_u += Vector3(0.0, sin(ph) * sway, cos(ph * 0.8) * sway * 0.6) - drag
			want_f += Vector3(0.0, sin(ph + 0.9) * sway, 0.0) - drag * 0.8
			# Recoil: the forearm kicks up and the arm back.
			if _kick[i] > 0.0:
				want_f += Vector3(0.0, 1.0, -0.4) * _kick[i] * recoil_kick
				want_u += Vector3(0.0, 0.3, -0.5) * _kick[i] * recoil_kick
				_kick[i] = move_toward(_kick[i], 0.0, dt * 6.0)
			# Out of the way of that side's wing cover swinging down.
			var w := smoothstep(tuck_from, tuck_to, flex.hinge_down(i)) if flex else 0.0
			if w > 0.0:
				want_u = want_u.normalized().lerp(_side(tuck_upper, i).normalized(), w)
				want_f = want_f.normalized()
				want_f.y = minf(want_f.y, lerpf(1.0, -0.1, w))
				var out_max := lerpf(1.0, 0.35, w)  # (outwards is -X for the left arm)
				if -want_f.x * s > out_max:
					want_f.x = -out_max * s
				want_f.z = maxf(want_f.z, 0.3 * w)
		if not frozen:
			for n in 2:
				var h := dt * 0.5
				_uv[i] += ((want_u.normalized() - _u[i]) * k - _uv[i] * d) * h
				_u[i] = (_u[i] + _uv[i] * h).normalized()
				_fv[i] += ((want_f.normalized() - _f[i]) * k - _fv[i] * d) * h
				_f[i] = (_f[i] + _fv[i] * h).normalized()
			if not dying and _u[i].y > max_raise:
				_u[i].y = max_raise
				_u[i] = _u[i].normalized()
				_uv[i].y = minf(_uv[i].y, 0.0)
		_pose(skel, i, s, shoulder)


## Shoulder basis: the arm along U (local -X left, +X right), the elbow's
## hinge (local Y) square to the plane of U and F, so bending the elbow
## (about Y) swings the forearm onto F.
func _pose(skel: Skeleton3D, i: int, s: float, shoulder: Vector3) -> void:
	var u := _u[i]
	var f := _f[i]
	var bend := f - u * f.dot(u)
	if bend.length_squared() < 1e-5:
		bend = Vector3.BACK - u * u.z
		if bend.length_squared() < 1e-5:
			bend = Vector3.UP
	var z := bend.normalized()
	var x := -u * s
	var y := z.cross(x).normalized()
	z = x.cross(y).normalized()
	skel.set_bone_global_pose(_sh[i], Transform3D(Basis(x, y, z), shoulder))
	var theta := u.angle_to(f)
	skel.set_bone_pose_rotation(_el[i], Quaternion(Vector3.UP, theta * s))
