class_name RobotDeathSparks
extends Node3D
## Electrical failure of a destroyed light robot: crackling arcs jumping
## between its joints, joint spark bursts (JointSparks), a flickering
## blue-white discharge light and a thin wisp of smoke from the torso.
## Strongest the moment it dies, then dying away (arcs thin out, bursts
## space out, smoke stops) over `duration`. Pooled and shared by all robots;
## follows the dead robot's skeleton.

const POOL_SIZE := 4
const ARC_COLOR := Color(0.75, 0.85, 1.0)
const ARC_HOT := Color(1.0, 1.0, 1.0)
## Joints the failure jumps between (Mixamo rig).
const BONES := [&"mixamorig_Head", &"mixamorig_Neck", &"mixamorig_Spine2", &"mixamorig_Spine", &"mixamorig_Hips",
	&"mixamorig_LeftArm", &"mixamorig_RightArm", &"mixamorig_LeftForeArm", &"mixamorig_RightForeArm",
	&"mixamorig_LeftUpLeg", &"mixamorig_RightUpLeg", &"mixamorig_LeftLeg", &"mixamorig_RightLeg"]

static var _pool: Array[RobotDeathSparks] = []
static var _next := 0

@export var duration := 4.5
## Intensity halves about every `decay` * 0.7 s.
@export var decay := 1.3

var _t := 99.0
var _skel: Skeleton3D
var _bones: Array[int] = []
var _arcs: Array[MeshInstance3D] = []
var _arc_ends: Array = []  # per arc: [bone a, bone b]
var _arc_t := 0.0
var _burst_t := 0.0
var _light: OmniLight3D
var _smoke: CPUParticles3D
var _smoke_bone := -1


static func play(skel: Skeleton3D, strength := 1.0) -> RobotDeathSparks:
	if skel == null or not skel.is_inside_tree():
		return null
	var fx := _take(skel.get_tree())
	if fx == null:
		return null
	fx._start(skel, strength)
	return fx


static func _take(tree: SceneTree) -> RobotDeathSparks:
	var host: Node = tree.current_scene if tree.current_scene else tree.root
	_pool = _pool.filter(func(p: RobotDeathSparks) -> bool: return is_instance_valid(p) and p.is_inside_tree())
	for p in _pool:
		if p._t >= p.duration:
			return p
	if _pool.size() < POOL_SIZE:
		var fx := RobotDeathSparks.new()
		host.add_child(fx)
		_pool.append(fx)
		return fx
	# All busy: take over the oldest.
	_next = (_next + 1) % _pool.size()
	return _pool[_next]


static func active_count() -> int:
	var n := 0
	for p in _pool:
		if is_instance_valid(p) and p._t < p.duration:
			n += 1
	return n


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for i in 3:
		var a := Vfx.quad("bolt", ARC_HOT if i == 0 else ARC_COLOR, Vector2.ONE)
		a.top_level = true
		a.visible = false
		a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(a)
		_arcs.append(a)
		_arc_ends.append([0, 0])
	_light = OmniLight3D.new()
	_light.light_color = Color(0.7, 0.8, 1.0)
	_light.omni_range = 3.0
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)
	Vfx.tame_light(_light)
	_smoke = Vfx.particles("smoke", 0.32, 10, 1.6)
	(_smoke.mesh as QuadMesh).material = Vfx.mix_material("smoke")  # dark smoke, not additive glow
	_smoke.local_coords = false
	_smoke.direction = Vector3.UP
	_smoke.spread = 18.0
	_smoke.initial_velocity_min = 0.25
	_smoke.initial_velocity_max = 0.6
	_smoke.gravity = Vector3(0, 0.35, 0)
	_smoke.scale_amount_curve = Vfx.curve([Vector2(0, 0.5), Vector2(1, 2.0)])
	_smoke.color_ramp = Vfx.ramp([Color(0.3, 0.3, 0.32, 0.0), Color(0.28, 0.28, 0.3, 0.45), Color(0.4, 0.4, 0.42, 0.0)], [0.0, 0.2, 1.0])
	_smoke.emitting = false
	add_child(_smoke)
	set_process(false)


