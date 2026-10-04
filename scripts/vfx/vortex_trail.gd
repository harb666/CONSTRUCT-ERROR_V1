class_name VortexTrail
extends Node3D
## The black hole's wake: purple glowing motes, black dust and dark purple
## mist that ORBIT the line the black hole travelled along. Each particle is
## born at the black hole, keeps its spot along the flight axis and circles
## that axis (faster as it spirals in), so the path left behind becomes a
## slowly winding vortex tube. Drawn with three MultiMeshes and simulated in
## one cheap loop (no physics). Lives in the world so the wake outlasts the
## black hole; frees itself once emission stopped and all particles faded.

## Kinds: [texture, blend (true = additive), max count, per second, size range, life range]
const KINDS := [
	["glow", true, 90, 60.0, Vector2(0.12, 0.3), Vector2(1.2, 2.0)],   # purple motes
	["dot", false, 70, 42.0, Vector2(0.07, 0.16), Vector2(1.2, 2.0)],   # black dust
	["smoke", false, 44, 22.0, Vector2(0.9, 1.7), Vector2(1.3, 2.2)],   # dark mist
]
const COLORS := [
	[Color(0.62, 0.22, 1.0), Color(0.85, 0.55, 1.0)],
	[Color(0.03, 0.0, 0.06), Color(0.1, 0.02, 0.16)],
	[Color(0.26, 0.06, 0.45), Color(0.05, 0.0, 0.09)],
]

## Black hole (emitter) to follow; when null/freed, emission stops.
var source: Node3D
var axis := Vector3.FORWARD
## Black hole diameter (m): particles orbit about half of it out.
var size := 1.0
var emitting := true

var _mm: Array[MultiMesh] = []
var _parts: Array = []   # per kind: Array of [anchor, angle, radius, w, age, life, scale, col_k]
var _acc: Array[float] = [0.0, 0.0, 0.0]
var _u := Vector3.RIGHT
var _v := Vector3.UP


static func spawn(parent: Node, black_hole: Node3D, dir: Vector3) -> VortexTrail:
	var t := VortexTrail.new()
	t.source = black_hole
	t.axis = dir.normalized()
	parent.add_child(t)
	return t


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_u = axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	_v = axis.cross(_u).normalized()
	for k in KINDS.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var q := QuadMesh.new()
		var mat: StandardMaterial3D
		if KINDS[k][1]:
			mat = Vfx.material(KINDS[k][0], Color.WHITE, BaseMaterial3D.BILLBOARD_ENABLED, true, true)
		else:
			mat = Vfx.mix_material(KINDS[k][0], BaseMaterial3D.BILLBOARD_ENABLED).duplicate()
		q.material = mat
		mm.mesh = q
		mm.instance_count = KINDS[k][2]
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 200.0
		add_child(mi)
		_mm.append(mm)
		_parts.append([])


func stop() -> void:
	emitting = false


func particle_count() -> int:
	var n := 0
	for p in _parts:
		n += (p as Array).size()
	return n


## [anchor on the axis, distance from the axis] of a live particle (tests).
func sample(kind: int, i: int) -> Array:
	var p: Array = _parts[kind][i]
	return [p[0], _pos(p).distance_to(p[0]), p[1]]


func _pos(p: Array) -> Vector3:
	return p[0] + (_u * cos(p[1]) + _v * sin(p[1])) * p[2]


func _process(delta: float) -> void:
	var src_ok := emitting and source != null and is_instance_valid(source) and source.is_inside_tree()
	if src_ok:
		var at := source.get_global_transform_interpolated().origin
		for k in KINDS.size():
			_acc[k] += float(KINDS[k][3]) * delta
			while _acc[k] >= 1.0:
				_acc[k] -= 1.0
				if (_parts[k] as Array).size() < int(KINDS[k][2]):
					var life: Vector2 = KINDS[k][5]
					var sz: Vector2 = KINDS[k][4]
					# Born around the disc, a little behind it along the axis.
					var r := size * randf_range(0.25, 0.65) + 0.1
					(_parts[k] as Array).append([at - axis * randf_range(0.0, 0.4) * size, randf() * TAU, r,
						randf_range(2.2, 4.5) * (1.0 if k != 1 else 1.3), 0.0, randf_range(life.x, life.y),
						randf_range(sz.x, sz.y) * (1.0 + size * 0.15), randf()])
	elif particle_count() == 0:
		queue_free()
		return
	for k in KINDS.size():
		var list: Array = _parts[k]
		var j := 0
		while j < list.size():
			var p: Array = list[j]
			p[4] += delta
			if p[4] >= p[5]:
				list.remove_at(j)
				continue
			# Orbit the axis; spiral slowly inwards and spin up as it does.
			p[2] = maxf(p[2] - delta * 0.25 * p[2], 0.08)
			p[1] += p[3] * delta * (1.0 + 0.6 / maxf(p[2], 0.3))
			j += 1
		var mm := _mm[k]
		mm.visible_instance_count = list.size()
		var c0: Color = COLORS[k][0]
		var c1: Color = COLORS[k][1]
		for i in list.size():
			var p: Array = list[i]
			var t: float = p[4] / p[5]
			var fade := minf(t * 6.0, 1.0) * (1.0 - t)
			var s: float = p[6] * (1.0 + (t * 0.8 if k == 2 else 0.0))
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), _pos(p)))
			var col := c0.lerp(c1, p[7])
			col.a = fade * (1.0 if k == 0 else (0.9 if k == 1 else 0.6))
			mm.set_instance_color(i, col)
