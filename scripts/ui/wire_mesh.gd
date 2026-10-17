class_name WireMesh
extends RefCounted
## The glitchy main menu's character preview merging in and out of its wire
## mesh (owner asked). Every mesh under the model gets a line copy - its
## crease edges (and open edges): line art like the glitch video's, not
## every edge of a 58k-triangle mesh - bound to the same skeleton and skin,
## so it moves with the model, drawn with wire_line.gdshader; the original
## gets an overlay (wire_hide.gdshader) that paints the body out where the
## wire shows. Both read the same dissolve uniforms (`set_all`). (One view
## draws both: this renderer poses a skinned mesh per view, and a second
## view of only the copies drew them unposed.)

const LINE_SHADER := preload("res://scripts/ui/wire_line.gdshader")
const HIDE_SHADER := preload("res://scripts/ui/wire_hide.gdshader")
## Edges kept where the surface bends at least this much (degrees).
static var crease_deg := 45.0

static var _cache := {}  # source Mesh -> line ArrayMesh


## Give every MeshInstance3D under `root` a wire copy in `color` and the
## paint-out overlay. Returns the two materials [line, overlay].
static func add_to(root: Node, color: Color, hide_color := Color(0.03, 0.09, 0.11)) -> Array:
	var line := ShaderMaterial.new()
	line.shader = LINE_SHADER
	line.set_shader_parameter("color", color)
	line.render_priority = 10
	var hide := ShaderMaterial.new()
	hide.shader = HIDE_SHADER
	hide.set_shader_parameter("hide_color", hide_color)
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.has_meta(&"wire_copy"):
			continue
		mi.material_overlay = hide
		var lines := lines_of(mi.mesh)
		if lines == null:
			continue
		var w := MeshInstance3D.new()
		w.name = String(mi.name) + "_Wire"
		w.set_meta(&"wire_copy", true)
		w.mesh = lines
		w.material_override = line
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.transform = mi.transform
		mi.get_parent().add_child(w)
		if mi.skin:
			w.skin = mi.skin
		var sk := mi.get_node_or_null(mi.skeleton)
		if sk:
			w.skeleton = w.get_path_to(sk)
	return [line, hide]


## Set a dissolve uniform on every material in `mats`.
static func set_all(mats: Array, param: StringName, value: Variant) -> void:
	for m in mats:
		(m as ShaderMaterial).set_shader_parameter(param, value)


## `mesh` as lines: each triangle edge once, same vertices (and bones /
## weights, so it can be skinned). Null if it has no triangles.
static func lines_of(mesh: Mesh) -> ArrayMesh:
	if _cache.has(mesh):
		return _cache[mesh]
	var out := ArrayMesh.new()
	for si in mesh.get_surface_count():
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		# Edges by welded position (UV seams split vertices); kept where the
		# surface creases (the two faces' normals more than `crease_deg`
		# apart) or open (one face) - line art, like the video's crease
		# edges, not every edge of a 58k-triangle mesh (a solid blur).
		var weld := {}
		var wid := PackedInt32Array()
		wid.resize(verts.size())
		for i in verts.size():
			var key := verts[i].snapped(Vector3.ONE * 0.0005)
			if not weld.has(key):
				weld[key] = weld.size()
			wid[i] = weld[key]
		var n := weld.size()
		var first := {}  # edge -> [a, b, face normal]
		var lines := PackedInt32Array()
		var cos_max := cos(deg_to_rad(crease_deg))
		for t in range(0, idx.size() - 2, 3):
			var p0 := verts[idx[t]]
			var fn := (verts[idx[t + 1]] - p0).cross(verts[idx[t + 2]] - p0)
			if fn.length_squared() < 1e-14:
				continue
			fn = fn.normalized()
			for e in 3:
				var a := idx[t + e]
				var b := idx[t + (e + 1) % 3]
				var wa := wid[a]
				var wb := wid[b]
				if wa == wb:
					continue
				var k := mini(wa, wb) * n + maxi(wa, wb)
				var f = first.get(k)
				if f == null:
					first[k] = [a, b, fn]
				elif f is Array:
					if (f[2] as Vector3).dot(fn) < cos_max:
						lines.append(f[0])
						lines.append(f[1])
					first[k] = true  # paired
		for k in first:
			var f = first[k]
			if f is Array:  # open edge
				lines.append(f[0])
				lines.append(f[1])
		if lines.is_empty():
			continue
		var la := []
		la.resize(Mesh.ARRAY_MAX)
		la[Mesh.ARRAY_VERTEX] = verts
		la[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]  # (the GPU skinning pass wants them)
		la[Mesh.ARRAY_INDEX] = lines
		if arrays[Mesh.ARRAY_BONES] != null and arrays[Mesh.ARRAY_WEIGHTS] != null:
			la[Mesh.ARRAY_BONES] = arrays[Mesh.ARRAY_BONES]
			la[Mesh.ARRAY_WEIGHTS] = arrays[Mesh.ARRAY_WEIGHTS]
		var flags := 0
		if arrays[Mesh.ARRAY_BONES] != null and arrays[Mesh.ARRAY_BONES].size() == verts.size() * 8:
			flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, la, [], {}, flags)
	if out.get_surface_count() == 0:
		out = null
	_cache[mesh] = out
	return out
