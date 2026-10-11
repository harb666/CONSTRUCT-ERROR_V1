class_name FrostBlizzard
extends Node3D
## The Frost Byte's blast (owner asked): a powerful cold blizzard roaring out
## of the muzzle in a cone that widens further out - dramatic spiralling
## bands of white and ice blue (frost_spiral.gdshader on a mesh built once),
## a storm of snow, glittering ice shards, rolling frost mist and frosted
## floor along its path. It races out at `speed`; every robot it reaches in
## the cone (not behind a wall) is frozen solid for `freeze_time` (grunts and
## skirmishers into ice sculptures, the boss frosted over - FrostFreeze).
## Pooled (2); local +Z = the blast's direction.

const SPIRAL_SHADER := preload("res://scripts/vfx/frost_spiral.gdshader")
const VORTEX_SHADER := preload("res://scripts/vfx/frost_vortex.gdshader")
const FLOOR_SHADER := preload("res://scripts/vfx/frost_floor.gdshader")
const POOL_SIZE := 2
const BANDS := 8
const SEGMENTS := 72
const TWIST := 0.85  # turns of the spiral per metre (radians x 2pi / m)
const MIST_PUFFS := 4
const FLOOR_PATCHES := 4

## Reach (m), radius at the muzzle and how fast it widens (m per m).
@export var length := 16.0
@export var start_radius := 0.35
@export var widen := 0.3
@export var speed := 30.0
@export var life := 1.35
@export var freeze_time := 10.0

static var _pool: Array[FrostBlizzard] = []
static var _mesh: ArrayMesh
static var _tube: ArrayMesh
static var spawned := 0

var active := false
var shooter: Node3D
## Robots frozen by this blast (tests).
var frozen: Array = []
var _t := 99.0
var _dir := Vector3.FORWARD
var _origin := Vector3.ZERO
var _spiral: MeshInstance3D
var _spiral_mat: ShaderMaterial
var _vortex: MeshInstance3D
var _vortex_mat: ShaderMaterial
var _snow: CPUParticles3D
var _shards: CPUParticles3D
var _mist: Array[ToonPuff] = []
var _mist_d: Array[float] = []
var _floor: Array[MeshInstance3D] = []
var _floor_d: Array[float] = []
var _done := {}


static func fire(tree: SceneTree, at: Vector3, dir: Vector3, from: Node3D) -> FrostBlizzard:
	_pool = _pool.filter(func(b: FrostBlizzard) -> bool: return is_instance_valid(b) and b.is_inside_tree())
	var b: FrostBlizzard = null
	for p in _pool:
		if not p.active:
			b = p
			break
	if b == null:
		if _pool.size() < POOL_SIZE:
			b = FrostBlizzard.new()
			var host: Node = tree.current_scene if tree.current_scene else tree.root
			host.add_child(b)
			_pool.append(b)
		else:
			b = _pool[0]
	b._start(at, dir, from)
	spawned += 1
	return b


## Radius of the cone `d` metres out.
func radius_at(d: float) -> float:
	return start_radius + widen * d


## How far the front has got (m).
func front() -> float:
	return minf(_t * speed, length)


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if _mesh == null:
		_mesh = _build_mesh()
	if _tube == null:
		_tube = _build_tube()
	_vortex = MeshInstance3D.new()
	_vortex.mesh = _tube
	_vortex_mat = ShaderMaterial.new()
	_vortex_mat.shader = VORTEX_SHADER
	_vortex.material_override = _vortex_mat
	_vortex.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vortex.extra_cull_margin = 20.0
	add_child(_vortex)
	_spiral = MeshInstance3D.new()
	_spiral.mesh = _mesh
	_spiral_mat = ShaderMaterial.new()
	_spiral_mat.shader = SPIRAL_SHADER
	_spiral.material_override = _spiral_mat
	_spiral.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spiral.extra_cull_margin = 20.0
	add_child(_spiral)
	_snow = _make_snow()
	add_child(_snow)
	_shards = _make_shards()
	add_child(_shards)
	for k in MIST_PUFFS:
		var pf := ToonPuff.new()
		pf.set_colors(Color(0.88, 0.95, 1.0))
		add_child(pf)
		_mist.append(pf)
		_mist_d.append(0.0)
	for k in FLOOR_PATCHES:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.orientation = PlaneMesh.FACE_Y
		mi.mesh = q
		var m := ShaderMaterial.new()
		m.shader = FLOOR_SHADER
		m.set_shader_parameter("seed", randf() * 30.0)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true
		mi.visible = false
		add_child(mi)
		_floor.append(mi)
		_floor_d.append(0.0)
	visible = false
	set_process(false)
	set_physics_process(false)


