class_name LaserGateFX
extends Node3D
## A laser gate's look (owner asked: "make the laser gates look amazingly
## better"). Built over the level's own gate (the map maker's beams - its
## `<group>__laser` mesh - are read for where each beam runs, then made
## invisible; the blocker and the gate's frame are unchanged):
##   - every beam: a camera-facing ribbon with a white-hot core in a red
##     glow, energy pulses racing along it, a fast flicker
##     (laser_beam.gdshader);
##   - a star-spiked flare at both ends of each beam (laser_flare.gdshader)
##     and sparks spitting from the emitters;
##   - a faint hexagon force field with sweeping scan lines between the
##     beams (laser_field.gdshader);
##   - a player pressing into it: sparks and a flare where they touch;
##   - opening (`open()`): the beams overload, flash white-hot and collapse
##     to nothing with a burst of sparks, the field wipes away.

const BEAM_SHADER := preload("res://scripts/vfx/laser_beam.gdshader")
const FLARE_SHADER := preload("res://scripts/vfx/laser_flare.gdshader")
const FIELD_SHADER := preload("res://scripts/vfx/laser_field.gdshader")

## Beams found (tests): [start, end] world points.
var beams: Array = []
var opened := false
var _beam_mat: ShaderMaterial
var _flare_mat: ShaderMaterial
var _field_mat: ShaderMaterial
var _beam_mesh: MeshInstance3D
var _flare_mesh: MeshInstance3D
var _sparks: CPUParticles3D
var _burst: CPUParticles3D
var _touch: CPUParticles3D
var _plane_n := Vector3.FORWARD
var _plane_o := Vector3.ZERO
var _rect := AABB()
var _open_t := -1.0
var _touch_cd := 0.0


## Build the look for the gate whose beams are `laser` (the level's merged
## beam mesh), and make that mesh invisible.
func build(laser: MeshInstance3D) -> void:
	beams = find_beams(laser)
	if beams.is_empty():
		return
	var hide := StandardMaterial3D.new()
	hide.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hide.albedo_color = Color(0, 0, 0, 0)
	hide.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	laser.material_override = hide
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = BEAM_SHADER
	_flare_mat = ShaderMaterial.new()
	_flare_mat.shader = FLARE_SHADER
	var lo := Vector3.INF
	var hi := -Vector3.INF
	var ends := PackedVector3Array()
	# All the beams in one mesh, all the flares in another (one draw each).
	var bv := PackedVector3Array()
	var buv := PackedVector2Array()
	var bc := PackedFloat32Array()
	var fv := PackedVector3Array()
	var fuv := PackedVector2Array()
	var fc := PackedFloat32Array()
	var len := 0.0
	var i := 0
	for b in beams:
		var a: Vector3 = b[0]
		var e: Vector3 = b[1]
		len = maxf(len, a.distance_to(e))
		var mid := (a + e) * 0.5
		_quad(bv, buv, bc, [a, e, e, a], mid, float(i) * 1.37)
		for p in [a, e]:
			_quad(fv, fuv, fc, [p, p, p, p], p, float(ends.size()) * 0.77)
			ends.append(p)
		lo = lo.min(a.min(e))
		hi = hi.max(a.max(e))
		i += 1
	_beam_mat.set_shader_parameter("length", len)
	_beam_mat.set_shader_parameter("axis", (beams[0][1] - beams[0][0]).normalized())
	_beam_mesh = _mesh_node("Beams", bv, buv, bc, _beam_mat)
	_flare_mesh = _mesh_node("Flares", fv, fuv, fc, _flare_mat)
	# The force field between the beams.
	var a0: Vector3 = beams[0][0]
	var e0: Vector3 = beams[0][1]
	var along := (e0 - a0).normalized()
	_plane_n = along.cross(Vector3.UP).normalized()
	_rect = AABB(lo, hi - lo)
	var mid := (lo + hi) * 0.5
	_plane_o = mid
	var field := MeshInstance3D.new()
	field.name = "Field"
	var fq2 := QuadMesh.new()
	var w := a0.distance_to(e0)
	var h := hi.y - lo.y + 0.6
	fq2.size = Vector2(w, h)
	field.mesh = fq2
	_field_mat = ShaderMaterial.new()
	_field_mat.shader = FIELD_SHADER
	_field_mat.set_shader_parameter("size", Vector2(w, h))
	field.material_override = _field_mat
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	field.transform = Transform3D(Basis(along, Vector3.UP, _plane_n), mid)
	add_child(field)
	# Sparks spitting from the emitters.
	_sparks = _spark_emitter("Sparks", 26, 0.5, 1.0)
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	_sparks.emission_points = ends
	_burst = _spark_emitter("Burst", 160, 0.9, 1.6)
	_burst.one_shot = true
	_burst.emitting = false
	_burst.explosiveness = 0.9
	_burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	_burst.emission_points = ends
	_touch = _spark_emitter("Touch", 40, 0.45, 1.3)
	_touch.one_shot = true
	_touch.emitting = false
	_touch.explosiveness = 1.0


