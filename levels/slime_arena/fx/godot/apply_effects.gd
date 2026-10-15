extends Node3D
## image-to-level Stage 4 runtime starter for Godot 4 (UNTESTED in Godot here - treat as a starting point).
## Recreates effects.json on an imported level: liquid shaders, emission pulses/flicker, particles, mist sheets, sky drift.
## Setup: put the level folder at res://levels/<name>/, instance level.glb (and background.glb), add a Node3D at the
## world origin with this script, assign level_root (the instanced level.glb) and optionally environment.
## Particles use CPUParticles3D so they work in the Mobile and Compatibility renderers.
## kill_below_spawn (splash): droplets falling back are simply hidden by the opaque liquid surface here.

@export_file("*.json") var effects_path: String = "res://levels/toxic_arena/effects.json"
@export_enum("off", "performance", "balanced", "quality") var quality: String = "balanced"
@export var level_root: Node3D
@export var environment: WorldEnvironment

var _base_dir: String = ""
var _anims: Array = []    # [material, base_energy, params, kind, next_change]
var _bursts: Array = []   # [CPUParticles3D, time_left, interval_min, interval_max]
var _sky_speed: float = 0.0
var _t: float = 0.0


var _spins: Array = []  # [rotor node, rad/s]
var _travel: Array = []  # [node, rest position, speed m/s, spacing m] (Stage 43: barrels up the column bores)
var _launch: Array = []  # [node, rest position, speed, period, phase, travel] (Stage 49: pods shooting up the columns)


func _ready() -> void:
	if quality == "off":
		return
	_base_dir = effects_path.get_base_dir()
	# Construct Error: the mobile effects file lives in mobile/, the fx
	# textures / shaders and environment.json in the level folder above it.
	if _base_dir.ends_with("/mobile"):
		_base_dir = _base_dir.get_base_dir()
	var data = JSON.parse_string(FileAccess.get_file_as_string(effects_path))
	if data == null:
		push_error("effects.json missing or invalid: " + effects_path)
		return
	for fx in data["effects"]:
		var q: Dictionary = fx["quality"][quality]
		if not q["enabled"]:
			continue
		var p: Dictionary = q["params"]
		match fx["category"]:
			"surface_shader":
				_surface(fx, p)
			"material_animation":
				_material_anim(fx, p)
			"material_shader":  # Stage 26: tv_static on screen materials
				_material_shader(fx, p)
			"light":  # Stage 39: soft coloured lights (ceiling fans) - no shadows, mobile friendly
				for e in fx.get("emitters", []):
					var l := OmniLight3D.new()
					l.light_color = Color(p["color"][0], p["color"][1], p["color"][2])
					l.light_energy = float(p["energy"])
					l.omni_range = float(p["range"])
					l.shadow_enabled = false
					add_child(l)
					l.global_position = Vector3(e["pos"][0], e["pos"][1], e["pos"][2])
			"tube_bubbles":  # Stage 48: bubbles up the vat / column tubes (one shader-animated mesh)
				_bubbles(fx, p)
			"particles":
				_particles(fx, p)
			"transparent_mesh":
				_fog_sheet(fx, p)
			"cloud_layer":
				_cloud_layer(fx, p)
			"billboards":
				_cloud_puffs(fx, p)
			"flyby":
				_flyby(fx, p)
			"environment":
				_sky_speed = deg_to_rad(float(p.get("speed_deg_s", 0.0)))
			"launch":  # Stage 49: each entry's nodes wait, shoot up `travel` m at `speed`, repeat every `period` s (own phase)
				for l in fx.get("launches", []):
					for n in l.get("targets", []):
						var nd := level_root.find_child(String(n), true, false) as Node3D
						if nd != null:
							_launch.append([nd, nd.position, float(p["speed"]), float(l["period"]), float(l["phase"]), float(l["travel"])])
			"translate_loop":  # Stage 43: move up by fmod(t * speed, spacing), all targets in step (wraps out of sight)
				for n in fx.get("targets", []):
					var nd := level_root.find_child(String(n), true, false) as Node3D
					if nd != null:
						_travel.append([nd, nd.position, float(p["speed"]), float(p["spacing"])])
			"transform_animation":  # spinning fan rotors (own nodes; origin = rotor centre, local +y = axis)
				for n in fx.get("targets", []):
					var nd := level_root.find_child(String(n), true, false) as Node3D
					if nd != null:
						_spins.append([nd, float(fx.get("speeds", {}).get(n, p.get("speed_rpm", 20.0))) * TAU / 60.0])


