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

var _bone := -1
var _axis := Vector3.RIGHT
var _r := 0.0
var _v := 0.0
var _shake := 0.0


func setup(skel: Skeleton3D) -> void:
	_bone = skel.find_bone("mixamorig_Spine1")


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
	_v += 9.0 * clampf(strength, 0.0, 1.5)
	_shake = minf(_shake + strength, 1.5)


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
	_shake = move_toward(_shake, 0.0, dt * 4.0)
	if absf(_r) < 1e-4 and absf(_v) < 1e-3 and _shake <= 0.0:
		_r = 0.0
		_v = 0.0
		return
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * deg_to_rad(shake_deg) * _shake
	var g := skel.get_bone_global_pose(_bone)
	var rot := Basis(_axis, deg_to_rad(max_lean_deg) * _r) * Basis.from_euler(jitter)
	skel.set_bone_global_pose(_bone, Transform3D(rot * g.basis, g.origin))
