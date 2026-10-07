class_name BossCoreCables
extends Node3D
## The boss core's power connections: a few chunky cables and ribbed hoses
## running from the chest recess wall into the core, with metal connectors
## at both ends and a faint red power pulse (it powers the robot).
## Lives in the core socket's space (follows the chest). While intact it is
## ONE mesh (one draw call). snap() (core destroyed): every connection
## breaks in the middle - the core-side stubs stay on the dead core, the
## wall-side ends recoil and swing down under their weight (damped
## pendulums), the power glow dies. broken_ends() gives the severed ends
## (world) for sparks / arcs / smoke.

const SEGMENTS := 12
const SIDES := 8
const SHADER := preload("res://scripts/enemies/boss_cables.gdshader")

## Model-space frame (from the boss): the socket's transform in the model,
## the core centre, its radius and how far forward the recess wall is.
var socket_in_model := Transform3D.IDENTITY
var core_radius := 0.052
var wall_ahead := 0.047

## [angle (deg, round the core seen from the front), tube radius, is hose,
##  wall radius] in model units.
var specs := [[28.0, 0.012, false, 0.12], [152.0, 0.012, false, 0.125], [252.0, 0.016, true, 0.118],
	[292.0, 0.016, true, 0.122], [95.0, 0.01, false, 0.11]]

var broken := false
var _mat: ShaderMaterial
var _whole: MeshInstance3D
var _stubs: MeshInstance3D
var _pieces: Array[Node3D] = []
var _swing: Array = []  # per piece: [axis, angle, velocity, target, free end (piece local)]
var _stub_ends: Array[Vector3] = []


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	var whole := SurfaceTool.new()
	whole.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stubs := SurfaceTool.new()
	stubs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var to_local := socket_in_model.affine_inverse()
	var c := socket_in_model.origin  # core centre (model space)
	var down := (to_local.basis * Vector3.DOWN).normalized()
	for sp in specs:
		var ang := deg_to_rad(float(sp[0]))
		var r: float = sp[1]
		var hose: bool = sp[2]
		var d := Vector3(cos(ang), sin(ang), 0.0)
		var wall := c + d * float(sp[3]) + Vector3(0, 0, wall_ahead + 0.004)
		var plug := c + d * core_radius * 0.92 + Vector3(0, 0, 0.012)
		var p0 := to_local * wall
		var p1 := to_local * (wall + Vector3(0, 0, 0.035))
		var p2 := to_local * (plug + d * 0.03 + Vector3(0, 0, 0.03))
		var p3 := to_local * plug
		var pts: Array[Vector3] = []
		for i in SEGMENTS + 1:
			var t := float(i) / SEGMENTS
			var u := 1.0 - t
			pts.append(p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t)
		_tube(whole, pts, r, hose, Vector3.ZERO)
		_connector(whole, pts[0], pts[1] - pts[0], r, Vector3.ZERO)
		_connector(whole, pts[SEGMENTS], pts[SEGMENTS - 1] - pts[SEGMENTS], r, Vector3.ZERO)
		# Broken: the core-side half stays on the core ...
		var half := SEGMENTS / 2
		var core_half: Array[Vector3] = []
		for i in range(half + 1, SEGMENTS + 1):
			core_half.append(pts[i])
		_tube(stubs, core_half, r, hose, Vector3.ZERO)
		_connector(stubs, pts[SEGMENTS], pts[SEGMENTS - 1] - pts[SEGMENTS], r, Vector3.ZERO)
		_stub_ends.append(pts[half + 1])
		# ... the wall-side half hangs from its connector (own node).
		var piece := MeshInstance3D.new()
		var pst := SurfaceTool.new()
		pst.begin(Mesh.PRIMITIVE_TRIANGLES)
		var wall_half: Array[Vector3] = []
		for i in half + 1:
			wall_half.append(pts[i])
		_tube(pst, wall_half, r, hose, p0)
		_connector(pst, pts[0], pts[1] - pts[0], r, p0)
		piece.mesh = pst.commit()
		piece.material_override = _mat
		piece.position = p0
		piece.visible = false
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(piece)
		_pieces.append(piece)
		var end_local := pts[half] - p0
		var axis := end_local.cross(down)
		axis = axis.normalized() if axis.length_squared() > 1e-8 else Vector3.RIGHT
		_swing.append([axis, 0.0, 0.0, end_local.angle_to(down) * 0.85, end_local])
	_whole = MeshInstance3D.new()
	_whole.mesh = whole.commit()
	_whole.material_override = _mat
	_whole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_whole)
	_stubs = MeshInstance3D.new()
	_stubs.mesh = stubs.commit()
	_stubs.material_override = _mat
	_stubs.visible = false
	_stubs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_stubs)
	set_process(false)