func _start(skel: Skeleton3D, strength: float) -> void:
	_skel = skel
	_bones.clear()
	for b in BONES:
		var i := skel.find_bone(b)
		if i >= 0:
			_bones.append(i)
	_smoke_bone = skel.find_bone(&"mixamorig_Spine2")
	_t = 0.0
	_arc_t = 0.0
	_burst_t = 0.0
	decay = 1.3 * clampf(strength, 0.5, 1.5)
	# The moment of death: two strong joint bursts at once.
	for k in 2:
		if not _bones.is_empty():
			JointSparks.play_on_bone(skel, _bones[randi() % _bones.size()], 1.0)
	_smoke.emitting = true
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration or not is_instance_valid(_skel) or not _skel.is_inside_tree() or not _skel.is_visible_in_tree():
		_stop()
		return
	var k := exp(-_t / decay)  # 1 -> ~0
	var xf := _skel.global_transform
	# Smoke rises from the chest for the first few seconds.
	if _smoke_bone >= 0:
		_smoke.global_position = xf * _skel.get_bone_global_pose(_smoke_bone).origin
	if _smoke.emitting and _t > duration * 0.6:
		_smoke.emitting = false
	# Bursts of joint sparks, further and further apart.
	_burst_t -= delta
	if _burst_t <= 0.0 and not _bones.is_empty():
		_burst_t = randf_range(0.18, 0.4) / maxf(k, 0.12)
		JointSparks.play_on_bone(_skel, _bones[randi() % _bones.size()], clampf(0.3 + 0.7 * k, 0.3, 1.0))
	# Crackling arcs between neighbouring joints: re-strike every few
	# frames, fewer and fewer of them.
	_arc_t -= delta
	var cam := get_viewport().get_camera_3d()
	if _arc_t <= 0.0:
		_arc_t = randf_range(0.045, 0.09)
		for i in _arcs.size():
			var on := randf() < k * (1.0 if i == 0 else 0.7)
			_arcs[i].visible = on and cam != null
			if on:
				var a: int = _bones[randi() % _bones.size()]
				var b: int = _bones[randi() % _bones.size()]
				if a == b:
					b = _skel.get_bone_parent(a) if _skel.get_bone_parent(a) >= 0 else a
				_arc_ends[i] = [a, b]
	var lit := 0.0
	for i in _arcs.size():
		if not _arcs[i].visible or cam == null:
			continue
		var ends: Array = _arc_ends[i]
		var pa: Vector3 = xf * _skel.get_bone_global_pose(ends[0]).origin
		var pb: Vector3 = xf * _skel.get_bone_global_pose(ends[1]).origin
		if pa.distance_squared_to(pb) < 0.0025:
			pb = pa + Vector3(randf_range(-0.15, 0.15), randf_range(0.05, 0.2), randf_range(-0.15, 0.15))
		# Jitter so the arc crackles rather than sitting still.
		pa += Vector3(randf_range(-0.04, 0.04), randf_range(-0.04, 0.04), randf_range(-0.04, 0.04))
		MachineGunFlash._stretch(_arcs[i], pa, pb, 0.05 + 0.04 * k, cam)
		Vfx.set_alpha(_arcs[i], 0.6 + 0.4 * randf())
		lit += 1.0
		_light.global_position = (pa + pb) * 0.5
	_light.visible = lit > 0.0
	_light.light_energy = (1.0 + 2.5 * k) * randf_range(0.5, 1.0) if lit > 0.0 else 0.0


func _stop() -> void:
	_t = duration
	for a in _arcs:
		a.visible = false
	_light.visible = false
	_smoke.emitting = false
	_skel = null
	set_process(false)
