class_name HairSprings
extends SkeletonModifier3D
## Lager's long hair swings on its own (owner asked: it moved as one block
## with her head and back; then "weird and stretched when she jumps and
## slides"; then "buggy / glitchy while running"). tools/build_lager.py
## gives the hanging hair a chain of bones from the head down her back
## (Hair_Root -> Hair_1 -> Hair_2 -> Hair_End); this hangs and swings that
## chain like a heavy rope:
## - it lies along her back, not her head: the bones hang from the head,
##   so a clip throwing the head back (jump, slide) tipped the whole hair
##   out like a board. Each segment's resting direction is its bind
##   direction carried by her torso - the hips-to-neck line and the
##   shoulder line, from the joints' positions (her retargeted spine bones'
##   own frames sit far off their bind even standing) - from the root
##   pinned under the head; near the head it partly follows the head
##   (`head_follow`), and it hangs a little towards straight down (`hang`);
## - it's simulated in her torso's own frame, so it goes wherever she goes
##   and swings only from what she does: her acceleration (starts, stops,
##   jumps, landings, turns - capped, `max_accel`: she reaches full speed in
##   a frame and her clips' blends can pop the body several cm, which flung
##   a hair simulated in the world onto its limit every few steps) and the
##   air she runs through (`air_drag`, streams it back);
## - each joint is a damped spring towards its resting place, with a little
##   gravity on the swing;
## - every joint has a swing limit from its resting direction (tighter
##   towards her back), segment lengths never change, and a limit stops the
##   motion into it (no bounce), so the skinned hair never stretches, folds
##   into her or snaps.
## (Godot's SpringBoneSimulator3D, used first, has no swing limits and threw
## the hair over her head.) A pose layer on her skeleton, moved after all the
## others (the CharacterAnimator's), so it swings with her final pose.
## Visual only (each device its own). Also on the character-select preview.

@export var bone_names: PackedStringArray = ["Hair_Root", "Hair_1", "Hair_2", "Hair_End"]
## How much each segment's resting direction follows the head instead of
## the torso (root, middle, tip).
@export var head_follow := PackedFloat32Array([0.5, 0.2, 0.0])
## How far each segment's resting direction hangs towards straight down
## (its weight), from lying along her back (0).
@export var hang := 0.3
## Spring towards the resting place (1/s^2) and damping of the swing (1/s),
## per joint below the root (stiffer at the root).
@export var stiffness := PackedFloat32Array([60.0, 40.0, 30.0])
@export var damping := PackedFloat32Array([9.0, 8.0, 7.0])
## How strongly her acceleration swings the hair (1 = as a free rope), and
## the most of it felt (m/s^2).
@export var inertia := 0.6
@export var max_accel := 25.0
## Her acceleration is smoothed over this long (s) before the hair feels
## it: a one-frame pop of her body in a clip's blend gave two opposite kicks
## a frame apart (the hair whipped out and straight back).
@export var accel_smoothing := 0.08
## Drag of the air she moves through (1/s, on her speed, capped at
## `max_air` m/s): streams the hair back a little while she runs.
@export var air_drag := 0.12
@export var max_air := 12.0
## Gravity on the swing (m/s^2): a little sag.
@export var gravity := 1.0
## Simulation steps a frame.
@export var substeps := 4
## Largest swing from the resting direction (deg) per segment, and the
## largest towards her back.
@export var max_swing := PackedFloat32Array([38.0, 28.0, 28.0])
@export var max_swing_in := PackedFloat32Array([6.0, 10.0, 10.0])
## A jump of the hair root further than this in one frame (m) is a
## teleport (respawn): the hair starts again from its resting place.
@export var teleport := 1.0