## A quad: corners `c` (bottom-left, bottom-right, top-right, top-left),
## UVs 0..1, CUSTOM0 = centre + seed on every corner.
func _quad(v: PackedVector3Array, uv: PackedVector2Array, cu: PackedFloat32Array, c: Array, centre: Vector3, sd: float) -> void:
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for k in [0, 1, 2, 0, 2, 3]:
		v.append(c[k])
		uv.append(uvs[k])
		cu.append_array([centre.x, centre.y, centre.z, sd])


func _mesh_node(nm: String, v: PackedVector3Array, uv: PackedVector2Array, cu: PackedFloat32Array, mat: ShaderMaterial) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_CUSTOM0] = cu
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 3.0
	add_child(mi)
	return mi


func _spark_emitter(nm: String, amount: int, life: float, speed: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = nm
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 1.5 * speed
	p.initial_velocity_max = 4.0 * speed
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1.0, 0.55, 0.45)
	m.albedo_texture = _spark_tex()
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.85))
	g.set_color(1, Color(1.0, 0.05, 0.1, 0.0))
	p.color_ramp = g
	p.local_coords = false
	add_child(p)
	return p


static var _tex: Texture2D


## A soft round spark (radial white -> clear).
static func _spark_tex() -> Texture2D:
	if _tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 32
		t.height = 32
		_tex = t
	return _tex


## Beams of a gate's merged laser mesh: its vertices grouped by height, each
## group's ends along the gate's long side. [[start, end], ...], bottom up.
static func find_beams(laser: MeshInstance3D) -> Array:
	if laser == null or laser.mesh == null:
		return []
	var pts := PackedVector3Array()
	for s in laser.mesh.get_surface_count():
		for v in laser.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			pts.append(laser.global_transform * v)
	if pts.is_empty():
		return []
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	var along_x := box.size.x >= box.size.z
	var sorted := Array(pts)
	sorted.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)
	var groups: Array = []
	var cur: Array = []
	for p in sorted:
		if not cur.is_empty() and p.y - (cur.back() as Vector3).y > 0.35:
			groups.append(cur)
			cur = []
		cur.append(p)
	if not cur.is_empty():
		groups.append(cur)
	var out: Array = []
	var span := box.size.x if along_x else box.size.z
	for g in groups:
		var lo := INF
		var hi := -INF
		var y := 0.0
		var other := 0.0
		for p: Vector3 in g:
			var t := p.x if along_x else p.z
			lo = minf(lo, t)
			hi = maxf(hi, t)
			y += p.y
			other += p.z if along_x else p.x
		y /= g.size()
		other /= g.size()
		if hi - lo < span * 0.6:  # (caps / stubs, not a beam)
			continue
		if along_x:
			out.append([Vector3(lo, y, other), Vector3(hi, y, other)])
		else:
			out.append([Vector3(other, y, lo), Vector3(other, y, hi)])
	return out


## The gate opens: overload, white flash, collapse, sparks.
func open() -> void:
	if opened:
		return
	opened = true
	_open_t = 0.0
	if _sparks:
		_sparks.emitting = false


func _process(delta: float) -> void:
	if beams.is_empty():
		return
	if _open_t >= 0.0:
		_open_t += delta
		var t := _open_t
		var inten := 1.0
		var thin := 1.0
		if t < 0.45:  # overload: brighter, faster flicker
			inten = 1.0 + 2.2 * (t / 0.45) * (0.75 + 0.25 * sin(t * 90.0))
		elif t < 0.8:  # flash and collapse
			var k := (t - 0.45) / 0.35
			inten = 3.2 * (1.0 - k) + 0.2
			thin = (1.0 - k) * (1.0 - k) * 1.6
			if _burst and not _burst.emitting and k < 0.2:
				_burst.restart()
				_burst.emitting = true
		else:
			inten = 0.0
			thin = 0.0
		_beam_mat.set_shader_parameter("intensity", inten)
		_beam_mat.set_shader_parameter("thin", thin)
		_flare_mat.set_shader_parameter("intensity", inten)
		_flare_mat.set_shader_parameter("size", (1.4 + 1.6 * clampf(t / 0.6, 0.0, 1.0)) * (1.0 if t < 0.8 else maxf(0.0, 1.0 - (t - 0.8) * 4.0)))
		_field_mat.set_shader_parameter("wipe", clampf(t / 0.7, 0.0, 1.0))
		_field_mat.set_shader_parameter("intensity", maxf(0.0, 1.0 + 1.5 * sin(minf(t, 0.45) / 0.45 * PI)))
		if t > 2.5:
			queue_free()
		return
	# Players pressing into the beams: sparks and a flare where they touch.
	_touch_cd -= delta
	if _touch_cd > 0.0:
		return
	for p in get_tree().get_nodes_in_group(&"players"):
		var n := p as Node3D
		if n == null:
			continue
		var at := n.global_position + Vector3.UP * 1.0
		var d := (at - _plane_o).dot(_plane_n)
		if absf(d) > 0.9:
			continue
		var on := at - _plane_n * d
		if on.y < _rect.position.y - 0.5 or on.y > _rect.end.y + 0.5:
			continue
		if on.x < _rect.position.x - 0.5 or on.x > _rect.end.x + 0.5 or on.z < _rect.position.z - 0.5 or on.z > _rect.end.z + 0.5:
			continue
		_touch.global_position = on
		_touch.restart()
		_touch.emitting = true
		_touch_cd = 0.35
		break
