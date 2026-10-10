class_name PlayerRocket
extends Node3D
## The Rocket Launcher's rocket (pooled, no physics body; ray-cast movement).
## Same size and look as the one loaded in the launcher's bore: its nose IS
## the launcher model's own warhead mesh (same texture), on a slim body of
## the same width with a red band and four small fins.
##
## Leaves the bore along the barrel, speeds up from `launch_speed` to
## `speed`, and after `guide_delay` steers towards the arm's locked target
## (at most `turn_rate` deg/s, so it can still miss a target that dodges).
## Explodes on hitting anything (players' own bodies excepted), on passing
## within `proximity` of the target, or after `max_life`. The blast
## (MissileBlast: cartoon fireballs, smoke and a mini shockwave) plays one of
## the owner's three explosion sounds (random, never the same twice running).
##
## Damage (kept below the Black Hole Generator, the strongest pickup):
## robots it strikes, and any within `kill_radius` of the blast, die at once
## and are blown apart by the blast (`kill_force`: pieces fly out from the
## blast centre). Big enemies (the robot boss) only take `boss_damage`.
## Everything else within `blast_radius` takes `splash_damage` (less with
## distance) and is shoved.
##
## Engine (at the tail): white-hot core flame, orange outer flame, glow,
## smoke puffs, a light and a SmokeTrail ribbon along the flight path that
## lingers after impact.

signal exploded(at: Vector3)

const POOL_SIZE := 6
const LAUNCHER_MODEL := preload("res://assets/weapons/rocket_launcher/rocket_launcher.glb")
## The launcher model's scale in its weapon scene, and where the warhead sits
## in the model (its base centre, mesh space; the tip points to -X there).
const MODEL_SCALE := 0.47
const WARHEAD_BASE := Vector3(-0.821, -0.04, 0.0)
## Body behind the warhead (m): radius, length.
const BODY_RADIUS := 0.0215
const BODY_LENGTH := 0.2

@export var launch_speed := 14.0
@export var speed := 40.0
## Seconds to reach full speed.
@export var accel_time := 0.6
## Flies straight out of the bore this long before steering (s).
@export var guide_delay := 0.12
## Steering towards the locked target (deg/s).
@export var turn_rate := 150.0
## Explodes this close to the target's aim point (m).
@export var proximity := 0.6
@export var max_life := 3.5
## Splash damage within `blast_radius` (full at the centre, falling off);
## not enough on its own to kill a grunt or a skirmisher.
@export var splash_damage := 1.0
@export var blast_radius := 2.0
@export var blast_force := 14.0
## Robots (not the boss) struck, or this close to the blast (m, level
## distance from their middle), are killed outright.
@export var kill_radius := 1.2
## Explosive force of a killing blast: blows the body apart (break-apart
## power ~1.3, the heaviest level; a little less towards `kill_radius`).
@export var kill_force := 44.0
## Damage to big enemies (the robot boss) per rocket, before its armour.
@export var boss_damage := 0.4

@export_group("Audio")
@export var explode_volume_db := 0.0
@export var explode_near := 6.0
@export var explode_far := 80.0
@export_group("")

static var _pool: Array[PlayerRocket] = []
static var _warhead_mesh: Mesh
static var _last_explode_pick := -1
## Explosion sounds played (all rockets; for tests).
static var explode_sounds := 0
## Test switch: false = no outright kills (splash damage only).
static var lethal := true
static var last_explode_sound: AudioStream

var target: Targetable
var shooter: Node
var arm_side := &""
var velocity := Vector3.ZERO
var done := true
var _life := 0.0
var _exclude: Array[RID] = []
var _model: Node3D
var _engine: Node3D
var _flames: Array[MeshInstance3D] = []
var _glow: MeshInstance3D
var _puffs: CPUParticles3D
var _light: OmniLight3D
var _trail: SmokeTrail
var _wait := 0.0
var _pooled := true


## Launch from `from` (origin = the warhead's base in the bore, +Z = out of
## the barrel) at `at` (a locked Targetable, or null to fly straight).
static func launch(parent: Node, from: Transform3D, at: Targetable, by: Node, side := &"") -> PlayerRocket:
	var r := _take(parent)
	r.target = at
	r.shooter = by
	r.arm_side = side
	r._exclude.clear()
	for p in parent.get_tree().get_nodes_in_group(&"players"):
		if p is CollisionObject3D:
			r._exclude.append((p as CollisionObject3D).get_rid())
	if by is CollisionObject3D and not r._exclude.has((by as CollisionObject3D).get_rid()):
		r._exclude.append((by as CollisionObject3D).get_rid())
	r._start(from)
	return r


