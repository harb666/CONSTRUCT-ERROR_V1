class_name SupernovaBlast
extends Node3D
## Supernova: blinding flash, two expanding shockwave rings (one facing the
## camera, one along the surface), a screen-distortion shock bubble, a big
## spark burst and a bright light pop. Frees itself.

const DISTORTION := preload("res://scripts/vfx/gravity_distortion.gdshader")

@export var duration := 0.6

var radius := 11.0
var normal := Vector3.UP
var _t := 0.0
var _flash: MeshInstance3D
var _ring: MeshInstance3D
var _ground_ring: MeshInstance3D
var _bubble: MeshInstance3D
var _light: OmniLight3D


static func spawn(parent: Node, at: Vector3, r: float, surface_normal: Vector3) -> SupernovaBlast:
	var b := SupernovaBlast.new()
	b.radius = r
	b.normal = surface_normal
	parent.add_child(b)
	b.global_position = at
	return b


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if Vfx.distortion_enabled:
		_bubble = MeshInstance3D.new()
		_bubble.mesh = QuadMesh.new()
		var m := ShaderMaterial.new()
		m.shader = DISTORTION
		m.render_priority = -1
		m.set_shader_parameter("swirl", 0.0)
		m.set_shader_parameter("spin_speed", 0.0)
		m.set_shader_parameter("strength", -0.5)
		m.set_shader_parameter("tint_amount", 0.0)
		_bubble.material_override = m
		_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_bubble)
	_ring = Vfx.quad("ring", Vfx.PURPLE, Vector2.ONE)
	_ground_ring = Vfx.quad("ring", Vfx.PINK, Vector2.ONE)
	_flash = Vfx.quad("star", Vfx.HOT, Vector2.ONE)
	for q in [_ring, _ground_ring, _flash]:
		add_child(q)
	# Ground ring lies in the surface plane.
	var n := normal.normalized()
	var x := n.cross(Vector3.FORWARD if absf(n.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(n)
	_ground_ring.basis = Basis(x, z, n)  # quad +Z along the normal

	var sparks := Vfx.particles("glow", 0.16, 70, 0.9)
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.direction = n
	sparks.spread = 100.0
	sparks.initial_velocity_min = 10.0
	sparks.initial_velocity_max = 24.0
	sparks.damping_min = 6.0
	sparks.damping_max = 10.0
	sparks.gravity = Vector3(0, -8, 0)
	sparks.color_ramp = Vfx.ramp([Color(1, 1, 1, 1), Color(0.85, 0.4, 1, 1), Color(0.5, 0.1, 0.9, 0)], [0.0, 0.35, 1.0])
	sparks.scale_amount_curve = Vfx.curve([Vector2(0, 1), Vector2(1, 0.2)])
	add_child(sparks)
	sparks.emitting = true

	_light = OmniLight3D.new()
	_light.light_color = Color(0.85, 0.5, 1.0)
	_light.omni_range = radius * 1.6
	_light.shadow_enabled = false
	add_child(_light)
	Vfx.tame_light(_light)
	_update()


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration + 0.6:
		queue_free()
		return
	_update()


func _update() -> void:
	var k := clampf(_t / duration, 0.0, 1.0)
	var out := 1.0 - pow(1.0 - k, 3.0)  # fast out, slowing
	var fade := 1.0 - k
	Vfx.face_camera(_flash, radius * (0.9 - 0.5 * k), k * 1.5)
	Vfx.set_alpha(_flash, clampf(1.0 - k * 2.5, 0.0, 1.0))
	Vfx.face_camera(_ring, radius * 2.2 * out, 0.0)
	Vfx.set_alpha(_ring, fade)
	var gs := radius * 2.6 * out
	_ground_ring.scale = Vector3(gs, gs, 1.0)
	_ground_ring.global_position = global_position + normal.normalized() * 0.05
	Vfx.set_alpha(_ground_ring, fade * 0.9)
	if _bubble:
		Vfx.face_camera(_bubble, radius * 2.0 * out)
		(_bubble.material_override as ShaderMaterial).set_shader_parameter("strength", -0.5 * fade)
	_light.light_energy = 14.0 * fade * fade
