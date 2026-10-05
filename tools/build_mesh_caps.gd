extends SceneTree
## Finds the open holes (boundary loops) in a model's meshes and writes a
## MeshCaps resource with a minimal cap for each:
##   godot --headless --path . -s tools/build_mesh_caps.gd
## Vertices are welded by position first (UV/normal seams aren't holes), all
## surfaces of a mesh count together (a hole already closed by another
## surface, e.g. the robot's interior caps, is left alone), and only real
## holes are capped: closed loops of >= MIN_EDGES edges, roughly flat, of a
## sensible size. Each cap is a shallow fan (centre slightly recessed, like a
## socket), both windings, skinned like its rim.

const MIN_EDGES := 5
const MIN_RADIUS := 0.01
const MAX_RADIUS := 0.25
## Max distance of rim points from the best plane, relative to the radius.
const MAX_BEND := 0.6
## How far the centre sits back into the hole (fraction of the radius).
const RECESS := 0.18
## Existing cap triangles reaching further than this outside the mesh's
## other surfaces' bounds are dropped (stray spikes in authored caps).
const STRAY_MARGIN := 0.012

## [model, output, cap surface material hint ("" = surface 0), UV for caps,
##  opaque material hint]
const MODELS := [
	["res://assets/characters/grinch/grinch.glb", "res://assets/characters/grinch/grinch_caps.res", "", Vector2(0.7422, 0.584), ""],
	["res://assets/characters/robot/robot_enemy.glb", "res://assets/characters/robot/robot_caps.res", "Interior", Vector2.ZERO, "Interior"],
]


func _init() -> void:
	for m in MODELS:
		var scene: Node = (load(m[0]) as PackedScene).instantiate()
		var res := MeshCaps.new()
		res.opaque_material_hint = m[4]
		var total := 0
		for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			var cap := _caps_for(mi.mesh as ArrayMesh, m[2], m[3], mi)
			if not cap.is_empty():
				res.caps[mi.name] = cap
				total += (cap.indices as PackedInt32Array).size() / 3
				print("%s: %s -> %d holes, %d triangles, %d stray triangles dropped" % [m[0].get_file(), mi.name, cap.holes, (cap.indices as PackedInt32Array).size() / 3, (cap.drop as PackedInt32Array).size()])
		ResourceSaver.save(res, m[1], ResourceSaver.FLAG_COMPRESS)
		print("%s: %d cap triangles -> %s" % [m[0].get_file(), total, m[1]])
		scene.free()
	quit()


