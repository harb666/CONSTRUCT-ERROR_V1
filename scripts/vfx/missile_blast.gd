class_name MissileBlast
extends Node3D
## Missile explosion (pooled, short and punchy): a white-hot impact flash,
## a bright core, expanding orange/red fireballs, a mini SHOCKWAVE (a ring
## racing out along the ground plus a pressure ring facing the camera),
## sparks, flying debris, thick smoke, a brief strong light and a scorch
## mark that fades away. `spawn()` takes a pooled one (restarts it).
## Also used, smaller (`fx_scale`), for the boss core's internal explosion.

const POOL_SIZE := 3
const SCORCH_SHADER := preload("res://scripts/vfx/scorch_mul.gdshader")

@export var duration := 0.7
@export var shockwave_time := 0.32

static var _pool: Array[MissileBlast] = []

var radius := 2.6
var fx_scale := 1.0
## Ground shockwave ring and scorch (off for blasts in mid-air).
var ground := true
var active := false
var _t := 99.0
var _roll := 0.0
var _flash: MeshInstance3D
var _core: MeshInstance3D
var _fire: Array[MeshInstance3D] = []
var _wave: MeshInstance3D
var _wave_air: MeshInstance3D
var _scorch: MeshInstance3D
var _light: OmniLight3D
var _sparks: CPUParticles3D
var _debris: CPUParticles3D
var _smoke: CPUParticles3D


static func spawn(parent: Node, at: Vector3, blast_radius: float, scale_fx := 1.0, on_ground := true) -> MissileBlast:
	_pool = _pool.filter(func(b: MissileBlast) -> bool: return is_instance_valid(b) and b.is_inside_tree())
	var b: MissileBlast = null
	for p in _pool:
		if not p.active:
			b = p
			break
	if b == null:
		if _pool.size() < POOL_SIZE:
			b = MissileBlast.new()
			parent.add_child(b)
			_pool.append(b)
		else:
			b = _pool[0]
			for p in _pool:
				if p._t > b._t:
					b = p
	b.radius = blast_radius
	b.fx_scale = scale_fx
	b.ground = on_ground
	b._start(at)
	return b


static func busy_count() -> int:
	var n := 0
	for b in _pool:
		if is_instance_valid(b) and b.active:
			n += 1
	return n


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Scorch: multiplies the floor darker where the (greyscale) mark is.
	_scorch = MeshInstance3D.new()
	var sq0 := QuadMesh.new()
	_scorch.mesh = sq0
	_scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := ShaderMaterial.new()
	sm.shader = SCORCH_SHADER
	sm.set_shader_parameter("tex", Vfx.TEX.scorch)
	_scorch.material_override = sm
	add_child(_scorch)
	for k in 2:
		var f := Vfx.quad("fireball", Color(1.0, 0.62, 0.22) if k == 0 else Color(1.0, 0.3, 0.06), Vector2.ONE)
		add_child(f)
		_fire.append(f)
	_core = Vfx.quad("glow", Color(1.0, 0.92, 0.7), Vector2.ONE)
	add_child(_core)
	_flash = Vfx.quad("flare", Color(1.0, 0.97, 0.85), Vector2.ONE)
	add_child(_flash)
	_wave = Vfx.quad("ring", Color(1.0, 0.75, 0.45), Vector2.ONE)
	add_child(_wave)
	_wave_air = Vfx.quad("ring", Color(1.0, 0.85, 0.7), Vector2.ONE)
	add_child(_wave_air)
	_sparks = Vfx.particles("glow", 0.1, 40, 0.75)
	_sparks.one_shot = true
	_sparks.explosiveness = 0.95
	_sparks.local_coords = false
	_sparks.direction = Vector3.UP
	_sparks.spread = 85.0
	_sparks.initial_velocity_min = 5.0
	_sparks.initial_velocity_max = 14.0
	_sparks.gravity = Vector3(0, -14, 0)
	_sparks.damping_min = 0.5
	_sparks.damping_max = 1.5
	_sparks.color_ramp = Vfx.ramp([Color(1, 0.97, 0.75, 1), Color(1, 0.55, 0.12, 1), Color(0.7, 0.15, 0.02, 0)], [0.0, 0.45, 1.0])
	_sparks.emitting = false
	add_child(_sparks)
	_debris = CPUParticles3D.new()
	var dq := QuadMesh.new()
	dq.size = Vector2.ONE * 0.16
	dq.material = Vfx.mix_material("dot")
	_debris.mesh = dq
	_debris.amount = 14
	_debris.lifetime = 1.0
	_debris.one_shot = true
	_debris.explosiveness = 1.0
	_debris.local_coords = false
	_debris.direction = Vector3.UP
	_debris.spread = 70.0
	_debris.initial_velocity_min = 4.0
	_debris.initial_velocity_max = 9.0
	_debris.gravity = Vector3(0, -16, 0)
	_debris.scale_amount_min = 0.5
	_debris.scale_amount_max = 1.3
	_debris.color = Color(0.12, 0.1, 0.09)
	_debris.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_debris.emitting = false
	add_child(_debris)
	_smoke = CPUParticles3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2.ONE * 1.6
	sq.material = Vfx.mix_material("smoke")
	_smoke.mesh = sq
	_smoke.amount = 16
	_smoke.lifetime = 2.0
	_smoke.one_shot = true
	_smoke.explosiveness = 0.8
	_smoke.local_coords = false
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_smoke.emission_sphere_radius = 0.6
	_smoke.direction = Vector3.UP
	_smoke.spread = 60.0
	_smoke.initial_velocity_min = 1.0
	_smoke.initial_velocity_max = 3.0
	_smoke.gravity = Vector3(0, 0.9, 0)
	_smoke.damping_min = 1.2
	_smoke.damping_max = 2.0
	_smoke.angle_max = 180.0
	_smoke.scale_amount_curve = Vfx.curve([Vector2(0, 0.5), Vector2(1, 1.8)])
	_smoke.color_ramp = Vfx.ramp([Color(0.35, 0.3, 0.26, 0.0), Color(0.25, 0.22, 0.2, 0.75), Color(0.2, 0.2, 0.2, 0.0)], [0.0, 0.12, 1.0])
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke.emitting = false
	add_child(_smoke)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.shadow_enabled = false
	add_child(_light)
	Vfx.tame_light(_light)
	visible = false
	set_process(false)