## Core destroyed: the connections snap.
func snap() -> void:
	if broken:
		return
	broken = true
	_whole.visible = false
	_stubs.visible = true
	for i in _pieces.size():
		_pieces[i].visible = true
		_pieces[i].basis = Basis.IDENTITY
		var sw: Array = _swing[i]
		sw[1] = 0.0
		sw[2] = randf_range(5.0, 9.0)  # recoil out of the plug
	_mat.set_shader_parameter("power", 0.0)
	set_process(true)


func reset() -> void:
	broken = false
	_whole.visible = true
	_stubs.visible = false
	for p in _pieces:
		p.visible = false
	_mat.set_shader_parameter("power", 1.0)
	set_process(false)


## Power glow (0..1), e.g. flickering while the core fails.
func set_power(v: float) -> void:
	_mat.set_shader_parameter("power", v)


## World positions of the severed ends: [wall-side end, core stub end] per
## connection; the bool is true for hoses (they smoke).
func broken_ends() -> Array:
	var out := []
	for i in _pieces.size():
		var sw: Array = _swing[i]
		var wall_end: Vector3 = _pieces[i].global_transform * (sw[4] as Vector3)
		out.append([wall_end, global_transform * _stub_ends[i], specs[i][2]])
	return out


func _process(delta: float) -> void:
	# Damped pendulums: the loose ends drop and swing, then hang.
	for i in _pieces.size():
		var sw: Array = _swing[i]
		var a: float = sw[1]
		var v: float = sw[2]
		var target: float = sw[3]
		for k in 3:
			var h := delta / 3.0
			v += (-30.0 * sin(a - target) - 2.2 * v) * h
			a += v * h
		sw[1] = a
		sw[2] = v
		_pieces[i].basis = Basis(sw[0] as Vector3, a)


## A tube through `pts` (radius r; hoses ribbed), vertices relative to `o`.
func _tube(st: SurfaceTool, pts: Array[Vector3], r: float, hose: bool, o: Vector3) -> void:
	var n := pts.size()
	var prev_side := Vector3.ZERO
	var rings: Array = []
	for i in n:
		var tan := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := prev_side - tan * tan.dot(prev_side) if prev_side != Vector3.ZERO else tan.cross(Vector3.UP if absf(tan.y) < 0.9 else Vector3.RIGHT)
		side = side.normalized()
		prev_side = side
		var up := tan.cross(side)
		var rr := r * (1.15 if hose and i % 2 == 0 else 1.0)
		var ring := []
		for k in SIDES + 1:
			var ang := TAU * k / SIDES
			var nrm := side * cos(ang) + up * sin(ang)
			ring.append([pts[i] + nrm * rr - o, nrm])
		rings.append(ring)
	var col := Color(0.16, 0.15, 0.15, 0.0) if hose else Color(0.06, 0.06, 0.065, 0.0)
	for i in n - 1:
		for k in SIDES:
			# A thin red power stripe along each cable (alpha = glow).
			var stripe := 1.0 if (k == 0 and not hose) else 0.0
			var c := Color(0.55, 0.04, 0.03, 1.0) if stripe > 0.0 else col
			for v in [[i, k], [i + 1, k + 1], [i + 1, k], [i, k], [i, k + 1], [i + 1, k + 1]]:
				var e: Array = rings[v[0]][v[1]]
				st.set_color(c)
				st.set_normal(e[1])
				st.add_vertex(e[0])


## A short metal connector sleeve at `p`, pointing along `dir`.
func _connector(st: SurfaceTool, p: Vector3, dir: Vector3, r: float, o: Vector3) -> void:
	var a := dir.normalized()
	var side := a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := a.cross(side)
	var rr := r * 1.7
	var l := r * 2.4
	for k in SIDES:
		var t0 := TAU * k / SIDES
		var t1 := TAU * (k + 1) / SIDES
		var n0 := side * cos(t0) + up * sin(t0)
		var n1 := side * cos(t1) + up * sin(t1)
		var q := [p + n0 * rr - o, p + n1 * rr - o, p + n1 * rr + a * l - o, p + n0 * rr + a * l - o]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_color(Color(0.42, 0.42, 0.45, 0.0))
			st.set_normal(n0 if idx in [0, 3] else n1)
			st.add_vertex(q[idx])
