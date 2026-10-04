extends SceneTree
## Regenerates the weapon spawn pad's walk-on ramp resources:
##   godot --headless --path . -s tools/build_pad_ramp.gd
## The pad is sunk so its top sits TOP_H above the floor. The ramp is a ring
## whose inner edge tucks under the pad's rim (no visible seam) and slopes
## down to the floor. It uses the pad's own material/textures, mapped to the
## atlas patch whose colour best matches the pad's outer wall (no glow).

const DIR := "res://assets/props/weapon_spawn_pad/"
const TUCK_R := 0.78    # hidden inside the pad
const TUCK_H := 0.02
const RIM_R := 0.875    # just inside the pad's top rim
const RIM_H := 0.14
const OUTER_R := 1.07   # ~35° slope: under the 45° walkable limit
const SEGMENTS := 64
const PATCH := 0.04     # UV size of the sampled atlas patch
const UV_REPEATS := 32


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var pad: Node3D = load("res://scenes/props/weapon_spawn_pad.tscn").instantiate()
	root.add_child(pad)
	await process_frame
	var src: MeshInstance3D = pad.get_node("Model").find_children("*", "MeshInstance3D", true, false)[0]
	var mat := (src.get_active_material(0) as BaseMaterial3D).duplicate() as BaseMaterial3D
	mat.emission_enabled = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.resource_name = "PadRampMaterial"

	var uv0 := _pick_patch(src, pad, mat)
	var uv1 := uv0 + Vector2(PATCH, PATCH)

	var rings := [[TUCK_R, TUCK_H, uv0.y], [RIM_R, RIM_H, lerpf(uv0.y, uv1.y, 0.2)], [OUTER_R, 0.0, uv1.y]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var per := SEGMENTS / UV_REPEATS
	for i in SEGMENTS:
		var a0 := TAU * i / SEGMENTS
		var a1 := TAU * (i + 1) / SEGMENTS
		var u0 := lerpf(uv0.x, uv1.x, float(i % per) / per)
		var u1 := lerpf(uv0.x, uv1.x, float(i % per + 1) / per)
		for k in rings.size() - 1:
			var ra: Array = rings[k]
			var rb: Array = rings[k + 1]
			var p00 := Vector3(cos(a0) * ra[0], ra[1], sin(a0) * ra[0])
			var p01 := Vector3(cos(a1) * ra[0], ra[1], sin(a1) * ra[0])
			var p10 := Vector3(cos(a0) * rb[0], rb[1], sin(a0) * rb[0])
			var p11 := Vector3(cos(a1) * rb[0], rb[1], sin(a1) * rb[0])
			# Wound so faces point up/outward.
			for v in [[p00, Vector2(u0, ra[2])], [p11, Vector2(u1, rb[2])], [p01, Vector2(u1, ra[2])],
					[p00, Vector2(u0, ra[2])], [p10, Vector2(u0, rb[2])], [p11, Vector2(u1, rb[2])]]:
				st.set_uv(v[1])
				st.add_vertex(v[0])
	st.generate_normals()
	st.generate_tangents()
	var mesh := st.commit()
	var ny := (mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0].y
	assert(ny > 0.0, "ramp normals must face up")
	mesh.surface_set_material(0, mat)
	mesh.resource_name = "PadRampMesh"

	ResourceSaver.save(mat, DIR + "pad_ramp_material.tres")
	mat.take_over_path(DIR + "pad_ramp_material.tres")
	ResourceSaver.save(mesh, DIR + "pad_ramp_mesh.res")
	ResourceSaver.save(mesh.create_trimesh_shape(), DIR + "pad_ramp_shape.res")
	print("saved ramp resources, patch uv ", uv0)
	quit()


## Find the atlas patch whose base colour best matches the pad's outer wall,
## with no emissive (glow) content and little detail variation.
func _pick_patch(src: MeshInstance3D, pad: Node3D, mat: BaseMaterial3D) -> Vector2:
	var albedo := mat.albedo_texture.get_image()
	albedo.decompress()
	var emissive := (src.get_active_material(0) as BaseMaterial3D).emission_texture.get_image()
	emissive.decompress()
	var arrays := src.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var xf := pad.global_transform.affine_inverse() * src.global_transform
	var wall := Color(0, 0, 0)
	var n := 0
	for i in verts.size():
		var q := xf * verts[i]
		if Vector2(q.x, q.z).length() > 0.86 and q.y > 0.0 and q.y < 0.12:
			wall += _sample(albedo, uvs[i])
			n += 1
	wall /= maxf(n, 1)
	var best := Vector2.ZERO
	var best_score := INF
	var steps := 48
	for gy in steps:
		for gx in steps:
			var o := Vector2(gx, gy) / steps
			if o.x + PATCH > 1.0 or o.y + PATCH > 1.0:
				continue
			var mean := Color(0, 0, 0)
			var var_sum := 0.0
			var glow := 0.0
			var samples := []
			for sy in 4:
				for sx in 4:
					var uv := o + Vector2(sx + 0.5, sy + 0.5) / 4.0 * PATCH
					var c := _sample(albedo, uv)
					samples.append(c)
					mean += c
					var e := _sample(emissive, uv)
					glow = maxf(glow, e.r + e.g + e.b)
			if glow > 0.03:
				continue
			mean /= 16.0
			for c in samples:
				var_sum += (c.r - mean.r) ** 2 + (c.g - mean.g) ** 2 + (c.b - mean.b) ** 2
			var score := absf(mean.r - wall.r) + absf(mean.g - wall.g) + absf(mean.b - wall.b) + var_sum * 2.0
			if mean.r + mean.g + mean.b < 0.02:
				continue  # empty atlas space
			if score < best_score:
				best_score = score
				best = o
	print("pad wall colour ", wall, " (", n, " verts), best patch score ", best_score)
	return best


func _sample(img: Image, uv: Vector2) -> Color:
	var x := clampi(int(uv.x * img.get_width()), 0, img.get_width() - 1)
	var y := clampi(int(uv.y * img.get_height()), 0, img.get_height() - 1)
	return img.get_pixel(x, y)
