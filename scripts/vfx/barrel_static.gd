class_name BarrelStatic
extends Node3D
## Static electricity / plasma crackling inside the barrel and around the
## muzzle while the gun recharges. Lives in the weapon's local space (barrel
## along +X); `intensity` (0..1) drives how much of it shows.

## Barrel interior span (weapon-local X) and bore radius / centre.
@export var barrel_start_x := 0.42
@export var muzzle_x := 0.965
@export var bore_radius := 0.1
@export var bore_center := Vector2(-0.004, -0.0006)
## Where the open chamber ends and how much wider it is than the bore.
@export var chamber_end_x := 0.78
@export var chamber_radius_scale := 1.6
@export var inner_arc_count := 7
@export var muzzle_arc_count := 5
@export var arc_width := 0.13
@export var reroll_time := Vector2(0.03, 0.09)

var intensity := 0.0

var _arcs: Array[MeshInstance3D] = []
var _a: Array[Vector3] = []
var _b: Array[Vector3] = []
var _timers: Array[float] = []
var _glow: MeshInstance3D
var _sparks: CPUParticles3D
var _t := 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for i in inner_arc_count + muzzle_arc_count:
		var q := Vfx.quad("bolt", Vfx.HOT if i % 2 == 0 else Vfx.PINK, Vector2.ONE)
		q.visible = false
		add_child(q)
		_arcs.append(q)
		_a.append(Vector3.ZERO)
		_b.append(Vector3.ZERO)
		_timers.append(0.0)
	_glow = Vfx.quad("glow", Vfx.PURPLE, Vector2.ONE)
	_glow.top_level = true
	add_child(_glow)
	_sparks = Vfx.particles("glow", 0.025, 10, 0.3)
	_sparks.position = Vector3(muzzle_x, bore_center.x, bore_center.y)
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_sparks.emission_ring_axis = Vector3.RIGHT
	_sparks.emission_ring_radius = bore_radius
	_sparks.emission_ring_inner_radius = bore_radius * 0.7
	_sparks.emission_ring_height = 0.0
	_sparks.direction = Vector3.RIGHT
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 0.3
	_sparks.initial_velocity_max = 1.2
	_sparks.gravity = Vector3.ZERO
	_sparks.color = Vfx.HOT
	_sparks.emitting = false
	add_child(_sparks)
	visible = false


func _wall(x: float, angle: float, r := 1.0) -> Vector3:
	return Vector3(x, bore_center.x + cos(angle) * bore_radius * r, bore_center.y + sin(angle) * bore_radius * r)


func _reroll(i: int) -> void:
	_timers[i] = randf_range(reroll_time.x, reroll_time.y) * (1.3 - intensity * 0.6)
	var a := randf() * TAU
	if i < inner_arc_count:
		# Jumps between the bore walls, a little way along the barrel.
		var x := randf_range(barrel_start_x, muzzle_x - 0.02)
		# The open chamber section is wider than the bore.
		var r := 1.0 if x > chamber_end_x else chamber_radius_scale
		_a[i] = _wall(x, a, r * randf_range(0.6, 1.0))
		_b[i] = _wall(clampf(x + randf_range(-0.16, 0.16), barrel_start_x, muzzle_x), a + PI + randf_range(-1.2, 1.2), r * randf_range(0.6, 1.0))
	else:
		# Licks out of the muzzle rim.
		_a[i] = _wall(muzzle_x - 0.01, a)
		_b[i] = _wall(muzzle_x + randf_range(0.08, 0.26) * (0.5 + intensity), a + randf_range(-0.8, 0.8), randf_range(1.1, 1.8))
	_arcs[i].visible = randf() < 0.15 + intensity * 0.85
	Vfx.set_alpha(_arcs[i], randf_range(0.45, 1.0) * clampf(intensity * 1.4, 0.0, 1.0))


func _process(delta: float) -> void:
	visible = intensity > 0.02
	_sparks.emitting = intensity > 0.35
	if not visible:
		return
	_t += delta
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for i in _arcs.size():
		_timers[i] -= delta
		if _timers[i] <= 0.0:
			_reroll(i)
		if not _arcs[i].visible:
			continue
		var a := global_transform * _a[i]
		var b := global_transform * _b[i]
		var axis := b - a
		var len := axis.length()
		if len < 1e-4:
			continue
		var y := axis / len
		var x := y.cross((cam.global_position - (a + b) * 0.5).normalized()).normalized()
		var z := x.cross(y)
		var w := arc_width * global_basis.get_scale().x * (1.0 if randf() < 0.5 else -1.0)
		_arcs[i].global_transform = Transform3D(Basis(x * w, y * len, z), (a + b) * 0.5)
	# Flickering plasma glow at the mouth of the barrel.
	_glow.global_position = global_transform * Vector3(muzzle_x - 0.02, bore_center.x, bore_center.y)
	var flicker := 0.75 + 0.25 * sin(_t * 47.0) * sin(_t * 31.0 + 1.3)
	Vfx.face_camera(_glow, (0.3 + 0.35 * intensity) * flicker * global_basis.get_scale().x, _t * 3.0)
	Vfx.set_alpha(_glow, clampf(intensity * flicker, 0.0, 1.0))