static func active_count() -> int:
	var n := 0
	for r in _pool:
		if is_instance_valid(r) and not r.done:
			n += 1
	return n


static func _take(parent: Node) -> PlayerRocket:
	_pool = _pool.filter(func(r: PlayerRocket) -> bool: return is_instance_valid(r) and r.is_inside_tree())
	for r in _pool:
		if r.done and r._trail.is_done() and r._wait <= 0.0:
			if r.get_parent() != parent:
				r.reparent(parent, false)
			return r
	var nr := PlayerRocket.new()
	parent.add_child(nr)
	if _pool.size() < POOL_SIZE:
		_pool.append(nr)
	else:
		nr._pooled = false  # overflow: frees itself once its trail is gone
	return nr


## The launcher model's own warhead mesh (shared).
static func warhead_mesh() -> Mesh:
	if _warhead_mesh == null:
		var m: Node = LAUNCHER_MODEL.instantiate()
		var w := m.find_child("Warhead", true, false) as MeshInstance3D
		_warhead_mesh = w.mesh if w else null
		m.free()
	return _warhead_mesh


## The rocket's look, +Z = nose, origin = warhead base (also used for tests).
static func make_model() -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var war := MeshInstance3D.new()
	war.name = "Warhead"
	war.mesh = warhead_mesh()
	# Model space: tip along -X, scaled like the launcher -> rocket: tip +Z.
	var b := Basis(Vector3.UP, PI * 0.5).scaled(Vector3.ONE * MODEL_SCALE)
	war.transform = Transform3D(b, -(b * WARHEAD_BASE))
	root.add_child(war)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.07, 0.07, 0.08)
	dark.metallic = 0.7
	dark.roughness = 0.35
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.75, 0.04, 0.03)
	red.metallic = 0.4
	red.roughness = 0.3
	var body := MeshInstance3D.new()
	body.name = "Body"
	var cyl := CylinderMesh.new()
	cyl.top_radius = BODY_RADIUS
	cyl.bottom_radius = BODY_RADIUS
	cyl.height = BODY_LENGTH
	cyl.radial_segments = 12
	cyl.rings = 1
	cyl.material = dark
	body.mesh = cyl
	body.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -BODY_LENGTH * 0.5))
	root.add_child(body)
	var band := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = BODY_RADIUS * 1.06
	bc.bottom_radius = BODY_RADIUS * 1.06
	bc.height = 0.025
	bc.radial_segments = 12
	bc.rings = 1
	bc.material = red
	band.mesh = bc
	band.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.035))
	root.add_child(band)
	var nozzle := MeshInstance3D.new()
	var nc := CylinderMesh.new()
	nc.top_radius = BODY_RADIUS * 0.8
	nc.bottom_radius = BODY_RADIUS * 0.6
	nc.height = 0.02
	nc.radial_segments = 10
	nc.rings = 1
	nc.material = dark
	nozzle.mesh = nc
	nozzle.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -BODY_LENGTH - 0.01))
	root.add_child(nozzle)
	var fin := BoxMesh.new()
	fin.size = Vector3(0.003, 0.03, 0.055)
	fin.material = red
	for k in 4:
		var f := MeshInstance3D.new()
		f.mesh = fin
		var a := PI * 0.25 + k * PI * 0.5
		f.transform = Transform3D(Basis(Vector3.BACK, a), Vector3(-sin(a), cos(a), 0) * (BODY_RADIUS + 0.012) + Vector3(0, 0, -BODY_LENGTH + 0.03))
		root.add_child(f)
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_model = make_model()
	add_child(_model)
	_engine = Node3D.new()
	_engine.position = Vector3(0, 0, -BODY_LENGTH - 0.02)
	add_child(_engine)
	# Flames point up their textures (+Y): laid back along -Z, crossed.
	for k in 4:
		var hot := k < 2
		var q := Vfx.quad("flame_a" if hot else "flame_b", Color(1.0, 0.93, 0.6) if hot else Color(1.0, 0.45, 0.08),
			Vector2(0.09, 0.42) * (0.6 if hot else 1.0))
		var x := Vector3.RIGHT if k % 2 == 0 else Vector3.UP
		q.transform = Transform3D(Basis(x, Vector3.FORWARD, x.cross(Vector3.FORWARD)), Vector3(0, 0, -0.2 * (0.6 if hot else 1.0)))
		_engine.add_child(q)
		_flames.append(q)
	_glow = Vfx.quad("glow", Color(1.0, 0.8, 0.4), Vector2.ONE)
	_engine.add_child(_glow)
	_puffs = CPUParticles3D.new()
	var pq := QuadMesh.new()
	pq.size = Vector2.ONE * 0.2
	pq.material = Vfx.mix_material("smoke")
	_puffs.mesh = pq
	_puffs.amount = 40
	_puffs.lifetime = 1.3
	_puffs.local_coords = false
	_puffs.direction = Vector3(0, 0, -1)
	_puffs.spread = 20.0
	_puffs.initial_velocity_min = 0.5
	_puffs.initial_velocity_max = 2.0
	_puffs.gravity = Vector3(0, 0.6, 0)
	_puffs.damping_min = 1.5
	_puffs.damping_max = 3.0
	_puffs.angle_max = 180.0
	_puffs.angular_velocity_min = -40.0
	_puffs.angular_velocity_max = 40.0
	_puffs.scale_amount_curve = Vfx.curve([Vector2(0, 0.4), Vector2(1, 3.2)])
	_puffs.color_ramp = Vfx.ramp([Color(1.0, 0.7, 0.4, 0.8), Color(0.62, 0.6, 0.58, 0.6), Color(0.5, 0.49, 0.48, 0.0)], [0.0, 0.15, 1.0])
	_puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_puffs.emitting = false
	_engine.add_child(_puffs)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.62, 0.25)
	_light.omni_range = 4.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0, -0.1)
	_engine.add_child(_light)
	Vfx.tame_light(_light)
	_trail = SmokeTrail.new()
	_trail.start_width = 0.12
	_trail.end_width = 1.1
	_trail.spacing = 0.35
	_trail.lifetime = 2.2
	add_child(_trail)
	_set_flying(false)


