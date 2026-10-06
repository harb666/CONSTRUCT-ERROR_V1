class_name MissileBlast
extends Node3D
## Boss missile explosion: an orange fireball flash, a burst of sparks, a
## dark smoke puff and a brief light. Frees itself.

@export var duration := 0.5

var radius := 2.5
var _t := 0.0
var _fire: MeshInstance3D
var _ring: MeshInstance3D
var _light: OmniLight3D
var _roll := 0.0


static func spawn(parent: Node, at: Vector3, blast_radius: float) -> MissileBlast:
	var b := MissileBlast.new()
	b.radius = blast_radius
	parent.add_child(b)
	b.global_position = at + Vector3.UP * 0.3
	return b


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_roll = randf() * TAU
	_fire = Vfx.quad("fireball", Color(1.0, 0.75, 0.35), Vector2.ONE)
	add_child(_fire)
	_ring = Vfx.quad("ring", Color(1.0, 0.4, 0.1), Vector2.ONE)
	_ring.rotation.x = -PI / 2.0
	_ring.position.y = -0.25
	add_child(_ring)
	var sparks := Vfx.particles("glow", 0.12, 26, 0.6)
	sparks.one_shot = true
	sparks.explosiveness = 0.95
	sparks.direction = Vector3.UP
	sparks.spread = 80.0
	sparks.initial_velocity_min = 4.0
	sparks.initial_velocity_max = 9.0
	sparks.gravity = Vector3(0, -12, 0)
	sparks.damping_min = 1.0
	sparks.damping_max = 2.0
	sparks.color_ramp = Vfx.ramp([Color(1, 0.95, 0.6, 1), Color(1, 0.5, 0.1, 1), Color(0.6, 0.1, 0.0, 0)], [0.0, 0.4, 1.0])
	add_child(sparks)
	sparks.emitting = true
	var smoke := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * radius * 0.7
	q.material = Vfx.mix_material("smoke")
	smoke.mesh = q
	smoke.amount = 10
	smoke.lifetime = 1.1
	smoke.one_shot = true
	smoke.explosiveness = 0.85
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = radius * 0.3
	smoke.direction = Vector3.UP
	smoke.spread = 60.0
	smoke.initial_velocity_min = 0.6
	smoke.initial_velocity_max = 1.6
	smoke.gravity = Vector3(0, 0.6, 0)
	smoke.damping_min = 1.0
	smoke.damping_max = 1.5
	smoke.scale_amount_curve = Vfx.curve([Vector2(0, 0.5), Vector2(1, 1.3)])
	smoke.color_ramp = Vfx.ramp([Color(0.3, 0.27, 0.25, 0.0), Color(0.25, 0.23, 0.22, 0.6), Color(0.2, 0.2, 0.2, 0.0)], [0.0, 0.2, 1.0])
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smoke)
	smoke.emitting = true
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.omni_range = radius * 2.5
	_light.shadow_enabled = false
	add_child(_light)
	_update()


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration + 1.2:  # let the smoke finish
		queue_free()
		return
	_update()


func _update() -> void:
	var k := clampf(_t / duration, 0.0, 1.0)
	var fade := 1.0 - k
	Vfx.face_camera(_fire, radius * (0.8 + 1.0 * sqrt(k)), _roll)
	Vfx.set_alpha(_fire, minf(fade * 1.4, 1.0))
	_ring.scale = Vector3.ONE * radius * (0.6 + 1.6 * k)
	Vfx.set_alpha(_ring, fade * 0.8)
	_light.light_energy = 5.0 * fade * fade
	_light.visible = k < 1.0
