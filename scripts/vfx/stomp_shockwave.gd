class_name StompShockwave
extends Node3D
## The robot boss's foot stomp (pooled): a cartoon mini SHOCKWAVE racing out
## along the floor in the same style as the missile blast's (toon_ring:
## cream band with an ink rim), a thinner second ring close behind, a burst
## of dust clouds rolling out in a ring, chunks of floor kicked up and a
## white impact flash at the foot. `radius` = how far the wave reaches;
## `wave_time` = how long it takes to get there (the boss's knock-back
## travels with it).

const POOL_SIZE := 2
const RING_SHADER := preload("res://scripts/vfx/toon_ring.gdshader")
const DUST_PUFFS := 12

@export var wave_time := 0.32
@export var duration := 1.3

static var _pool: Array[StompShockwave] = []
static var spawned := 0

var radius := 7.0
var active := false
var _t := 99.0
var _at := Vector3.ZERO
var _wave: MeshInstance3D
var _wave2: MeshInstance3D
var _flash: MeshInstance3D
var _dust: Array[ToonPuff] = []
var _chunks: CPUParticles3D


static func spawn(tree: SceneTree, at: Vector3, wave_radius: float) -> StompShockwave:
	_pool = _pool.filter(func(s: StompShockwave) -> bool: return is_instance_valid(s) and s.is_inside_tree())
	var w: StompShockwave = null
	for s in _pool:
		if not s.active:
			w = s
			break
	if w == null:
		if _pool.size() < POOL_SIZE:
			w = StompShockwave.new()
			var host: Node = tree.current_scene if tree.current_scene else tree.root
			host.add_child(w)
			_pool.append(w)
		else:
			w = _pool[0]
	w.radius = wave_radius
	w._start(at)
	spawned += 1
	return w


## How far the wave has got (m), for the knock-back.
func wave_radius() -> float:
	return radius * _wave_k(_t)


func _wave_k(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t / wave_time, 0.0, 1.0), 2.0)


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_wave = _ring(0.3, Color(1.0, 0.93, 0.74))
	_wave2 = _ring(0.12, Color(1.0, 0.97, 0.88))
	_flash = Vfx.quad("flare", Color(1.0, 0.97, 0.85), Vector2.ONE)
	add_child(_flash)
	for k in DUST_PUFFS:
		var d := ToonPuff.new()
		d.set_colors(Color(0.5, 0.45, 0.4))
		add_child(d)
		_dust.append(d)
	_chunks = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.2
	q.material = Vfx.mix_material("dot")
	_chunks.mesh = q
	_chunks.amount = 22
	_chunks.lifetime = 0.9
	_chunks.one_shot = true
	_chunks.explosiveness = 1.0
	_chunks.local_coords = false
	_chunks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_chunks.emission_sphere_radius = 0.8
	_chunks.direction = Vector3.UP
	_chunks.spread = 55.0
	_chunks.initial_velocity_min = 4.0
	_chunks.initial_velocity_max = 9.0
	_chunks.gravity = Vector3(0, -18, 0)
	_chunks.scale_amount_min = 0.6
	_chunks.scale_amount_max = 1.5
	_chunks.color = Color(0.22, 0.2, 0.19)
	_chunks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_chunks.emitting = false
	add_child(_chunks)
	visible = false
	set_process(false)


func _ring(width: float, fill: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = QuadMesh.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = RING_SHADER
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("fill_color", fill)
	mi.material_override = m
	mi.top_level = true
	add_child(mi)
	return mi


func _start(at: Vector3) -> void:
	_at = at
	_t = 0.0
	active = true
	global_position = at
	for w in [_wave, _wave2]:
		(w.material_override as ShaderMaterial).set_shader_parameter("seed", randf() * 100.0)
	var roll := randf() * TAU
	for i in _dust.size():
		var d := _dust[i]
		var a := roll + TAU * (i + randf_range(-0.3, 0.3)) / _dust.size()
		var out := Vector3(cos(a), 0.0, sin(a))
		d.size = randf_range(0.38, 0.58)
		d.life = randf_range(0.6, 0.85)
		d.rise = randf_range(0.2, 0.45)
		d.drift = out * radius * randf_range(0.45, 0.65)
		d.delay = randf_range(0.0, 0.05)
		d.play(at + out * 0.9 + Vector3.UP * 0.35, false)
	_chunks.global_position = at + Vector3.UP * 0.1
	_chunks.restart()
	_chunks.emitting = true
	visible = true
	set_process(true)
	_update()


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		visible = false
		active = false
		set_process(false)
		return
	_update()


func _update() -> void:
	var flat := Basis(Vector3.RIGHT, -PI / 2.0)
	for i in 2:
		var w: MeshInstance3D = [_wave, _wave2][i]
		var lag := 0.06 * i
		var k := _wave_k(_t - lag)
		w.visible = _t >= lag and (_t - lag) < wave_time + 0.15
		var r := radius * (0.1 + 0.9 * k) * (1.0 if i == 0 else 0.85)
		w.global_transform = Transform3D(flat.scaled(Vector3.ONE * r * 2.0), _at + Vector3.UP * (0.06 + 0.02 * i))
		var m := w.material_override as ShaderMaterial
		m.set_shader_parameter("progress", k)
		m.set_shader_parameter("fade", 1.0 - smoothstep(0.55, 1.0, clampf((_t - lag) / (wave_time + 0.15), 0.0, 1.0)))
	var fk := clampf(_t / 0.12, 0.0, 1.0)
	_flash.visible = fk < 1.0
	if _flash.visible:
		_flash.global_position = _at + Vector3.UP * 0.5
		Vfx.face_camera(_flash, 2.2 + 2.5 * fk)
		Vfx.set_alpha(_flash, 1.0 - fk)
