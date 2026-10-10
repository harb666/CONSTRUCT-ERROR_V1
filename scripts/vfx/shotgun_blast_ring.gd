class_name ShotgunBlastRing
extends Node3D
## Fiery cartoon blast rings out of the shotgun's barrel cluster, one set per
## shot (pooled), left in the world where the shot was fired (like the
## streams' trails): a big ring bursting out across the muzzle and thinning
## away, and a second, smaller ring that hangs round the start of the
## streams for as long as their trails linger - so a trail left behind when
## the player moves on starts from a ring of fire, not a flat cut.
## toon_ring.gdshader in the shotgun's fire colours (cream-hot band, dark red
## ink rim), facing along the shot.

const SHADER := preload("res://scripts/vfx/toon_ring.gdshader")
const POOL_SIZE := 4
const FILL := Color(1.0, 0.72, 0.2)
const FILL_LINGER := Color(1.0, 0.45, 0.06)
const RIM := Color(0.62, 0.12, 0.02)
## Burst ring: seconds, size from / to (m across).
const BURST_TIME := 0.22
const BURST_FROM := 0.35
const BURST_TO := 1.7
## Lingering ring: seconds (the streams' trails stay ~0.7 s + flight), size.
const LINGER_TIME := 0.85
const LINGER_FROM := 0.45
const LINGER_TO := 1.05

static var _pool: Array[ShotgunBlastRing] = []
static var spawned := 0

var active := false
var _t := 99.0
var _burst: MeshInstance3D
var _linger: MeshInstance3D
var _bm: ShaderMaterial
var _lm: ShaderMaterial
var _at := Vector3.ZERO
var _dir := Vector3.FORWARD


static func spawn(tree: SceneTree, at: Vector3, dir: Vector3) -> ShotgunBlastRing:
	_pool = _pool.filter(func(m: ShotgunBlastRing) -> bool: return is_instance_valid(m) and m.is_inside_tree())
	var r: ShotgunBlastRing = null
	for m in _pool:
		if not m.active:
			r = m
			break
	if r == null:
		if _pool.size() < POOL_SIZE:
			r = ShotgunBlastRing.new()
			var host: Node = tree.current_scene if tree.current_scene else tree.root
			host.add_child(r)
			_pool.append(r)
		else:
			r = _pool[0]
			for m in _pool:
				if m._t > r._t:
					r = m
	r._start(at, dir)
	spawned += 1
	return r


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_bm = _ring_mat(FILL, 0.3)
	_lm = _ring_mat(FILL_LINGER, 0.42)
	_burst = _ring_mesh(_bm)
	_linger = _ring_mesh(_lm)
	visible = false
	set_process(false)


func _ring_mat(fill: Color, width: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("fill_color", fill)
	m.set_shader_parameter("rim_color", RIM)
	m.set_shader_parameter("width", width)
	return m


func _ring_mesh(m: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = QuadMesh.new()  # faces +Z: turned to face along the shot
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _start(at: Vector3, dir: Vector3) -> void:
	_at = at
	_dir = dir.normalized() if dir.length_squared() > 1e-4 else Vector3.FORWARD
	var up := Vector3.UP if absf(_dir.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(_dir).normalized()
	var b := Basis(x, _dir.cross(x).normalized(), _dir).rotated(_dir, randf() * TAU)
	global_transform = Transform3D(b, at)
	_bm.set_shader_parameter("seed", randf() * 20.0)
	_lm.set_shader_parameter("seed", randf() * 20.0)
	_t = 0.0
	active = true
	visible = true
	set_process(true)
	_update()


func _process(delta: float) -> void:
	_t += delta
	if _t >= maxf(BURST_TIME, LINGER_TIME):
		active = false
		visible = false
		set_process(false)
		return
	_update()


func _update() -> void:
	var kb := clampf(_t / BURST_TIME, 0.0, 1.0)
	_burst.visible = kb < 1.0
	if _burst.visible:
		var e := 1.0 - pow(1.0 - kb, 3.0)
		_burst.scale = Vector3.ONE * lerpf(BURST_FROM, BURST_TO, e)
		_burst.position = Vector3(0, 0, 0.25 * e)
		_bm.set_shader_parameter("progress", kb)
		_bm.set_shader_parameter("fade", 1.0 - smoothstep(0.45, 1.0, kb))
	var kl := clampf(_t / LINGER_TIME, 0.0, 1.0)
	var el := 1.0 - pow(1.0 - kl, 2.0)
	_linger.scale = Vector3.ONE * lerpf(LINGER_FROM, LINGER_TO, el)
	_linger.position = Vector3(0, 0, 0.12 * el)
	_lm.set_shader_parameter("progress", kl * 0.5)
	_lm.set_shader_parameter("fade", (1.0 - kl * kl) * clampf(_t / 0.04, 0.0, 1.0))
