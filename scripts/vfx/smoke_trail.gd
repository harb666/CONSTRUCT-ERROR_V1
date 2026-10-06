class_name SmokeTrail
extends MeshInstance3D
## A missile's smoke trail: one camera-facing ribbon through the points the
## missile passed, so the whole curved flight path stays visible. Each point
## puffs out (wider) and fades over `lifetime`; the newest stretch is warm
## (lit by the flame). One draw call, rebuilt each frame (<= MAX_POINTS).
## Keeps fading after the missile is gone; `reset()` for reuse.

const MAX_POINTS := 72

@export var lifetime := 2.6
@export var start_width := 0.35
@export var end_width := 2.2
## A new point every this many metres travelled.
@export var spacing := 0.7
@export var smoke_color := Color(0.62, 0.6, 0.58)
@export var hot_color := Color(1.0, 0.62, 0.25)

var emitting := false
var _pts: Array[Vector3] = []
var _age: Array[float] = []
var _seed: Array[float] = []
var _im: ImmediateMesh
var _mat: StandardMaterial3D


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_im = ImmediateMesh.new()
	mesh = _im
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.vertex_color_use_as_albedo = true
	material_override = _mat
	extra_cull_margin = 60.0


func reset() -> void:
	_pts.clear()
	_age.clear()
	_seed.clear()
	emitting = false
	_im.clear_surfaces()


## The missile is at `p` now (call every tick while it flies). A point is
## kept every `spacing` metres; the newest one follows the missile.
func feed(p: Vector3) -> void:
	if not emitting:
		return
	var n := _pts.size()
	if n < 2 or _pts[n - 2].distance_to(p) >= spacing:
		if n >= MAX_POINTS:
			_pts.remove_at(0)
			_age.remove_at(0)
			_seed.remove_at(0)
		_pts.append(p)
		_age.append(0.0)
		_seed.append(randf())
	else:
		_pts[n - 1] = p  # the head follows the missile


func is_done() -> bool:
	return not emitting and _pts.is_empty()


func _process(delta: float) -> void:
	for i in _age.size():
		_age[i] += delta
	while not _age.is_empty() and _age[0] >= lifetime:
		_pts.remove_at(0)
		_age.remove_at(0)
		_seed.remove_at(0)
	_im.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null or _pts.size() < 2:
		return
	# Three columns across (edge, centre, edge): soft-edged, solid along
	# its length, so the whole path reads as one continuous trail.
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := _pts.size()
	var rows: Array = []
	for i in n:
		var p := _pts[i]
		var tang := (_pts[mini(i + 1, n - 1)] - _pts[maxi(i - 1, 0)])
		if tang.length_squared() < 1e-6:
			tang = Vector3.UP
		var side := tang.cross(cam.global_position - p).normalized()
		var k := clampf(_age[i] / lifetime, 0.0, 1.0)
		# Turbulent: the older smoke billows (uneven width) and drifts up.
		var w := lerpf(start_width, end_width, sqrt(k)) * (0.8 + 0.4 * _seed[i])
		var drift := Vector3(0, 0.9 * k * k, 0) + side * sin(_seed[i] * 12.0 + _age[i] * 1.7) * 0.3 * k
		var heat := clampf(1.0 - _age[i] / 0.2, 0.0, 1.0) if emitting else 0.0
		var c := smoke_color.lerp(hot_color, heat)
		c.a = (1.0 - k) * (1.0 - k) * 0.85 * (0.75 + 0.25 * _seed[i])
		if i == n - 1 and emitting:
			c.a = 0.0
		var e := Color(c.r, c.g, c.b, 0.0)
		var cp := p + drift
		rows.append([cp - side * w * 0.5, cp, cp + side * w * 0.5, e, c])
	for i in n - 1:
		var r0: Array = rows[i]
		var r1: Array = rows[i + 1]
		for col in 2:
			var a0: Vector3 = r0[col]
			var a1: Vector3 = r0[col + 1]
			var b0: Vector3 = r1[col]
			var b1: Vector3 = r1[col + 1]
			var ca0: Color = r0[3] if col == 0 else r0[4]
			var ca1: Color = r0[4] if col == 0 else r0[3]
			var cb0: Color = r1[3] if col == 0 else r1[4]
			var cb1: Color = r1[4] if col == 0 else r1[3]
			for v in [[a0, ca0], [b0, cb0], [b1, cb1], [a0, ca0], [b1, cb1], [a1, ca1]]:
				_im.surface_set_color(v[1])
				_im.surface_add_vertex(v[0])
	_im.surface_end()
