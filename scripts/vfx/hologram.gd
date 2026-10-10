class_name Hologram
extends Node
## Hologram looks on a model (hologram.gdshader as each mesh's
## material_overlay, so skinned / animated models work unchanged):
## - `teleport_in(model)`: the model materialises from the feet up - a
##   bright scan line sweeps up through a cyan hologram of it, with a ring of
##   light on the ground - then the overlay is removed. About 0.8 s.
## - `idle(model, colour)`: a permanent faint hologram coat (rim + scan
##   lines), e.g. the weapons floating over the spawn pads.
## Only meshes of the model itself (ArrayMesh) get it, not effect quads.

const SHADER := preload("res://scripts/vfx/hologram.gdshader")
const CYAN := Color(0.3, 0.85, 1.0)

var target: Node3D
var height := 2.0
var duration := 0.75
var color := CYAN
var _mat: ShaderMaterial
var _meshes: Array[GeometryInstance3D] = []
## Each mesh's overlay before (put back afterwards, e.g. a pad's idle coat).
var _before: Array[Material] = []
var _ring: MeshInstance3D
var _t := 0.0
var _base_y := 0.0


## Materialise `model` (any Node3D; its meshes) from its feet up.
## `model_height` <= 0: measured from the meshes.
static func teleport_in(model: Node3D, model_height := 2.0, col := CYAN, time := 0.75) -> Hologram:
	if model == null or not model.is_inside_tree():
		return null
	var h := Hologram.new()
	h.target = model
	h.height = model_height
	h.color = col
	h.duration = time
	model.add_child(h)
	return h


## Permanent faint hologram coat on `model` (returns the shared material).
static func idle(model: Node3D, col := CYAN, coat := 0.18) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("coat", coat)
	m.set_shader_parameter("line_y", -1000.0)
	m.set_shader_parameter("band", 0.0001)
	for g in _model_meshes(model):
		g.material_overlay = m
	return m


static func _model_meshes(model: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh is ArrayMesh and mi.visible:
			out.append(mi)
	return out


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("color", color)
	_meshes = _model_meshes(target)
	if height <= 0.0:
		height = _model_height()
	for g in _meshes:
		_before.append(g.material_overlay)
		g.material_overlay = _mat
	# Ring of light on the ground, shrinking in as the model forms.
	_ring = Vfx.quad("ring", color, Vector2.ONE)
	_ring.top_level = true
	add_child(_ring)
	_base_y = target.global_position.y
	_update()


## Height of the model's meshes above its origin (m).
func _model_height() -> float:
	var top := 0.5
	for g in _meshes:
		var box := g.global_transform * g.get_aabb()
		top = maxf(top, box.end.y - target.global_position.y)
	return top


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration + 0.2:
		for i in _meshes.size():
			var g := _meshes[i]
			if is_instance_valid(g) and g.material_overlay == _mat:
				g.material_overlay = _before[i]
		queue_free()
		return
	_update()


func _update() -> void:
	var k := clampf(_t / duration, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	var base := target.global_position.y
	_mat.set_shader_parameter("line_y", base - 0.1 + (height + 0.25) * e)
	_mat.set_shader_parameter("strength", 1.0 - clampf((_t - duration) / 0.2, 0.0, 1.0))
	_ring.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0).scaled(Vector3.ONE * (2.4 - 1.2 * e)),
		Vector3(target.global_position.x, base + 0.05, target.global_position.z))
	Vfx.set_alpha(_ring, (1.0 - k) * 0.9)
