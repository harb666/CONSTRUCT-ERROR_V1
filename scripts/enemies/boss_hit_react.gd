class_name BossHitReact
extends SkeletonModifier3D
## Small additive hit reactions for the robot boss, layered over whatever
## clip plays: the upper body (Spine1) jerks back away from the hit on a
## stiff spring and shakes mechanically for a moment. `kick()` adds to it,
## so rapid small hits give small twitches and big hits a stronger recoil;
## it never interrupts the animation or the AI. Runs before BossGunAim, so
## the chaingun still aims where it should.

## Lean per unit of kick (deg), and the spring (stiff, quickly settled).
@export var max_lean_deg := 7.0
@export var stiffness := 170.0
@export var damping := 13.0
## Mechanical shake per unit of kick (deg).
@export var shake_deg := 1.6
## Caps the spring speed and shake so rapid fire can't stack into a huge lean.
@export var max_kick_speed := 14.0
## Bone that leans (light robots use the same reaction).
@export var bone_name := &"mixamorig_Spine1"
## Cartoon flinch (light robots and players; 0 = off, the boss): the upper
## body squashes down and bulges out on the hit, springs up into a stretch
## and wobbles back - squash per unit of kick, and its springy wobble.
@export var squash := 0.0
@export var squash_bone := &"mixamorig_Spine"
@export var squash_stiffness := 260.0
@export var squash_damping := 9.0
@export var max_squash := 0.32

var _bone := -1
var _axis := Vector3.RIGHT
var _r := 0.0
var _v := 0.0
var _shake := 0.0
var _sq_bone := -1
var _q := 0.0
var _qv := 0.0


func setup(skel: Skeleton3D) -> void:
	_bone = skel.find_bone(bone_name)
	_sq_bone = skel.find_bone(squash_bone)


## A hit: `strength` 0..1 (1 = heavy), from world direction `dir` (the way
## the shot was travelling).
func kick(strength: float, dir: Vector3) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	var d := skel.global_basis.inverse() * dir
	d.y = 0.0
	if d.length_squared() < 1e-4:
		d = Vector3(0, 0, -1)
	# Lean away from the hit: rotate about the horizontal axis across it.
	_axis = Vector3.UP.cross(d.normalized()).normalized()
	_v = minf(_v + 9.0 * clampf(strength, 0.0, 1.5), max_kick_speed)
	_shake = minf(_shake + strength, 1.5)
	if squash > 0.0:
		_qv -= 14.0 * squash * clampf(strength, 0.0, 1.5)
		_qv = maxf(_qv, -14.0 * max_squash * 1.5)


## Current squash (-squash, +stretch) for tests.
func squash_amount() -> float:
	return _q


## Current lean (0..~1) for tests.
func amount() -> float:
	return absf(_r) + _shake


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or _bone < 0:
		return
	var dt := get_process_delta_time() if is_inside_tree() else 0.016
	var steps := 3
	var h := dt / steps
	for i in steps:
		_v += (-stiffness * _r - damping * _v) * h
		_r += _v * h
		_qv += (-squash_stiffness * _q - squash_damping * _qv) * h
		_q = clampf(_q + _qv * h, -max_squash, max_squash)
	_shake = move_toward(_shake, 0.0, dt * 4.0)
	if absf(_q) < 1e-4 and absf(_qv) < 1e-3:
		_q = 0.0
		_qv = 0.0
	elif _sq_bone >= 0:
		# Squash (q < 0): shorter and wider; stretch (q > 0): taller, thinner.
		var gq := skel.get_bone_global_pose(_sq_bone)
		var sc := Basis.from_scale(Vector3(1.0 - _q * 0.5, 1.0 + _q, 1.0 - _q * 0.5))
		skel.set_bone_global_pose(_sq_bone, Transform3D(sc * gq.basis, gq.origin))
	if absf(_r) < 1e-4 and absf(_v) < 1e-3 and _shake <= 0.0:
		_r = 0.0
		_v = 0.0
		return
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * deg_to_rad(shake_deg) * _shake
	var g := skel.get_bone_global_pose(_bone)
	var rot := Basis(_axis, deg_to_rad(max_lean_deg) * _r) * Basis.from_euler(jitter)
	skel.set_bone_global_pose(_bone, Transform3D(rot * g.basis, g.origin))
