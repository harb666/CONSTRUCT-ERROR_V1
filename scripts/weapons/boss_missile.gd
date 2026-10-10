class_name BossMissile
extends Node3D
## The robot boss's missile (pooled; the look is BossMissileModel, one shared
## mesh). It leaves the launcher's silo along the tube, pitches up into a
## steep climb to `climb_height` above the launcher, arcs over and dives onto
## a FIXED point (where the player stood at launch), never onto the player,
## so it can be dodged. Explodes on reaching that point or on hitting
## anything on the way; the blast (MissileBlast) damages and shoves
## everything nearby at the moment it goes off.
##
## Flight: a straight exit of `exit_distance` along the tube, then a cubic
## curve (start straight up-ish, apex, near-vertical dive), flown by arc
## length with a speed that builds through the climb and surges in the
## dive. Ray-cast movement (no physics body).
## Engine (at the rear, follows the missile's orientation): white-hot core
## flame, orange outer flame, glow, sparks, turbulent smoke puffs, a light
## and a SmokeTrail ribbon tracing the whole path (it lingers after impact).

signal exploded(at: Vector3)

const POOL_SIZE := 4
const PATH_SAMPLES := 48

## Speed (m/s) leaving the tube, through the climb, and at the end of the dive.
@export var launch_speed := 14.0
@export var speed := 24.0
@export var dive_speed := 42.0
## Straight run out of the tube before pitching up (m).
@export var exit_distance := 2.5
## Apex height above the higher of launcher / target (m).
@export var climb_height := 16.0
@export var damage := 3.0
@export var blast_radius := 2.6
@export var blast_force := 9.0
@export var max_life := 10.0

static var _pool: Array[BossMissile] = []

var target := Vector3.ZERO
var shooter: Node
var marker: MissileTargetMarker
var velocity := Vector3.ZERO
var done := true
## Missile length (m).
var length := 1.8

var _life := 0.0
var _s := 0.0
var _path: PackedVector3Array = PackedVector3Array()
var _dist: PackedFloat32Array = PackedFloat32Array()
var _exclude: Array[RID] = []
var _model: Node3D
var _engine: Node3D
var _flames: Array[MeshInstance3D] = []
var _glow: MeshInstance3D
var _sparks: CPUParticles3D
var _puffs: CPUParticles3D
var _light: OmniLight3D
var _trail: SmokeTrail
var _wait := 0.0
var _pooled := true


## Launch from `from` (its +Z is the launch direction, its origin the
## missile's centre) towards `at`. `missile_length` in metres.
static func launch(parent: Node, from: Transform3D, at: Vector3, by: Node, target_marker: MissileTargetMarker = null,
		missile_length := 1.8) -> BossMissile:
	var m := _take(parent, missile_length)
	m.target = at
	m.shooter = by
	m.marker = target_marker
	m._exclude.clear()
	if by is CollisionObject3D:
		m._exclude.append((by as CollisionObject3D).get_rid())
	m._start(from)
	return m


static func active_count() -> int:
	var n := 0
	for m in _pool:
		if is_instance_valid(m) and not m.done:
			n += 1
	return n


