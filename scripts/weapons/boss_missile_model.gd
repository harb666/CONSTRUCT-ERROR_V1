class_name BossMissileModel
extends RefCounted
## The boss missile's look, shared by every missile: one mesh, instanced
## for the round loaded in the launcher and for each one in flight.
##
## Uses `GLB` when it exists (the supplied missile asset, optimised); until
## then a procedural missile in the boss's colours (one 16-sided lathe body,
## ogive nose, red band and tip, four tail fins and four canards, a dark
## nozzle bell; vertex colours, one material, ~600 triangles).
##
## Model space: nose along +Z, rear (engine) at -Z, centred on the origin,
## length 1 (scale it to the wanted length); `RADIUS` = largest radius
## (fin tips) at length 1.

const GLB := "res://assets/enemies/robot_boss/missile/boss_missile.glb"
const BODY_RADIUS := 0.1
const RADIUS := 0.2
## Where the engine nozzle ends (model space, length 1).
const NOZZLE_Z := -0.5

static var _mesh: Mesh
static var _scene: PackedScene


## A new instance of the shared missile model, `length` metres long (in its
## parent's space).
static func create(length: float) -> Node3D:
	if _scene == null and ResourceLoader.exists(GLB):
		_scene = load(GLB)
	var n: Node3D
	if _scene:
		n = _scene.instantiate()
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = _procedural()
		mi.name = "MissileMesh"
		n = Node3D.new()
		n.add_child(mi)
	n.name = "Missile"
	n.scale = Vector3.ONE * length
	return n


static func _procedural() -> Mesh:
	if _mesh:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grey := Color(0.62, 0.63, 0.66)
	var red := Color(0.85, 0.06, 0.05)
	var dark := Color(0.13, 0.13, 0.15)
	# Lathe profile (z, radius, colour), rear to tip.
	var prof := [
		[-0.5, 0.072, dark], [-0.47, 0.082, dark], [-0.45, 0.07, dark], [-0.44, 0.088, grey],
		[-0.43, BODY_RADIUS, grey], [0.04, BODY_RADIUS, grey], [0.045, 0.103, red], [0.11, 0.103, red],
		[0.115, BODY_RADIUS, grey], [0.22, BODY_RADIUS, grey]]
	for i in 7:
		var t := (i + 1) / 7.0
		var z := 0.22 + 0.28 * t
		var r := BODY_RADIUS * pow(maxf(1.0 - pow(t, 1.8), 0.0), 0.55)
		prof.append([z, maxf(r, 0.0), red if t > 0.55 else grey])
	var seg := 16
	for k in prof.size() - 1:
		var a: Array = prof[k]
		var b: Array = prof[k + 1]
		var slope := Vector2(b[0] - a[0], b[1] - a[1])
		for s in seg:
			var t0 := TAU * s / seg
			var t1 := TAU * (s + 1) / seg
			var quad := [[t0, a], [t1, a], [t1, b], [t0, b]]
			var pts: Array[Vector3] = []
			var nrm: Array[Vector3] = []
			for q in quad:
				var ang: float = q[0]
				var ring: Array = q[1]
				var dir := Vector3(cos(ang), sin(ang), 0.0)
				pts.append(dir * float(ring[1]) + Vector3(0, 0, float(ring[0])))
				# Lathe normal: outward, tilted back by the profile slope.
				var nn := (dir * slope.x - Vector3(0, 0, slope.y)).normalized() if slope.length() > 1e-6 else dir
				nrm.append(nn)
			var col: Color = b[2]
			for i in [0, 2, 1, 0, 3, 2]:
				st.set_color(col)
				st.set_normal(nrm[i])
				st.add_vertex(pts[i])
	# Rear cap (nozzle back wall, dark).
	for s in seg:
		var t0 := TAU * s / seg
		var t1 := TAU * (s + 1) / seg
		for v in [Vector3(0, 0, -0.46), Vector3(cos(t1), sin(t1), 0) * 0.07 + Vector3(0, 0, -0.5), Vector3(cos(t0), sin(t0), 0) * 0.07 + Vector3(0, 0, -0.5)]:
			st.set_color(Color(0.05, 0.05, 0.05))
			st.set_normal(Vector3(0, 0, -1))
			st.add_vertex(v)
	# Tail fins (big) and canards (small): thin plates, four each.
	for f in 4:
		var ang := TAU * f / 4.0 + PI / 4.0
		_fin(st, ang, -0.42, -0.2, -0.42, -0.33, RADIUS, 0.008, dark)
		_fin(st, ang, 0.13, 0.2, 0.13, 0.165, 0.15, 0.006, red)
	_mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.metallic = 0.55
	m.roughness = 0.38
	_mesh.surface_set_material(0, m)
	return _mesh


## A trapezoid fin at angle `ang`: root chord z0..z1 on the body, tip chord
## t0..t1 at radius `span`, `thick` thick (a thin box).
static func _fin(st: SurfaceTool, ang: float, z0: float, z1: float, t0: float, t1: float, span: float, thick: float, col: Color) -> void:
	var out := Vector3(cos(ang), sin(ang), 0)
	var side := Vector3(-sin(ang), cos(ang), 0) * thick * 0.5
	var r0 := BODY_RADIUS * 0.95
	var c := [out * r0 + Vector3(0, 0, z0), out * r0 + Vector3(0, 0, z1), out * span + Vector3(0, 0, t1), out * span + Vector3(0, 0, t0)]
	var faces := [
		[[c[0] + side, c[1] + side, c[2] + side, c[3] + side], side.normalized()],
		[[c[3] - side, c[2] - side, c[1] - side, c[0] - side], -side.normalized()],
		[[c[3] + side, c[2] + side, c[2] - side, c[3] - side], out],
		[[c[1] + side, c[1] - side, c[2] - side, c[2] + side], (out * (z1 - t1) + Vector3(0, 0, span - r0)).normalized()],
		[[c[0] - side, c[3] - side, c[3] + side, c[0] + side], (out * (t0 - z0) - Vector3(0, 0, span - r0)).normalized()],
	]
	for fc in faces:
		var p: Array = fc[0]
		var n: Vector3 = fc[1]
		# Wind each quad to face its normal.
		var p0: Vector3 = p[0]
		var p1: Vector3 = p[1]
		var p2: Vector3 = p[2]
		var fn := (p1 - p0).cross(p2 - p0)
		var order := [0, 1, 2, 0, 2, 3] if fn.dot(n) < 0.0 else [0, 2, 1, 0, 3, 2]
		for i in order:
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(p[i])
