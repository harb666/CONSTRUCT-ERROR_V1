class_name FrostFreeze
extends Node3D
## A robot frozen solid by the Frost Byte (child of the robot; owner asked).
##  - Grunts / skirmishers ("light"): encased in a thick ice shell in their
##    own frozen pose (ice_coat.gdshader as a material_overlay on every body
##    mesh: a sculpture of the body), jagged ice crystals growing out of it
##    and a patch of frosted ice on the floor round its feet. Any hit from a
##    player shatters it (RobotEnemy.shatter) and the pieces melt away.
##  - The robot boss ("heavy"): a white frosted layer over its armour, icicles
##    hanging off its arms, chest and guns and frost on the floor; it just
##    stands frozen and takes damage as usual.
## Frozen for `seconds` (refreshed if blasted again), then it thaws: the ice
## cracks off in a burst of shards and the robot carries on. The robot holds
## still meanwhile (its own scripts check `active`). While frozen it strains
## in the ice: the owner's two frozen sounds (Sfx.ENEMY_FROZEN_1 / _2), one
## after the other, never the same twice running, until it thaws or shatters.

const SHADER := preload("res://scripts/vfx/ice_coat.gdshader")
const GROW_TIME := 0.28
const THAW_TIME := 0.35

static var frozen_count := 0
## Frozen sounds (owner asked: quiet unless the player is near): full volume
## within `near` m of the robot, fading out to silence at `far` m.
static var frozen_sound_near := 2.5
static var frozen_sound_far := 9.0
static var frozen_sound_near_heavy := 5.0
static var frozen_sound_far_heavy := 15.0

var robot: Node3D
var heavy := false
var active := false
var time_left := 0.0
## Robot's size factor (skirmishers 2x, the boss's model scale).
var size := 1.0
var _mat: ShaderMaterial
var _meshes: Array[GeometryInstance3D] = []
var _crystals: Array[Node3D] = []
var _crystal_scale: Array[Vector3] = []
var _floor: MeshInstance3D
var _t := 0.0
var _thaw_t := -1.0
var _shards: CPUParticles3D
var _sound: DynamicSound
var _last_sound := -1
var _last_chip_ms := -100000
## Frozen sounds started (tests).
var sounds_played := 0


## Freeze `r` for `seconds` (or keep it frozen longer if it already is).
static func apply(r: Node3D, seconds: float, is_heavy: bool, body_size: float) -> FrostFreeze:
	var f := r.get_node_or_null("FrostFreeze") as FrostFreeze
	if f and f.active:
		f.time_left = maxf(f.time_left, seconds)
		f._thaw_t = -1.0
		return f
	if f:
		f.queue_free()
		f.name = "FrostFreezeOld"
	f = FrostFreeze.new()
	f.name = "FrostFreeze"
	f.robot = r
	f.heavy = is_heavy
	f.size = body_size
	f.time_left = seconds
	r.add_child(f)
	return f


static func is_frozen(r: Node) -> bool:
	var f := r.get_node_or_null("FrostFreeze") as FrostFreeze if r else null
	return f != null and f.active


func _ready() -> void:
	active = true
	frozen_count += 1
	top_level = false
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("seed", randf() * 50.0)
	if heavy:
		_mat.set_shader_parameter("frost", 1.0)
		_mat.set_shader_parameter("thickness", 0.012)
		_mat.set_shader_parameter("scale", 9.0)
	else:
		_mat.set_shader_parameter("frost", 0.12)
		# Mesh units: the grunt's model is ~1 unit tall per metre.
		_mat.set_shader_parameter("thickness", 0.045)
		_mat.set_shader_parameter("scale", 7.0)
	_mat.set_shader_parameter("amount", 0.0)
	var visual := robot.get_node_or_null("Visual") as Node3D
	var root: Node = visual if visual else robot
	for g: GeometryInstance3D in root.find_children("*", "GeometryInstance3D", true, false):
		if g is MeshInstance3D and g.material_overlay == null and not (g is CPUParticles3D):
			g.material_overlay = _mat
			_meshes.append(g)
	_make_crystals()
	_make_floor_frost()
	_shards = _make_shards()
	add_child(_shards)
	_burst(0.8)
	_update_look()
	_start_sound()


