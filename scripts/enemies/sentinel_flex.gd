class_name SentinelFlex
extends SkeletonModifier3D
## The Neon Sentinel's wings and antennae moving with its flight (owner asked:
## "move fluently with the enemies movement and flight"), on top of its
## flight clips: springs carried by the body's acceleration - the antennae
## lag back when it surges forward, swing out on a sideways dash and wobble
## back; the wings droop as it climbs, lift as it drops, sweep back as it
## speeds up and flex with the bank - each overshooting and settling a
## little (spring + damping). RobotSentinel feeds `accel` (m/s^2, in the
## model's frame) and `bank` every tick.
##
## Expressions (owner asked: "often rotate up/down the red wing plates
## exposing the back plate fully ... tie into movements and the enemies
## expressions"): RobotSentinel says where each red cover plate should be
## (`cover`: -1 swung right up, 0 shut, 1 swung right down - either way the
## whole yellow back plate shows) and how far each back plate flares out
## (`plate`: 0 at rest, 1 flared, below 0 tucked in); they spring there,
## snapping over with a little overshoot. Held still while frozen (`hold`).
##
## Dying: the eye's plasma bone is held at full size (the death clip shrinks
## it, and the electric arcs hang off it) so the model's own branching
## discharges can crackle out of the smashed socket - flickering, spinning,
## jumping in size - dying away over `arc_time` (RobotSentinel hides the
## plasma gas itself).

## Antenna lean (rad) per m/s^2, and the most.
@export var antenna_gain := 0.045
@export var antenna_max := 0.55
@export var antenna_stiffness := 70.0
@export var antenna_damping := 5.5
## Wing droop / sweep (rad) per m/s^2, flex per rad of bank, and the most.
@export var wing_gain := 0.03
@export var wing_bank := 0.35
@export var wing_max := 0.4
@export var wing_stiffness := 55.0
@export var wing_damping := 6.0
@export var arc_time := 3.2
## The red covers' swing (deg) fully up / fully down, the back plates' flare.
@export var cover_up_deg := 55.0
@export var cover_down_deg := 75.0
@export var plate_flare_deg := 28.0
@export var cover_stiffness := 95.0
@export var cover_damping := 9.0

var accel := Vector3.ZERO
var bank := 0.0
var dying := false
var die_t := 0.0
## Arcs shown this frame after death (tests).
var arcs_lit := 0
## Where the red covers / back plates go ([left, right]; see above).
var cover := Vector2.ZERO
var plate := Vector2.ZERO
var hold := false

var _ant: Array[int] = []
var _wing: Array[int] = []
var _plasma := -1
var _arcs: Array[int] = []
var _cover_b: Array[int] = []
var _plate_b: Array[int] = []
var _hinge: Array[float] = [0.0, 0.0]
## Spring state per bone: [angle about X, about Z (or Y for wings), velocities].
var _s := {}


func setup(skel: Skeleton3D) -> void:
	_ant = [skel.find_bone(&"Antenna_L"), skel.find_bone(&"Antenna_R")]
	_wing = [skel.find_bone(&"Wing_L"), skel.find_bone(&"Wing_R")]
	_plasma = skel.find_bone(&"Eye_Plasma")
	_arcs.clear()
	for n in [&"Eye_Electric_Arc_A", &"Eye_Electric_Arc_B", &"Eye_Electric_Arc_2", &"Eye_Electric_Arc_3", &"Eye_Electric_Arc_4", &"Eye_Electric_Arc_5"]:
		var b := skel.find_bone(n)
		if b >= 0:
			_arcs.append(b)
	_cover_b = [skel.find_bone(&"Wing_Red_Cover_L"), skel.find_bone(&"Wing_Red_Cover_R")]
	_plate_b = [skel.find_bone(&"Wing_Plate_L"), skel.find_bone(&"Wing_Plate_R")]
	for b in _ant + _wing + _cover_b + _plate_b:
		_s[b] = Vector4.ZERO


## Knocks red cover `i` about (rad/s; + swings it down): a shot's kick, a
## flinch.
func kick_cover(i: int, speed: float) -> void:
	if i >= 0 and i < _cover_b.size() and _s.has(_cover_b[i]):
		var v: Vector4 = _s[_cover_b[i]]
		v.z += speed
		_s[_cover_b[i]] = v


## Red cover `i`'s swing now (rad; + down; tests).
func cover_angle(i: int) -> float:
	return (_s.get(_cover_b[i], Vector4.ZERO) as Vector4).x if i < _cover_b.size() else 0.0


## Back plate `i`'s flare now (rad; tests).
func plate_angle(i: int) -> float:
	return (_s.get(_plate_b[i], Vector4.ZERO) as Vector4).x if i < _plate_b.size() else 0.0


