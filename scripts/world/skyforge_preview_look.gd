class_name SkyforgePreviewLook
extends Node
## Gives Skyforge Arena's level and background meshes the image-to-level
## PREVIEW's look (owner asked: exactly like the map maker): every material
## becomes preview_lit (a port of the preview's three.js lighting; see
## preview_lit.gdshaderinc), built from the material's own textures and
## values. Variants:
## outline "ink" shells unlit; untextured vertex-coloured non-terrain meshes
## Lambert + flat (the preview swaps those to MeshLambertMaterial); the
## scrolling fall (effects "liquid_flow") keeps its material and moves its
## UVs like the preview. Pulsing / flickering glows (apply_effects.gd
## animates the source materials' emission) are copied across each frame.
## Spawn / Boundary meshes are hidden, as in the preview.

const INCLUDE := "res://scripts/world/preview_lit.gdshaderinc"
const IBL := preload("res://levels/skyforge_arena/sky/ibl_atlas.png")

var scene_params := {}
var _shaders := {}
var _made := {}  # [source material, defines] -> ShaderMaterial
var _anim: Array = []  # [source BaseMaterial3D, ShaderMaterial]
## Materials converted (tests).
var converted := 0


## Scene-wide values from environment.json, as the preview uses them.
func setup(env: Dictionary) -> void:
	var lin := func(a: Array) -> Vector3: return Vector3(float(a[0]), float(a[1]), float(a[2]))
	var amb: Dictionary = env.get("ambient", {})
	var sun: Dictionary = env.get("sun", {})
	var fog: Dictionary = env.get("fog", {})
	var style: Dictionary = env.get("style", {})
	var toon: Dictionary = style.get("toon", {})
	var amb_e := float(amb.get("energy", 1.0))
	# HemisphereLight(sky.lerp(white, .5), ground, 1.2 x energy) (colours are
	# three.js working = linear values).
	var sky_c: Vector3 = lin.call(amb.get("sky_color", [0.5, 0.5, 0.5])).lerp(Vector3.ONE, 0.5)
	scene_params = {
		"ibl_atlas": IBL,
		"sun_dir": (lin.call(sun.get("direction_to_sun", [0, 1, 0])) as Vector3).normalized(),
		"sun_color": (lin.call(sun.get("color", [1, 1, 1])) as Vector3) * 1.25 * float(sun.get("energy", 1.0)),
		"toon_floor": float(toon.get("floor", 0.5)) if not toon.is_empty() else 1.0,
		"hemi_sky": sky_c * 1.2 * amb_e,
		"hemi_ground": (lin.call(amb.get("ground_color", [0.3, 0.3, 0.3])) as Vector3) * 1.2 * amb_e,
		"env_intensity": float(toon.get("ambient", 1.25)) if not toon.is_empty() else 0.9,
		"fog_color": lin.call(fog.get("color", [0.5, 0.5, 0.5])),
		"fog_start": float(fog.get("start", 1.0e4)) if fog.get("enabled", false) else 1.0e5,
		"fog_end": float(fog.get("end", 2.0e4)) if fog.get("enabled", false) else 2.0e5,
		"fog_height": float(fog.get("height", 0.0)),
		"fog_height_density": float(fog.get("height_density", 0.0)) if fog.get("enabled", false) else 0.0,
	}