func _physics_process(delta: float) -> void:
	_t += delta
	if _thaw_t >= 0.0:
		_thaw_t += delta
		_update_look()
		if _thaw_t >= THAW_TIME:
			_finish()
		return
	if not active:
		return
	time_left -= delta
	_update_look()
	if time_left <= 0.0:
		thaw()


func _update_look() -> void:
	var grow := clampf(_t / GROW_TIME, 0.0, 1.0)
	grow = 1.0 - pow(1.0 - grow, 3.0)
	var out := 1.0 - clampf(_thaw_t / THAW_TIME, 0.0, 1.0) if _thaw_t >= 0.0 else 1.0
	var a := grow * out
	_mat.set_shader_parameter("amount", a)
	for i in _crystals.size():
		var c := _crystals[i]
		if is_instance_valid(c):
			c.scale = _crystal_scale[i] * maxf(a, 0.001)
	if _floor:
		_floor.scale = Vector3.ONE * maxf(a, 0.001)


## Thaw: the ice cracks off and the robot is free.
func thaw() -> void:
	if not active:
		return
	active = false
	_thaw_t = 0.0
	_burst(0.6)
	Sfx.fade_out(_sound, 0.3)
	if robot and robot.has_method("on_thawed"):
		robot.on_thawed()


## Shattered (light robots, by a hit): the crystals burst off as shards; the
## ice coat stays on the body's meshes (now flying pieces) to melt with them.
func shatter() -> void:
	active = false
	_burst(1.4)
	Sfx.fade_out(_sound, 0.15)
	for c in _crystals:
		if is_instance_valid(c):
			c.queue_free()
	_crystals.clear()
	if _floor:
		var tw := _floor.create_tween()
		tw.tween_property(_floor, "scale", Vector3.ONE * 0.001, 1.2).set_delay(0.6)
	# The shards play on; free once they're done (the meshes keep the coat).
	_meshes.clear()
	get_tree().create_timer(2.2).timeout.connect(func() -> void:
		if is_instance_valid(self):
			queue_free())


## Hit while frozen (the boss): `seconds` less to go, and a few chips of ice
## fly off (at most every 0.25 s).
func chip(seconds: float) -> void:
	if not active:
		return
	time_left -= seconds
	var now := Time.get_ticks_msec()
	if _shards and now - _last_chip_ms >= 250:
		_last_chip_ms = now
		_shards.restart()
		_shards.emitting = true


# --- Sound ---

func _start_sound() -> void:
	# Owner asked: quiet unless the player is near the frozen robot.
	var near := frozen_sound_near_heavy if heavy else frozen_sound_near
	var far := frozen_sound_far_heavy if heavy else frozen_sound_far
	_sound = Sfx.emitter(self, Sfx.ENEMY_FROZEN_1, 0.0, near, far)
	_sound.position = Vector3.UP * (2.4 if heavy else 0.9 * size)
	_sound.finished.connect(_next_sound)
	_next_sound()


func _next_sound() -> void:
	if not active or _sound == null:
		return
	var pick := randi() % 2 if _last_sound < 0 else 1 - _last_sound
	_last_sound = pick
	_sound.stream = Sfx.ENEMY_FROZEN_1 if pick == 0 else Sfx.ENEMY_FROZEN_2
	_sound.fade = 1.0
	_sound.play()
	sounds_played += 1


func _finish() -> void:
	for g in _meshes:
		if is_instance_valid(g) and g.material_overlay == _mat:
			g.material_overlay = null
	_meshes.clear()
	queue_free()


func _exit_tree() -> void:
	if active:
		active = false
	frozen_count = maxi(frozen_count - 1, 0)
	for g in _meshes:
		if is_instance_valid(g) and g.material_overlay == _mat:
			g.material_overlay = null


# --- Look ---