func _set_flying(on: bool) -> void:
	_model.visible = on
	_engine.visible = on
	_puffs.emitting = on
	_light.visible = on
	set_physics_process(on)
	set_process(true)


func _start(from: Transform3D) -> void:
	done = false
	_life = 0.0
	_wait = 0.0
	global_transform = Transform3D(from.basis.orthonormalized(), from.origin)
	set_meta(&"start", from.origin)
	velocity = global_basis.z.normalized() * launch_speed
	_trail.reset()
	_trail.emitting = true
	_trail.feed(from.origin)
	_set_flying(true)
	_puffs.restart()


func _physics_process(delta: float) -> void:
	if done:
		return
	_life += delta
	var dir := velocity.normalized()
	var aim := target.get_aim_point() if target and is_instance_valid(target) and target.is_valid_target() else Vector3.INF
	if aim != Vector3.INF and _life >= guide_delay:
		var want := (aim - global_position).normalized()
		var ang := dir.angle_to(want)
		if ang > 1e-4:
			var axis := dir.cross(want)
			if axis.length_squared() > 1e-8:
				dir = dir.rotated(axis.normalized(), minf(ang, deg_to_rad(turn_rate) * delta))
	var spd := lerpf(launch_speed, speed, clampf(_life / maxf(accel_time, 0.01), 0.0, 1.0))
	velocity = dir * spd
	var from := global_position
	var to := from + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.exclude = _exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_explode(hit.position, hit.collider as Node)
		return
	global_position = to
	_trail.feed(to)
	if aim != Vector3.INF and to.distance_to(aim) <= proximity:
		_explode(to, target.get_parent() if target else null)
		return
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	global_basis = Basis.looking_at(-dir, up)  # looking_at faces -Z; nose is +Z
	if _life >= max_life:
		_explode(global_position, null)


func _process(delta: float) -> void:
	if done:
		if _wait > 0.0:
			_wait -= delta
		elif not _pooled and _trail.is_done():
			queue_free()
		return
	# Flickering engine.
	var fl := randf_range(0.85, 1.2)
	for f in _flames:
		f.scale = Vector3(randf_range(0.85, 1.15), fl * randf_range(0.9, 1.1), 1.0)
	Vfx.face_camera(_glow, 0.35 * fl)
	_light.light_energy = 2.5 * fl


