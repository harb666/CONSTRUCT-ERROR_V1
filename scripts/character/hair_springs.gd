class_name HairSprings
extends SkeletonModifier3D
## Lager's long hair swings on its own (owner asked: it moved as one block
## with her head and back; then "weird and stretched when she jumps and
## slides"). tools/build_lager.py gives the hanging hair a chain of bones
## from the head down her back (Hair_Root -> Hair_1 -> Hair_2 -> Hair_End);
## this hangs and swings that chain like a heavy rope:
## - it lies along her back, not her head: the bones hang from the head,
##   so a clip throwing the head back (jump, slide) tipped the whole hair
##   out like a board. Each segment's resting direction is its bind
##   direction carried by her torso - the hips-to-neck line and the
##   shoulder line, from the joints' positions (her retargeted spine bones'
##   own frames sit far off their bind even standing) - from the root
##   pinned under the head; near the head it partly follows the head
##   (`head_follow`), so the hair bends smoothly out of the scalp;
## - each joint is a damped spring towards that resting place, so starts,
##   stops, turns, jumps and landings make it lag and follow through, the
##   tip more than the root; steady running doesn't keep it flying out (the
##   springs act on the motion relative to her), only a little air drag
##   streams it back;
## - gravity pulls on it, so it hangs when she leans or lies;
## - every joint has a swing limit from its resting direction (tighter
##   towards her back), and segment lengths never change, so the skinned
##   hair never stretches or folds into her.
## (Godot's SpringBoneSimulator3D, used first, has no swing limits and threw
## the hair over her head.) A pose layer on her skeleton, moved after all the
## others (the CharacterAnimator's), so it swings with her final pose.
## Visual only (each device its own). Also on the character-select preview.

@export var bone_names: PackedStringArray = ["Hair_Root", "Hair_1", "Hair_2", "Hair_End"]
## How much each segment's resting direction follows the head instead of
## the torso (root, middle, tip).
@export var head_follow := PackedFloat32Array([0.5, 0.2, 0.0])
## Spring towards the resting place (1/s^2) and damping of the motion
## relative to it (1/s), per joint below the root (stiffer at the root).
@export var stiffness := PackedFloat32Array([60.0, 40.0, 30.0])
@export var damping := PackedFloat32Array([7.0, 6.0, 5.0])
## Drag of the joint's own motion through the air (1/s): streams it back a
## little while she runs.
@export var air_drag := 0.15
## Gravity on the hair (m/s^2).
@export var gravity := 6.0
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
var _pos: Array[Vector3] = []
var _vel: Array[Vector3] = []
var _prev_target: Array[Vector3] = []
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
	# Resting place of each joint: the root where the head holds it, the
	# rest along the upper back.
	var pts: Array[Vector3] = []
	for t in _torso:
		pts.append(sk.get_bone_global_pose(t).origin)
	var fbasis := gt.basis * _frame(pts)
	var anim: Array[Vector3] = []
	for b in _bones:
		anim.append(gt * sk.get_bone_global_pose(b).origin)
	var target: Array[Vector3] = [anim[0]]
	for i in range(1, n):
		var body := (fbasis * _rest_dir[i - 1]).normalized()
		var w := head_follow[mini(i - 1, head_follow.size() - 1)]
		var dir := body.slerp((anim[i] - anim[i - 1]).normalized(), w) if w > 0.0 else body
		target.append(target[i - 1] + dir.normalized() * _length[i - 1])
	if not _live or delta <= 0.0 or target[0].distance_to(_prev_target[0]) > teleport:
		_pos = target.duplicate()
		_vel = []
		for i in n:
			_vel.append(Vector3.ZERO)
		_prev_target = target.duplicate()
		_live = true
	else:
		_simulate(sk, gt, target, minf(delta, 1.0 / 20.0))
	# Turn each bone so it points at its simulated child joint, root to tip
	# (the chain's poses worked out here: the skeleton doesn't refresh a
	# child's global pose as soon as its parent is turned).
	var inv := gt.affine_inverse()
	var parent_g := sk.get_bone_global_pose(sk.get_bone_parent(_bones[0]))
	for i in range(n - 1):
		var g := parent_g * sk.get_bone_pose(_bones[i])
		var child := g * sk.get_bone_pose(_bones[i + 1]).origin
		var cur := (child - g.origin).normalized()
		var want := (inv * _pos[i + 1] - inv * _pos[i]).normalized()
		if i < swing.size():
			swing[i] = rad_to_deg((target[i + 1] - target[i]).normalized().angle_to((_pos[i + 1] - _pos[i]).normalized()))
		if cur.length() > 0.5 and want.length() > 0.5 and cur.dot(want) < 0.99999:
			g.basis = Basis(Quaternion(cur, want)) * g.basis
			sk.set_bone_pose_rotation(_bones[i], (parent_g.basis.inverse() * g.basis).get_rotation_quaternion())
		parent_g = g


func _simulate(sk: Skeleton3D, gt: Transform3D, target: Array[Vector3], dt: float) -> void:
	var n := _bones.size()
	var steps := 2
	var h := dt / steps
	var target_vel: Array[Vector3] = []
	for i in n:
		target_vel.append((target[i] - _prev_target[i]) / dt)
	_prev_target = target.duplicate()
	# Away from her back: from the upper spine out through the hair.
	var along := (target[1] - target[0]).normalized()
	var out := target[1] - gt * sk.get_bone_global_pose(_torso[1]).origin
	out -= along * out.dot(along)
	out = out.normalized() if out.length() > 0.001 else Vector3.ZERO
	for s in steps:
		_pos[0] = target[0]
		for i in range(1, n):
			var k := stiffness[mini(i - 1, stiffness.size() - 1)]
			var c := damping[mini(i - 1, damping.size() - 1)]
			var acc := (target[i] - _pos[i]) * k + (target_vel[i] - _vel[i]) * c - _vel[i] * air_drag + Vector3.DOWN * gravity
			_vel[i] += acc * h
			_pos[i] += _vel[i] * h
		# Lengths and swing limits, root to tip.
		for i in range(1, n):
			var rest := (target[i] - target[i - 1]).normalized()
			var d := _pos[i] - _pos[i - 1]
			d = d.normalized() if d.length() > 0.0001 else rest
			d = _limit(d, rest, out, deg_to_rad(max_swing[mini(i - 1, max_swing.size() - 1)]),
					deg_to_rad(max_swing_in[mini(i - 1, max_swing_in.size() - 1)]))
			var fixed := _pos[i - 1] + d * _length[i - 1]
			# What the limits took away doesn't carry on as speed.
			_vel[i] += (fixed - _pos[i]) / h * 0.5
			_pos[i] = fixed


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
