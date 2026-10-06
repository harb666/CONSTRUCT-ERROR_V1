class_name DodgeDust
extends Node3D
## A small puff of dust kicked up by the feet as a dodge / slide ends: a
## handful of soft, alpha-blended smoke quads (one draw call, existing
## texture) that drift forward and up, spread out and fade. Frees itself.

@export var lifetime := 0.75

var _t := 0.0


## `dir`: the slide's horizontal direction (dust carries on along it).
static func spawn(parent: Node, at: Vector3, dir: Vector3) -> DodgeDust:
	var d := DodgeDust.new()
	parent.add_child(d)
	var flat := Vector3(dir.x, 0.0, dir.z)
	flat = flat.normalized() if flat.length_squared() > 1e-4 else Vector3.FORWARD
	# Just ahead of the feet: the body is still braking along the slide.
	d.global_position = at + flat * 0.35
	d._make(flat)
	return d


func _make(dir: Vector3) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.5
	q.material = Vfx.mix_material("smoke")
	p.mesh = q
	p.amount = 12
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.22, 0.03, 0.22)
	p.direction = (dir + Vector3.UP * 0.4).normalized()
	# Thrown along with the braking body (about as fast, braking about as
	# hard), so the dust rolls with the feet and settles where they stop.
	p.spread = 35.0
	p.initial_velocity_min = 4.5
	p.initial_velocity_max = 7.5
	p.damping_min = 10.0
	p.damping_max = 13.0
	p.gravity = Vector3(0, 0.25, 0)
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	p.scale_amount_curve = Vfx.curve([Vector2(0, 0.45), Vector2(1, 1.25)])
	# Light, dusty tan: faint, so it reads as a kick of dust, not smoke.
	p.color_ramp = Vfx.ramp([Color(0.66, 0.57, 0.45, 0.0), Color(0.64, 0.55, 0.43, 0.55), Color(0.6, 0.54, 0.46, 0.0)], [0.0, 0.12, 1.0])
	p.position.y = 0.06
	add_child(p)
	p.emitting = true


func _process(delta: float) -> void:
	_t += delta
	if _t >= lifetime + 0.1:
		queue_free()