func _explode(at: Vector3, struck: Node) -> void:
	done = true
	global_position = at
	_blast(at, struck)
	# Scorch only when it goes off near the floor; the ground shockwave and
	# dust also run along the floor under a blast up to body height.
	var down := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.1, at + Vector3.DOWN * 1.8)
	down.collision_mask = 1
	down.exclude = _exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(down)
	var on_ground := not hit.is_empty() and at.y - (hit.position as Vector3).y <= 0.8
	var floor_point: Vector3 = hit.position if not hit.is_empty() else Vector3.INF
	MissileBlast.spawn(get_parent(), at, blast_radius, 1.0, on_ground, floor_point)
	_explode_sound(at)
	exploded.emit(at)
	# The rocket and engine go; the smoke trail lingers and fades.
	_trail.emitting = false
	_set_flying(false)
	_wait = _puffs.lifetime


## One of the owner's three explosion sounds at random, never the one
## heard last.
func _explode_sound(at: Vector3) -> void:
	var sounds: Array[AudioStream] = [Sfx.ROCKET_EXPLODE_0, Sfx.ROCKET_EXPLODE_1, Sfx.ROCKET_EXPLODE_2]
	var pick := randi() % sounds.size()
	if pick == _last_explode_pick:
		pick = (pick + 1 + randi() % (sounds.size() - 1)) % sounds.size()
	_last_explode_pick = pick
	last_explode_sound = sounds[pick]
	Sfx.play_at(get_parent(), sounds[pick], at, explode_volume_db, explode_near, explode_far)
	explode_sounds += 1


## Damage and push everything within the blast radius (not the shooter or
## other players). Robots struck or within `kill_radius` die, blown apart;
## the boss takes `boss_damage`; the rest take falling-off splash damage.
func _blast(at: Vector3, struck: Node) -> void:
	var shape := SphereShape3D.new()
	shape.radius = blast_radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), at)
	q.collision_mask = 1
	q.exclude = _exclude
	var seen := {}
	for r in get_world_3d().direct_space_state.intersect_shape(q, 32):
		var col: Object = r.collider
		if col == null or seen.has(col) or col == shooter or (col is Node and (col as Node).is_in_group(&"players")):
			continue
		seen[col] = true
		var body := col as Node3D
		var off := body.global_position + Vector3.UP * 0.8 - at
		var k := 1.0 if col == struck else clampf(1.0 - off.length() / (blast_radius + 0.8), 0.25, 1.0)
		var push_dir := (off + Vector3.UP * 0.6).normalized()
		if col.has_method("apply_damage"):
			var info: DamageInfo
			if col is RobotBoss:
				info = DamageInfo.make(boss_damage, DamageInfo.Type.EXPLOSION, at, push_dir, 0.0, blast_force * k, shooter)
			elif lethal and col is RobotEnemy and _kills(col as RobotEnemy, at, struck):
				# Dead at once and blown apart from the blast centre: the
				# closer it was, the harder.
				var flat := Vector2(off.x, off.z).length()
				var kk := 1.0 if col == struck else clampf(1.0 - 0.3 * flat / maxf(kill_radius, 0.01), 0.7, 1.0)
				var e := col as RobotEnemy
				info = DamageInfo.make(maxf(e.health, 0.0) + 1.0, DamageInfo.Type.EXPLOSION, at, push_dir, 0.0, kill_force * kk, shooter)
			else:
				info = DamageInfo.make(splash_damage * k, DamageInfo.Type.EXPLOSION, at, push_dir, 0.0, blast_force * k, shooter)
			info.weapon = &"rocket"
			info.arm = arm_side
			col.apply_damage(info)
		elif col is RigidBody3D and not (col as RigidBody3D).freeze:
			var rb := col as RigidBody3D
			rb.apply_central_impulse(push_dir * blast_force * k * minf(rb.mass, 20.0) * 0.5)


## Killed outright: the robot it struck, or one whose middle is within
## `kill_radius` (level distance) of the blast and not far above / below it.
func _kills(e: RobotEnemy, at: Vector3, struck: Node) -> bool:
	if e == struck:
		return true
	var off := e.global_position - at
	return Vector2(off.x, off.z).length() <= kill_radius and off.y < 1.0 and off.y > -3.0
