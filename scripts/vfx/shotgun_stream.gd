class_name ShotgunStream
extends Node3D
## One shotgun energy stream (pooled), a cartoon MAGMA jet like Ratchet:
## Gladiator's Magma Cannon: a fat flame body with ragged licking edges,
## white-hot core and dark red rim (magma_stream.gdshader), two jagged
## crackling fire bolts zig-zagging around it (fire_bolt.gdshader, re-jagged
## every few frames), a cartoon fireball at its head, wrapped in a spiral
## ribbon and sparkling motes. It races from its barrel to the impact at `speed`
## (feels instant, but visible), then the whole trail lingers, the spiral
## slowly widening and fading. The path may curve slightly (a stream
## assisted towards a secondary enemy leaves along its spread direction and
## bends onto it). On arrival it lands its hit (`Shotgun.land_stream`).
## Visual only otherwise: no physics. Per stream: three ArrayMeshes (beam,
## bolts, spiral) built ONCE per shot along the whole path - the shaders turn
## them to the camera, jag the bolts and reveal them up to the head, so no
## graphics buffers are rebuilt every frame (that churn is hard on phones'
## browsers) - and one MultiMesh (motes).

const POOL_SIZE := 40
const MOTES := 36
## How long the trail stays after the impact (s).
const LINGER := 0.7
const RADIUS := 0.085
## Spiral turns per metre and ribbon width (m).
const TWIST := 1.5
const RIBBON := 0.07
const SEGMENTS_PER_M := 14.0
const BEAM_SEGMENTS := 16
## Width of the magma jet (core + flames + rim).
const BEAM_WIDTH := 0.3
const BEAM_SHADER := preload("res://scripts/vfx/magma_stream.gdshader")
const BOLT_SHADER := preload("res://scripts/vfx/fire_bolt.gdshader")
## Jagged fire bolts around the jet: count, width, zig-zag size (m), kink
## spacing (m), seconds between re-jags, and how long into the linger
## they last (share of LINGER).
const BOLTS := 2
const BOLT_WIDTH := 0.055
const BOLT_JAG := 0.15
const BOLT_STEP := 0.4
const BOLT_REJAG := 0.035
const BOLT_LINGER := 0.4
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