static func _take(parent: Node, missile_length: float) -> BossMissile:
	_pool = _pool.filter(func(m: BossMissile) -> bool: return is_instance_valid(m) and m.is_inside_tree())
	for m in _pool:
		if m.done and m._trail.is_done() and m._wait <= 0.0 and is_equal_approx(m.length, missile_length):
			if m.get_parent() != parent:
				m.reparent(parent, false)
			return m
	var nm := BossMissile.new()
	nm.length = missile_length
	parent.add_child(nm)
	if _pool.size() < POOL_SIZE:
		_pool.append(nm)
	else:
		nm._pooled = false  # overflow: frees itself once its trail is gone
	return nm


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_model = BossMissileModel.create(length)
	add_child(_model)
	_engine = Node3D.new()
	_engine.position = Vector3(0, 0, BossMissileModel.NOZZLE_Z * length)
	add_child(_engine)
	var L := length
	# Flames point up their textures (+Y): laid back along -Z, crossed.
	for k in 4:
		var hot := k < 2
		var q := Vfx.quad("flame_a" if hot else "flame_b", Color(1.0, 0.93, 0.6) if hot else Color(1.0, 0.45, 0.08),
			Vector2(0.42, 1.7) * L * (0.6 if hot else 1.0))
		# The quad's +Y (flame) along -Z; the pair crossed (planes XZ / YZ).
		var x := Vector3.RIGHT if k % 2 == 0 else Vector3.UP
		q.transform = Transform3D(Basis(x, Vector3.FORWARD, x.cross(Vector3.FORWARD)), Vector3(0, 0, -0.8 * L * (0.6 if hot else 1.0)))
		_engine.add_child(q)
		_flames.append(q)
	_glow = Vfx.quad("glow", Color(1.0, 0.8, 0.4), Vector2.ONE)
	_engine.add_child(_glow)
	_sparks = Vfx.particles("glow", 0.06, 24, 0.4)
	_sparks.local_coords = false
	_sparks.direction = Vector3(0, 0, -1)
	_sparks.spread = 18.0
	_sparks.initial_velocity_min = 6.0
	_sparks.initial_velocity_max = 12.0
	_sparks.gravity = Vector3(0, -6, 0)
	_sparks.color_ramp = Vfx.ramp([Color(1, 0.95, 0.7, 1), Color(1, 0.55, 0.1, 1), Color(0.8, 0.2, 0.02, 0)], [0.0, 0.5, 1.0])
	_sparks.emitting = false
	_engine.add_child(_sparks)
	_puffs = CPUParticles3D.new()
	var pq := QuadMesh.new()
	pq.size = Vector2.ONE * 0.55 * L
	pq.material = Vfx.mix_material("smoke")
	_puffs.mesh = pq
	_puffs.amount = 36
	_puffs.lifetime = 1.4
	_puffs.local_coords = false
	_puffs.direction = Vector3(0, 0, -1)
	_puffs.spread = 25.0
	_puffs.initial_velocity_min = 1.0
	_puffs.initial_velocity_max = 3.0
	_puffs.gravity = Vector3(0, 0.7, 0)
	_puffs.damping_min = 1.5
	_puffs.damping_max = 3.0
	_puffs.angle_max = 180.0
	_puffs.angular_velocity_min = -40.0
	_puffs.angular_velocity_max = 40.0
	_puffs.scale_amount_curve = Vfx.curve([Vector2(0, 0.35), Vector2(1, 2.4)])
	_puffs.color_ramp = Vfx.ramp([Color(1.0, 0.7, 0.4, 0.75), Color(0.6, 0.58, 0.56, 0.55), Color(0.45, 0.44, 0.43, 0.0)], [0.0, 0.15, 1.0])
	_puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_puffs.emitting = false
	_engine.add_child(_puffs)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.62, 0.25)
	_light.omni_range = 7.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0, -0.3 * L)
	_engine.add_child(_light)
	Vfx.tame_light(_light)
	_trail = SmokeTrail.new()
	_trail.start_width = 0.8 * L / 1.8
	_trail.end_width = 3.2 * L / 1.8
	add_child(_trail)
	_set_flying(false)


func _set_flying(on: bool) -> void:
	_model.visible = on
	_engine.visible = on
	_sparks.emitting = on
	_puffs.emitting = on
	_light.visible = on
	set_physics_process(on)
	set_process(true)


func _start(from: Transform3D) -> void:
	done = false
	_life = 0.0
	_s = 0.0
	_wait = 0.0
	global_transform = Transform3D(from.basis.orthonormalized(), from.origin)
	_build_path(from.origin, from.basis.z.normalized())
	velocity = from.basis.z.normalized() * launch_speed
	_trail.reset()
	_trail.emitting = true
	_trail.feed(from.origin)
	_set_flying(true)
	_sparks.restart()
	_puffs.restart()


## Exit straight along the tube, then a cubic curve: up from the exit, over
## an apex `climb_height` above, steeply down onto the target.
func _build_path(p0: Vector3, axis: Vector3) -> void:
	var b0 := p0 + axis * exit_distance
	var flat := target - b0
	flat.y = 0.0
	var d := flat.length()
	var hdir := flat / d if d > 0.01 else Vector3.ZERO
	var apex := maxf(b0.y, target.y) + climb_height
	var b1 := b0 + axis * 2.0 + Vector3.UP * (apex - b0.y) * 1.3 + hdir * d * 0.15
	var b2 := target + Vector3.UP * (apex - target.y) * 1.3 - hdir * d * 0.12
	_path.resize(PATH_SAMPLES + 2)
	_dist.resize(PATH_SAMPLES + 2)
	_path[0] = p0
	_dist[0] = 0.0
	for i in PATH_SAMPLES + 1:
		var t := float(i) / PATH_SAMPLES
		var u := 1.0 - t
		_path[i + 1] = b0 * u * u * u + b1 * 3.0 * u * u * t + b2 * 3.0 * u * t * t + target * t * t * t
		_dist[i + 1] = _dist[i] + _path[i + 1].distance_to(_path[i])


