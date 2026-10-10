class_name ToonPuff
extends MeshInstance3D
## One puffy cartoon cloud ball (toon_puff.gdshader on a shared sphere): it
## pops out, burns from white-hot through orange to smoke, drifts up and
## dissolves away. Owned and restarted by an effect (no allocation per use).
## No textures; alpha-scissored (opaque pass), so cheap on phones.

const SHADER := preload("res://scripts/vfx/toon_puff.gdshader")

static var _sphere: SphereMesh

## Size (diameter-ish, m), seconds of fire before it's smoke, total life.
var size := 1.0
var burn_time := 0.35
var life := 1.4
var rise := 1.2
var drift := Vector3.ZERO
## Starts this many seconds after `play` (staggered clouds).
var delay := 0.0
var _t := 99.0
var _origin := Vector3.ZERO
var _mat: ShaderMaterial


func _init() -> void:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 0.5
		_sphere.height = 1.0
		_sphere.radial_segments = 24
		_sphere.rings = 12
	mesh = _sphere
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visible = false
	set_process(false)


## Start at `at`. `fire` false = smoke only (no burn).
func play(at: Vector3, fire := true) -> void:
	_origin = at
	_t = -delay
	_mat.set_shader_parameter("seed", randf() * 100.0)
	_mat.set_shader_parameter("heat", 1.0 if fire else 0.0)
	_mat.set_shader_parameter("progress", 0.0)
	if not fire:
		burn_time = 0.0
	rotation = Vector3(randf() * TAU, randf() * TAU, 0.0)
	set_process(true)
	_update()


func set_colors(smoke: Color, hot := Color(1.0, 0.95, 0.7), mid := Color(1.0, 0.55, 0.1), cool := Color(0.45, 0.08, 0.02)) -> void:
	_mat.set_shader_parameter("smoke_color", smoke)
	_mat.set_shader_parameter("fire_hot", hot)
	_mat.set_shader_parameter("fire_mid", mid)
	_mat.set_shader_parameter("fire_cool", cool)


func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		visible = false
		set_process(false)
		return
	_update()


func _update() -> void:
	visible = _t >= 0.0
	if not visible:
		return
	var k := clampf(_t / life, 0.0, 1.0)
	# Pops out fast, then keeps swelling slowly.
	var pop := 1.0 - pow(1.0 - clampf(_t / 0.12, 0.0, 1.0), 3.0)
	scale = Vector3.ONE * size * (0.35 + 0.65 * pop) * (1.0 + 0.45 * k)
	global_position = _origin + (Vector3.UP * rise + drift) * (1.0 - pow(1.0 - k, 2.0))
	var heat := 1.0 - clampf(_t / maxf(burn_time, 0.001), 0.0, 1.0) if burn_time > 0.0 else 0.0
	_mat.set_shader_parameter("heat", heat * heat)
	# Holds its shape, then is eaten away.
	_mat.set_shader_parameter("progress", smoothstep(0.35, 1.0, k) * 0.95)
