extends Node3D
## Builds a simple movement test arena from a list of boxes.
## Heights are chosen to exercise the jump (~1.9 m) and double jump (~3.4 m).

const GRID_SHADER := preload("res://scripts/world/grid.gdshader")

@export var arena_size := 80.0
@export var wall_height := 5.0

# [position (center of base), size, color]
var _blocks := [
	# Single-jump steps
	[Vector3(-8, 0, -8), Vector3(4, 0.8, 4), Color(0.35, 0.55, 0.85)],
	[Vector3(-14, 0, -8), Vector3(4, 1.6, 4), Color(0.35, 0.55, 0.85)],
	# Double-jump platform
	[Vector3(-20, 0, -8), Vector3(5, 3.0, 5), Color(0.85, 0.45, 0.35)],
	# Elevated walkway reachable from the double-jump platform
	[Vector3(-20, 2.6, -18), Vector3(4, 0.4, 15), Color(0.85, 0.45, 0.35)],
	# Pillars to weave between
	[Vector3(8, 0, -6), Vector3(1.5, 4, 1.5), Color(0.7, 0.7, 0.75)],
	[Vector3(12, 0, -10), Vector3(1.5, 4, 1.5), Color(0.7, 0.7, 0.75)],
	[Vector3(16, 0, -6), Vector3(1.5, 4, 1.5), Color(0.7, 0.7, 0.75)],
	[Vector3(12, 0, -2), Vector3(1.5, 4, 1.5), Color(0.7, 0.7, 0.75)],
	[Vector3(20, 0, -10), Vector3(1.5, 4, 1.5), Color(0.7, 0.7, 0.75)],
	# Cover walls (waist and head height)
	[Vector3(0, 0, 10), Vector3(6, 1.1, 0.6), Color(0.45, 0.75, 0.45)],
	[Vector3(8, 0, 14), Vector3(0.6, 2.2, 6), Color(0.45, 0.75, 0.45)],
	[Vector3(-8, 0, 14), Vector3(0.6, 2.2, 6), Color(0.45, 0.75, 0.45)],
	# Gap jump between two platforms
	[Vector3(16, 0, 18), Vector3(4, 1.2, 4), Color(0.85, 0.75, 0.3)],
	[Vector3(24, 0, 18), Vector3(4, 1.2, 4), Color(0.85, 0.75, 0.3)],
	[Vector3(32, 0, 18), Vector3(4, 2.4, 4), Color(0.85, 0.75, 0.3)],
]

# [base position, size, rotation degrees around X]
var _ramps := [
	[Vector3(0, 0, -20), Vector3(5, 0.4, 12), 15.0],
	[Vector3(-30, 0, 10), Vector3(5, 0.4, 14), 30.0],
]


func _ready() -> void:
	var floor_mat := _make_mat(Color(0.55, 0.57, 0.6), 2.0)
	_add_box(Vector3(0, -0.5, 0), Vector3(arena_size, 1, arena_size), floor_mat)
	var wall_mat := _make_mat(Color(0.4, 0.42, 0.48), 1.0)
	var h := arena_size * 0.5
	_add_box(Vector3(0, wall_height * 0.5, -h), Vector3(arena_size, wall_height, 1), wall_mat)
	_add_box(Vector3(0, wall_height * 0.5, h), Vector3(arena_size, wall_height, 1), wall_mat)
	_add_box(Vector3(-h, wall_height * 0.5, 0), Vector3(1, wall_height, arena_size), wall_mat)
	_add_box(Vector3(h, wall_height * 0.5, 0), Vector3(1, wall_height, arena_size), wall_mat)

	var mats := {}
	for b in _blocks:
		var col: Color = b[2]
		if not mats.has(col):
			mats[col] = _make_mat(col, 1.0)
		var size: Vector3 = b[1]
		_add_box(b[0] + Vector3(0, size.y * 0.5, 0), size, mats[col])

	var ramp_mat := _make_mat(Color(0.6, 0.5, 0.75), 1.0)
	for r in _ramps:
		var size: Vector3 = r[1]
		var angle := deg_to_rad(r[2])
		# Tilt so the low edge touches the floor at +Z and rises toward -Z.
		var rise := sin(angle) * size.z * 0.5
		var body := _add_box(r[0] + Vector3(0, rise - size.y * 0.5, 0), size, ramp_mat)
		body.rotation.x = angle


func _make_mat(color: Color, cell: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GRID_SHADER
	m.set_shader_parameter("color_a", color)
	m.set_shader_parameter("color_b", color.darkened(0.12))
	m.set_shader_parameter("cell", cell)
	return m


func _add_box(center: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mesh.mesh = bm
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	add_child(body)
	return body
