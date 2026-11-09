extends Node3D
## The menus' light backdrop (owner asked: the full test arena behind the
## title / character select / level select held every weapon, robot and the
## boss in a phone's memory before anyone picked a level; "WebGL context
## lost" on the character select). A neon grid floor and a few slowly
## turning wireframe shapes in the HUD's cyan, all drawn by shaders: nearly
## nothing to load.

const SHAPES := 7


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.27, 0.86, 0.96)
	for i in SHAPES:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		var s := rng.randf_range(1.2, 3.2)
		box.size = Vector3(s, s, s)
		mi.mesh = _edges(box)
		mi.material_override = mat
		var a := TAU * float(i) / SHAPES + rng.randf_range(-0.3, 0.3)
		var r := rng.randf_range(11.0, 26.0)
		mi.position = Vector3(sin(a) * r, rng.randf_range(2.5, 9.0), cos(a) * r)
		mi.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0.0)
		mi.set_meta(&"spin", Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.4, 0.4), 0.0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _process(delta: float) -> void:
	for c: Node3D in get_children():
		if c.has_meta(&"spin"):
			c.rotation += (c.get_meta(&"spin") as Vector3) * delta


## A box's 12 edges as lines.
static func _edges(box: BoxMesh) -> ArrayMesh:
	var h := box.size * 0.5
	var corners: Array[Vector3] = []
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				corners.append(Vector3(x * h.x, y * h.y, z * h.z))
	var v := PackedVector3Array()
	for i in 8:
		for j in range(i + 1, 8):
			var d := corners[i] - corners[j]
			# Neighbours differ in exactly one axis.
			if int(absf(d.x) > 0.01) + int(absf(d.y) > 0.01) + int(absf(d.z) > 0.01) == 1:
				v.append(corners[i])
				v.append(corners[j])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return m