## Spiral bands wound round the cone (local +Z), built once and shared.
func _build_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for b in BANDS:
		var phase := TAU * b / BANDS
		var white := 1.0 if b % 2 == 0 else 0.0
		# Inner bands (smaller radius, tighter) and outer ones alternate.
		var rk := 1.0 if b % 3 != 2 else 0.62
		var base := verts.size()
		for i in SEGMENTS + 1:
			var u := float(i) / SEGMENTS
			var z := u * length
			var r := radius_at(z) * rk
			var a := phase + z * TWIST * (1.0 if b % 2 == 0 else 0.92)
			# Band width on the cone's surface, growing with the cone.
			var half := (0.22 + 0.16 * z) * 0.5
			var da := half / maxf(r, 0.05)
			for side in 2:
				var aa := a + (da if side == 1 else -da)
				verts.append(Vector3(cos(aa) * r, sin(aa) * r, z))
				uvs.append(Vector2(u, float(side)))
				cols.append(Color(white, 0, 0, 1))
			if i > 0:
				var k := base + i * 2
				idx.append_array([k - 2, k - 1, k, k - 1, k + 1, k])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## The blizzard's swirling body: an open tube along the cone (built once).
func _build_tube() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 40
	var segs := 24
	for i in rings + 1:
		var u := float(i) / rings
		var z := u * length
		# A little inside the spiral bands.
		var r := radius_at(z) * 0.82
		for j in segs + 1:
			var v := float(j) / segs
			var a := v * TAU
			st.set_uv(Vector2(u, v))
			st.set_normal(Vector3(cos(a), sin(a), -widen).normalized())
			st.add_vertex(Vector3(cos(a) * r, sin(a) * r, z))
	for i in rings:
		for j in segs:
			var a := i * (segs + 1) + j
			var b := a + segs + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	return st.commit()


func _make_snow() -> CPUParticles3D:
	var p := Vfx.particles("glow", 0.12, 150, 0.62)
	p.one_shot = true
	p.explosiveness = 0.55
	p.local_coords = false
	p.direction = Vector3(0, 0, 1)
	p.spread = rad_to_deg(atan(widen)) * 1.05
	p.initial_velocity_min = speed * 0.75
	p.initial_velocity_max = speed * 1.05
	p.damping_min = 4.0
	p.damping_max = 9.0
	p.gravity = Vector3(0, -2.0, 0)
	p.scale_amount_min = 0.35
	p.scale_amount_max = 1.4
	p.color_ramp = Vfx.ramp([Color(1, 1, 1, 1), Color(0.75, 0.92, 1.0, 0.9), Color(0.6, 0.85, 1.0, 0.0)], [0.0, 0.55, 1.0])
	p.emitting = false
	return p


func _make_shards() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.07, 0.24, 0.05)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.82, 0.95, 1.0, 0.85)
	m.roughness = 0.05
	m.emission_enabled = true
	m.emission = Color(0.5, 0.85, 1.0)
	m.emission_energy_multiplier = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = m
	p.mesh = mesh
	p.amount = 40
	p.lifetime = 0.75
	p.one_shot = true
	p.explosiveness = 0.7
	p.local_coords = false
	p.direction = Vector3(0, 0, 1)
	p.spread = rad_to_deg(atan(widen))
	p.initial_velocity_min = speed * 0.55
	p.initial_velocity_max = speed * 0.95
	p.angular_velocity_min = -900.0
	p.angular_velocity_max = 900.0
	p.damping_min = 3.0
	p.damping_max = 8.0
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.5
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	return p


