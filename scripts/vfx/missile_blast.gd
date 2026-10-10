class_name MissileBlast
extends Node3D
## Missile explosion (pooled, short and punchy): a white-hot impact flash,
## a bright core, puffy 3D cartoon fireballs that burn from white-hot to
## orange and roll into dark smoke clouds (ToonPuff), a mini SHOCKWAVE (a ring
## racing out along the ground plus a pressure ring facing the camera),
## sparks, flying debris, a brief strong light and a scorch
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
## Fireballs (burn into smoke) then the smoke clouds left behind.
var _fire: Array[ToonPuff] = []
var _clouds: Array[ToonPuff] = []
var _wave: MeshInstance3D
var _wave_air: MeshInstance3D
var _scorch: MeshInstance3D
var _light: OmniLight3D
var _sparks: CPUParticles3D
var _debris: CPUParticles3D


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
	for k in 5:
		var f := ToonPuff.new()
		add_child(f)
		_fire.append(f)
	for k in 3:
		var c := ToonPuff.new()
		c.set_colors(Color(0.36, 0.34, 0.33))
		add_child(c)
		_clouds.append(c)
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
	for p: CPUParticles3D in [_sparks, _debris]:
		p.scale_amount_min = fx_scale
		p.scale_amount_max = fx_scale * (1.3 if p == _debris else 1.0)
		p.restart()
		p.emitting = true
	_sparks.initial_velocity_max = 14.0 * sqrt(fx_scale)
	_light.omni_range = r * 3.5
	var base := at + Vector3.UP * 0.3 * fx_scale
	for i in _fire.size():
		var f := _fire[i]
		var off := Vector3(randf_range(-1, 1), randf_range(0.0, 0.8), randf_range(-1, 1)) * r * (0.0 if i == 0 else 0.3)
		f.size = r * (0.5 if i == 0 else randf_range(0.3, 0.42))
		f.burn_time = randf_range(0.3, 0.45)
		f.life = randf_range(1.1, 1.4)
		f.rise = r * randf_range(0.25, 0.45)
		f.drift = off * 0.6
		f.delay = 0.0 if i == 0 else randf_range(0.0, 0.07)
		f.play(base + off, true)
	for i in _clouds.size():
		var c := _clouds[i]
		var off := Vector3(randf_range(-1, 1), 0.2, randf_range(-1, 1)) * r * 0.32
		c.size = r * randf_range(0.42, 0.55)
		c.life = randf_range(1.6, 2.0)
		c.rise = r * randf_range(0.6, 0.9)
		c.drift = off
		c.delay = randf_range(0.18, 0.3)
		c.play(base + off + Vector3.UP * r * 0.2, false)
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