func _skeleton() -> Skeleton3D:
	var found := robot.find_children("*", "Skeleton3D", true, false)
	return found[0] if not found.is_empty() else null


## Jagged crystals growing out of the ice (light) / icicles hanging off it
## (heavy), on the body's bones.
func _make_crystals() -> void:
	var sk := _skeleton()
	if sk == null:
		return
	var bones: Array
	var count: int
	if heavy:
		bones = ["LeftForeArm", "RightForeArm", "LeftArm", "RightArm", "Spine2", "Spine2", "Head", "LeftHand", "RightHand", "Hips", "LeftLeg", "RightLeg"]
		count = 12
	else:
		bones = ["Spine2", "Spine1", "Head", "LeftArm", "RightArm", "LeftForeArm", "RightForeArm", "Hips", "LeftUpLeg", "RightUpLeg", "Neck", "Spine"]
		count = 11
	for i in count:
		var b := sk.find_bone("mixamorig_" + bones[i % bones.size()])
		if b < 0:
			continue
		var att := BoneAttachment3D.new()
		att.bone_name = sk.get_bone_name(b)
		sk.add_child(att)
		var mi := MeshInstance3D.new()
		var holder := Node3D.new()
		att.add_child(holder)
		holder.add_child(mi)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_overlay = null
		var len: float
		if heavy:
			# Icicle: hangs straight down, wide at the top.
			len = randf_range(0.13, 0.26)
			holder.position = Vector3(randf_range(-0.05, 0.05), randf_range(0.0, 0.08), randf_range(-0.05, 0.05))
			# Bone frames vary: undo the bone's turn so it hangs straight
			# down (the body is frozen still).
			mi.position = Vector3(0, -len * 0.5, 0)
			var bone_basis := (sk.global_transform.basis * sk.get_bone_global_pose(b).basis).orthonormalized()
			holder.basis = bone_basis.inverse()
		else:
			# Crystal: a long faceted spike sticking out at a random angle.
			len = randf_range(0.12, 0.26)
			mi.position = Vector3(0, len * 0.45, 0)
			holder.rotation = Vector3(randf_range(-1.3, 1.3), randf() * TAU, randf_range(-1.3, 1.3))
			holder.position = Vector3(randf_range(-0.06, 0.06), randf_range(0.0, 0.12), randf_range(-0.06, 0.06))
		# One shared unit crystal / icicle mesh, sized by scale.
		mi.mesh = crystal_mesh(heavy)
		mi.scale = Vector3.ONE * len
		_crystals.append(holder)
		_crystal_scale.append(holder.scale)
		holder.scale = Vector3.ONE * 0.001


## The crystals' / icicles' mesh, 1 m long (shared by every frozen robot,
## nothing built per freeze): a spike pointing up, or an icicle pointing
## down (wide at the top).
static func crystal_mesh(is_heavy: bool) -> CylinderMesh:
	if _crystal_meshes.has(is_heavy):
		return _crystal_meshes[is_heavy]
	var m := CylinderMesh.new()
	m.radial_segments = 5
	m.rings = 1
	m.cap_top = false
	m.top_radius = 0.2 if is_heavy else 0.0
	m.bottom_radius = 0.0 if is_heavy else 0.2
	m.height = 1.0
	m.material = crystal_material(is_heavy)
	_crystal_meshes[is_heavy] = m
	return m


static var _crystal_meshes := {}
static var _crystal_mats := {}
static var _shard_meshes := {}


## Clear ice for the crystals and shards (shared, one per kind).
static func crystal_material(is_heavy: bool) -> StandardMaterial3D:
	if _crystal_mats.has(is_heavy):
		return _crystal_mats[is_heavy]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.78, 0.93, 1.0, 0.72) if not is_heavy else Color(0.88, 0.96, 1.0, 0.85)
	m.metallic = 0.0
	m.roughness = 0.05
	m.rim_enabled = true
	m.rim = 1.0
	m.rim_tint = 0.2
	m.emission_enabled = true
	m.emission = Color(0.45, 0.75, 1.0)
	m.emission_energy_multiplier = 0.35
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_crystal_mats[is_heavy] = m
	return m