func _mesh(node_name: String) -> MeshInstance3D:
	if level_root == null:
		return null
	return level_root.find_child(node_name, true, false) as MeshInstance3D


func _surface(fx: Dictionary, p: Dictionary) -> void:
	var file := "liquid_surface.gdshader" if fx["type"] == "liquid_surface" else "liquid_flow.gdshader"
	var shader: Shader = load(_base_dir + "/fx/godot/" + file)
	for n in fx.get("targets", []):
		var mi := _mesh(n)
		if mi == null:
			continue
		var src := mi.get_active_material(0) as BaseMaterial3D
		var sm := ShaderMaterial.new()
		sm.shader = shader
		if src:
			sm.set_shader_parameter("albedo_tex", src.albedo_texture)
		if fx["type"] == "liquid_surface":
			sm.set_shader_parameter("scroll", Vector2(p["scroll"][0], p["scroll"][1]))
			sm.set_shader_parameter("swirl", p["swirl"])
			sm.set_shader_parameter("pulse_speed", p["pulse_speed"])
			sm.set_shader_parameter("pulse_amount", p["pulse_amount"])
			var rp: Array = []  # Stage 49: ripple points [x, z, amplitude, radius]
			for q in fx.get("ripples", []):
				rp.append(Vector4(q[0], q[1], q[2], q[3]))
			sm.set_shader_parameter("ripple_points", rp)
			sm.set_shader_parameter("ripple_count", rp.size())
			sm.set_shader_parameter("ripple", float(p.get("ripple", 1.0)))
			sm.set_shader_parameter("drops", float(p.get("drops", 1.0)))
			var rc: Array = p.get("ripple_color", [0.92, 1.0, 0.7])
			sm.set_shader_parameter("ripple_color", Color(rc[0], rc[1], rc[2]))
		else:
			sm.set_shader_parameter("uv_speed", float(p["speed"]) / float(fx.get("material_tile_m", 2.0)))
			sm.set_shader_parameter("wobble", p["wobble"])
			var f: Array = fx.get("flow_uv", [0.0, 1.0])
			sm.set_shader_parameter("flow_dir", Vector2(f[0], f[1]))
		sm.set_shader_parameter("glow_energy", p["glow_energy"])
		mi.material_override = sm


func _material_anim(fx: Dictionary, p: Dictionary) -> void:
	var seen := {}
	var meshes: Array = []
	if fx.has("target_material"):  # works for the dev AND the merged mobile export (node names differ, material names don't)
		for node in level_root.find_children("*", "MeshInstance3D", true, false):
			var mm := (node as MeshInstance3D).get_active_material(0)
			if mm and mm.resource_name.begins_with(fx["target_material"]):
				meshes.append(node)
	else:
		for n in fx.get("targets", []):
			meshes.append(_mesh(n))
	for mi in meshes:
		if mi == null:
			continue
		var m := (mi as MeshInstance3D).get_active_material(0) as BaseMaterial3D
		if m == null or seen.has(m):
			continue
		seen[m] = true
		m.emission_enabled = true
		_anims.append([m, m.emission_energy_multiplier, p, fx["type"], 0.0])


