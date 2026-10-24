class_name GlitchGlide
extends Node3D
## The player glitching while they power-glide in to melee (owner asked:
## "I want the player to be glitchy as they power glide"), in the game's
## glitch style (the menu's band shifts and RGB split):
##  - the body torn into sideways-thrown cyan / magenta bands, scan-lined
##    (glitch_glide.gdshader as the character's material_overlay);
##  - the model jitters and skips a few centimetres, in steps;
##  - a trail of pixel blocks (cyan, magenta, white) left in the air.
## `start(player)` turns it on (made once per player, then reused: no new
## materials or particles per glide), `stop()` fades it out (0.15 s) and
## puts back what was there. One overlay pass (a second one redrew the whole
## character again - a phone's frame mid-glide); shader warmed up behind
## the title (Vfx.warm_up).

const SHADER := preload("res://scripts/vfx/glitch_glide.gdshader")
const CYAN := Color(0.0, 0.95, 1.0)
const MAGENTA := Color(1.0, 0.1, 0.85)

var player: Node3D
var amount := 0.0
var fading := false
## On (gliding, or fading out).
var active := false
var _mat: ShaderMaterial
var _meshes: Array[GeometryInstance3D] = []
var _before: Array[Material] = []
var _model: Node3D
var _model_pos := Vector3.ZERO
var _jit_t := 0.0
var _trail: CPUParticles3D
var _streaks: CPUParticles3D
## The flight's velocity (PlayerMelee): the speed streaks lie along it.
var direction := Vector3.ZERO

static var started := 0
static var _trail_mat: StandardMaterial3D
static var _streak_mat: StandardMaterial3D


static func start(p: Node3D) -> GlitchGlide:
	if p == null or not p.is_inside_tree():
		return null
	var g := p.get_node_or_null(^"GlitchGlide") as GlitchGlide
	if g == null:
		g = GlitchGlide.new()
		g.name = "GlitchGlide"
		g.player = p
		p.add_child(g)
	g._begin()
	started += 1
	return g


static func make_material() -> ShaderMaterial:
	var a := ShaderMaterial.new()
	a.shader = SHADER
	a.set_shader_parameter("tint", CYAN)
	a.set_shader_parameter("tint2", MAGENTA)
	a.set_shader_parameter("shift", 0.16)
	return a


## Warm-up items (Vfx.warm_up): the overlay on a small mesh.
static func warm_up_items() -> Array[Node3D]:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3.ONE * 0.2
	mi.mesh = m
	mi.material_overlay = make_material()
	return [mi, _make_trail(), _make_streaks()]


func _ready() -> void:
	_mat = make_material()
	_set_amount(0.0)
	_trail = _make_trail()
	add_child(_trail)
	_trail.position = Vector3.UP * 1.0
	_streaks = _make_streaks()
	add_child(_streaks)
	_streaks.position = Vector3.UP * 1.0
	set_process(false)


## On: the overlay onto the model's meshes now (weapons change between
## glides), the pixel trail running.
func _begin() -> void:
	if active and not fading:
		return
	if active:
		_restore()
	active = true
	fading = false
	var visual := player.get_node_or_null(^"Visual") as Node3D
	_model = visual.get_child(0) as Node3D if visual and visual.get_child_count() > 0 else null
	_meshes.clear()
	_before.clear()
	if _model:
		_model_pos = _model.position
		for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null or not mi.visible:
				continue
			_meshes.append(mi)
			_before.append(mi.material_overlay)
			mi.material_overlay = _mat
	_trail.emitting = true
	direction = Vector3.ZERO
	set_process(true)


static func _make_trail() -> CPUParticles3D:
	var c := CPUParticles3D.new()
	c.name = "PixelTrail"
	c.amount = 40
	c.lifetime = 0.4
	c.local_coords = false
	c.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	c.emission_box_extents = Vector3(0.35, 0.8, 0.35)
	c.direction = Vector3.UP
	c.spread = 180.0
	c.initial_velocity_min = 0.2
	c.initial_velocity_max = 1.2
	c.gravity = Vector3.ZERO
	c.scale_amount_min = 0.5
	c.scale_amount_max = 1.6
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.07
	if _trail_mat == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		# Blocks the camera flies past fade out instead of filling the screen.
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		m.distance_fade_min_distance = 0.6
		m.distance_fade_max_distance = 2.2
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_trail_mat = m
	q.material = _trail_mat
	c.mesh = q
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), CYAN, MAGENTA, Color(0, 0, 0, 0)])
	c.color_ramp = g
	c.emitting = false
	return c


## Speed streaks (owner asked: sonic): long thin white / cyan / magenta
## lines left in the air all round the player along the flight - from the
## chase camera they rush past like speed lines.
static func _make_streaks() -> CPUParticles3D:
	var c := CPUParticles3D.new()
	c.name = "SpeedStreaks"
	c.amount = 48
	c.lifetime = 0.22
	c.local_coords = false
	c.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	c.emission_sphere_radius = 1.1
	c.particle_flag_align_y = true
	c.direction = Vector3.BACK
	c.spread = 0.0
	c.initial_velocity_min = 1.5
	c.initial_velocity_max = 3.0
	c.gravity = Vector3.ZERO
	c.scale_amount_min = 0.6
	c.scale_amount_max = 1.4
	var b := BoxMesh.new()
	b.size = Vector3(0.025, 2.2, 0.025)
	if _streak_mat == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		m.distance_fade_min_distance = 0.8
		m.distance_fade_max_distance = 2.5
		_streak_mat = m
	b.material = _streak_mat
	c.mesh = b
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), CYAN, Color(MAGENTA, 0.0)])
	c.color_ramp = g
	c.emitting = false
	return c


func _set_amount(a: float) -> void:
	amount = a
	_mat.set_shader_parameter("amount", a)


func stop() -> void:
	fading = true
	if _trail:
		_trail.emitting = false
	if _streaks:
		_streaks.emitting = false


func _process(delta: float) -> void:
	if fading:
		_set_amount(maxf(amount - delta / 0.15, 0.0))
		if amount <= 0.0:
			_finish()
			return
	else:
		_set_amount(minf(amount + delta / 0.06, 1.0))
	# Streaks only once it's flying, lying back along the flight.
	if _streaks and not fading:
		var speed := direction.length()
		_streaks.emitting = speed > 5.0
		if speed > 5.0:
			_streaks.direction = global_basis.inverse() * (-direction / speed)
	# The model jumps a few cm, in steps (and now and then further).
	_jit_t -= delta
	if _model and _jit_t <= 0.0:
		_jit_t = randf_range(0.03, 0.07)
		var j := Vector3(randf_range(-1, 1), randf_range(-0.4, 0.4), randf_range(-1, 1)) * 0.05
		if randf() < 0.18:
			j *= 4.0
		_model.position = _model_pos + j * amount


## Off: what was there before put back (the trail's last blocks finish in
## the air by themselves).
func _finish() -> void:
	_restore()
	active = false
	fading = false
	_trail.emitting = false
	_streaks.emitting = false
	set_process(false)


func _restore() -> void:
	for i in _meshes.size():
		var mi := _meshes[i]
		if is_instance_valid(mi) and mi.material_overlay == _mat:
			mi.material_overlay = _before[i]
	if _model and is_instance_valid(_model):
		_model.position = _model_pos
	_meshes.clear()
	_before.clear()


func _exit_tree() -> void:
	_restore()
