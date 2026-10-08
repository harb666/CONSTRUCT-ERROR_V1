class_name Vfx
extends RefCounted
## Shared VFX helpers: greyscale Kenney particle textures (CC0) tinted at
## runtime with additive, unshaded materials (cheap on mobile), plus helpers
## for camera-facing quads. All effects are visual only.

const TEX := {
	"muzzle": preload("res://assets/vfx/muzzle_02.png"),
	"star": preload("res://assets/vfx/star_06.png"),
	"bolt": preload("res://assets/vfx/spark_06.png"),
	"crackle": preload("res://assets/vfx/spark_01.png"),
	"twirl": preload("res://assets/vfx/twirl_02.png"),
	"glow": preload("res://assets/vfx/circle_05.png"),
	"ring": preload("res://assets/vfx/circle_02.png"),
	"scorch": preload("res://assets/vfx/scorch_02.png"),
	"streak": preload("res://assets/vfx/trace_01.png"),
	"halo": preload("res://assets/vfx/light_02.png"),
	"smoke": preload("res://assets/vfx/smoke_puff.png"),
	"dot": preload("res://assets/vfx/soft_dot.png"),
	# Flames (Kenney particle pack, CC0, via the supplied weapon VFX pack).
	"flame_a": preload("res://assets/vfx/muzzle_01.png"),
	"flame_b": preload("res://assets/vfx/muzzle_04.png"),
	"flame_c": preload("res://assets/vfx/muzzle_05.png"),
	"lick_a": preload("res://assets/vfx/flame_01.png"),
	"lick_b": preload("res://assets/vfx/flame_03.png"),
	"fireball": preload("res://assets/vfx/fire_01.png"),
	"flare": preload("res://assets/vfx/star_09.png"),
}

const PURPLE := Color(0.72, 0.22, 1.0)
const PINK := Color(1.0, 0.45, 0.95)
const HOT := Color(0.95, 0.8, 1.0)

## Global switch for the screen-distortion effect (costs a screen copy).
static var distortion_enabled := true
## Short-lived effect lights (muzzle flashes, impacts, blasts). Off on
## phones/tablets in the browser: iOS WebGL renders objects those lights
## touch black, and they cost a lot there. The flashes themselves are
## sprites and still show. ?lights=1 forces them on (testing).
static var effect_lights := true


## Called once at startup (Main).
static func configure_for_device() -> void:
	var web_touch := OS.has_feature("web") and DisplayServer.is_touchscreen_available()
	var force := StressTest._param("lights") == "1"
	effect_lights = force or not web_touch
	# The black hole's screen-space lens also reads the screen; same reason.
	if web_touch and not force:
		distortion_enabled = false


## Every effect light goes through here: when effect lights are off it
## lights nothing (no per-object light cost, nothing turns black).
static func tame_light(l: Light3D) -> void:
	if l and not effect_lights:
		l.light_cull_mask = 0
		l.light_energy = 0.0
		l.set_meta(&"tamed", true)

static var _cache := {}


## Additive unshaded material for a greyscale texture. `billboard`:
## BaseMaterial3D.BILLBOARD_* ; `vertex_color` for particles (colour ramps).
## `unique` returns a fresh copy (for per-instance fading).
static func material(tex: String, color: Color, billboard := BaseMaterial3D.BILLBOARD_DISABLED, vertex_color := false, unique := false) -> StandardMaterial3D:
	var key := "%s|%s|%d|%s" % [tex, color, billboard, vertex_color]
	if not unique and _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.albedo_texture = TEX[tex]
	m.albedo_color = color
	m.billboard_mode = billboard
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = vertex_color
	if not unique:
		_cache[key] = m
	return m


static func quad(tex: String, color: Color, size: Vector2, billboard := BaseMaterial3D.BILLBOARD_DISABLED, unique := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.material_override = material(tex, color, billboard, false, unique)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Turn `node` to face the active camera (quad +Z towards camera), rolled by
## `roll` radians, with uniform `size` scale.
static func face_camera(node: Node3D, size: float, roll := 0.0) -> void:
	var cam := node.get_viewport().get_camera_3d()
	if cam == null:
		return
	var z := cam.global_position - node.global_position
	if z.length_squared() < 1e-6:
		return
	z = z.normalized()
	var x := cam.global_basis.y.cross(z).normalized()
	var y := z.cross(x)
	var c := cos(roll)
	var s := sin(roll)
	node.global_basis = Basis(x * c + y * s, -x * s + y * c, z).scaled(Vector3.ONE * size)


## Fade an additive quad (its unique material) to `alpha`.
static func set_alpha(mi: MeshInstance3D, alpha: float) -> void:
	var m := mi.material_override as StandardMaterial3D
	m.albedo_color.a = clampf(alpha, 0.0, 1.0)


## Alpha-blended (not additive) unshaded material, so effects can be dark
## (black dust, smoky mist). Uses vertex colour for particle colour ramps.
static func mix_material(tex: String, billboard := BaseMaterial3D.BILLBOARD_PARTICLES) -> StandardMaterial3D:
	var key := "mix|%s|%d" % [tex, billboard]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.albedo_texture = TEX[tex]
	m.billboard_mode = billboard
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	_cache[key] = m
	return m


## Short-lived particle burst/stream using a camera-facing textured quad.
static func particles(tex: String, quad_size: float, amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * quad_size
	q.material = material(tex, Color.WHITE, BaseMaterial3D.BILLBOARD_PARTICLES, true)
	p.mesh = q
	p.amount = amount
	p.lifetime = lifetime
	p.gravity = Vector3.ZERO
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func ramp(colors: Array, offsets: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	return g


static func curve(points: Array) -> Curve:
	var c := Curve.new()
	for pt: Vector2 in points:
		c.add_point(pt)
	return c