var _beam: ArrayMesh
var _beam_mi: MeshInstance3D
var _helix: ArrayMesh
var _helix_mi: MeshInstance3D
var _helix_mat: ShaderMaterial
var _beam_shader_mat: ShaderMaterial
var _mm: MultiMesh
var _head: MeshInstance3D
var _bolt: ArrayMesh
var _bolt_mat: ShaderMaterial
## Meshes built (once per shot; tests).
var mesh_builds := 0


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
	_beam = ArrayMesh.new()
	_beam_mi = MeshInstance3D.new()
	_beam_mi.mesh = _beam
	_beam_mi.material_override = _beam_shader_mat
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
	_bolt_mat = ShaderMaterial.new()
	_bolt_mat.shader = BOLT_SHADER
	_bolt_mat.set_shader_parameter("width", BOLT_WIDTH)
	_bolt_mat.set_shader_parameter("jag", BOLT_JAG)
	_bolt_mat.set_shader_parameter("rejag", BOLT_REJAG)
	_bolt = ArrayMesh.new()
	var bmi := MeshInstance3D.new()
	bmi.mesh = _bolt
	bmi.material_override = _bolt_mat
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bmi.extra_cull_margin = 60.0
	add_child(bmi)
	# Head: a cartoon fireball star.
	_head = Vfx.toon_flash(0, Color(1.0, 0.5, 0.08), Color(1.0, 0.97, 0.8), Color(0.6, 0.1, 0.02), Vector2.ONE, 9.0)
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
	_beam_shader_mat.set_shader_parameter("seed", randf() * 50.0)
	_bolt_mat.set_shader_parameter("color", color.lerp(hot, 0.45))
	_bolt_mat.set_shader_parameter("hot", Color(1, 1, 0.92))
	_bolt_mat.set_shader_parameter("rim", color.darkened(0.35))
	_bolt_mat.set_shader_parameter("seed", randf() * 100.0)
	_build_beam()
	_build_bolts()
	mesh_builds += 1
	_helix_mat.set_shader_parameter("hot", hot)
	_helix_mat.set_shader_parameter("head", 0.0)
	_helix_mat.set_shader_parameter("fade", 1.0)
	_helix_mat.set_shader_parameter("expand", 0.0)
	for i in MOTES:
		_mote_u[i] = (i + randf()) / MOTES
		_mote_a[i] = randf() * TAU
	Vfx.toon_reseed(_head)
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
	# Beam and bolts: reveal up to the head, fade (shader-side; no rebuild).
	var head_pos := _point(head)
	_beam_shader_mat.set_shader_parameter("head", head)
	_beam_shader_mat.set_shader_parameter("head_pos", head_pos)
	_beam_shader_mat.set_shader_parameter("core", fade * fade)
	_beam_shader_mat.set_shader_parameter("fade", fade * fade)
	_beam_shader_mat.set_shader_parameter("width", BEAM_WIDTH * (1.0 + linger * 0.5) * (0.6 + 0.4 * fade))
	var bf := clampf(1.0 - linger / BOLT_LINGER, 0.0, 1.0)
	_bolt_mat.set_shader_parameter("head", head)
	_bolt_mat.set_shader_parameter("head_pos", head_pos)
	_bolt_mat.set_shader_parameter("core", bf)
	_bolt_mat.set_shader_parameter("fade", bf)
	_bolt_mat.set_shader_parameter("width", BOLT_WIDTH * (0.6 + 0.4 * bf))
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
		Vfx.face_camera(_head, 0.62, _t * 20.0)
		Vfx.set_alpha(_head, 1.0)


## The beam ribbon along the whole path (the shader faces it to the camera
## and reveals it up to the head): pairs of vertices on the path, the path
## direction in NORMAL, (share of the path, barrel taper) in UV2.
func _build_beam() -> void:
	var n := BEAM_SEGMENTS
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	for i in n + 1:
		var u := float(i) / n
		var p := _point(u)
		var t := _tangent(u)
		var taper := clampf(u * _len / 0.35, 0.3, 1.0)
		for side in 2:
			verts.append(p)
			norms.append(t)
			uvs.append(Vector2(u * _len, float(side)))
			uv2s.append(Vector2(u, taper))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	_beam.clear_surfaces()
	_beam.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)


## The jagged fire bolts (one surface each): a vertex pair per kink on the
## path, the path direction in NORMAL, a sideways axis in TANGENT, (share of
## the path, how far the kink may jag - none at the barrel) in UV2 and the
## bolt's seed in COLOR; the shader jags, reveals and faces them.
func _build_bolts() -> void:
	_bolt.clear_surfaces()
	var n := clampi(int(_len / BOLT_STEP), 2, 80)
	for k in BOLTS:
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var tans := PackedFloat32Array()
		var uvs := PackedVector2Array()
		var uv2s := PackedVector2Array()
		var cols := PackedColorArray()
		for i in n + 1:
			var u := float(i) / n
			var p := _point(u)
			var t := _tangent(u)
			var grow := clampf(u * _len / 0.6, 0.0, 1.0) * (0.0 if i == n else 1.0)
			for side in 2:
				verts.append(p)
				norms.append(t)
				tans.append_array([_n1.x, _n1.y, _n1.z, 1.0])
				uvs.append(Vector2(u * _len, float(side)))
				uv2s.append(Vector2(u, grow))
				cols.append(Color(float(k + 1) * 0.37, 0, 0, 1))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_TANGENT] = tans
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		arrays[Mesh.ARRAY_COLOR] = cols
		_bolt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)


func _finish() -> void:
	if not _arrived and not _hit.is_empty():
		_arrived = true
		Shotgun.land_stream(get_tree(), _hit)
	_hit = {}
	active = false
	visible = false
	set_process(false)
