class_name SmokeTrail
extends MeshInstance3D
## A missile's smoke trail: one camera-facing ribbon through the points the
## missile passed, so the whole curved flight path stays visible. Each point
## puffs out (wider) and fades over `lifetime`; the newest stretch is warm
## (lit by the flame). One draw call. The ribbon is shaped on the GPU
## (smoke_trail.gdshader): one fixed mesh, built once and shared by every
## trail, and the points go in as shader uniforms each frame - no graphics
## buffers rebuilt per frame (that churn is hard on phones' browsers).
## Keeps fading after the missile is gone; `reset()` for reuse.

const MAX_POINTS := 72
const SHADER := preload("res://scripts/vfx/smoke_trail.gdshader")

@export var lifetime := 2.6
@export var start_width := 0.35
@export var end_width := 2.2
## A new point every this many metres travelled.
@export var spacing := 0.7
@export var smoke_color := Color(0.62, 0.6, 0.58)
@export var hot_color := Color(1.0, 0.62, 0.25)

static var _ribbon: ArrayMesh

var emitting := false
var _pts: Array[Vector3] = []
var _age: Array[float] = []
var _seed: Array[float] = []
var _mat: ShaderMaterial
var _upload := PackedVector4Array()
var _seeds := PackedFloat32Array()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = _shared_ribbon()
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material_override = _mat
	_upload.resize(MAX_POINTS)
	_seeds.resize(MAX_POINTS)
	visible = false


## The fixed ribbon mesh: for each pair of neighbouring points, two strips
## (edge-centre, centre-edge) of two triangles; UV = (point, column).
static func _shared_ribbon() -> ArrayMesh:
	if _ribbon:
		return _ribbon
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in MAX_POINTS - 1:
		for col in 2:
			var c0 := float(col) - 1.0
			var c1 := float(col)
			for v in [[i, c0], [i + 1, c0], [i + 1, c1], [i, c0], [i + 1, c1], [i, c1]]:
				verts.append(Vector3.ZERO)
				uvs.append(Vector2(v[0], v[1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	_ribbon = ArrayMesh.new()
	_ribbon.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# The shader places the vertices anywhere: never cull it.
	_ribbon.custom_aabb = AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000))
	return _ribbon


func reset() -> void:
	_pts.clear()
	_age.clear()
	_seed.clear()
	emitting = false
	visible = false


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
	var n := _pts.size()
	visible = n >= 2
	if not visible:
		return
	for i in n:
		var p := _pts[i]
		_upload[i] = Vector4(p.x, p.y, p.z, _age[i])
		_seeds[i] = _seed[i]
	_mat.set_shader_parameter("pts", _upload)
	_mat.set_shader_parameter("seeds", _seeds)
	_mat.set_shader_parameter("count", n)
	_mat.set_shader_parameter("lifetime", lifetime)
	_mat.set_shader_parameter("start_width", start_width)
	_mat.set_shader_parameter("end_width", end_width)
	_mat.set_shader_parameter("emitting", emitting)
	_mat.set_shader_parameter("smoke_color", smoke_color)
	_mat.set_shader_parameter("hot_color", hot_color)
