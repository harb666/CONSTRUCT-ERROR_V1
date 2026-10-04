class_name BlackHoleFlightVfx
extends Node3D
## Aura around a flying black hole: gravity distortion disc, event-horizon
## ring glow, counter-rotating swirl, matter spiralling in, and crackles.
## Follows its projectile's interpolated position each rendered frame.

const DISTORTION := preload("res://scripts/vfx/gravity_distortion.gdshader")

var follow: Node3D
var projectile: Node3D
var size := 1.0
## Bodies the electricity rays ignore (the shooter).
var exclude: Array[RID] = []

var _ring: MeshInstance3D
var _swirls: Array[MeshInstance3D] = []
var _crackle: MeshInstance3D
var _distortion: MeshInstance3D
var _infall: CPUParticles3D
## Purple motes and black dust tumbling around it, and a dark purple mist
## it sheds as it travels (left behind in the world, tumbling as it fades).
var _motes: CPUParticles3D
var _dust: CPUParticles3D
var _mist: CPUParticles3D
var _lightning: BlackHoleLightning
var _t := 0.0
var _crackle_t := 0.0
var _swirl_a := 0.0
var _swirl_b := 0.0
var _crackle_size := 1.0
var _crackle_roll := 0.0


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if Vfx.distortion_enabled:
		_distortion = MeshInstance3D.new()
		var q := QuadMesh.new()
		_distortion.mesh = q
		var m := ShaderMaterial.new()
		m.shader = DISTORTION
		m.render_priority = -1
		_distortion.material_override = m
		_distortion.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_distortion)
	_ring = Vfx.quad("ring", Vfx.PURPLE, Vector2.ONE)
	add_child(_ring)
	for k in 2:
		var s := Vfx.quad("twirl", Vfx.PINK if k == 0 else Vfx.PURPLE, Vector2.ONE)
		add_child(s)
		_swirls.append(s)
	_crackle = Vfx.quad("crackle", Vfx.HOT, Vector2.ONE)
	add_child(_crackle)

	_infall = Vfx.particles("glow", 0.09, 28, 0.6)
	_infall.local_coords = true
	_infall.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	_infall.radial_accel_min = -14.0
	_infall.radial_accel_max = -10.0
	_infall.tangential_accel_min = 8.0
	_infall.tangential_accel_max = 12.0
	_infall.color_ramp = Vfx.ramp([Color(0.6, 0.2, 1.0, 0.0), Color(0.8, 0.35, 1.0, 1.0), Color(1.0, 0.85, 1.0, 0.0)], [0.0, 0.35, 1.0])
	_infall.scale_amount_curve = Vfx.curve([Vector2(0, 1.0), Vector2(1, 0.25)])
	add_child(_infall)

	_motes = Vfx.particles("glow", 0.12, 26, 0.9)
	_motes.local_coords = true
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	_motes.direction = Vector3.UP
	_motes.spread = 180.0
	_motes.initial_velocity_min = 0.2
	_motes.initial_velocity_max = 0.8
	_motes.color_ramp = Vfx.ramp([Color(0.55, 0.15, 1.0, 0.0), Color(0.75, 0.3, 1.0, 0.9), Color(0.4, 0.1, 0.8, 0.0)], [0.0, 0.3, 1.0])
	_motes.scale_amount_min = 0.5
	_motes.scale_amount_max = 1.4
	# Tangential accel orbits around the gravity direction; keep it tiny.
	_motes.gravity = Vector3(0, 0.001, 0)
	add_child(_motes)

	_dust = CPUParticles3D.new()
	var dq := QuadMesh.new()
	dq.material = Vfx.mix_material("dot")
	_dust.mesh = dq
	_dust.amount = 22
	_dust.lifetime = 1.0
	_dust.local_coords = true
	_dust.gravity = Vector3(0.3, 0.001, 0.2).normalized() * 0.001  # tilted orbit axis
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	_dust.direction = Vector3.UP
	_dust.spread = 180.0
	_dust.initial_velocity_min = 0.1
	_dust.initial_velocity_max = 0.5
	_dust.scale_amount_min = 0.4
	_dust.scale_amount_max = 1.2
	_dust.color_ramp = Vfx.ramp([Color(0.05, 0.0, 0.08, 0.0), Color(0.04, 0.0, 0.07, 0.9), Color(0.12, 0.02, 0.2, 0.0)], [0.0, 0.3, 1.0])
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dust)

	_mist = CPUParticles3D.new()
	var mq := QuadMesh.new()
	mq.material = Vfx.mix_material("smoke")
	_mist.mesh = mq
	_mist.amount = 20
	_mist.lifetime = 1.3
	_mist.local_coords = false  # left behind as it travels
	_mist.gravity = Vector3.ZERO
	_mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_mist.direction = Vector3.UP
	_mist.spread = 180.0
	_mist.initial_velocity_min = 0.2
	_mist.initial_velocity_max = 0.9
	_mist.damping_min = 0.5
	_mist.damping_max = 1.0
	_mist.angle_min = 0.0
	_mist.angle_max = 360.0
	_mist.angular_velocity_min = -120.0
	_mist.angular_velocity_max = 120.0
	_mist.scale_amount_min = 0.7
	_mist.scale_amount_max = 1.2
	_mist.scale_amount_curve = Vfx.curve([Vector2(0, 0.5), Vector2(1, 1.6)])
	_mist.color_ramp = Vfx.ramp([Color(0.3, 0.08, 0.5, 0.0), Color(0.28, 0.06, 0.48, 0.45), Color(0.06, 0.0, 0.1, 0.35), Color(0.0, 0.0, 0.0, 0.0)], [0.0, 0.2, 0.6, 1.0])
	_mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mist)
	_lightning = BlackHoleLightning.new()
	_lightning.exclude = exclude
	add_child(_lightning)
	set_size(size)