func _start(at: Vector3, dir: Vector3, from: Node3D) -> void:
	shooter = from
	_dir = dir.normalized() if dir.length_squared() > 1e-4 else Vector3.FORWARD
	_origin = at
	var up := Vector3.UP if absf(_dir.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(_dir).normalized()
	global_transform = Transform3D(Basis(x, _dir.cross(x).normalized(), _dir), at)
	_t = 0.0
	active = true
	frozen.clear()
	_done.clear()
	_spiral_mat.set_shader_parameter("seed", randf() * 20.0)
	_vortex_mat.set_shader_parameter("seed", randf() * 20.0)
	for p in [_snow, _shards]:
		p.restart()
		p.emitting = true
	# Frost mist rolling out along the blast, bigger further out.
	for i in _mist.size():
		var d := length * (0.35 + 0.6 * float(i) / maxf(_mist.size() - 1, 1))
		_mist_d[i] = d
		var pf := _mist[i]
		pf.size = radius_at(d) * randf_range(0.3, 0.42)
		pf.life = randf_range(0.9, 1.3)
		pf.rise = 0.5
		pf.drift = _dir * randf_range(1.0, 2.5) + Vector3(randf_range(-0.6, 0.6), 0.2, randf_range(-0.6, 0.6))
		pf.delay = d / speed
		# Out at the edges of the blast, rolling on as it passes.
		var side := Vector3(randf_range(-1, 1), randf_range(-0.4, 0.6), randf_range(-1, 1))
		side = (side - _dir * side.dot(_dir)).normalized()
		pf.play(at + _dir * d + side * radius_at(d) * 0.75, false)
	# Frost on the floor under the blast's path.
	var space := get_world_3d().direct_space_state
	for i in _floor.size():
		var d := length * (0.2 + 0.25 * i)
		_floor_d[i] = d
		var p := at + _dir * d
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * (radius_at(d) + 2.0))
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		var f := _floor[i]
		f.visible = false
		if hit.is_empty() or not (hit.collider is StaticBody3D):
			continue
		var r := radius_at(d) * 1.1
		(f.mesh as QuadMesh).size = Vector2.ONE * r * 2.0
		f.global_transform = Transform3D(Basis(Vector3.UP, randf() * TAU), hit.position + Vector3.UP * 0.035)
		f.scale = Vector3.ONE * 0.001
		f.set_meta(&"on", true)
	visible = true
	set_process(true)
	set_physics_process(true)
	_update()


func _process(delta: float) -> void:
	_t += delta
	if _t >= life + 2.6:
		active = false
		visible = false
		set_process(false)
		set_physics_process(false)
		for f in _floor:
			f.visible = false
		return
	_update()


func _update() -> void:
	var fr := front()
	_spiral.visible = _t < life
	_vortex.visible = _spiral.visible
	if _spiral.visible:
		_vortex_mat.set_shader_parameter("front", fr / length + 0.06)
		_vortex_mat.set_shader_parameter("fade", 1.0 - smoothstep(life * 0.45, life, _t))
		_spiral_mat.set_shader_parameter("front", fr / length + 0.04)
		_spiral_mat.set_shader_parameter("spin", _t * 9.0)
		_spiral_mat.set_shader_parameter("fade", 1.0 - smoothstep(life * 0.5, life, _t))
	for i in _floor.size():
		var f := _floor[i]
		if not f.has_meta(&"on"):
			continue
		var reach := clampf((fr - _floor_d[i]) / 2.0, 0.0, 1.0)
		var melt := 1.0 - clampf((_t - life - 1.4) / 1.2, 0.0, 1.0)
		f.visible = reach > 0.0 and melt > 0.0
		f.scale = Vector3.ONE * maxf(reach * melt, 0.001)
		if melt <= 0.0:
			f.remove_meta(&"on")


## Freeze every robot the front has reached inside the cone.
func _physics_process(_delta: float) -> void:
	if _t > life * 0.7:
		return
	var fr := front()
	var space := get_world_3d().direct_space_state
	for n in get_tree().get_nodes_in_group(&"enemies"):
		if _done.has(n) or not is_instance_valid(n):
			continue
		var e := n as Node3D
		var heavy := e is RobotBoss
		if not (e is RobotEnemy or heavy) or not e.get(&"alive"):
			continue
		var s = e.get(&"size_scale")
		var sz := float(s) if s != null else 1.0
		var mid := e.global_position + Vector3.UP * (2.4 if heavy else 0.9 * sz)
		var rel := mid - _origin
		var along := rel.dot(_dir)
		if along < 0.0 or along > fr:
			continue
		var body_r := 1.8 if heavy else 0.45 * sz
		if (rel - _dir * along).length() > radius_at(along) + body_r:
			continue
		# Not through walls.
		var q := PhysicsRayQueryParameters3D.create(_origin, mid)
		q.collision_mask = 1
		var ex: Array[RID] = [(e as CollisionObject3D).get_rid()]
		if shooter is CollisionObject3D:
			ex.append((shooter as CollisionObject3D).get_rid())
		q.exclude = ex
		var hit := space.intersect_ray(q)
		_done[n] = true
		if not hit.is_empty() and hit.collider is StaticBody3D:
			continue
		e.call(&"frost_freeze", freeze_time)
		frozen.append(e)
