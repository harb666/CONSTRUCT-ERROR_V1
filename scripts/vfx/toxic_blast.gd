class_name ToxicBlast
extends Node3D
## A toxic barrel bursting (owner asked: "explode and leave green flaming
## slime"), cartoon style in toxic green: a white-green star flash, puffy
## green fireballs (ToonPuff) bursting up and out, dark green smoke rolling
## up after them, a green shockwave ring racing over the floor, blobs of
## slime flung out in arcs, purple barrel chunks spinning away and a green
## glow. The slime puddles themselves are ToxicSlime (the barrel places
## them where the blobs land). Frees itself when done.

const RING_SHADER := preload("res://scripts/vfx/toon_ring.gdshader")
const GREEN := Color(0.35, 1.0, 0.1)
const HOT := Color(0.92, 1.0, 0.7)
const DARK := Color(0.03, 0.25, 0.04)
const FIREBALLS := 6
const SMOKE := 2

@export var life := 2.6
@export var ring_time := 0.32

static var spawned := 0
static var _blob_mesh: SphereMesh
static var _chunk_mesh: BoxMesh


## Shared meshes / materials for the slime blobs and barrel chunks.
static func blob_mesh() -> SphereMesh:
	if _blob_mesh == null:
		_blob_mesh = SphereMesh.new()
		_blob_mesh.radius = 0.09
		_blob_mesh.height = 0.18
		_blob_mesh.radial_segments = 8
		_blob_mesh.rings = 4
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.45, 1.0, 0.15)
		_blob_mesh.material = m
	return _blob_mesh


static func chunk_mesh() -> BoxMesh:
	if _chunk_mesh == null:
		_chunk_mesh = BoxMesh.new()
		_chunk_mesh.size = Vector3(0.22, 0.05, 0.16)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.32, 0.07, 0.26)
		m.metallic = 0.6
		m.roughness = 0.5
		_chunk_mesh.material = m
	return _chunk_mesh


## One of each material a barrel blast and its slime use, for Vfx.warm_up
## (phones build the shaders behind the title screen, not on the first
## explosion).
static func warm_up_items() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for mesh: Mesh in [blob_mesh(), chunk_mesh()]:
		var p := CPUParticles3D.new()
		p.mesh = mesh
		p.amount = 2
		p.initial_velocity_min = 0.0
		p.initial_velocity_max = 0.0
		p.gravity = Vector3.ZERO
		p.emitting = true
		out.append(p)
	for sh: Shader in [ToxicSlime.SHADER, ToxicSlime.FIRE]:
		var mi := MeshInstance3D.new()
		mi.mesh = QuadMesh.new()
		var m := ShaderMaterial.new()
		m.shader = sh
		mi.material_override = m
		out.append(mi)
	return out

var radius := 4.0
var _t := 0.0
var _at := Vector3.ZERO
var _star: MeshInstance3D
var _ring: MeshInstance3D
var _ring2: MeshInstance3D
var _blobs: CPUParticles3D
var _chunks: CPUParticles3D
var _light: OmniLight3D


static func spawn(parent: Node, at: Vector3, blast_radius: float) -> ToxicBlast:
	var b := ToxicBlast.new()
	b.radius = blast_radius
	parent.add_child(b)
	b._start(at)
	spawned += 1
	return b


