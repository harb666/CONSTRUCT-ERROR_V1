class_name GlitchGlide
extends Node3D
## The player glitching while they power-glide in to melee (owner asked:
## "I want the player to be glitchy as they power glide"), in the game's
## glitch style (the menu's band shifts and RGB split):
##  - the body torn into sideways-thrown cyan / magenta bands, scan-lined
##    (glitch_glide.gdshader as the character's material_overlay);
##  - the model jitters and skips a few centimetres, in steps;
##  - a trail of pixel blocks (cyan, magenta, white) left in the air.
## `start(player)` adds it, `stop()` fades it out (0.15 s) and puts back
## what was there. Shared materials (one shader, warmed up behind the
## title: Vfx.warm_up).

const SHADER := preload("res://scripts/vfx/glitch_glide.gdshader")
const CYAN := Color(0.0, 0.95, 1.0)
const MAGENTA := Color(1.0, 0.1, 0.85)

var player: Node3D
var amount := 0.0
var fading := false
var _mat: ShaderMaterial
var _meshes: Array[GeometryInstance3D] = []
var _before: Array[Material] = []
var _model: Node3D
var _model_pos := Vector3.ZERO
var _jit_t := 0.0
var _trail: CPUParticles3D

static var started := 0


static func start(p: Node3D) -> GlitchGlide:
	if p == null or not p.is_inside_tree():
		return null
	var g := GlitchGlide.new()
	g.name = "GlitchGlide"
	g.player = p
	p.add_child(g)
	started += 1
	return g


static func make_material() -> ShaderMaterial:
	var a := ShaderMaterial.new()
	a.shader = SHADER
	a.set_shader_parameter("tint", CYAN)
	a.set_shader_parameter("shift", 0.16)
	a.set_shader_parameter("seed", 0.0)
	var b := ShaderMaterial.new()
	b.shader = SHADER
	b.set_shader_parameter("tint", MAGENTA)
	b.set_shader_parameter("shift", -0.13)
	b.set_shader_parameter("seed", 17.0)
	a.next_pass = b
	return a


## Warm-up items (Vfx.warm_up): the overlay on a small mesh.
static func warm_up_items() -> Array[Node3D]:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3.ONE * 0.2
	mi.mesh = m
	mi.material_overlay = make_material()
	return [mi, _make_trail()]


func _ready() -> void:
	_mat = make_material()
	_set_amount(0.0)
	var visual := player.get_node_or_null(^"Visual") as Node3D
	_model = visual.get_child(0) as Node3D if visual and visual.get_child_count() > 0 else null
	if _model:
		_model_pos = _model.position
		for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null or not mi.visible:
				continue
			_meshes.append(mi)
			_before.append(mi.material_overlay)
			mi.material_overlay = _mat
	_trail = _make_trail()
	add_child(_trail)
	_trail.position = Vector3.UP * 1.0
	_trail.emitting = true


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
	q.material = m
	c.mesh = q
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), CYAN, MAGENTA, Color(0, 0, 0, 0)])
	c.color_ramp = g
	c.emitting = false
	return c


func _set_amount(a: float) -> void:
	amount = a
	_mat.set_shader_parameter("amount", a)
	(_mat.next_pass as ShaderMaterial).set_shader_parameter("amount", a)


func stop() -> void:
	fading = true
	if _trail:
		_trail.emitting = false


func _process(delta: float) -> void:
	if fading:
		_set_amount(maxf(amount - delta / 0.15, 0.0))
		if amount <= 0.0:
			_finish()
			return
	else:
		_set_amount(minf(amount + delta / 0.06, 1.0))
	# The model jumps a few cm, in steps (and now and then further).
	_jit_t -= delta
	if _model and _jit_t <= 0.0:
		_jit_t = randf_range(0.03, 0.07)
		var j := Vector3(randf_range(-1, 1), randf_range(-0.4, 0.4), randf_range(-1, 1)) * 0.05
		if randf() < 0.18:
			j *= 4.0
		_model.position = _model_pos + j * amount


func _finish() -> void:
	for i in _meshes.size():
		var mi := _meshes[i]
		if is_instance_valid(mi) and mi.material_overlay == _mat:
			mi.material_overlay = _before[i]
	if _model and is_instance_valid(_model):
		_model.position = _model_pos
	# The trail's last blocks finish where they are.
	if _trail and is_instance_valid(_trail):
		var host: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
		var keep := _trail.global_transform
		remove_child(_trail)
		host.add_child(_trail)
		_trail.global_transform = keep
		get_tree().create_timer(_trail.lifetime + 0.1).timeout.connect(_trail.queue_free)
	queue_free()


func _exit_tree() -> void:
	if not fading or amount > 0.0:
		for i in _meshes.size():
			var mi := _meshes[i]
			if is_instance_valid(mi) and mi.material_overlay == _mat:
				mi.material_overlay = _before[i]
		if _model and is_instance_valid(_model):
			_model.position = _model_pos
