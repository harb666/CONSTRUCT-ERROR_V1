class_name HitStar
extends Node3D
## Cartoon "POW" hit burst (pooled): a spiky star in the hit's colour with a
## white-hot centre and ink rim that pops out and snaps away, a small inked
## ring flying out behind it and a few speed-line spikes. Sized by how hard
## the hit was. Used for enemies and players taking damage.

const POOL_SIZE := 12
const RING_SHADER := preload("res://scripts/vfx/toon_ring.gdshader")

@export var life := 0.2

static var _pool: Array[HitStar] = []
static var spawned := 0

var active := false
var size := 0.5
var _t := 99.0
var _star: MeshInstance3D
var _inner: MeshInstance3D
var _ring: MeshInstance3D
var _roll := 0.0


## A burst at `at`, `size` m across, tinted `col`.
static func spawn(tree: SceneTree, at: Vector3, col: Color, burst_size := 0.5) -> HitStar:
	_pool = _pool.filter(func(h: HitStar) -> bool: return is_instance_valid(h) and h.is_inside_tree())
	var b: HitStar = null
	for h in _pool:
		if not h.active:
			b = h
			break
	if b == null:
		if _pool.size() < POOL_SIZE:
			b = HitStar.new()
			var host: Node = tree.current_scene if tree.current_scene else tree.root
			host.add_child(b)
			_pool.append(b)
		else:
			b = _pool[0]
			for h in _pool:
				if h._t > b._t:
					b = h
	b._start(at, col, burst_size)
	spawned += 1
	return b


static func busy_count() -> int:
	var n := 0
	for h in _pool:
		if is_instance_valid(h) and h.active:
			n += 1
	return n


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_star = Vfx.toon_flash(0, Color.WHITE, Color(1, 1, 0.95), Color(0.15, 0.05, 0.02), Vector2.ONE, 10.0)
	_star.top_level = true
	add_child(_star)
	_inner = Vfx.toon_flash(0, Color(1, 1, 0.9), Color.WHITE, Color(1, 1, 0.9), Vector2.ONE, 6.0)
	_inner.top_level = true
	add_child(_inner)
	_ring = MeshInstance3D.new()
	_ring.mesh = QuadMesh.new()
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = RING_SHADER
	m.set_shader_parameter("width", 0.16)
	_ring.material_override = m
	_ring.top_level = true
	add_child(_ring)
	for q: MeshInstance3D in [_star, _inner, _ring]:
		q.sorting_offset = 2.0
	visible = false
	set_process(false)


func _start(at: Vector3, col: Color, burst_size: float) -> void:
	active = true
	_t = 0.0
	size = burst_size
	_roll = randf() * TAU
	global_position = at
	var sm := _star.material_override as ShaderMaterial
	sm.set_shader_parameter("color", col)
	sm.set_shader_parameter("rim", col.darkened(0.7))
	Vfx.toon_reseed(_star)
	Vfx.toon_reseed(_inner)
	var rm := _ring.material_override as ShaderMaterial
	rm.set_shader_parameter("fill_color", col.lerp(Color.WHITE, 0.5))
	rm.set_shader_parameter("rim_color", col.darkened(0.7))
	rm.set_shader_parameter("seed", randf() * 100.0)
	visible = true
	set_process(true)
	_update()


func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		visible = false
		active = false
		set_process(false)
		return
	_update()


func _update() -> void:
	var k := clampf(_t / life, 0.0, 1.0)
	# Pops out big, then shrinks and snaps away (cartoon timing).
	var pop := 1.0 - pow(1.0 - clampf(k / 0.3, 0.0, 1.0), 3.0)
	var shrink := 1.0 - smoothstep(0.55, 1.0, k)
	for q: MeshInstance3D in [_star, _inner, _ring]:
		q.global_position = global_position
	Vfx.face_camera(_star, size * (0.5 + 0.7 * pop) * (0.4 + 0.6 * shrink), _roll)
	Vfx.set_alpha(_star, 1.0 if k < 0.75 else 1.0 - (k - 0.75) / 0.25)
	Vfx.face_camera(_inner, size * 0.55 * (0.5 + 0.5 * pop) * shrink, -_roll)
	Vfx.set_alpha(_inner, shrink)
	Vfx.face_camera(_ring, size * (0.4 + 1.3 * pop))
	var rm := _ring.material_override as ShaderMaterial
	rm.set_shader_parameter("progress", k)
	rm.set_shader_parameter("fade", 1.0 - smoothstep(0.5, 1.0, k))
