class_name SlimeSplash
extends Node3D
## A player plunging into a slime pool (owner asked: "a splash effect in the
## pools as the players fall into them"), cartoon style: a crown of fat
## slime blobs thrown up and out round the hole, a tall jet of drops up the
## middle, a foam patch, three ripple rings racing out over the surface and
## bubbles popping up after. Toxic green (the level's slime). One per
## plunge (they're rare), freed when done; materials shared and warmed up
## behind the title (Vfx.warm_up).

const RING_SHADER := preload("res://scripts/vfx/slime_ring.gdshader")
const SLIME := Color(0.45, 1.0, 0.15)

@export var duration := 1.7

static var spawned := 0
static var _blob_mat: StandardMaterial3D
static var _blob_mesh: SphereMesh
static var _drop_mesh: CapsuleMesh

var color := SLIME
var size := 1.0
var _t := 0.0
var _rings: Array[MeshInstance3D] = []
var _ring_mats: Array[ShaderMaterial] = []
var _foam: MeshInstance3D
var _foam_mat: ShaderMaterial


## A splash at `at` (on the slime's surface), `size` 1 = a player.
static func spawn(tree: SceneTree, at: Vector3, col := SLIME, scale_by := 1.0) -> SlimeSplash:
	var host: Node = tree.current_scene if tree.current_scene else tree.root
	var s := SlimeSplash.new()
	s.name = "SlimeSplash"
	s.color = col
	s.size = scale_by
	host.add_child(s)
	s.global_position = at
	spawned += 1
	return s


static func _materials() -> void:
	if _blob_mat:
		return
	_blob_mat = StandardMaterial3D.new()
	_blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blob_mat.vertex_color_use_as_albedo = true
	_blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blob_mat.disable_receive_shadows = true
	_blob_mesh = SphereMesh.new()
	_blob_mesh.radius = 0.11
	_blob_mesh.height = 0.22
	_blob_mesh.radial_segments = 8
	_blob_mesh.rings = 4
	_blob_mesh.material = _blob_mat
	_drop_mesh = CapsuleMesh.new()
	_drop_mesh.radius = 0.07
	_drop_mesh.height = 0.42
	_drop_mesh.radial_segments = 6
	_drop_mesh.rings = 2
	_drop_mesh.material = _blob_mat


## Warm-up items (Vfx.warm_up): one of each piece.
static func warm_up_items() -> Array[Node3D]:
	_materials()
	var out: Array[Node3D] = []
	var s := SlimeSplash.new()
	out.append(s)
	return out


func _ready() -> void:
	_materials()
	var light := color.lerp(Color(0.9, 1.0, 0.7), 0.45)
	# Crown: fat blobs thrown up and out all round the hole.
	var crown := _particles(48, 0.95, _blob_mesh)
	crown.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	crown.emission_ring_axis = Vector3.UP
	crown.emission_ring_radius = 0.55 * size
	crown.emission_ring_inner_radius = 0.35 * size
	crown.emission_ring_height = 0.05
	crown.direction = Vector3.UP
	crown.spread = 38.0
	crown.initial_velocity_min = 6.0 * size
	crown.initial_velocity_max = 10.0 * size
	crown.gravity = Vector3(0, -20.0, 0)
	crown.scale_amount_min = 1.0 * size
	crown.scale_amount_max = 2.6 * size
	crown.color_ramp = _ramp(light, color)
	crown.scale_amount_curve = _shrink()
	# Jet: a column of long drops straight up the middle.
	var jet := _particles(18, 0.85, _drop_mesh)
	jet.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	jet.emission_sphere_radius = 0.2 * size
	jet.direction = Vector3.UP
	jet.spread = 9.0
	jet.initial_velocity_min = 9.0 * size
	jet.initial_velocity_max = 15.0 * size
	jet.gravity = Vector3(0, -22.0, 0)
	jet.particle_flag_align_y = true
	jet.scale_amount_min = 1.0 * size
	jet.scale_amount_max = 1.8 * size
	jet.color_ramp = _ramp(Color(0.95, 1.0, 0.8), color)
	jet.scale_amount_curve = _shrink()
	# Bubbles popping up after it's gone under.
	var bub := _particles(14, 0.7, _blob_mesh)
	bub.one_shot = true
	bub.explosiveness = 0.0
	bub.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	bub.emission_sphere_radius = 0.7 * size
	bub.direction = Vector3.UP
	bub.spread = 15.0
	bub.initial_velocity_min = 0.6
	bub.initial_velocity_max = 1.4
	bub.gravity = Vector3.ZERO
	bub.scale_amount_min = 0.3
	bub.scale_amount_max = 0.8
	bub.color_ramp = _ramp(light, color)
	bub.position.y = -0.1
	bub.emitting = false
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		if is_instance_valid(bub):
			bub.emitting = true)
	# Foam patch and the ripple rings, flat on the surface.
	_foam_mat = _ring_material(1.0)
	_foam = _flat(_foam_mat)
	for i in 3:
		var m := _ring_material(0.0)
		_ring_mats.append(m)
		_rings.append(_flat(m))
	_update()


func _particles(n: int, life: float, mesh: Mesh) -> CPUParticles3D:
	var c := CPUParticles3D.new()
	c.amount = n
	c.lifetime = life
	c.one_shot = true
	c.explosiveness = 0.95
	c.local_coords = false
	c.mesh = mesh
	c.emitting = true
	add_child(c)
	return c


func _ramp(a: Color, b: Color) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	g.colors = PackedColorArray([a, b, Color(b, 0.0)])
	return g


func _shrink() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(0.75, 0.8))
	c.add_point(Vector2(1.0, 0.0))
	return c


func _ring_material(disc: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = RING_SHADER
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("disc", disc)
	return m


func _flat(m: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2.ONE * 2.0
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.04
	add_child(mi)
	return mi


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	_update()


func _update() -> void:
	# Foam: bursts open, then fades.
	var fk := clampf(_t / 0.18, 0.0, 1.0)
	_foam.scale = Vector3.ONE * size * lerpf(0.3, 1.2, 1.0 - pow(1.0 - fk, 2.0))
	_foam_mat.set_shader_parameter("amount", 1.0 - smoothstep(0.35, 1.2, _t))
	# Rings, one after another, racing out and thinning.
	for i in _rings.size():
		var lt := _t - i * 0.14
		var k := clampf(lt / 1.1, 0.0, 1.0)
		_rings[i].visible = lt > 0.0 and k < 1.0
		_rings[i].scale = Vector3.ONE * size * lerpf(0.5, 4.2 - i * 0.7, 1.0 - pow(1.0 - k, 2.5))
		_ring_mats[i].set_shader_parameter("amount", (1.0 - k) * (1.0 - i * 0.2))
		_ring_mats[i].set_shader_parameter("width", lerpf(0.22, 0.08, k))