## A patch of frosted ice on the floor round its feet.
func _make_floor_frost() -> void:
	_floor = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	var r := (1.1 if not heavy else 3.6) * (size if not heavy else 1.0)
	q.size = Vector2.ONE * r * 2.0
	_floor.mesh = q
	var m := ShaderMaterial.new()
	m.shader = FROST_FLOOR
	m.set_shader_parameter("seed", randf() * 30.0)
	_floor.material_override = m
	_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_floor.top_level = true
	add_child(_floor)
	_floor.global_transform = Transform3D(Basis(Vector3.UP, randf() * TAU), robot.global_position + Vector3.UP * 0.03)


const FROST_FLOOR := preload("res://scripts/vfx/frost_floor.gdshader")


func _make_shards() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var k := 2.0 if heavy else maxf(size, 1.0)
	var key := Vector2(k, 1.0 if heavy else 0.0)
	if not _shard_meshes.has(key):
		var mesh := PrismMesh.new()
		mesh.size = Vector3(0.06, 0.16, 0.04) * k
		mesh.material = crystal_material(heavy)
		_shard_meshes[key] = mesh
	p.mesh = _shard_meshes[key]
	p.amount = 26
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.6 * (3.0 if heavy else size)
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 7.0
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.gravity = Vector3(0, -16, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	p.position = Vector3.UP * (1.0 * (3.0 if heavy else size))
	return p


## Ice shards burst out (freezing, thawing, shattering) with a cold puff.
func _burst(strength: float) -> void:
	if _shards:
		_shards.amount = clampi(int(26 * strength), 8, 40)
		_shards.restart()
		_shards.emitting = true
	var host := get_tree().current_scene if get_tree().current_scene else get_tree().root
	var at := robot.global_position + Vector3.UP * (1.0 * (3.0 if heavy else size))
	for k in (3 if strength >= 1.0 else 2):
		var pf := ToonPuff.new()
		pf.set_colors(Color(0.86, 0.94, 1.0))
		host.add_child(pf)
		pf.size = randf_range(0.45, 0.7) * (2.5 if heavy else size)
		pf.life = randf_range(0.7, 1.0)
		pf.rise = 0.4
		pf.drift = Vector3(randf_range(-1, 1), 0.2, randf_range(-1, 1)) * 0.8
		pf.play(at + Vector3(randf_range(-0.4, 0.4), randf_range(-0.6, 0.3), randf_range(-0.4, 0.4)), false)
		get_tree().create_timer(pf.life + 0.3).timeout.connect(pf.queue_free)


## One of each material the freeze uses (ice coat, crystals as meshes and as
## particles, floor frost), for Vfx.warm_up: phones prepare their shaders
## behind the title screen instead of stalling the first time a crowd is
## frozen.
static func warm_up_items() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var coat := MeshInstance3D.new()
	coat.mesh = SphereMesh.new()
	var cm := ShaderMaterial.new()
	cm.shader = SHADER
	coat.material_override = cm
	out.append(coat)
	# As an overlay too (how it is drawn on the robots).
	var under := MeshInstance3D.new()
	under.mesh = BoxMesh.new()
	under.material_overlay = cm
	out.append(under)
	var fl := MeshInstance3D.new()
	fl.mesh = QuadMesh.new()
	var fm := ShaderMaterial.new()
	fm.shader = FROST_FLOOR
	fl.material_override = fm
	out.append(fl)
	for h in [false, true]:
		var c := MeshInstance3D.new()
		c.mesh = crystal_mesh(h)
		out.append(c)
		var p := CPUParticles3D.new()
		var pm := PrismMesh.new()
		pm.material = crystal_material(h)
		p.mesh = pm
		p.amount = 2
		p.lifetime = 0.5
		p.initial_velocity_min = 0.0
		p.initial_velocity_max = 0.0
		p.gravity = Vector3.ZERO
		p.emitting = true
		out.append(p)
	return out