func _spring(b: int, target: Vector2, k: float, d: float, lim: float, dt: float) -> Vector2:
	var s: Vector4 = _s.get(b, Vector4.ZERO)
	var steps := 2
	var h := dt / steps
	for i in steps:
		s.z += (k * (target.x - s.x) - d * s.z) * h
		s.w += (k * (target.y - s.y) - d * s.w) * h
		s.x = clampf(s.x + s.z * h, -lim, lim)
		s.y = clampf(s.y + s.w * h, -lim, lim)
	_s[b] = s
	return Vector2(s.x, s.y)


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	var dt := clampf(get_process_delta_time() if is_inside_tree() else 0.016, 0.0, 0.05)
	if dying:
		_discharge(skel, dt)
		return
	# Antennae: the tips lag behind the acceleration (forward surge -> lean
	# back about X; sideways -> lean out about Z).
	var a := Vector2(-accel.z, accel.x) * antenna_gain
	for i in _ant.size():
		var b := _ant[i]
		if b < 0:
			continue
		var t := a.limit_length(antenna_max) + Vector2(0.0, 0.08 * (1.0 if i == 0 else -1.0) * absf(bank))
		var r := _spring(b, t, antenna_stiffness, antenna_damping, antenna_max * 1.3, dt)
		skel.set_bone_pose_rotation(b, skel.get_bone_pose_rotation(b) * Quaternion.from_euler(Vector3(r.x, 0.0, r.y)))
	# Wings: droop / lift against vertical acceleration and flex with the bank
	# (about Z), sweep back as it surges forward (about Y).
	for i in _wing.size():
		var b := _wing[i]
		if b < 0:
			continue
		var side := 1.0 if i == 0 else -1.0  # Wing_L is at -X
		var droop := clampf(accel.y * wing_gain + bank * wing_bank, -wing_max, wing_max) * side
		var sweep := clampf(-accel.z * wing_gain, -wing_max, wing_max) * side
		var r := _spring(b, Vector2(droop, sweep), wing_stiffness, wing_damping, wing_max * 1.3, dt)
		skel.set_bone_pose_rotation(b, skel.get_bone_pose_rotation(b) * Quaternion.from_euler(Vector3(0.0, r.y, r.x)))
	# Expressions: the red covers swing about their hinge (local Z; the right
	# side mirrored), the back plates flare out about theirs - the same
	# hinge line, so the clip's swing, the plate's and the cover's add up
	# (and the wing's droop);
	# together they never take the cover down past `cover_down_deg` (any
	# further and it swings into the arm).
	var edt := 0.0 if hold else dt
	for i in _cover_b.size():
		var side := 1.0 if i == 0 else -1.0
		var cb := _cover_b[i]
		var pb := _plate_b[i]
		if cb < 0 or pb < 0:
			continue
		# (The whole wing's droop at its root swings them down too.)
		var clip := (_twist(skel.get_bone_pose_rotation(cb)) + _twist(skel.get_bone_pose_rotation(pb))) * side
		if i < _wing.size() and _wing[i] >= 0:
			clip += maxf(0.0, _twist(skel.get_bone_pose_rotation(_wing[i])) * side)
		var pw := deg_to_rad(clampf(plate[i], -0.5, 1.0) * plate_flare_deg)
		var pr := _spring(pb, Vector2(pw, 0.0), cover_stiffness * 0.7, cover_damping, deg_to_rad(plate_flare_deg + 10.0), edt).x
		var c := clampf(cover[i], -1.0, 1.0)
		var cap := deg_to_rad(cover_down_deg)
		var want := minf(deg_to_rad(c * (cover_down_deg if c > 0.0 else cover_up_deg)), cap - clip - pw)
		var r := _spring(cb, Vector2(want, 0.0), cover_stiffness, cover_damping, deg_to_rad(cover_down_deg + 12.0), edt).x
		r = minf(r, cap + deg_to_rad(4.0) - clip - pr)
		_hinge[i] = rad_to_deg(maxf(clip + pr + r, clip + pw + want))
		skel.set_bone_pose_rotation(pb, skel.get_bone_pose_rotation(pb) * Quaternion(Vector3.BACK, pr * side))
		skel.set_bone_pose_rotation(cb, skel.get_bone_pose_rotation(cb) * Quaternion(Vector3.BACK, r * side))


## A rotation's twist about Z (rad; the plates' hinge axis).
static func _twist(q: Quaternion) -> float:
	return 2.0 * atan2(q.z, q.w)


## How far down wing `i`'s red cover hangs, all told (deg; the clip, the
## back plate's flare and the cover's own swing - where it's going if
## that's further): SentinelArms keeps that side's arm clear of it.
func hinge_down(i: int) -> float:
	return _hinge[i] if not dying else 0.0


## After death: the branching discharges crackle out of the empty socket.
func _discharge(skel: Skeleton3D, dt: float) -> void:
	die_t += dt
	arcs_lit = 0
	if _plasma < 0:
		return
	var k := 1.0 - clampf(die_t / arc_time, 0.0, 1.0)
	if k <= 0.0:
		for b in _arcs:
			skel.set_bone_pose_scale(b, Vector3.ONE * 0.0001)
		return
	skel.set_bone_pose_scale(_plasma, Vector3.ONE)
	for b in _arcs:
		# Flicker: each arc is on in random flashes, more often early on.
		if randf() < 0.35 + 0.5 * k:
			var s := randf_range(0.9, 1.25 + 0.6 * k)
			skel.set_bone_pose_scale(b, Vector3(s, s, s * randf_range(1.0, 1.8)))
			skel.set_bone_pose_rotation(b, Quaternion.from_euler(Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), randf() * TAU)))
			skel.set_bone_pose_position(b, Vector3(randf_range(-0.03, 0.03), randf_range(-0.03, 0.03), randf_range(0.0, 0.09)))
			arcs_lit += 1
		else:
			skel.set_bone_pose_scale(b, Vector3.ONE * 0.0001)