func _start(at: Vector3) -> void:
	active = true
	_t = 0.0
	_roll = randf() * TAU
	global_transform = Transform3D(Basis(), at + Vector3.UP * 0.3 * fx_scale)
	var r := radius * fx_scale
	# Ground ring and scorch lie flat (just above the ground point).
	_wave.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), at + Vector3.UP * 0.08)
	_scorch.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0).rotated(Vector3.UP, _roll).scaled(Vector3.ONE * r * 1.4), at + Vector3.UP * 0.04)
	for p: CPUParticles3D in [_sparks, _debris, _smoke]:
		p.scale_amount_min = fx_scale
		p.scale_amount_max = fx_scale * (1.3 if p == _debris else 1.0)
		p.restart()
		p.emitting = true
	_sparks.initial_velocity_max = 14.0 * sqrt(fx_scale)
	_light.omni_range = r * 3.5
	visible = true
	set_process(true)
	_update()


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration + 2.2:  # smoke and scorch have faded
		visible = false
		active = false
		set_process(false)
		return
	_update()


func _update() -> void:
	var r := radius * fx_scale
	var k := clampf(_t / duration, 0.0, 1.0)
	var fade := 1.0 - k
	# Impact flash: the first instant, very bright.
	var fk := clampf(_t / 0.1, 0.0, 1.0)
	_flash.visible = fk < 1.0
	if _flash.visible:
		Vfx.face_camera(_flash, r * (1.4 + 1.6 * fk), _roll)
		Vfx.set_alpha(_flash, 1.0 - fk)
	# Bright core, then the fireballs swell and burn out orange -> red.
	var ck := clampf(_t / 0.22, 0.0, 1.0)
	_core.visible = ck < 1.0
	if _core.visible:
		Vfx.face_camera(_core, r * (0.9 + 0.6 * ck))
		Vfx.set_alpha(_core, 1.0 - ck)
	for i in _fire.size():
		var fs := r * (0.8 + 1.4 * sqrt(k)) * (1.0 if i == 0 else 1.25)
		_fire[i].visible = k < 1.0
		Vfx.face_camera(_fire[i], fs, _roll + i * 1.7 + k * (0.6 if i == 0 else -0.4))
		Vfx.set_alpha(_fire[i], minf(fade * (1.6 if i == 0 else 1.1), 1.0))
	# Shockwave: races out and thins.
	var wk := clampf(_t / shockwave_time, 0.0, 1.0)
	var we := 1.0 - pow(1.0 - wk, 3.0)
	_wave.visible = wk < 1.0 and ground
	_scorch.visible = ground
	_wave_air.visible = wk < 1.0
	if wk < 1.0:
		_wave.scale = Vector3.ONE * r * (0.4 + 3.4 * we)
		Vfx.set_alpha(_wave, (1.0 - wk) * 0.95)
		Vfx.face_camera(_wave_air, r * (0.3 + 2.6 * we))
		Vfx.set_alpha(_wave_air, (1.0 - wk) * 0.6)
	# Scorch fades away (not permanent).
	var sk := clampf((_t - 0.1) / (duration + 2.0), 0.0, 1.0)
	(_scorch.material_override as ShaderMaterial).set_shader_parameter("strength", 0.85 * (1.0 - sk))
	_light.light_energy = 9.0 * fx_scale * fade * fade
	_light.visible = k < 1.0
