class_name GravitySparks
extends Node3D
## Black Hole Generator muzzle flash: a burst of glowing blue particles (and
## a brief blue flare) that is immediately caught by the black hole's
## gravity — the particles swirl around its flight axis, stream after it
## and are swallowed when they reach its core. Simulated in one small loop,
## drawn with a MultiMesh; frees itself when done.

@export var count := 48
@export var flare_time := 0.12
## Attraction (m/s²) towards the black hole and swirl around its axis.
@export var pull := 42.0
@export var swirl := 18.0
@export var max_speed := 26.0
@export var life := Vector2(1.6, 2.6)
## Seconds each particle swirls around the black hole before it can be
## swallowed (so the stream is visible), and the swallow radius factor.
@export var swallow_after := Vector2(0.5, 1.1)
@export var swallow_fraction := 0.8

var target: Node3D
var axis := Vector3.FORWARD
var consumed := 0

var _mm: MultiMesh
var _flare: MeshInstance3D
var _t := 0.0
var _p: Array = []  # [pos, vel, age, life, size, hue]


static func spawn(parent: Node, muzzle: Transform3D, black_hole: Node3D, dir: Vector3) -> GravitySparks:
	var g := GravitySparks.new()
	g.target = black_hole
	g.axis = dir.normalized()
	parent.add_child(g)
	g._burst(muzzle)
	return g


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var q := QuadMesh.new()
	q.material = Vfx.material("glow", Color.WHITE, BaseMaterial3D.BILLBOARD_ENABLED, true, true)
	_mm.mesh = q
	_mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 200.0
	add_child(mi)
	_flare = Vfx.quad("star", Color(0.35, 0.6, 1.0), Vector2.ONE)
	_flare.top_level = true
	add_child(_flare)


func _burst(muzzle: Transform3D) -> void:
	var fwd := muzzle.basis.x.normalized()  # weapons fire along +X
	_flare.global_position = muzzle.origin
	for i in count:
		var spread := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var v := fwd * randf_range(2.0, 7.0) + spread * randf_range(1.5, 4.5)
		_p.append([muzzle.origin + spread * 0.05, v, 0.0, randf_range(life.x, life.y), randf_range(0.09, 0.22), randf(), randf_range(swallow_after.x, swallow_after.y)])


func alive_count() -> int:
	return _p.size()


func _process(delta: float) -> void:
	_t += delta
	var fk := 1.0 - _t / flare_time
	_flare.visible = fk > 0.0
	if _flare.visible:
		Vfx.set_alpha(_flare, fk)
		Vfx.face_camera(_flare, 0.5 + 0.4 * (1.0 - fk), _t * 9.0)
	var has_target := target != null and is_instance_valid(target) and target.is_inside_tree() and target.visible
	var c := target.get_global_transform_interpolated().origin if has_target else Vector3.ZERO
	var core_r := 0.35
	if has_target and "collision_radius" in target:
		core_r = maxf(float(target.collision_radius) * swallow_fraction, 0.12)
	var i := 0
	while i < _p.size():
		var p: Array = _p[i]
		p[2] += delta
		var pos: Vector3 = p[0]
		var v: Vector3 = p[1]
		if has_target:
			var rel := pos - c
			var d := rel.length()
			if d < core_r and p[2] > p[6]:
				consumed += 1
				_p.remove_at(i)
				continue
			# Pulled in hard, and swirled around the flight axis.
			var radial := rel - axis * rel.dot(axis)
			var tangent := axis.cross(radial).normalized() if radial.length_squared() > 1e-4 else Vector3.ZERO
			v += (-rel / d) * pull * clampf(4.0 / (1.0 + d), 0.5, 4.0) * delta
			v += tangent * swirl * delta
			# Lose orbit energy (relative to the moving hole) so they spiral in.
			var hv: Vector3 = target.direction * target.speed if "speed" in target else Vector3.ZERO
			v -= (v - hv) * minf(1.4 * delta, 0.3)
			v = v.limit_length(max_speed)
		else:
			v *= 1.0 - minf(2.0 * delta, 0.5)
		p[0] = pos + v * delta
		p[1] = v
		if p[2] >= p[3]:
			_p.remove_at(i)
			continue
		i += 1
	if _p.is_empty() and not _flare.visible:
		queue_free()
		return
	_mm.visible_instance_count = _p.size()
	for k in _p.size():
		var p: Array = _p[k]
		var t: float = p[2] / p[3]
		var s: float = p[4] * (1.0 - t * 0.5)
		if has_target:
			# Stretch/shrink as they fall into the core.
			s *= clampf((p[0] as Vector3).distance_to(c) / 1.5, 0.3, 1.0)
		_mm.set_instance_transform(k, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), p[0]))
		var col := Color(0.1, 0.4, 1.0).lerp(Color(0.45, 0.75, 1.0), p[5])
		col.a = minf(t * 10.0, 1.0) * (1.0 - t * t)
		_mm.set_instance_color(k, col)