func _bubbles(fx: Dictionary, p: Dictionary) -> void:
	var tubes: Array = fx.get("tubes", [])
	if tubes.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 48
	var verts := PackedVector3Array(); var uvs := PackedVector2Array(); var uv2s := PackedVector2Array()
	var cols := PackedColorArray(); var idx := PackedInt32Array()
	var lo := Vector3(INF, INF, INF); var hi := -lo
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for t in tubes:
		var c := Vector3(t[0], t[1], t[2]); var h := float(t[3]); var r := float(t[4])
		lo = lo.min(c - Vector3(r, 0, r)); hi = hi.max(c + Vector3(r, h + 1.0, r))
		var n := clampi(int(round(float(p["density"]) * h * r)), 12, 140)
		for i in n:
			var seed := Color(rng.randf(), rng.randf(), rng.randf(), rng.randf())
			var b := verts.size()
			for k in 4:
				verts.append(c); uvs.append(corners[k]); uv2s.append(Vector2(h, r)); cols.append(seed)
			idx.append_array(PackedInt32Array([b, b + 1, b + 2, b, b + 2, b + 3]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts; arr[Mesh.ARRAY_TEX_UV] = uvs; arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_COLOR] = cols; arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = load(_base_dir + "/fx/godot/tube_bubbles.gdshader")
	mat.render_priority = -1  # drawn before the tinted glass, so the glass shades them
	for k in ["wobble", "alpha", "nozzles"]:
		mat.set_shader_parameter(k, float(p[k]))
	mat.set_shader_parameter("size_range", Vector2(p["size"][0], p["size"][1]))
	mat.set_shader_parameter("speed_range", Vector2(p["speed"][0], p["speed"][1]))
	mat.set_shader_parameter("tint", Color(p["color"][0], p["color"][1], p["color"][2]))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh; mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(lo, hi - lo)  # vertices sit at the tube bottoms; the shader lifts them
	add_child(mi)


func _material_shader(fx: Dictionary, p: Dictionary) -> void:
	var shader: Shader = load(_base_dir + "/fx/godot/tv_static.gdshader")
	var made := {}  # one ShaderMaterial per source material (merged mobile cells share it)
	for node in level_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var src := mi.get_active_material(0) as BaseMaterial3D
		if src == null or not src.resource_name.begins_with(String(fx.get("target_material", "?"))):
			continue
		if not made.has(src):
			var sm := ShaderMaterial.new()
			sm.shader = shader
			sm.set_shader_parameter("albedo_tex", src.albedo_texture)
			for k in ["amount", "grain", "fps", "signal_every", "signal_len", "roll_speed", "glow", "seed"]:
				sm.set_shader_parameter(k, float(p[k]))
			for k in ["egg_id", "egg_every", "egg_len"]:  # Stage 52: easter egg on one screen
				if p.has(k):
					sm.set_shader_parameter(k, float(p[k]))
			if p.has("egg_rect"):
				sm.set_shader_parameter("egg_rect", Vector4(p["egg_rect"][0], p["egg_rect"][1], p["egg_rect"][2], p["egg_rect"][3]))
			made[src] = sm
		mi.material_override = made[src]


func _gradient(c: Array, a: float) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(c[0], c[1], c[2], 0.0))
	g.set_color(1, Color(c[0], c[1], c[2], 0.0))
	g.add_point(0.15, Color(c[0], c[1], c[2], a))
	return g


func _particles(fx: Dictionary, p: Dictionary) -> void:
	var tex: Texture2D = load(_base_dir + "/fx/" + str(p["texture"]) + ".png")
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	if p.get("blend", "alpha") == "add":
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var quad := QuadMesh.new()
	quad.material = mat
	var spots: Array = []
	if fx.has("emitters"):
		for e in fx["emitters"]:
			spots.append(e)
	elif fx.has("area"):
		spots.append({"area": fx["area"]})
	if fx.get("merge_emitters", false) and spots.size() > 1:
		# one draw call for the whole effect: a single system emitting from every point
		var pts := PackedVector3Array()
		for e in spots:
			pts.append(Vector3(e["pos"][0], e["pos"][1], e["pos"][2]))
		spots = [{"points": pts}]
	for e in spots:
		var cp := CPUParticles3D.new()
		cp.mesh = quad
		cp.lifetime = float(p["lifetime"])
		if p.has("count"):
			cp.amount = int(p["count"])
			cp.preprocess = cp.lifetime
		elif p.has("burst"):
			cp.amount = int(p["burst"])
			cp.one_shot = true
			cp.explosiveness = 1.0
			cp.emitting = false
			_bursts.append([cp, randf_range(p["interval"][0], p["interval"][1]), p["interval"][0], p["interval"][1]])
		else:
			cp.amount = max(1, int(ceil(float(p["rate"]) * cp.lifetime))) * (e["points"].size() if e.has("points") else 1)
		if e.has("points"):
			cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
			cp.emission_points = e["points"]
		elif e.has("area"):
			var a: Array = e["area"]
			var top: bool = p.has("rate") and not p.has("count")
			var y0: float = a[1] if top else (a[1] + a[4]) * 0.5
			cp.position = Vector3((a[0] + a[3]) * 0.5, y0, (a[2] + a[5]) * 0.5)
			cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			cp.emission_box_extents = Vector3((a[3] - a[0]) * 0.5, 0.05 if top else (a[4] - a[1]) * 0.5, (a[5] - a[2]) * 0.5)
		else:
			cp.position = Vector3(e["pos"][0], e["pos"][1], e["pos"][2])
			var r: float = float(e.get("radius", p.get("radius", 0.0)))
			if r > 0.0:
				cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
				cp.emission_sphere_radius = r
		cp.direction = Vector3(0, 1, 0)
		cp.spread = float(p.get("spread", 15))
		cp.initial_velocity_min = float(p["speed"][0])
		cp.initial_velocity_max = float(p["speed"][1])
		var wind: Array = p.get("wind", [0, 0, 0])
		cp.gravity = Vector3(wind[0], float(p.get("gravity", 0.0)), wind[2])
		var s0: float = float(p["size"][0])
		var s1: float = float(p["size"][1])
		var smax: float = max(s0, s1)
		cp.scale_amount_min = smax
		cp.scale_amount_max = smax
		var cv := Curve.new()
		cv.add_point(Vector2(0.0, s0 / smax))
		cv.add_point(Vector2(1.0, s1 / smax))
		cp.scale_amount_curve = cv
		cp.color_ramp = _gradient(p["color"], float(p["alpha"]))
		add_child(cp)


