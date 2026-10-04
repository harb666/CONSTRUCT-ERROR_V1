extends SceneTree
## Regenerates the weapon spawn pad's walk-on ramp resources:
##   godot --headless --path . -s tools/build_pad_ramp.gd
## The ramp is a sloped ring around the pad, textured with a plain dark-metal
## patch of the pad's own texture atlas (same textures, no glow).

const DIR := "res://assets/props/weapon_spawn_pad/"
const INNER_R := 0.88   # tucks just under the pad's rim
const OUTER_R := 2.0
const TOP_H := 0.3      # pad height
const SEGMENTS := 48
## Atlas patch (UV) of plain dark metal with no emissive content.
const UV_MIN := Vector2(0.547, 0.656)
const UV_MAX := Vector2(0.594, 0.703)
const UV_REPEATS := 24  # patch repeats around the ring


func _initialize() -> void:
	var pad: Node = load(DIR + "weapon_spawn_pad.glb").instantiate()
	var src: MeshInstance3D = pad.find_children("*", "MeshInstance3D", true, false)[0]
	var mat := (src.get_active_material(0) as BaseMaterial3D).duplicate() as BaseMaterial3D
	mat.emission_enabled = false
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.resource_name = "PadRampMaterial"

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var per := SEGMENTS / UV_REPEATS
	for i in SEGMENTS:
		var a0 := TAU * i / SEGMENTS
		var a1 := TAU * (i + 1) / SEGMENTS
		var u0 := lerpf(UV_MIN.x, UV_MAX.x, float(i % per) / per)
		var u1 := lerpf(UV_MIN.x, UV_MAX.x, float(i % per + 1) / per)
		var in0 := Vector3(cos(a0) * INNER_R, TOP_H, sin(a0) * INNER_R)
		var in1 := Vector3(cos(a1) * INNER_R, TOP_H, sin(a1) * INNER_R)
		var out0 := Vector3(cos(a0) * OUTER_R, 0.0, sin(a0) * OUTER_R)
		var out1 := Vector3(cos(a1) * OUTER_R, 0.0, sin(a1) * OUTER_R)
		# Counter-clockwise seen from above (front face up).
		for v in [[in0, Vector2(u0, UV_MIN.y)], [in1, Vector2(u1, UV_MIN.y)], [out1, Vector2(u1, UV_MAX.y)],
				[in0, Vector2(u0, UV_MIN.y)], [out1, Vector2(u1, UV_MAX.y)], [out0, Vector2(u0, UV_MAX.y)]]:
			st.set_uv(v[1])
			st.add_vertex(v[0])
	st.generate_normals()
	st.generate_tangents()
	var mesh := st.commit()
	# Ensure faces point up; flip winding if generated normals point down.
	var arrays := mesh.surface_get_arrays(0)
	if (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0].y < 0.0:
		st.clear()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for t in range(0, verts.size(), 3):
			for k in [0, 2, 1]:
				st.set_uv(uvs[t + k])
				st.add_vertex(verts[t + k])
		st.generate_normals()
		st.generate_tangents()
		mesh = st.commit()
	mesh.surface_set_material(0, mat)
	mesh.resource_name = "PadRampMesh"
	print("ramp normal y: ", (mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0].y)

	var shape := mesh.create_trimesh_shape()
	ResourceSaver.save(mat, DIR + "pad_ramp_material.tres")
	mat.take_over_path(DIR + "pad_ramp_material.tres")
	ResourceSaver.save(mesh, DIR + "pad_ramp_mesh.res")
	ResourceSaver.save(shape, DIR + "pad_ramp_shape.res")
	print("saved ramp resources")
	pad.free()
	quit()
