class_name ShotgunStream
extends Node3D
## One shotgun energy stream (pooled), drawn like a railgun trail: a cartoon
## beam (solid white-hot core, orange body, dark rim, pulses racing along
## it - toon_beam.gdshader), wrapped in a spiral ribbon
## and sparkling motes. It races from its barrel to the impact at `speed`
## (feels instant, but visible), then the whole trail lingers, the spiral
## slowly widening and fading. The path may curve slightly (a stream
## assisted towards a secondary enemy leaves along its spread direction and
## bends onto it). On arrival it lands its hit (`Shotgun.land_stream`).
## Visual only otherwise: no physics. Per stream: one ImmediateMesh (beam),
## one ArrayMesh (spiral, built once per shot) and one MultiMesh (motes).

const POOL_SIZE := 40
const MOTES := 36
## How long the trail stays after the impact (s).
const LINGER := 0.7
const RADIUS := 0.085
## Spiral turns per metre and ribbon width (m).
const TWIST := 1.5
const RIBBON := 0.07
const SEGMENTS_PER_M := 14.0
const BEAM_SEGMENTS := 10
## Width of the cartoon beam (core + body + rim).
const BEAM_WIDTH := 0.13
const BEAM_SHADER := preload("res://scripts/vfx/toon_beam.gdshader")
const HELIX_SHADER := preload("res://scripts/vfx/rail_helix.gdshader")

static var _pool: Array[ShotgunStream] = []
static var _next := 0

var active := false
var _a := Vector3.ZERO
var _b := Vector3.ZERO
var _c := Vector3.ZERO
var _len := 1.0
var _speed := 150.0
var _t := 0.0
var _arrived := false
var _hit := {}
var _phase := 0.0
var _color := Color.ORANGE
var _hot := Color.WHITE
var _n1 := Vector3.RIGHT
var _n2 := Vector3.UP
var _mote_u := PackedFloat32Array()
var _mote_a := PackedFloat32Array()

var _beam: ImmediateMesh
var _beam_mi: MeshInstance3D
var _helix: ArrayMesh
var _helix_mi: MeshInstance3D
var _helix_mat: ShaderMaterial
var _beam_shader_mat: ShaderMaterial
var _mm: MultiMesh
var _head: MeshInstance3D


## Fire a stream from `from` to `to`. `leave_dir` is the direction it leaves
## the barrel (differs from the straight line when it curves). `hit` is
## applied on arrival.
static func fire(tree: SceneTree, from: Vector3, to: Vector3, leave_dir: Vector3, speed: float,
		color: Color, hot: Color, hit: Dictionary) -> ShotgunStream:
	var s := _take(tree)
	s._launch(from, to, leave_dir, speed, color, hot, hit)
	return s


static func active_count() -> int:
	var n := 0
	for p in _pool:
		if is_instance_valid(p) and p.active:
			n += 1
	return n


static func _take(tree: SceneTree) -> ShotgunStream:
	var host: Node = tree.current_scene if tree.current_scene else tree.root
	_pool = _pool.filter(func(p: ShotgunStream) -> bool: return is_instance_valid(p) and p.is_inside_tree())
	for p in _pool:
		if not p.active:
			return p
	if _pool.size() < POOL_SIZE:
		var s := ShotgunStream.new()
		host.add_child(s)
		_pool.append(s)
		return s
	# All busy: finish the oldest now and reuse it.
	_next = (_next + 1) % _pool.size()
	var old := _pool[_next]
	old._finish()
	return old


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_beam_shader_mat = ShaderMaterial.new()
	_beam_shader_mat.shader = BEAM_SHADER
	_beam = ImmediateMesh.new()
	_beam_mi = MeshInstance3D.new()
	_beam_mi.mesh = _beam
	_beam_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam_mi.extra_cull_margin = 60.0
	add_child(_beam_mi)
	_helix = ArrayMesh.new()
	_helix_mat = ShaderMaterial.new()
	_helix_mat.shader = HELIX_SHADER
	_helix_mi = MeshInstance3D.new()
	_helix_mi.mesh = _helix
	_helix_mi.material_override = _helix_mat
	_helix_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_helix_mi.extra_cull_margin = 60.0
	add_child(_helix_mi)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var q := QuadMesh.new()
	q.material = Vfx.material("glow", Color.WHITE, BaseMaterial3D.BILLBOARD_ENABLED, true)
	_mm.mesh = q
	_mm.instance_count = MOTES
	_mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 60.0
	add_child(mi)
	_head = Vfx.quad("star", Color.WHITE, Vector2.ONE)
	_head.top_level = true
	add_child(_head)
	_mote_u.resize(MOTES)
	_mote_a.resize(MOTES)
	visible = false
	set_process(false)


func _launch(from: Vector3, to: Vector3, leave_dir: Vector3, speed: float, color: Color, hot: Color, hit: Dictionary) -> void:
	_a = from
	_b = to
	_len = maxf(from.distance_to(to), 0.05)
	# Bezier control point: along the leaving direction (on the straight
	# line when it doesn't curve).
	_c = from + leave_dir.normalized() * _len * 0.5
	_speed = speed
	_t = 0.0
	_arrived = false
	_hit = hit
	_phase = randf() * TAU
	_color = color
	_hot = hot
	var d := (to - from).normalized()
	_n1 = d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
	_n2 = d.cross(_n1).normalized()
	_build_helix()
	_helix_mat.set_shader_parameter("color", Color(color.r, color.g, color.b, 0.95))
	_beam_shader_mat.set_shader_parameter("color", color)
	_beam_shader_mat.set_shader_parameter("hot", hot)
	_beam_shader_mat.set_shader_parameter("rim", color.darkened(0.5))
	_helix_mat.set_shader_parameter("hot", hot)
	_helix_mat.set_shader_parameter("head", 0.0)
	_helix_mat.set_shader_parameter("fade", 1.0)
	_helix_mat.set_shader_parameter("expand", 0.0)
	for i in MOTES:
		_mote_u[i] = (i + randf()) / MOTES
		_mote_a[i] = randf() * TAU
	(_head.material_override as StandardMaterial3D).albedo_color = Color(hot.r, hot.g, hot.b, 1.0)
	active = true
	visible = true
	set_process(true)
	_process(0.0)