var _bones := PackedInt32Array()
## Torso joints: hips, neck, left / right shoulder.
var _torso := PackedInt32Array()
## Bind directions of the segments in the torso's bind frame, and lengths.
var _rest_dir: Array[Vector3] = []
var _length: Array[float] = []
## Joints relative to the root, in her torso's frame, and their speeds.
var _loc: Array[Vector3] = []
var _lvel: Array[Vector3] = []
var _prev_root := Vector3.ZERO
var _prev_speed := Vector3.ZERO
var _accel := Vector3.ZERO
var _live := false
## Each segment's swing (deg) from its resting direction, last frame.
var swing := PackedFloat32Array([0.0, 0.0, 0.0])


func _init() -> void:
	name = "HairSprings"


func _ready() -> void:
	# On the player the CharacterAnimator adds its pose layers in its own
	# _ready (after this node's): move onto the skeleton after them.
	_attach.call_deferred()


func _attach() -> void:
	if get_parent() is Skeleton3D:
		return
	var host := get_parent()
	if host == null:
		return
	var found := host.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return
	reparent.call_deferred(found[0], false)


func _setup(sk: Skeleton3D) -> bool:
	_bones.clear()
	for n in bone_names:
		var b := sk.find_bone(n)
		if b < 0:
			return false
		_bones.append(b)
	_torso.clear()
	for t in ["mixamorig_Hips", "mixamorig_Neck", "mixamorig_LeftShoulder", "mixamorig_RightShoulder"]:
		_torso.append(sk.find_bone(t))
	if _torso.has(-1):
		_bones.clear()
		return false
	var rest_pts: Array[Vector3] = []
	for t in _torso:
		rest_pts.append(sk.get_bone_global_rest(t).origin)
	var fb := _frame(rest_pts).inverse()
	_rest_dir.clear()
	_length.clear()
	for i in _bones.size() - 1:
		var a := sk.get_bone_global_rest(_bones[i]).origin
		var c := sk.get_bone_global_rest(_bones[i + 1]).origin
		_rest_dir.append(fb * (c - a).normalized())
		_length.append(a.distance_to(c))
	_live = false
	return true


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _bones.size() != bone_names.size() and not _setup(sk):
		return
	var gt := sk.global_transform
	var n := _bones.size()
	# Her torso's frame (world) and the hair's root (pinned under the head).
	var pts: Array[Vector3] = []
	for t in _torso:
		pts.append(sk.get_bone_global_pose(t).origin)
	var fbasis := (gt.basis * _frame(pts)).orthonormalized()
	var to_local := fbasis.inverse()
	var anim: Array[Vector3] = []
	for b in _bones:
		anim.append(gt * sk.get_bone_global_pose(b).origin)
	var root := anim[0]
	# Resting place of each joint (relative to the root, torso frame): along
	# her upper back, near the head partly following it, hanging a little.
	var rest: Array[Vector3] = [Vector3.ZERO]
	for i in range(1, n):
		var body := (fbasis * _rest_dir[i - 1]).normalized()
		var w := head_follow[mini(i - 1, head_follow.size() - 1)]
		var dir := body.slerp((anim[i] - anim[i - 1]).normalized(), w) if w > 0.0 else body
		dir = (dir.normalized() + Vector3.DOWN * hang).normalized()
		rest.append(rest[i - 1] + to_local * dir * _length[i - 1])
	if not _live or root.distance_to(_prev_root) > teleport:
		_loc = rest.duplicate()
		_lvel = []
		for i in n:
			_lvel.append(Vector3.ZERO)
		_prev_root = root
		_prev_speed = Vector3.ZERO
		_accel = Vector3.ZERO
		_live = true
	elif delta > 0.0:
		var dt := minf(delta, 1.0 / 20.0)
		var speed := (root - _prev_root) / delta
		var raw := ((speed - _prev_speed) / delta).limit_length(max_accel * 2.0)
		_accel = _accel.lerp(raw, 1.0 - exp(-delta / maxf(accel_smoothing, 0.001)))
		var accel := _accel.limit_length(max_accel)
		_prev_root = root
		_prev_speed = speed
		_simulate(rest, to_local * accel, to_local * speed.limit_length(max_air), to_local * Vector3.DOWN,
				to_local * (gt * sk.get_bone_global_pose(_torso[1]).origin - root), dt)
	# (A second update in a frame - no time passed - leaves the hair as it
	# is: it used to snap back to rest.)
	for i in range(n - 1):
		if i < swing.size():
			swing[i] = rad_to_deg((rest[i + 1] - rest[i]).normalized().angle_to((_loc[i + 1] - _loc[i]).normalized()))
	# Turn each bone so it points at its simulated child joint, root to tip
	# (the chain's poses worked out here: the skeleton doesn't refresh a
	# child's global pose as soon as its parent is turned).
	var inv := gt.affine_inverse()
	var parent_g := sk.get_bone_global_pose(sk.get_bone_parent(_bones[0]))
	for i in range(n - 1):
		var g := parent_g * sk.get_bone_pose(_bones[i])
		var child := g * sk.get_bone_pose(_bones[i + 1]).origin
		var cur := (child - g.origin).normalized()
		var want := (inv.basis * (fbasis * (_loc[i + 1] - _loc[i]))).normalized()
		if cur.length() > 0.5 and want.length() > 0.5 and cur.dot(want) < 0.99999:
			g.basis = Basis(Quaternion(cur, want)) * g.basis
			sk.set_bone_pose_rotation(_bones[i], (parent_g.basis.inverse() * g.basis).get_rotation_quaternion())
		parent_g = g


