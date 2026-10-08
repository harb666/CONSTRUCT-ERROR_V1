class_name LauncherBlast
extends Node3D
## The boss's missile launch, out of the launcher's nozzle (one per boss,
## restarted each launch): a bright fire burst and flame jet out of the
## mouth, sparks, thick smoke that billows out and spreads, a lingering
## smoke cloud round the launcher and a brief strong light. Placed at the
## silo mouth, +Z = out of the tube; all particles in world space, so the
## smoke stays where it was blown out while the arm moves on.

@export var duration := 0.45

var _t := 99.0
var _scale := 1.0
var _fire: Array[MeshInstance3D] = []
var _jet: Array[MeshInstance3D] = []
var _light: OmniLight3D
var _sparks: CPUParticles3D
var _smoke: CPUParticles3D
var _cloud: CPUParticles3D


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for k in 2:
		var f := Vfx.quad("fireball", Color(1.0, 0.7, 0.3) if k == 0 else Color(1.0, 0.95, 0.75), Vector2.ONE)
		add_child(f)
		_fire.append(f)
	for k in 2:
		var j := Vfx.quad("flame_a", Color(1.0, 0.6, 0.15), Vector2(0.6, 1.0))
		var x := Vector3.RIGHT if k == 0 else Vector3.UP
		j.transform = Transform3D(Basis(x, Vector3.BACK, x.cross(Vector3.BACK)), Vector3.ZERO)
		add_child(j)
		_jet.append(j)
	_sparks = Vfx.particles("glow", 0.08, 36, 0.6)
	_sparks.one_shot = true
	_sparks.explosiveness = 0.9
	_sparks.local_coords = false
	_sparks.direction = Vector3(0, 0, 1)
	_sparks.spread = 40.0
	_sparks.initial_velocity_min = 6.0
	_sparks.initial_velocity_max = 15.0
	_sparks.gravity = Vector3(0, -10, 0)
	_sparks.color_ramp = Vfx.ramp([Color(1, 0.97, 0.75, 1), Color(1, 0.55, 0.12, 1), Color(0.7, 0.15, 0.02, 0)], [0.0, 0.45, 1.0])
	_sparks.emitting = false
	add_child(_sparks)
	_smoke = _make_smoke(36, 2.2, 1.5, 0.85, Vector2(3.0, 9.0), 35.0)
	_cloud = _make_smoke(16, 4.0, 2.4, 0.95, Vector2(0.4, 1.8), 80.0)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.25)
	_light.omni_range = 9.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0, 0.6)
	add_child(_light)
	Vfx.tame_light(_light)
	visible = false
	set_process(false)


func _make_smoke(amount: int, life: float, size: float, explosive: float, vel: Vector2, spread: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	q.material = Vfx.mix_material("smoke")
	p.mesh = q
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = explosive
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.direction = Vector3(0, 0, 1)
	p.spread = spread
	p.initial_velocity_min = vel.x
	p.initial_velocity_max = vel.y
	p.gravity = Vector3(0, 0.8, 0)
	p.damping_min = 3.0
	p.damping_max = 5.0
	p.angle_max = 180.0
	p.angular_velocity_min = -30.0
	p.angular_velocity_max = 30.0
	p.scale_amount_curve = Vfx.curve([Vector2(0, 0.45), Vector2(1, 2.2)])
	p.color_ramp = Vfx.ramp([Color(1.0, 0.65, 0.35, 0.95), Color(0.36, 0.34, 0.32, 0.92), Color(0.3, 0.29, 0.28, 0.0)], [0.0, 0.12, 1.0])
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	add_child(p)
	return p


## Fire! `mouth`: the silo mouth, +Z out of the tube; `size` ~ the bore
## diameter (m).
func fire(mouth: Transform3D, size := 1.0) -> void:
	global_transform = Transform3D(mouth.basis.orthonormalized(), mouth.origin)
	_scale = size
	for p: CPUParticles3D in [_sparks, _smoke, _cloud]:
		p.scale_amount_min = size
		p.scale_amount_max = size * 1.2
		p.restart()
		p.emitting = true
	_t = 0.0
	visible = true
	set_process(true)
	_update()


func is_busy() -> bool:
	return is_processing()


func _process(delta: float) -> void:
	_t += delta
	if _t >= 4.2:
		visible = false
		set_process(false)
		return
	_update()


func _update() -> void:
	var k := clampf(_t / duration, 0.0, 1.0)
	var fade := 1.0 - k
	for i in _fire.size():
		_fire[i].visible = k < 1.0
		_fire[i].position = Vector3(0, 0, (0.4 + 0.9 * sqrt(k)) * _scale)
		Vfx.face_camera(_fire[i], _scale * (1.6 + 2.4 * sqrt(k)) * (1.0 if i == 0 else 0.6), k * 1.5 + i)
		Vfx.set_alpha(_fire[i], minf(fade * 1.5, 1.0))
	var jk := clampf(_t / 0.22, 0.0, 1.0)
	for j in _jet:
		j.visible = jk < 1.0
		j.scale = Vector3(_scale * 1.2, _scale * (2.2 + 1.5 * jk), 1.0)
		j.position = Vector3(0, 0, _scale * (1.1 + 0.75 * jk))
		Vfx.set_alpha(j, 1.0 - jk)
	_light.light_energy = 7.0 * fade * fade
	_light.visible = k < 1.0