func _start(at: Vector3) -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_at = at
	global_position = at
	_star = Vfx.toon_flash(0, GREEN, HOT, DARK, Vector2.ONE, 11.0)
	_star.top_level = true
	add_child(_star)
	_ring = _make_ring(0.3, Color(0.55, 1.0, 0.25))
	_ring2 = _make_ring(0.12, Color(0.85, 1.0, 0.6))
	# Fireballs: burst out and up from the barrel.
	for i in FIREBALLS:
		var f := ToonPuff.new()
		f.set_colors(Color(0.3, 0.42, 0.24), HOT, GREEN, DARK)
		add_child(f)
		var a := TAU * (i + randf_range(-0.3, 0.3)) / FIREBALLS
		var out := Vector3(cos(a), 0.0, sin(a))
		f.size = randf_range(1.3, 1.9) if i > 0 else 2.3
		f.burn_time = randf_range(0.35, 0.5)
		f.life = randf_range(1.0, 1.4)
		f.rise = randf_range(1.2, 2.2)
		f.drift = out * randf_range(1.2, 2.2) if i > 0 else Vector3.ZERO
		f.delay = 0.0 if i == 0 else randf_range(0.0, 0.08)
		f.play(at + Vector3.UP * (0.6 + 0.4 * randf()) + out * 0.4, true)
	# Smoke: murky green, rolling up after the fire.
	for i in SMOKE:
		var s := ToonPuff.new()
		s.set_colors(Color(0.34, 0.47, 0.26))
		add_child(s)
		s.size = randf_range(1.1, 1.5)
		s.life = randf_range(1.3, 1.7)
		s.rise = randf_range(2.5, 3.5)
		s.drift = Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * 0.8
		s.delay = randf_range(0.25, 0.45)
		s.play(at + Vector3.UP * 1.4, false)
	# Slime blobs flung out in arcs (they land as the puddles appear).
	_blobs = CPUParticles3D.new()
	_blobs.mesh = blob_mesh()
	_blobs.amount = 26
	_blobs.lifetime = 0.9
	_blobs.one_shot = true
	_blobs.explosiveness = 0.95
	_blobs.local_coords = false
	_blobs.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_blobs.emission_sphere_radius = 0.35
	_blobs.direction = Vector3.UP
	_blobs.spread = 70.0
	_blobs.initial_velocity_min = 4.5
	_blobs.initial_velocity_max = 9.0
	_blobs.gravity = Vector3(0, -16, 0)
	_blobs.scale_amount_min = 0.6
	_blobs.scale_amount_max = 1.8
	_blobs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_blobs)
	_blobs.global_position = at + Vector3.UP * 0.9
	_blobs.emitting = true
	# Barrel chunks: purple metal bits spinning away.
	_chunks = CPUParticles3D.new()
	_chunks.mesh = chunk_mesh()
	_chunks.amount = 12
	_chunks.lifetime = 1.3
	_chunks.one_shot = true
	_chunks.explosiveness = 1.0
	_chunks.local_coords = false
	_chunks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_chunks.emission_sphere_radius = 0.5
	_chunks.direction = Vector3.UP
	_chunks.spread = 80.0
	_chunks.initial_velocity_min = 5.0
	_chunks.initial_velocity_max = 11.0
	_chunks.angular_velocity_min = -720.0
	_chunks.angular_velocity_max = 720.0
	_chunks.gravity = Vector3(0, -18, 0)
	_chunks.scale_amount_min = 0.7
	_chunks.scale_amount_max = 2.2
	add_child(_chunks)
	_chunks.global_position = at + Vector3.UP * 0.9
	_chunks.emitting = true
	_light = OmniLight3D.new()
	_light.light_color = Color(0.45, 1.0, 0.2)
	_light.omni_range = radius * 2.5
	_light.shadow_enabled = false
	add_child(_light)
	_light.global_position = at + Vector3.UP * 1.2
	Vfx.tame_light(_light)
	_update()


func _make_ring(width: float, fill: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = QuadMesh.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = RING_SHADER
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("fill_color", fill)
	m.set_shader_parameter("rim_color", Color(0.05, 0.3, 0.05))
	m.set_shader_parameter("seed", randf() * 100.0)
	mi.material_override = m
	mi.top_level = true
	add_child(mi)
	return mi


func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	_update()


func _update() -> void:
	var sk := clampf(_t / 0.16, 0.0, 1.0)
	_star.visible = sk < 1.0
	if _star.visible:
		_star.global_position = _at + Vector3.UP * 1.0
		Vfx.face_camera(_star, 2.6 + 2.8 * sk, _t * 6.0)
		Vfx.set_alpha(_star, 1.0 - sk * sk)
	var flat := Basis(Vector3.RIGHT, -PI / 2.0)
	for i in 2:
		var w: MeshInstance3D = [_ring, _ring2][i]
		var lag := 0.05 * i
		var k := 1.0 - pow(1.0 - clampf((_t - lag) / ring_time, 0.0, 1.0), 2.0)
		w.visible = _t >= lag and (_t - lag) < ring_time + 0.2
		var r := radius * (0.15 + 0.85 * k) * (1.0 if i == 0 else 0.82)
		w.global_transform = Transform3D(flat.scaled(Vector3.ONE * r * 2.0), _at + Vector3.UP * (0.07 + 0.02 * i))
		var m := w.material_override as ShaderMaterial
		m.set_shader_parameter("progress", k)
		m.set_shader_parameter("fade", 1.0 - smoothstep(0.55, 1.0, clampf((_t - lag) / (ring_time + 0.2), 0.0, 1.0)))
	if Vfx.effect_lights:
		_light.light_energy = 9.0 * (1.0 - smoothstep(0.0, 0.6, _t))