func _point(u: float) -> Vector3:
	var v := 1.0 - u
	return _a * v * v + _c * 2.0 * u * v + _b * u * u


func _tangent(u: float) -> Vector3:
	var t := (_c - _a) * 2.0 * (1.0 - u) + (_b - _c) * 2.0 * u
	return t.normalized() if t.length_squared() > 1e-8 else (_b - _a).normalized()


## Spiral ribbon along the whole path (revealed by the shader as it flies).
func _build_helix() -> void:
	var n := clampi(int(_len * SEGMENTS_PER_M), 8, 420)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize((n + 1) * 2)
	norms.resize((n + 1) * 2)
	uvs.resize((n + 1) * 2)
	for i in n + 1:
		var u := float(i) / n
		var c := _point(u)
		var d := _tangent(u)
		var ang := u * _len * TWIST * TAU + _phase
		var radial := (_n1 * cos(ang) + _n2 * sin(ang))
		# Swell in from the barrel over the first half metre.
		var r := RADIUS * clampf(u * _len / 0.5, 0.25, 1.0)
		var p := c + radial * r
		verts[i * 2] = p - d * RIBBON * 0.5
		verts[i * 2 + 1] = p + d * RIBBON * 0.5
		norms[i * 2] = radial
		norms[i * 2 + 1] = radial
		uvs[i * 2] = Vector2(u, 0.0)
		uvs[i * 2 + 1] = Vector2(u, 1.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	_helix.clear_surfaces()
	_helix.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)


func _process(delta: float) -> void:
	_t += delta
	var head := minf(_t * _speed / _len, 1.0)
	if head >= 1.0 and not _arrived:
		_arrived = true
		Shotgun.land_stream(get_tree(), _hit)
		_hit = {}
	var travel_time := _len / _speed
	var linger := maxf(_t - travel_time, 0.0) / LINGER
	if linger >= 1.0:
		_finish()
		return
	var fade := 1.0 - linger
	_helix_mat.set_shader_parameter("head", head + 0.011)
	_helix_mat.set_shader_parameter("fade", fade * fade)
	_helix_mat.set_shader_parameter("expand", linger * 0.12)
	_draw_beam(head, fade, linger)
	# Motes: sparkle along the revealed spiral, drifting outwards as it fades.
	var spin := _t * 6.0
	var count := 0
	for i in MOTES:
		var u: float = _mote_u[i]
		if u > head:
			continue
		var ang: float = u * _len * TWIST * TAU + _phase + _mote_a[i] * 0.15 + spin * 0.2
		var radial := (_n1 * cos(ang) + _n2 * sin(ang))
		var p := _point(u) + radial * (RADIUS * (1.0 + linger * 2.2) + 0.02 * sin(_mote_a[i] + spin))
		var s := 0.07 * (1.0 - linger * 0.5)
		_mm.set_instance_transform(count, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), p))
		var col := _color.lerp(_hot, 0.3 + 0.4 * (0.5 + 0.5 * sin(_mote_a[i] * 3.0 + _t * 30.0)))
		col.a = 0.9 * fade
		_mm.set_instance_color(count, col)
		count += 1
	_mm.visible_instance_count = count
	_head.visible = not _arrived
	if not _arrived:
		_head.global_position = _point(head)
		Vfx.face_camera(_head, 0.42, _t * 20.0)


## Camera-facing cartoon beam (toon_beam.gdshader: white-hot core, orange
## body, dark rim, racing pulses) from the barrel to the head.
func _draw_beam(head: float, fade: float, linger: float) -> void:
	_beam.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null or head <= 0.0:
		return
	_beam_shader_mat.set_shader_parameter("core", fade * fade)
	var col := Color(1, 1, 1, fade * fade)
	var width := BEAM_WIDTH * (1.0 + linger * 0.5) * (0.6 + 0.4 * fade)
	_beam.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _beam_shader_mat)
	for i in BEAM_SEGMENTS + 1:
		var u := head * float(i) / BEAM_SEGMENTS
		var p := _point(u)
		var side := _tangent(u).cross((cam.global_position - p).normalized()).normalized()
		# Taper in at the barrel.
		var w := width * 0.5 * clampf(u * _len / 0.35, 0.3, 1.0)
		_beam.surface_set_color(col)
		_beam.surface_set_uv(Vector2(u * _len, 0.0))
		_beam.surface_add_vertex(p - side * w)
		_beam.surface_set_color(col)
		_beam.surface_set_uv(Vector2(u * _len, 1.0))
		_beam.surface_add_vertex(p + side * w)
	_beam.surface_end()


func _finish() -> void:
	if not _arrived and not _hit.is_empty():
		_arrived = true
		Shotgun.land_stream(get_tree(), _hit)
	_hit = {}
	_beam.clear_surfaces()
	active = false
	visible = false
	set_process(false)
