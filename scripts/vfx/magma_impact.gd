class_name MagmaImpact
extends Node3D
## Shotgun stream impact, Magma Cannon style (pooled): a white-hot cartoon
## star burst, a puffy fireball (ToonPuff) bursting out of the hit, a ring
## of fire tongues licking up that keep burning for a moment, and a spray
## of embers. Streams landing close together in the same instant merge into
## one bigger burst instead of piling up effects.

const POOL_SIZE := 8
const TONGUES := 4
const ORANGE := Color(1.0, 0.45, 0.06)
const WHITE_HOT := Color(1.0, 0.96, 0.78)
const RIM := Color(0.6, 0.1, 0.02)
## Merge window: same place (m) within this time (s).
const MERGE_DIST := 0.6
const MERGE_TIME := 0.08

@export var life := 0.75

static var _pool: Array[MagmaImpact] = []
static var spawned := 0

var active := false
var strength := 1.0
var _t := 99.0
var _at := Vector3.ZERO
var _normal := Vector3.UP
var _star: MeshInstance3D
var _puff: ToonPuff
var _tongues: Array[MeshInstance3D] = []
var _tongue_off: Array[Vector3] = []
var _embers: CPUParticles3D


## A burst at `at`; `normal` points out of the surface it hit.
static func spawn(tree: SceneTree, at: Vector3, normal: Vector3, power := 1.0) -> MagmaImpact:
	_pool = _pool.filter(func(m: MagmaImpact) -> bool: return is_instance_valid(m) and m.is_inside_tree())
	for m in _pool:
		if m.active and m._t < MERGE_TIME and m._at.distance_to(at) < MERGE_DIST:
			m.strength = minf(m.strength + 0.15 * power, 1.5)
			return m
	var b: MagmaImpact = null
	for m in _pool:
		if not m.active:
			b = m
			break
	if b == null:
		if _pool.size() < POOL_SIZE:
			b = MagmaImpact.new()
			var host: Node = tree.current_scene if tree.current_scene else tree.root
			host.add_child(b)
			_pool.append(b)
		else:
			b = _pool[0]
			for m in _pool:
				if m._t > b._t:
					b = m
	b._start(at, normal, power)
	spawned += 1
	return b


static func busy_count() -> int:
	var n := 0
	for m in _pool:
		if is_instance_valid(m) and m.active:
			n += 1
	return n


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_star = Vfx.toon_flash(0, ORANGE, WHITE_HOT, RIM, Vector2.ONE, 10.0)
	_star.top_level = true
	add_child(_star)
	_puff = ToonPuff.new()
	add_child(_puff)
	for i in TONGUES:
		var t := Vfx.toon_flash(1, ORANGE, WHITE_HOT, RIM, Vector2.ONE)
		t.top_level = true
		add_child(t)
		_tongues.append(t)
		_tongue_off.append(Vector3.ZERO)
	_embers = Vfx.particles("glow", 0.07, 18, 0.55)
	_embers.one_shot = true
	_embers.explosiveness = 0.95
	_embers.local_coords = false
	_embers.spread = 70.0
	_embers.initial_velocity_min = 3.0
	_embers.initial_velocity_max = 8.0
	_embers.gravity = Vector3(0, -9, 0)
	_embers.damping_min = 1.0
	_embers.damping_max = 3.0
	_embers.color_ramp = Vfx.ramp([Color(1, 0.95, 0.7, 1), Color(1, 0.5, 0.08, 1), Color(0.7, 0.12, 0.0, 0)], [0.0, 0.45, 1.0])
	_embers.emitting = false
	add_child(_embers)
	visible = false
	set_process(false)


func _start(at: Vector3, normal: Vector3, power: float) -> void:
	active = true
	_t = 0.0
	_at = at
	_normal = normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	strength = power
	global_position = at
	Vfx.toon_reseed(_star)
	_puff.size = 0.28
	_puff.burn_time = 0.3
	_puff.life = 0.42
	_puff.rise = 0.3
	_puff.drift = _normal * 0.35
	_puff.delay = 0.0
	_puff.play(at + _normal * 0.12, true)
	var a0 := randf() * TAU
	for i in _tongues.size():
		var a := a0 + TAU * i / _tongues.size()
		_tongue_off[i] = Vector3(cos(a), 0.0, sin(a)) * randf_range(0.08, 0.2)
		Vfx.toon_reseed(_tongues[i])
	_embers.global_position = at + _normal * 0.05
	_embers.direction = _normal
	_embers.restart()
	_embers.emitting = true
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
	var s := strength
	# Star burst: the first instant.
	var sk := clampf(_t / 0.13, 0.0, 1.0)
	_star.visible = sk < 1.0
	if _star.visible:
		_star.global_position = _at + _normal * 0.1
		Vfx.face_camera(_star, s * (0.7 + 0.6 * sk), _t * 8.0)
		Vfx.set_alpha(_star, 1.0 - sk * sk)
	_puff.size = 0.28 * s
	# Fire tongues: lick up fast, flicker, then shrink away.
	var cam := get_viewport().get_camera_3d()
	var k := _t / life
	var grow := 1.0 - pow(1.0 - clampf(_t / 0.12, 0.0, 1.0), 3.0)
	for i in _tongues.size():
		var t := _tongues[i]
		var l := 1.05 * s * grow * (1.0 - k * k) * randf_range(0.8, 1.15) * (1.0 if i % 2 == 0 else 0.7)
		t.visible = l > 0.02
		if not t.visible:
			continue
		var base := _at + _tongue_off[i] * s
		var y := Vector3.UP
		var mid := base + y * l * 0.45
		var view := cam.global_position - mid if cam else Vector3.BACK
		view.y = 0.0
		var x := y.cross(view.normalized() if view.length_squared() > 1e-4 else Vector3.BACK).normalized()
		t.global_transform = Transform3D(Basis(x * l * 0.5, y * l, x.cross(y)), mid)
		Vfx.set_alpha(t, 1.0 - smoothstep(0.6, 1.0, k))