## Total flight path length (m).
func path_length() -> float:
	return _dist[_dist.size() - 1] if _dist.size() > 0 else 0.0


## Highest point of the flight path.
func apex_height() -> float:
	var y := -INF
	for p in _path:
		y = maxf(y, p.y)
	return y


func _point_at(s: float) -> Vector3:
	var n := _dist.size()
	if s <= 0.0:
		return _path[0]
	if s >= _dist[n - 1]:
		return _path[n - 1]
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if _dist[mid] <= s:
			lo = mid
		else:
			hi = mid
	var seg := _dist[hi] - _dist[lo]
	return _path[lo].lerp(_path[hi], (s - _dist[lo]) / maxf(seg, 1e-5))


## Speed along the path: builds through the climb, surges in the dive.
func _speed_at(f: float) -> float:
	var v := lerpf(launch_speed, speed, smoothstep(0.0, 0.35, f))
	return v + (dive_speed - speed) * pow(clampf((f - 0.55) / 0.45, 0.0, 1.0), 1.5)


func _physics_process(delta: float) -> void:
	if done:
		return
	_life += delta
	var total := path_length()
	var from := global_position
	var f := _s / maxf(total, 0.01)
	_s = minf(_s + _speed_at(f) * delta, total)
	var to := _point_at(_s)
	var motion := to - from
	if marker and is_instance_valid(marker):
		marker.progress = clampf(_s / maxf(total, 0.01), 0.0, 1.0)
	if motion.length_squared() > 1e-8:
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1
		q.exclude = _exclude
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			_explode(hit.position)
			return
		velocity = motion / delta
	global_position = to
	_trail.feed(to)
	if _s >= total - 0.01:
		_explode(target)
		return
	# Nose along the flight direction (turns quickly, not instantly).
	if velocity.length_squared() > 0.01:
		var fwd := velocity.normalized()
		var up := Vector3.UP if absf(fwd.y) < 0.98 else Vector3.RIGHT
		var want := Basis.looking_at(-fwd, up)  # looking_at faces -Z; nose is +Z
		global_basis = global_basis.orthonormalized().slerp(want, minf(delta * 14.0, 1.0))
	if _life >= max_life:
		_explode(global_position)


func _process(delta: float) -> void:
	if done:
		if _wait > 0.0:
			_wait -= delta
		elif not _pooled and _trail.is_done():
			queue_free()
		return
	# Flickering engine.
	var fl := randf_range(0.85, 1.2)
	for i in _flames.size():
		_flames[i].scale = Vector3(randf_range(0.85, 1.15), fl * randf_range(0.9, 1.1), 1.0)
	Vfx.face_camera(_glow, 1.5 * length * fl)
	_light.light_energy = 3.5 * fl


func _explode(at: Vector3) -> void:
	done = true
	global_position = at
	if marker and is_instance_valid(marker):
		marker.finish()
	_blast(at)
	MissileBlast.spawn(get_parent(), at, blast_radius)
	Sfx.play_at(get_parent(), Sfx.BH_EXPLODE, at, -3.0, 6.0, 70.0)
	exploded.emit(at)
	DebugHud.note("boss missile hit")
	# The model and engine go; the smoke trail lingers and fades.
	_trail.emitting = false
	_set_flying(false)
	_wait = _puffs.lifetime


## Damage and push everything within the blast radius (not the shooter).
func _blast(at: Vector3) -> void:
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
		if col == null or seen.has(col) or col == shooter:
			continue
		seen[col] = true
		var body := col as Node3D
		var off := body.global_position + Vector3.UP * 0.8 - at
		var k := clampf(1.0 - off.length() / (blast_radius + 0.8), 0.15, 1.0)
		var push_dir := (off + Vector3.UP * 0.6).normalized()
		if col.has_method("apply_damage"):
			col.apply_damage(DamageInfo.make(damage * k, DamageInfo.Type.EXPLOSION, at, push_dir, 0.0, blast_force * k, shooter))
		if col is PlayerController:
			(col as PlayerController).apply_external_impulse(push_dir * blast_force * k)
		elif col is RigidBody3D and not (col as RigidBody3D).freeze:
			var rb := col as RigidBody3D
			rb.apply_central_impulse(push_dir * blast_force * k * minf(rb.mass, 20.0) * 0.5)