## Rest-pose skinned position of vertex `i` of surface arrays `a` (what is
## actually drawn); mesh space if the mesh isn't skinned.
func _skinned(mi: MeshInstance3D, a: Array, i: int) -> Vector3:
	var v: Vector3 = a[Mesh.ARRAY_VERTEX][i]
	var sk := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	if sk == null or mi.skin == null or a[Mesh.ARRAY_BONES] == null:
		return v
	var per: int = (a[Mesh.ARRAY_BONES] as PackedInt32Array).size() / (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var out := Vector3.ZERO
	for k in per:
		var w: float = a[Mesh.ARRAY_WEIGHTS][i * per + k]
		if w <= 0.0:
			continue
		var bind: int = a[Mesh.ARRAY_BONES][i * per + k]
		var bn := mi.skin.get_bind_name(bind)
		var bone := sk.find_bone(bn) if bn != "" else mi.skin.get_bind_bone(bind)
		out += (sk.get_bone_global_rest(bone) * mi.skin.get_bind_pose(bind) * v) * w
	return out


func _caps_for(mesh: ArrayMesh, hint: String, uv: Vector2, mi: MeshInstance3D) -> Dictionary:
	if mesh == null:
		return {}
	var target := 0
	if hint != "":
		target = -1
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if mat and mat.resource_name.contains(hint):
				target = s
		if target < 0:
			return {}
	# Stray triangles in the cap surface (authored caps can have spikes that
	# poke out of the part): anything outside the other surfaces' bounds.
	var drop := PackedInt32Array()
	if target >= 0 and mesh.get_surface_count() > 1:
		var main := AABB()
		var first := true
		for s in mesh.get_surface_count():
			if s == target:
				continue
			var sa := mesh.surface_get_arrays(s)
			for i in (sa[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
				var v := _skinned(mi, sa, i)
				if first:
					main = AABB(v, Vector3.ZERO)
					first = false
				else:
					main = main.expand(v)
		main = main.grow(STRAY_MARGIN)
		var ta := mesh.surface_get_arrays(target)
		var ti: PackedInt32Array = ta[Mesh.ARRAY_INDEX]
		var tv := PackedVector3Array()
		for i in (ta[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
			tv.append(_skinned(mi, ta, i))
		for t in range(0, ti.size(), 3):
			if not (main.has_point(tv[ti[t]]) and main.has_point(tv[ti[t + 1]]) and main.has_point(tv[ti[t + 2]])):
				drop.append(t / 3)
	var dropped := {}
	for t in drop:
		dropped[t] = true
	# Gather every surface (welded by position).
	var pos := PackedVector3Array()
	var src := []  # global vertex -> [surface, index]
	var tris := PackedInt32Array()
	var weld := {}
	var wid := PackedInt32Array()
	var rep := {}  # welded id -> global vertex
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var base := pos.size()
		for i in v.size():
			pos.append(v[i])
			src.append([s, i])
			var k := Vector3i(roundi(v[i].x * 1e5), roundi(v[i].y * 1e5), roundi(v[i].z * 1e5))
			if not weld.has(k):
				weld[k] = weld.size()
				rep[weld[k]] = base + i
			wid.append(weld[k])
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			if s == target and dropped.has(t / 3):
				continue
			for k in 3:
				tris.append(wid[base + idx[t + k]])
	# Edge use counts and directed edges.
	var count := {}
	var directed := {}
	for t in range(0, tris.size(), 3):
		var tri := [tris[t], tris[t + 1], tris[t + 2]]
		if tri[0] == tri[1] or tri[1] == tri[2] or tri[0] == tri[2]:
			continue
		for e in 3:
			var u: int = tri[e]
			var w: int = tri[(e + 1) % 3]
			var key := Vector2i(mini(u, w), maxi(u, w))
			count[key] = count.get(key, 0) + 1
			directed[Vector2i(u, w)] = true
	var nxt := {}
	for key: Vector2i in count:
		if count[key] != 1:
			continue
		var d := key if directed.has(key) else Vector2i(key.y, key.x)
		if not nxt.has(d.x):
			nxt[d.x] = []
		nxt[d.x].append(d.y)
	# Walk boundary loops.
	var used := {}
	var loops := []
	for st in nxt:
		for first in nxt[st]:
			if used.has(Vector2i(st, first)):
				continue
			var loop := [st]
			var u: int = st
			var w: int = first
			while true:
				used[Vector2i(u, w)] = true
				if w == st or loop.size() > 4000:
					break
				loop.append(w)
				var cand := []
				for x in nxt.get(w, []):
					if not used.has(Vector2i(w, x)):
						cand.append(x)
				if cand.is_empty():
					break
				u = w
				w = cand[0]
			if w == st and loop.size() >= MIN_EDGES:
				loops.append(loop)
	if loops.is_empty() and drop.is_empty():
		return {}
	var tgt := mesh.surface_get_arrays(target if target >= 0 else 0)
	var cap := {"surface": target, "vertices": PackedVector3Array(), "normals": PackedVector3Array(), "uv": uv,
		"bones": PackedInt32Array(), "weights": PackedFloat32Array(), "bones_per_vertex": 4, "indices": PackedInt32Array(), "holes": 0,
		"drop": drop}
	var all_arrays := []
	for s in mesh.get_surface_count():
		all_arrays.append(mesh.surface_get_arrays(s))
	var per := 4
	if tgt[Mesh.ARRAY_BONES] != null:
		per = (tgt[Mesh.ARRAY_BONES] as PackedInt32Array).size() / (tgt[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	cap.bones_per_vertex = per
	for loop in loops:
		var pts: Array[Vector3] = []
		for w in loop:
			pts.append(pos[rep[w]])
		var c := Vector3.ZERO
		for p in pts:
			c += p
		c /= pts.size()
		# Newell normal and size.
		var nrm := Vector3.ZERO
		var r := 0.0
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			nrm += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
			r += a.distance_to(c)
		r /= pts.size()
		if nrm.length() < 1e-9 or r < MIN_RADIUS or r > MAX_RADIUS:
			continue
		nrm = nrm.normalized()
		var bend := 0.0
		for p in pts:
			bend = maxf(bend, absf((p - c).dot(nrm)))
		if bend / r > MAX_BEND:
			continue
		# Outward: away from the mesh's nearby bulk.
		var near := Vector3.ZERO
		var nn := 0
		for i in range(0, pos.size(), 7):
			if pos[i].distance_to(c) < r * 3.0:
				near += pos[i]
				nn += 1
		var out := nrm
		if nn > 0 and (c - near / nn).dot(nrm) < 0.0:
			out = -nrm
		var centre := c - out * r * RECESS
		# Skin data: each rim vertex keeps its own; the centre copies the
		# rim's most common vertex.
		var rim_bw := []
		for w in loop:
			var g: Array = src[rep[w]]
			var a: Array = all_arrays[g[0]]
			var bw := [PackedInt32Array(), PackedFloat32Array()]
			if a[Mesh.ARRAY_BONES] != null:
				var sp: int = (a[Mesh.ARRAY_BONES] as PackedInt32Array).size() / (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				for k in per:
					bw[0].append(a[Mesh.ARRAY_BONES][g[1] * sp + k] if k < sp else 0)
					bw[1].append(a[Mesh.ARRAY_WEIGHTS][g[1] * sp + k] if k < sp else 0.0)
			rim_bw.append(bw)
		for side in 2:
			var nside := out if side == 0 else -out
			var base: int = cap.vertices.size()
			cap.vertices.append(centre)
			cap.normals.append(nside)
			_skin(cap, rim_bw[0], per)
			for i in pts.size():
				cap.vertices.append(pts[i])
				cap.normals.append(nside)
				_skin(cap, rim_bw[i], per)
			for i in pts.size():
				var a := base + 1 + i
				var b := base + 1 + (i + 1) % pts.size()
				# Godot front faces are clockwise: pick the order whose face
				# normal points along nside.
				var pa: Vector3 = cap.vertices[a]
				var pb: Vector3 = cap.vertices[b]
				var face := (pb - centre).cross(pa - centre)
				if face.dot(nside) >= 0.0:
					cap.indices.append_array([base, a, b])
				else:
					cap.indices.append_array([base, b, a])
		cap.holes += 1
	if cap.holes == 0 and drop.is_empty():
		return {}
	return cap


func _skin(cap: Dictionary, bw: Array, per: int) -> void:
	if (bw[0] as PackedInt32Array).is_empty():
		for k in per:
			cap.bones.append(0)
			cap.weights.append(1.0 if k == 0 else 0.0)
		return
	cap.bones.append_array(bw[0])
	cap.weights.append_array(bw[1])
