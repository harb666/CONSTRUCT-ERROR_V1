class_name ImpactBurst
extends Node3D
## Black-hole impact: bright flash, scorch star, expanding shock ring, sparks
## thrown out, and a short light pop. Frees itself.

@export var duration := 0.45

var _t := 0.0
var _flash: MeshInstance3D
var _scorch: MeshInstance3D
var _ring: MeshInstance3D
var _light: OmniLight3D
var _roll := 0.0


static func spawn(parent: Node, at: Vector3, scale_m := 1.0) -> ImpactBurst:
	var b := ImpactBurst.new()
	parent.add_child(b)
	b.global_position = at
	b.scale = Vector3.ONE * scale_m
	return b


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_roll = randf() * TAU
	_flash = Vfx.quad("star", Vfx.HOT, Vector2.ONE)
	_scorch = Vfx.quad("scorch", Vfx.PINK, Vector2.ONE)
	_ring = Vfx.quad("ring", Vfx.PURPLE, Vector2.ONE)
	for q in [_ring, _scorch, _flash]:
		add_child(q)
	var sparks := Vfx.particles("glow", 0.08, 22, 0.5)
	sparks.one_shot = true
	sparks.explosiveness = 0.95
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.2
	sparks.direction = Vector3.UP
	sparks.spread = 180.0
	sparks.initial_velocity_min = 3.0
	sparks.initial_velocity_max = 7.0
	sparks.damping_min = 4.0
	sparks.damping_max = 6.0
	sparks.gravity = Vector3(0, -6, 0)
	sparks.color_ramp = Vfx.ramp([Color(1, 0.9, 1, 1), Color(0.75, 0.3, 1, 1), Color(0.5, 0.1, 0.9, 0)], [0.0, 0.4, 1.0])
	sparks.scale_amount_curve = Vfx.curve([Vector2(0, 1), Vector2(1, 0.3)])
	add_child(sparks)
	sparks.emitting = true
	_light = OmniLight3D.new()
	_light.light_color = Vfx.PURPLE
	_light.omni_range = 5.0
	_light.shadow_enabled = false
	add_child(_light)
	_update()


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration + 0.3:  # let the sparks finish
		queue_free()
		return
	_update()


func _update() -> void:
	var k := clampf(_t / duration, 0.0, 1.0)
	var fade := 1.0 - k
	var s := scale.x
	Vfx.face_camera(_flash, s * (1.6 * (1.0 - k * 0.6)), _roll)
	Vfx.set_alpha(_flash, fade * fade)
	Vfx.face_camera(_scorch, s * (1.0 + k * 1.2), _roll + k)
	Vfx.set_alpha(_scorch, fade * 0.8)
	Vfx.face_camera(_ring, s * (0.4 + k * 3.2), 0.0)
	Vfx.set_alpha(_ring, fade)
	_light.light_energy = 4.0 * fade
