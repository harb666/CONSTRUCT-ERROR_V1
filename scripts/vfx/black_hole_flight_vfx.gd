class_name BlackHoleFlightVfx
extends Node3D
## Aura around a flying black hole: gravity distortion disc, event-horizon
## ring glow, counter-rotating swirl, matter spiralling in, and crackles.
## Follows its projectile's interpolated position each rendered frame.

const DISTORTION := preload("res://scripts/vfx/gravity_distortion.gdshader")

var follow: Node3D
var size := 1.0

var _ring: MeshInstance3D
var _swirls: Array[MeshInstance3D] = []
var _crackle: MeshInstance3D
var _distortion: MeshInstance3D
var _infall: CPUParticles3D
var _t := 0.0
var _crackle_t := 0.0
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
	set_size(size)


func set_size(s: float) -> void:
	size = maxf(s, 0.001)
	if _infall:
		_infall.emission_sphere_radius = size * 1.1
		_infall.scale = Vector3.ONE


func _process(delta: float) -> void:
	_t += delta
	if follow and is_instance_valid(follow):
		global_position = follow.get_global_transform_interpolated().origin
	if _distortion:
		Vfx.face_camera(_distortion, size * 2.6)
	Vfx.face_camera(_ring, size * 1.45, _t * 0.5)
	Vfx.face_camera(_swirls[0], size * 1.9, _t * 2.4)
	Vfx.face_camera(_swirls[1], size * 1.6, -_t * 1.7 + 1.0)
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


## Fade everything out over `seconds`, then free.
func fade_out(seconds: float) -> void:
	_infall.emitting = false
	var tw := create_tween()
	tw.tween_method(_set_all_alpha, 1.0, 0.0, seconds)
	tw.tween_callback(queue_free)


func _set_all_alpha(a: float) -> void:
	for q in [_ring, _crackle] + _swirls:
		Vfx.set_alpha(q, a * 0.6)
	if _distortion:
		(_distortion.material_override as ShaderMaterial).set_shader_parameter("strength", 0.55 * a)
