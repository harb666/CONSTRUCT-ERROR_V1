class_name MeshCaps
extends Resource
## Small end caps that seal open holes in a model's meshes (cut / removed
## parts: the player's hand-less gauntlets, a robot's separated sections),
## so you can't see through them. Made offline by tools/build_mesh_caps.gd
## from the model (the source GLB is never modified): a shallow fan per hole,
## skinned like the hole's rim, using an existing material and a dark texel
## of the existing texture. `apply()` merges them into an existing surface of
## each mesh (no extra draw calls, LODs kept) and shares the result between
## every instance of the model.
##
## It also replaces transparent "interior" materials (the robot's own
## Hidden_Dark_Mechanical_Interior caps, authored invisible) by an opaque
## copy, so the model's built-in caps actually seal its cut sections.

## Mesh node name -> {"surface": int, "vertices", "normals", "uv": Vector2,
## "bones", "weights", "bones_per_vertex": int, "indices", "drop"} (mesh
## space; "drop" = stray triangles of that surface to remove).
@export var caps := {}
## Surfaces whose material name contains this become opaque ("" = none).
@export var opaque_material_hint := ""

static var _cache := {}
static var _opaque := {}


## Seal every matching mesh under `root`. Returns how many meshes changed.
func apply(root: Node) -> int:
	var n := 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if not (mi.mesh is ArrayMesh):
			continue
		var key := "%s|%d" % [resource_path, mi.mesh.get_instance_id()]
		if not _cache.has(key):
			_cache[key] = _build(mi.mesh as ArrayMesh, caps.get(mi.name, {}))
		if _cache[key] != mi.mesh:
			mi.mesh = _cache[key]
			n += 1
	return n


func _build(src: ArrayMesh, cap: Dictionary) -> ArrayMesh:
	var touch_materials := false
	if opaque_material_hint != "":
		for s in src.get_surface_count():
			var m := src.surface_get_material(s)
			if m and m.resource_name.contains(opaque_material_hint):
				touch_materials = true
	if cap.is_empty() and not touch_materials:
		return src
	var out := ArrayMesh.new()
	out.resource_name = src.resource_name
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var lods := _lods(src, s, (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		if not cap.is_empty() and int(cap.surface) == s:
			var drop: PackedInt32Array = cap.get("drop", PackedInt32Array())
			if not drop.is_empty():
				# Stray triangles out; this (small) surface's LODs aren't
				# worth keeping then.
				arrays[Mesh.ARRAY_INDEX] = _without(arrays[Mesh.ARRAY_INDEX], drop)
				lods = {}
			var base := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			_append(arrays, cap, base)
			var extra := PackedInt32Array()
			for i: int in cap.indices:
				extra.append(i + base)
			for d in lods:
				lods[d] = (lods[d] as PackedInt32Array) + extra
		var flags := src.surface_get_format(s) & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS | Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), arrays, [], lods, flags)
		out.surface_set_name(s, src.surface_get_name(s))
		out.surface_set_material(s, _material(src.surface_get_material(s)))
	return out


## Existing LOD index buffers of a surface (as edge length -> indices).
static func _lods(src: ArrayMesh, s: int, vertex_count: int) -> Dictionary:
	var out := {}
	var sd := RenderingServer.mesh_get_surface(src.get_rid(), s)
	for l: Dictionary in sd.get("lods", []):
		var bytes: PackedByteArray = l.index_data
		var idx := PackedInt32Array()
		if vertex_count <= 65535:
			idx.resize(bytes.size() / 2)
			for i in idx.size():
				idx[i] = bytes.decode_u16(i * 2)
		else:
			idx = bytes.to_int32_array()
		out[l.edge_length] = idx
	return out


static func _without(idx: PackedInt32Array, drop: PackedInt32Array) -> PackedInt32Array:
	var gone := {}
	for t in drop:
		gone[t] = true
	var out := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if not gone.has(t / 3):
			out.append(idx[t])
			out.append(idx[t + 1])
			out.append(idx[t + 2])
	return out


static func _append(arrays: Array, cap: Dictionary, base: int) -> void:
	var verts: PackedVector3Array = cap.vertices
	var n := verts.size()
	arrays[Mesh.ARRAY_VERTEX] = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array) + verts
	if arrays[Mesh.ARRAY_NORMAL] != null:
		arrays[Mesh.ARRAY_NORMAL] = (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array) + (cap.normals as PackedVector3Array)
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var t := PackedFloat32Array()
		t.resize(n * 4)
		for i in n:
			var nm: Vector3 = cap.normals[i]
			var tg := nm.cross(Vector3.UP if absf(nm.y) < 0.9 else Vector3.RIGHT).normalized()
			t[i * 4] = tg.x
			t[i * 4 + 1] = tg.y
			t[i * 4 + 2] = tg.z
			t[i * 4 + 3] = 1.0
		arrays[Mesh.ARRAY_TANGENT] = (arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array) + t
	for k in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if arrays[k] != null:
			var uv := PackedVector2Array()
			uv.resize(n)
			uv.fill(cap.uv)
			arrays[k] = (arrays[k] as PackedVector2Array) + uv
	if arrays[Mesh.ARRAY_COLOR] != null:
		var c := PackedColorArray()
		c.resize(n)
		c.fill(Color.WHITE)
		arrays[Mesh.ARRAY_COLOR] = (arrays[Mesh.ARRAY_COLOR] as PackedColorArray) + c
	if arrays[Mesh.ARRAY_BONES] != null:
		var per := (arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size() / base
		arrays[Mesh.ARRAY_BONES] = (arrays[Mesh.ARRAY_BONES] as PackedInt32Array) + _restride(cap.bones, int(cap.bones_per_vertex), per, n)
		arrays[Mesh.ARRAY_WEIGHTS] = (arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array) + _restride(cap.weights, int(cap.bones_per_vertex), per, n)
	arrays[Mesh.ARRAY_INDEX] = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array) + _offset(cap.indices, base)


static func _restride(src, from: int, to: int, n: int):
	if from == to:
		return src
	var out = PackedInt32Array() if src is PackedInt32Array else PackedFloat32Array()
	out.resize(n * to)
	for i in n:
		for k in mini(from, to):
			out[i * to + k] = src[i * from + k]
	return out


static func _offset(idx: PackedInt32Array, base: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(idx.size())
	for i in idx.size():
		out[i] = idx[i] + base
	return out


## Opaque copy of a transparent interior material (shared).
func _material(m: Material) -> Material:
	if m == null or opaque_material_hint == "" or not m.resource_name.contains(opaque_material_hint):
		return m
	if not _opaque.has(m):
		var o := m.duplicate() as Material
		if o is BaseMaterial3D:
			var b := o as BaseMaterial3D
			b.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			b.albedo_color.a = 1.0
			b.cull_mode = BaseMaterial3D.CULL_DISABLED
		_opaque[m] = o
	return _opaque[m]