func _fog_sheet(fx: Dictionary, p: Dictionary) -> void:
	if not fx.has("area"):
		return
	var a: Array = fx["area"]
	var shader: Shader = load(_base_dir + "/fx/godot/fog_sheet.gdshader")
	for i in range(int(p.get("layers", 1))):
		var mi := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(a[3] - a[0], a[5] - a[2])
		mi.mesh = plane
		var sm := ShaderMaterial.new()
		sm.shader = shader
		sm.set_shader_parameter("color", Color(p["color"][0], p["color"][1], p["color"][2]))
		sm.set_shader_parameter("opacity", float(p["opacity"]) / (1.0 + i))
		sm.set_shader_parameter("scroll", Vector2(p["scroll"][0], p["scroll"][1]) * (1.0 + 0.5 * i))
		mi.material_override = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3((a[0] + a[3]) * 0.5, a[1] + float(p["height"]) + 0.6 * i, (a[2] + a[5]) * 0.5)
		add_child(mi)


func _sun_dir() -> Vector3:
	# direction TO the sun: from environment.json next to effects.json (same values the browser preview uses)
	var env = JSON.parse_string(FileAccess.get_file_as_string(_base_dir + "/environment.json"))
	if env == null:
		return Vector3(0.0, 0.3, -1.0)
	var d: Array = env["sun"]["direction_to_sun"]
	return Vector3(d[0], d[1], d[2]).normalized()


func _cloud_layer(fx: Dictionary, p: Dictionary) -> void:
	var shader: Shader = load(_base_dir + "/fx/godot/cloud_layer.gdshader")
	var c: Array = fx.get("center", [0.0, 0.0])
	for i in range(int(p["layers"])):
		var r := float(p["radius"]) * (1.0 - 0.1 * i)
		var mi := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(2.0 * r, 2.0 * r)   # square mesh, the shader fades it to a disc
		plane.subdivide_width = 8
		plane.subdivide_depth = 8
		mi.mesh = plane
		var sm := ShaderMaterial.new()
		sm.shader = shader
		for k in ["color", "shade", "glow"]:
			sm.set_shader_parameter(k, Color(p[k][0], p[k][1], p[k][2]))
		sm.set_shader_parameter("opacity", float(p["opacity"]) * (0.7 if i > 0 else 1.0))
		sm.set_shader_parameter("coverage", float(p["coverage"]) + 0.06 * i)
		sm.set_shader_parameter("scale", float(p["scale"]) * (1.0 + 0.31 * i))
		sm.set_shader_parameter("scroll", Vector2(p["scroll"][0], p["scroll"][1]))
		sm.set_shader_parameter("center", Vector2(c[0], c[1]))
		sm.set_shader_parameter("radius", r)
		sm.set_shader_parameter("inner", float(p["inner"]))
		sm.set_shader_parameter("seed", 17.3 * i)
		sm.set_shader_parameter("sun_dir", _sun_dir())
		mi.material_override = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(c[0], float(p["y"]) + float(p["spacing"]) * i, c[1])
		add_child(mi)


func _cloud_puffs(fx: Dictionary, p: Dictionary) -> void:
	## all puffs of one effect = ONE MultiMeshInstance3D (one draw call); billboard StandardMaterial3D, per-instance colour
	var em: Array = fx.get("emitters", [])
	var idx: Array = fx.get("emitters_by_quality", {}).get(quality, range(em.size()))
	if idx.is_empty():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, float(p["squash"]))
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = load(_base_dir + "/fx/cloud.png")
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 4.0
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 1.5
	mat.distance_fade_max_distance = 9.0
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = idx.size()
	var sun := _sun_dir()
	var lit := Color(p["color"][0], p["color"][1], p["color"][2])
	var glo := Color(p["glow"][0], p["glow"][1], p["glow"][2])
	for k in range(idx.size()):
		var e: Dictionary = em[int(idx[k])]
		var s := float(e["size"])
		var pos := Vector3(e["pos"][0], e["pos"][1], e["pos"][2])
		mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3(s, s, s)), pos))
		# sun-side puffs glow warmer (baked per instance; the browser preview computes it per view)
		var side: float = clamp(Vector2(pos.x, pos.z).normalized().dot(Vector2(sun.x, sun.z).normalized()), 0.0, 1.0)
		var c := lit.lerp(glo, 0.35 * side)
		c.a = float(p["opacity"])
		mm.set_instance_color(k, c)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


