class_name JointSparks
extends Node3D
## SMALL electrical failure at a broken mechanical joint (exposed, damaged
## electronics, not a lightning attack): a short burst of sparks, a few tiny
## arcs and a brief purple/white discharge flicker, rapidly dying down to an
## occasional residual spark. Pooled; follows a bone of a Skeleton3D (the
## socket on the body, or the end of a flying piece).

const POOL_SIZE := 16
## Arc/flash colours: white-hot core, purple discharge.
const ARC_COLORS := [Color(0.9, 0.75, 1.0), Color(0.62, 0.25, 1.0), Color(0.75, 0.45, 1.0), Color(0.55, 0.2, 1.0)]

static var _pool: Array[JointSparks] = []
static var _next := 0

## Seconds of the initial burst, and of the residual sparking afterwards.
@export var burst_time := 0.35
@export var residual_time := 2.2
@export var arc_count := 4
@export var arc_length := Vector2(0.07, 0.2)

var strength := 1.0
var _t := 99.0
var _skel: Skeleton3D
var _bone := -1
var _offset := Vector3.ZERO
var _arcs: Array[MeshInstance3D] = []
var _arc_ends: Array[Vector3] = []
var _arc_timer := 0.0
var _flash: MeshInstance3D
var _sparks: CPUParticles3D
var _motes: CPUParticles3D
var _residual_t := 0.0


## Play at a skeleton bone's origin (+ local `offset` in bone space).
## `strength` 1 = fresh detachment, ~0.4 = subtle malfunction crackle.
static func play_on_bone(skel: Skeleton3D, bone: int, strength_k := 1.0, offset := Vector3.ZERO) -> JointSparks:
	if skel == null or not skel.is_inside_tree() or bone < 0:
		return null
	var fx := _take(skel.get_tree())
	if fx == null:
		return null
	fx._skel = skel
	fx._bone = bone
	fx._offset = offset
	fx._start(strength_k)
	return fx


static func _take(tree: SceneTree) -> JointSparks:
	var host: Node = tree.current_scene if tree.current_scene else tree.root
	# Drop pooled effects that went away with an old scene.
	_pool = _pool.filter(func(f: JointSparks) -> bool: return is_instance_valid(f) and f.is_inside_tree())
	if _pool.size() < POOL_SIZE:
		var f := JointSparks.new()
		host.add_child(f)
		_pool.append(f)
		return f
	# Reuse the oldest one.
	_next = (_next + 1) % _pool.size()
	return _pool[_next]


static func active_count() -> int:
	var n := 0
	for f in _pool:
		if is_instance_valid(f) and f.is_playing():
			n += 1
	return n


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for i in arc_count:
		var q := Vfx.quad("bolt", ARC_COLORS[i % ARC_COLORS.size()], Vector2.ONE)
		q.visible = false
		add_child(q)
		_arcs.append(q)
		_arc_ends.append(Vector3.ZERO)
	_flash = Vfx.quad("star", Color(0.7, 0.4, 1.0), Vector2.ONE)
	_flash.visible = false
	add_child(_flash)
	_sparks = Vfx.particles("glow", 0.05, 18, 0.45)
	_sparks.one_shot = true
	_sparks.explosiveness = 0.9
	_sparks.emitting = false
	_sparks.direction = Vector3.UP
	_sparks.spread = 180.0
	_sparks.initial_velocity_min = 1.2
	_sparks.initial_velocity_max = 3.5
	_sparks.gravity = Vector3(0, -9.0, 0)
	_sparks.damping_min = 1.0
	_sparks.damping_max = 2.0
	_sparks.color_ramp = Vfx.ramp([Color(1, 1, 1, 1), Color(0.8, 0.5, 1, 1), Color(0.5, 0.15, 0.9, 0)], [0.0, 0.4, 1.0])
	_sparks.scale_amount_curve = Vfx.curve([Vector2(0, 1.0), Vector2(1, 0.3)])
	add_child(_sparks)
	_motes = Vfx.particles("glow", 0.035, 8, 0.8)
	_motes.emitting = false
	_motes.direction = Vector3.UP
	_motes.spread = 180.0
	_motes.initial_velocity_min = 0.05
	_motes.initial_velocity_max = 0.3
	_motes.gravity = Vector3(0, 0.15, 0)
	_motes.color_ramp = Vfx.ramp([Color(0.8, 0.5, 1, 0), Color(0.85, 0.6, 1, 1), Color(0.6, 0.3, 1, 0)], [0.0, 0.3, 1.0])
	add_child(_motes)
	visible = false
	set_process(false)


func is_playing() -> bool:
	return _t < burst_time + residual_time


func _start(k: float) -> void:
	strength = clampf(k, 0.1, 1.0)
	_t = 0.0
	_residual_t = 0.0
	_arc_timer = 0.0
	visible = true
	set_process(true)
	_follow()
	_sparks.amount = maxi(int(18 * strength), 4)
	_sparks.restart()
	_sparks.emitting = true
	_motes.emitting = true
	_flash.visible = true


func _follow() -> void:
	if _skel and is_instance_valid(_skel) and _skel.is_inside_tree() and _bone >= 0:
		global_position = (_skel.global_transform * _skel.get_bone_global_pose(_bone)) * _offset
	elif _t < 99.0:
		# The body it was on is gone: finish quietly.
		_t = burst_time + residual_time


func _process(delta: float) -> void:
	_t += delta
	_follow()
	if not is_playing():
		visible = false
		_motes.emitting = false
		for a in _arcs:
			a.visible = false
		set_process(false)
		return
	var burst := _t < burst_time
	# Brief discharge flash, flickering as it dies.
	var fk := clampf(1.0 - _t / (burst_time * 0.8), 0.0, 1.0)
	_flash.visible = fk > 0.0 and randf() > 0.25
	if _flash.visible:
		Vfx.set_alpha(_flash, fk * strength)
		Vfx.face_camera(_flash, (0.18 + 0.3 * fk) * strength, randf() * TAU)
	if _t > burst_time * 1.5:
		_motes.emitting = false
	# Tiny arcs: crackle constantly during the burst, then only now and then.
	_arc_timer -= delta
	if _arc_timer <= 0.0:
		_arc_timer = randf_range(0.025, 0.06)
		var chance := 1.0 if burst else 0.06
		for i in _arcs.size():
			var on := randf() < chance * (0.6 if i > 0 else 1.0)
			_arcs[i].visible = on
			if on:
				_arc_ends[i] = Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)).normalized() * randf_range(arc_length.x, arc_length.y) * (0.6 + 0.4 * strength)
				Vfx.set_alpha(_arcs[i], randf_range(0.6, 1.0) * strength)
	# Residual: an occasional small spark spit after the burst.
	if not burst:
		_residual_t -= delta
		if _residual_t <= 0.0:
			_residual_t = randf_range(0.25, 0.7)
			if randf() < 0.5:
				_sparks.amount = 4
				_sparks.restart()
				_sparks.emitting = true
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var a := global_position
	for i in _arcs.size():
		if not _arcs[i].visible:
			continue
		var b := a + _arc_ends[i]
		var axis := b - a
		var len := axis.length()
		if len < 1e-4:
			continue
		var y := axis / len
		var x := y.cross((cam.global_position - (a + b) * 0.5).normalized()).normalized()
		var z := x.cross(y)
		var w := 0.08 * (1.0 if randf() < 0.5 else -1.0)
		_arcs[i].global_transform = Transform3D(Basis(x * w, y * len, z), (a + b) * 0.5)