## Convert every mesh under `root`. `flows`: mesh name -> [flow_dir, speed
## (m/s / tile m), wobble] for the scrolling liquids.
func apply(root: Node, flows: Dictionary = {}) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var n := String(mi.name)
		if n.begins_with("Spawn") or n.begins_with("Boundary"):
			mi.visible = false
			continue
		if mi.mesh == null:
			continue
		var flow: Array = flows.get(n, [])
		if not flow.is_empty():
			mi.material_override = null  # (apply_effects' liquid shader)
		var is_ter := n.begins_with("TR_") or n.begins_with("TRM_")
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as BaseMaterial3D
			var ov := mi.get_surface_override_material(s) as BaseMaterial3D
			if ov:
				src = ov
			if src == null:
				continue
			var has_col: bool = (mi.mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_COLOR) != 0
			var defs: Array[String] = []
			var has_normals: bool = (mi.mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_NORMAL) != 0
			if src.resource_name == "ink":
				defs.append("UNLIT")
			elif src.albedo_texture == null and has_col and not is_ter:
				defs.append_array(["LAMBERT", "FLAT", "VCOL"])
			else:
				if has_col:
					defs.append("VCOL")
				# No normals in the mesh (the decks): the preview shades
				# them flat.
				if not has_normals:
					defs.append("FLAT")
				if src.normal_enabled and src.normal_texture:
					defs.append("NMAP")
			if src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA or src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
				defs.append("ALPHA")
			var cull := "cull_disabled" if src.cull_mode == BaseMaterial3D.CULL_DISABLED else ("cull_front" if src.cull_mode == BaseMaterial3D.CULL_FRONT else "cull_back")
			var key := [src, ",".join(defs), cull, flow]
			var sm: ShaderMaterial = _made.get(key)
			if sm == null:
				sm = _material(src, defs, cull, flow)
				_made[key] = sm
			mi.set_surface_override_material(s, sm)
		# Like the preview: the level's own geometry casts no shadows (the
		# sun only shadows players and robots).
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _shader(defs: Array[String], cull: String) -> Shader:
	var k := ",".join(defs) + "|" + cull
	if _shaders.has(k):
		return _shaders[k]
	var code := "shader_type spatial;\n"
	for x in defs:
		code += "#define %s\n" % x
	if cull == "cull_disabled":
		code += "#define CULL_DISABLED\n"
	elif cull == "cull_front":
		code += "#define CULL_FRONT\n"
	code += "#include \"%s\"\n" % INCLUDE
	var sh := Shader.new()
	sh.code = code
	_shaders[k] = sh
	return sh


func _material(src: BaseMaterial3D, defs: Array[String], cull: String, flow: Array) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = _shader(defs, cull)
	sm.resource_name = src.resource_name
	for k in scene_params:
		sm.set_shader_parameter(k, scene_params[k])
	sm.set_shader_parameter("albedo_color", src.albedo_color)
	if src.albedo_texture:
		sm.set_shader_parameter("albedo_tex", src.albedo_texture)
	var orm: Texture2D = src.metallic_texture if src.metallic_texture else src.roughness_texture
	if orm:
		sm.set_shader_parameter("orm_tex", orm)
	sm.set_shader_parameter("roughness", src.roughness)
	sm.set_shader_parameter("metallic", src.metallic)
	if src.normal_enabled and src.normal_texture:
		sm.set_shader_parameter("normal_tex", src.normal_texture)
		sm.set_shader_parameter("normal_scale", src.normal_scale)
	if src.emission_enabled:
		sm.set_shader_parameter("emission_color", src.emission)
		sm.set_shader_parameter("emission_energy", src.emission_energy_multiplier)
		if src.emission_texture:
			sm.set_shader_parameter("emission_tex", src.emission_texture)
		_anim.append([src, sm])
	sm.set_shader_parameter("uv_scale", Vector2(src.uv1_scale.x, src.uv1_scale.y))
	sm.set_shader_parameter("uv_offset", Vector2(src.uv1_offset.x, src.uv1_offset.y))
	if not flow.is_empty():
		sm.set_shader_parameter("flow_dir", flow[0])
		sm.set_shader_parameter("flow_speed", flow[1])
		sm.set_shader_parameter("flow_wobble", flow[2])
	converted += 1
	return sm


func _process(_delta: float) -> void:
	# Pulsing / flickering glows: apply_effects.gd drives the source
	# materials' emission energy.
	for a in _anim:
		var src: BaseMaterial3D = a[0]
		(a[1] as ShaderMaterial).set_shader_parameter("emission_energy", src.emission_energy_multiplier)