var _flyers: Array = []   # [MultiMesh, ships Array]


func _flyby(fx: Dictionary, p: Dictionary) -> void:
	## background ships on deterministic arcs (effects.json "ships"), one MultiMesh per design, unshaded vertex colours
	var by := {}
	for sh in p["ships"]:
		if not by.has(sh["design"]):
			by[sh["design"]] = []
		by[sh["design"]].append(sh)
	var hc := Color(p["color"][0], p["color"][1], p["color"][2])
	var gc := Color(p["glow"][0], p["glow"][1], p["glow"][2])
	for d in by.keys():
		var g: Dictionary = fx["meshes"][d]
		var verts := PackedVector3Array(); var cols := PackedColorArray(); var idx := PackedInt32Array()
		for i in range(g["v"].size()):
			verts.append(Vector3(g["v"][i][0], g["v"][i][1], g["v"][i][2])); cols.append(gc if int(g["glow"][i]) == 1 else hc)
		for f in g["f"]:
			idx.append(int(f[0])); idx.append(int(f[2])); idx.append(int(f[1]))  # Godot front faces are clockwise
		var arr := []; arr.resize(Mesh.ARRAY_MAX); arr[Mesh.ARRAY_VERTEX] = verts; arr[Mesh.ARRAY_COLOR] = cols; arr[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := StandardMaterial3D.new(); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mat.vertex_color_use_as_albedo = true
		mesh.surface_set_material(0, mat)
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = mesh; mm.instance_count = by[d].size()
		var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm; mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi); _flyers.append([mm, by[d]])


func _update_flyers() -> void:
	for f in _flyers:
		var mm: MultiMesh = f[0]
		for i in range(f[1].size()):
			var sh: Dictionary = f[1][i]
			var cyc: float = sh["travel"] + sh["gap"]
			var k: float = fmod(_t + sh["phase"], cyc) / sh["travel"]
			if k >= 1.0:
				mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)); continue
			var env: float = smoothstep(0.0, 0.2, k) * (1.0 - smoothstep(0.8, 1.0, k))  # grow + approach / shrink + recede
			var far: float = 1.0 + 0.5 * (1.0 - env)
			var az: float = deg_to_rad(sh["a0"] + (sh["a1"] - sh["a0"]) * k); var dir: float = sign(sh["a1"] - sh["a0"])
			var pos := Vector3(sh["r"] * far * sin(az), sh["y"] + 18.0 * (1.0 - env) + sh["bob"] * sin(_t * 0.7 + sh["phase"]), -sh["r"] * far * cos(az))
			var b := Basis.from_euler(Vector3(0.0, atan2(-cos(az) * dir, -sin(az) * dir), 0.12 * dir)).scaled(Vector3.ONE * max(float(sh["size"]) * env, 0.001))
			mm.set_instance_transform(i, Transform3D(b, pos))


func _process(delta: float) -> void:
	_t += delta
	for sp in _spins:
		(sp[0] as Node3D).rotate_object_local(Vector3.UP, float(sp[1]) * delta)
	for la in _launch:
		(la[0] as Node3D).position = (la[1] as Vector3) + Vector3.UP * minf(fmod(_t + float(la[4]), float(la[3])) * float(la[2]), float(la[5]))
	for tv in _travel:
		(tv[0] as Node3D).position = (tv[1] as Vector3) + Vector3.UP * fmod(_t * float(tv[2]), float(tv[3]))
	_update_flyers()
	for an in _anims:
		var m: BaseMaterial3D = an[0]
		var p: Dictionary = an[2]
		if an[3] == "pulse_light":
			m.emission_energy_multiplier = an[1] * (1.0 + float(p["amount"]) * sin(TAU * float(p["speed"]) * _t + float(p["phase"])))
		else:
			an[4] -= delta
			if an[4] <= 0.0:
				an[4] = 1.0 / float(p["rate"])
				m.emission_energy_multiplier = an[1] * (1.0 - float(p["amount"]) * randf())
	for b in _bursts:
		b[1] -= delta
		if b[1] <= 0.0:
			(b[0] as CPUParticles3D).restart()
			b[1] = randf_range(b[2], b[3])
	if _sky_speed != 0.0 and environment and environment.environment:
		environment.environment.sky_rotation.y += _sky_speed * delta
