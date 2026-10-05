class_name ShotgunStream
extends Node3D
## One shotgun energy stream (pooled): a hot core streak with a double helix
## of glowing motes spiralling around it, racing from a barrel to its impact
## at `speed` (fast enough to feel instant, slow enough to see), then
## lingering for a moment and fading. The path may curve slightly (a stream
## assisted towards a secondary enemy leaves along its spread direction and
## bends onto it). On arrival it lands its hit (`Shotgun.land_stream`).
## Visual only otherwise: no physics; one MultiMesh + two quads per stream.

const POOL_SIZE := 40
const MOTES := 26
## Longest visible stretch behind the head (m).
const TRAIL := 7.0
const LINGER := 0.13
const RADIUS := 0.09
## Helix turns per metre.
const TWIST := 1.6

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

var _mm: MultiMesh
var _core: MeshInstance3D
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
	_core = Vfx.quad("glow", Color.WHITE, Vector2.ONE)
	_core.top_level = true
	_core.extra_cull_margin = 30.0
	add_child(_core)
	_head = Vfx.quad("star", Color.WHITE, Vector2.ONE)
	_head.top_level = true
	add_child(_head)
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
	var core := color.lerp(hot, 0.35)
	(_core.material_override as StandardMaterial3D).albedo_color = Color(core.r, core.g, core.b, 1.0)
	(_head.material_override as StandardMaterial3D).albedo_color = Color(hot.r, hot.g, hot.b, 1.0)
	active = true
	visible = true
	set_process(true)
	_process(0.0)


func _point(u: float) -> Vector3:
	var v := 1.0 - u
	return _a * v * v + _c * 2.0 * u * v + _b * u * u


func _process(delta: float) -> void:
	_t += delta
	var head := minf(_t * _speed / _len, 1.0)
	if head >= 1.0 and not _arrived:
		_arrived = true
		Shotgun.land_stream(get_tree(), _hit)
		_hit = {}
	var travel_time := _len / _speed
	var fade := 1.0
	if _t > travel_time:
		fade = 1.0 - (_t - travel_time) / LINGER
		if fade <= 0.0:
			_finish()
			return
	var tail := maxf(head - TRAIL / _len, 0.0)
	if _arrived:
		# Tail catches up while it fades.
		tail = lerpf(tail, head, 1.0 - fade)
	var span := head - tail
	# Spiral motes: two strands, spinning, swelling slightly towards the head.
	var spin := _t * 40.0 + _phase
	for i in MOTES:
		var k := float(i) / float(MOTES - 1)
		var u := tail + span * k
		var p := _point(u)
		var ang := u * _len * TWIST * TAU + spin + (PI if i % 2 else 0.0)
		var r := RADIUS * (0.5 + 0.7 * k)
		p += (_n1 * cos(ang) + _n2 * sin(ang)) * r
		var s := 0.07 + 0.09 * k
		_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), p))
		var col := _color.lerp(_hot, pow(k, 6.0))
		col.a = (0.3 + 0.55 * k) * fade
		_mm.set_instance_color(i, col)
	_mm.visible_instance_count = MOTES
	# Core streak (camera-facing ribbon, straight from tail to head).
	var cam := get_viewport().get_camera_3d()
	var pa := _point(tail)
	var pb := _point(head)
	var axis := pb - pa
	var length := axis.length()
	if cam and length > 0.001:
		var y := axis / length
		var x := y.cross((cam.global_position - (pa + pb) * 0.5).normalized()).normalized()
		var z := x.cross(y)
		_core.global_transform = Transform3D(Basis(x * 0.07, y * length, z), (pa + pb) * 0.5)
		_core.visible = true
		Vfx.set_alpha(_core, 0.6 * fade)
	else:
		_core.visible = false
	_head.global_position = pb
	Vfx.face_camera(_head, 0.35 * (0.6 + 0.4 * fade), spin * 0.2)
	Vfx.set_alpha(_head, fade if not _arrived else fade * 0.6)


func _finish() -> void:
	if not _arrived and not _hit.is_empty():
		_arrived = true
		Shotgun.land_stream(get_tree(), _hit)
	_hit = {}
	active = false
	visible = false
	set_process(false)