## One frame of the swing, in the torso frame: `rest` resting places,
## `accel` / `speed` of the root, `down`, `neck` (from the root).
func _simulate(rest: Array[Vector3], accel: Vector3, speed: Vector3, down: Vector3, neck: Vector3, dt: float) -> void:
	var n := _bones.size()
	var steps := maxi(substeps, 1)
	var h := dt / steps
	# Away from her back: from the neck out through the hair.
	var along := (rest[1] - rest[0]).normalized()
	var out := rest[1] - neck
	out -= along * out.dot(along)
	out = out.normalized() if out.length() > 0.001 else Vector3.ZERO
	var push := -accel * inertia + down * gravity
	for s in steps:
		var before := _loc.duplicate()
		for i in range(1, n):
			var k := stiffness[mini(i - 1, stiffness.size() - 1)]
			var c := damping[mini(i - 1, damping.size() - 1)]
			var acc := (rest[i] - _loc[i]) * k - _lvel[i] * c + push - (speed + _lvel[i]) * air_drag
			_loc[i] += (_lvel[i] + acc * h) * h
		# Lengths and swing limits, root to tip.
		for i in range(1, n):
			var r := (rest[i] - rest[i - 1]).normalized()
			var d := _loc[i] - _loc[i - 1]
			d = d.normalized() if d.length() > 0.0001 else r
			d = _limit(d, r, out, deg_to_rad(max_swing[mini(i - 1, max_swing.size() - 1)]),
					deg_to_rad(max_swing_in[mini(i - 1, max_swing_in.size() - 1)]))
			_loc[i] = _loc[i - 1] + d * _length[i - 1]
		# Speed from where the joints actually went (a limit stops the
		# motion into it - no bounce, no kick).
		for i in n:
			_lvel[i] = (_loc[i] - before[i]) / h


## Orthonormal torso frame from [hips, neck, left shoulder, right shoulder].
static func _frame(p: Array[Vector3]) -> Basis:
	var up := (p[1] - p[0]).normalized()
	var side := p[2] - p[3]
	side = (side - up * side.dot(up)).normalized()
	return Basis(side, up, side.cross(up))


## `d` limited to `max_out` from `rest`, and to `max_in` towards the body
## (against `out`).
static func _limit(d: Vector3, rest: Vector3, out: Vector3, max_out: float, max_in: float) -> Vector3:
	var ang := rest.angle_to(d)
	if ang > max_out:
		d = rest.slerp(d, max_out / ang).normalized()
	var side := out - rest * rest.dot(out)
	if side.length() > 0.0001:
		side = side.normalized()
		var into := -d.dot(side)
		var lim := sin(max_in)
		if into > lim:
			d = (d + side * (into - lim)).normalized()
	return d