func set_size(s: float) -> void:
	size = maxf(s, 0.001)
	if _infall:
		_infall.emission_sphere_radius = size * 0.75
		(_infall.mesh as QuadMesh).size = Vector2.ONE * clampf(size * 0.05, 0.06, 0.2)
		_infall.radial_accel_min = -14.0 * maxf(size, 1.0)
		_infall.radial_accel_max = -10.0 * maxf(size, 1.0)
		_infall.amount = 28 if size < 2.0 else 44
	if _motes:
		# Tumbling around just outside the disc.
		_motes.emission_sphere_radius = size * 0.6
		(_motes.mesh as QuadMesh).size = Vector2.ONE * clampf(size * 0.06, 0.04, 0.2)
		_motes.tangential_accel_min = 3.0 * maxf(size, 0.5)
		_motes.tangential_accel_max = 6.0 * maxf(size, 0.5)
		_motes.radial_accel_min = -2.0 * maxf(size, 0.5)
		_motes.radial_accel_max = -0.5 * maxf(size, 0.5)
		_dust.emission_sphere_radius = size * 0.55
		(_dust.mesh as QuadMesh).size = Vector2.ONE * clampf(size * 0.045, 0.03, 0.15)
		_dust.tangential_accel_min = -6.0 * maxf(size, 0.5)
		_dust.tangential_accel_max = -3.0 * maxf(size, 0.5)
		_dust.radial_accel_min = -1.5 * maxf(size, 0.5)
		_dust.radial_accel_max = 0.5 * maxf(size, 0.5)
		_mist.emission_sphere_radius = size * 0.45
		(_mist.mesh as QuadMesh).size = Vector2.ONE * clampf(size * 0.7, 0.2, 2.4)
	if _lightning:
		_lightning.radius = size


func _process(delta: float) -> void:
	_t += delta
	if follow and is_instance_valid(follow):
		global_position = follow.get_global_transform_interpolated().origin
	if _distortion:
		Vfx.face_camera(_distortion, size * 2.0)
	Vfx.face_camera(_ring, size * 1.45, _t * 0.5)
	_swirl_a += delta * 2.4 * (1.0 + instability * 2.5)
	_swirl_b -= delta * 1.7 * (1.0 + instability * 2.5)
	Vfx.face_camera(_swirls[0], size * 1.9, _swirl_a)
	Vfx.face_camera(_swirls[1], size * 1.6, _swirl_b + 1.0)
	Vfx.set_alpha(_swirls[0], 0.55)
	Vfx.set_alpha(_swirls[1], 0.45)
	_crackle_t -= delta
	if _crackle_t <= 0.0:
		_crackle_t = randf_range(0.05, 0.12)
		_crackle.visible = randf() < 0.55
		_crackle_size = randf_range(1.1, 1.6)
		_crackle_roll = randf() * TAU
		Vfx.set_alpha(_crackle, randf_range(0.4, 0.9))
	Vfx.face_camera(_crackle, size * _crackle_size, _crackle_roll)


## 0..1 gravity-well instability: stronger distortion, faster swirls,
## more energetic particles and more violent lightning.
var instability := 0.0


func set_instability(k: float) -> void:
	instability = k
	if _distortion:
		(_distortion.material_override as ShaderMaterial).set_shader_parameter("strength", 0.55 * (1.0 + k * 1.2))
		(_distortion.material_override as ShaderMaterial).set_shader_parameter("spin_speed", 1.3 * (1.0 + k * 2.0))
	if _infall:
		_infall.speed_scale = 1.0 + k * 2.0
	if _motes:
		_motes.speed_scale = 1.0 + k * 1.5
		_dust.speed_scale = 1.0 + k * 1.5
	if _lightning:
		_lightning.violence = k


## Blue-violet lightning erupts violently out of it.
func erupt() -> void:
	if _lightning:
		_lightning.erupt()


## Fade everything out over `seconds`, then free.
func fade_out(seconds: float) -> void:
	_infall.emitting = false
	_motes.emitting = false
	_dust.emitting = false
	_mist.emitting = false
	if _lightning:
		_lightning.stop()
	var tw := create_tween()
	tw.tween_method(_set_all_alpha, 1.0, 0.0, seconds)
	tw.tween_callback(queue_free)


func _set_all_alpha(a: float) -> void:
	for q in [_ring, _crackle] + _swirls:
		Vfx.set_alpha(q, a * 0.6)
	if _distortion:
		(_distortion.material_override as ShaderMaterial).set_shader_parameter("strength", 0.55 * a)
