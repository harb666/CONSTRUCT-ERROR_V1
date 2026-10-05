class_name WeaponSwitchFx
extends Node3D
## Energy burst at an arm's weapon mount while switching weapons: a bright
## flash, a ring snapping out round the arm, crackling arcs and a spray of
## sparks, in the weapon's colour. One per arm (child of its WeaponSocket,
## +X = along the forearm), restarted for each step; mobile-light.

var _t := 99.0
var _life := 0.22
var _strength := 1.0
var _flash: MeshInstance3D
var _ring: MeshInstance3D
var _arcs: Array[MeshInstance3D] = []
var _arc_dirs: Array[Vector3] = []
var _sparks: CPUParticles3D


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_flash = Vfx.quad("glow", Color.WHITE, Vector2.ONE)
	_flash.top_level = true
	add_child(_flash)
	_ring = Vfx.quad("ring", Color.WHITE, Vector2.ONE)
	add_child(_ring)
	for i in 3:
		var a := Vfx.quad("bolt", Color.WHITE, Vector2.ONE)
		add_child(a)
		_arcs.append(a)
		_arc_dirs.append(Vector3.ZERO)
	_sparks = Vfx.particles("glow", 0.05, 22, 0.32)
	_sparks.one_shot = true
	_sparks.explosiveness = 0.9
	_sparks.emitting = false
	_sparks.local_coords = false
	_sparks.direction = Vector3.RIGHT
	_sparks.spread = 80.0
	_sparks.initial_velocity_min = 1.5
	_sparks.initial_velocity_max = 4.5
	_sparks.damping_min = 4.0
	_sparks.damping_max = 7.0
	add_child(_sparks)
	visible = false
	set_process(false)


## Flash in `color`; `strength` 1 = materialise, ~0.7 = retract.
func play(color: Color, strength := 1.0, life := 0.22) -> void:
	_t = 0.0
	_life = life
	_strength = strength
	var hot := color.lerp(Color.WHITE, 0.55)
	(_flash.material_override as StandardMaterial3D).albedo_color = Color(hot.r, hot.g, hot.b, 1.0)
	(_ring.material_override as StandardMaterial3D).albedo_color = Color(color.r, color.g, color.b, 1.0)
	for a in _arcs:
		(a.material_override as StandardMaterial3D).albedo_color = Color(hot.r, hot.g, hot.b, 1.0)
	for i in _arc_dirs.size():
		_arc_dirs[i] = Vector3(randf_range(-0.2, 0.6), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	_sparks.color_ramp = Vfx.ramp([Color(1, 1, 1, 1), Color(color.r, color.g, color.b, 1), Color(color.r, color.g, color.b, 0)], [0.0, 0.35, 1.0])
	_sparks.restart()
	_sparks.emitting = true
	visible = true
	set_process(true)
	_process(0.0)


func is_playing() -> bool:
	return _t < _life


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		visible = false
		set_process(false)
		return
	var k := _t / _life
	var fade := (1.0 - k) * (1.0 - k)
	_flash.global_position = global_position
	Vfx.face_camera(_flash, (0.7 + 0.5 * k) * _strength, k * 3.0)
	Vfx.set_alpha(_flash, fade)
	# Ring round the arm: faces along the forearm (+X), expanding.
	var r := (0.2 + 0.5 * sqrt(k)) * _strength
	_ring.transform = Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3(r, r, r)), Vector3.ZERO)
	Vfx.set_alpha(_ring, minf(fade * 1.3, 1.0))
	# Crackling arcs out from the mount.
	for i in _arcs.size():
		var a := _arcs[i]
		var on := randf() < 0.7
		a.visible = on
		if not on:
			continue
		var d := _arc_dirs[i].rotated(Vector3.RIGHT, _t * 25.0 + i)
		var length := randf_range(0.2, 0.38) * _strength
		var y := d
		var x := y.cross(Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.UP).normalized()
		a.transform = Transform3D(Basis(x * 0.1, y * length, x.cross(y)), d * length * 0.5)
		Vfx.set_alpha(a, fade)
