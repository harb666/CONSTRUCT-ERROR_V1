class_name PlasmaTrail
extends MeshInstance3D
## The Neon Sentinel's booster trail (owner asked: "amazing looking plasma
## trails ... similar to halo sentinels"): a glowing plasma ribbon streaming
## from the booster through the air it flew through - white-hot core, neon
## glow cooling from lime-yellow to magenta, energy pulses racing back along
## it (plasma_trail.gdshader) - plus a throbbing flare at the booster mouth
## (booster_flare.gdshader) and a few neon sparks shed into the wake. Even
## hovering it streams a short plume (the exhaust blows the trail back).
## Shaped on the GPU like SmokeTrail: one fixed mesh shared by every trail,
## the points sent as uniforms, so no graphics buffers are rebuilt per frame.
## Lives in the world (top level); `follow` is the exhaust node it trails.

const MAX_POINTS := 48
const SHADER := preload("res://scripts/vfx/plasma_trail.gdshader")
const FLARE_SHADER := preload("res://scripts/vfx/booster_flare.gdshader")

@export var lifetime := 0.85
## A new point every this many metres travelled, or this often (s).
@export var spacing := 0.18
@export var interval := 0.03
## The exhaust blows each new point back this fast (m/s), slowing down.
@export var exhaust_speed := 3.2
@export var exhaust_drag := 3.5
@export var head_width := 0.13
@export var max_width := 0.55
@export var flare_size := 0.42

static var _ribbon: ArrayMesh

## The exhaust node it streams from (the way the exhaust blows is `back`,
## set every frame by its owner).
var follow: Node3D
## The way the exhaust blows (world, unit).
var back := Vector3.BACK
## 0..1: how hard the booster is pushing (flare size, spark rate).
var throttle := 0.5
## Fades the whole effect (1 = on; the trail dies away when 0).
var emitting := true
var flare: MeshInstance3D
var sparks: CPUParticles3D
var _pts: Array[Vector3] = []
var _vel: Array[Vector3] = []
var _age: Array[float] = []
var _since := 0.0
var _mat: ShaderMaterial
var _flare_mat: ShaderMaterial
var _upload := PackedVector4Array()
var _fade := 1.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = _shared_ribbon()
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material_override = _mat
	_upload.resize(MAX_POINTS)
	_mat.set_shader_parameter("lifetime", lifetime)
	_mat.set_shader_parameter("head_width", head_width)
	_mat.set_shader_parameter("max_width", max_width)
	flare = MeshInstance3D.new()
	flare.name = "Flare"
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	flare.mesh = q
	_flare_mat = ShaderMaterial.new()
	_flare_mat.shader = FLARE_SHADER
	_flare_mat.set_shader_parameter("size", flare_size)
	flare.material_override = _flare_mat
	flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flare.top_level = true
	flare.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(flare)
	sparks = CPUParticles3D.new()
	sparks.name = "Sparks"
	sparks.amount = 14
	sparks.lifetime = 0.45
	sparks.local_coords = false
	sparks.direction = Vector3(0, 0, 1)
	sparks.spread = 22.0
	sparks.initial_velocity_min = 1.5
	sparks.initial_velocity_max = 4.0
	sparks.gravity = Vector3(0, -1.5, 0)
	sparks.damping_min = 2.0
	sparks.damping_max = 4.0
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	sparks.scale_amount_curve = curve
	var sq := QuadMesh.new()
	sq.size = Vector2(0.045, 0.045)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.albedo_color = Color(0.85, 1.0, 0.35)
	sm.vertex_color_use_as_albedo = true
	sq.material = sm
	sparks.mesh = sq
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 0.8))
	ramp.set_color(1, Color(1.0, 0.15, 0.6, 0.0))
	sparks.color_ramp = ramp
	sparks.top_level = true
	add_child(sparks)


## The fixed ribbon mesh: for each pair of neighbouring points, two strips
## (edge-centre, centre-edge) of two triangles; UV = (point, column).
static func _shared_ribbon() -> ArrayMesh:
	if _ribbon:
		return _ribbon
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in MAX_POINTS - 1:
		for col in 2:
			var c0 := float(col) - 1.0
			var c1 := float(col)
			for v in [[i, c0], [i + 1, c0], [i + 1, c1], [i, c0], [i + 1, c1], [i, c1]]:
				verts.append(Vector3.ZERO)
				uvs.append(Vector2(v[0], v[1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	_ribbon = ArrayMesh.new()
	_ribbon.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_ribbon.custom_aabb = AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000))
	return _ribbon


## Points in the trail now (tests).
func point_count() -> int:
	return _pts.size()


func _process(delta: float) -> void:
	var on := emitting and follow != null and is_instance_valid(follow) and follow.is_inside_tree()
	_fade = move_toward(_fade, 1.0 if on else 0.0, delta * (6.0 if on else 1.5))
	for i in _age.size():
		_age[i] += delta
		_pts[i] += _vel[i] * delta
		_vel[i] *= maxf(0.0, 1.0 - exhaust_drag * delta)
	while not _age.is_empty() and _age[0] >= lifetime:
		_pts.remove_at(0)
		_vel.remove_at(0)
		_age.remove_at(0)
	if on:
		var p := follow.global_position
		_since += delta
		var n := _pts.size()
		if n < 2 or _pts[n - 2].distance_to(p) >= spacing or _since >= interval:
			_since = 0.0
			if n >= MAX_POINTS:
				_pts.remove_at(0)
				_vel.remove_at(0)
				_age.remove_at(0)
			_pts.append(p)
			_vel.append(back * exhaust_speed * randf_range(0.8, 1.2))
			_age.append(0.0)
		else:
			_pts[n - 1] = p  # the head stays on the booster
			_age[n - 1] = 0.0
		flare.global_position = p
	flare.visible = _fade > 0.01
	_flare_mat.set_shader_parameter("throttle", throttle)
	_flare_mat.set_shader_parameter("intensity", _fade)
	sparks.emitting = on and throttle > 0.25
	if on:
		sparks.global_transform = Transform3D(Basis.looking_at(-back, Vector3.UP if absf(back.y) < 0.95 else Vector3.RIGHT), follow.global_position)
	var count := _pts.size()
	visible = count >= 2 and _fade > 0.01
	if not visible:
		return
	for i in count:
		var q := _pts[i]
		_upload[i] = Vector4(q.x, q.y, q.z, _age[i])
	_mat.set_shader_parameter("pts", _upload)
	_mat.set_shader_parameter("count", count)
	_mat.set_shader_parameter("intensity", _fade)
