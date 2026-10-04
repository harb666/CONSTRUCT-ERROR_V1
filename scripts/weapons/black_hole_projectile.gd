class_name BlackHoleProjectile
extends Node3D
## A fired black hole: carries the BlackHoleCore that left the gun's chamber
## (its own spin animation keeps playing).
##
## States: FIRED -> TRAVELLING -> STUCK_GRAVITY_WELL -> COLLAPSING ->
##         SUPERNOVA -> FINISHED
## On hitting anything it sticks at the contact point and becomes an unstable
## gravity well (GravityWell) for `gravity_well_duration`, building up, then
## collapses to a point and goes supernova. If it flies its full range
## without hitting anything it just fizzles out.

signal impacted(position: Vector3, collider: Object)
signal supernova_exploded(position: Vector3)

enum State { FIRED, TRAVELLING, STUCK_GRAVITY_WELL, COLLAPSING, SUPERNOVA, FINISHED }

@export_group("Flight")
@export var speed := 18.0
@export var max_distance := 80.0
## Size it surges to once clear of the gun (m across; ~1.75x player height).
@export var flight_size := 3.0
## Distance travelled at chamber size before it expands (clears the barrel).
@export var clear_distance := 1.4
@export var expand_time := 0.32
@export var expand_overshoot := 1.4
## Solid collision radius as a fraction of the visible diameter.
@export var collision_fraction := 0.22
@export var flight_tilt_degrees := 30.0
@export var turn_time := 0.15

@export_group("Gravity well")
@export var gravity_well_duration := 5.0
@export var gravity_radius := 9.0
@export var gravity_strength := 60.0
@export var player_gravity_strength := 20.0
@export var capture_radius := 1.0
## Field radius while flying (it pulls things into its wake as it goes).
@export var flight_gravity_radius := 7.0
@export var orbit_strength := 26.0
@export var shrink_rate := 1.6
## Size pulse while stuck (fraction of size) and its base speed; both grow
## with instability, and the pulse is deliberately irregular.
@export var pulse_amount := 0.1
@export var pulse_speed := 6.0
@export var maximum_affected_objects := 20
@export var maximum_captured_objects := 10
## Max simultaneous wells (mobile): the oldest collapses early if exceeded.
@export var max_active_wells := 3

@export_group("Collapse / supernova")
@export var collapse_time := 0.28
@export var compression_hold := 0.08
@export var supernova_radius := 11.0
@export var supernova_damage := 3.0
@export var supernova_launch_force := 24.0
@export var fizzle_time := 0.35
## Plasma burst reaches this far beyond the damage radius (m).
@export var supernova_finish_margin := 1.0
## Direct hit on whatever it strikes (before the well forms): ordinary
## damage, modest force (DamageInfo.impact_force). The supernova does the
## violent part.
@export var impact_damage := 1.0
@export var impact_force := 6.0

@export_group("Audio")
## Each sound is full volume within its "near" distance (m) of the player
## and fades to silence at its "far" distance. The explosion is the loudest.
## Energy hum that follows the black hole from the barrel to the explosion.
@export var loop_volume_db := -6.0
@export var loop_near := 3.0
@export var loop_far := 30.0
## Rising charge while it's stuck; timed to end just before the explosion.
@export var charge_volume_db := -2.0
@export var charge_near := 4.0
@export var charge_far := 40.0
## Gap (s) between the charge sound ending and the explosion.
@export var charge_end_gap := 0.05
## Energy burst starts this many seconds before the supernova.
@export var burst_lead_time := 1.3
@export var burst_volume_db := -3.0
@export var burst_near := 5.0
@export var burst_far := 50.0
@export var explode_volume_db := 3.0
@export var explode_near := 10.0
@export var explode_far := 90.0

static var _active_wells: Array = []
## Test/debug switch: when false, impacts fizzle out instead of forming wells.
static var gravity_wells_enabled := true

var state := State.FIRED
var core: BlackHoleCore
var direction := Vector3.FORWARD
var well: GravityWell
var _shooter_rid: RID
var _travelled := 0.0
var _age := 0.0
var _start_size := 0.28
var _start_basis := Basis.IDENTITY
var _flight_basis := Basis.IDENTITY
var _vfx: BlackHoleFlightVfx
var _size := 0.28
var _expand_t := -1.0
var _sphere := SphereShape3D.new()
var _state_t := 0.0
var _collapse_from := 0.0
var _fizzle := false
var _surface_normal := Vector3.UP
var _pulse_seed := randf() * 100.0
var _star: MeshInstance3D
var _hum: DynamicSound
var _pass_through: Array[RID] = []
var _charge_snd: DynamicSound
var _charge_start_t := -1.0  # stuck time at which the charge sound starts
var _burst_played := false

## Current solid radius (m) and the wider influence radius.
var collision_radius: float:
	get: return _size * collision_fraction
var influence_radius: float:
	get: return gravity_radius if state == State.STUCK_GRAVITY_WELL else _size * 1.2


func launch(c: BlackHoleCore, dir: Vector3, shooter: Node3D) -> void:
	core = c
	direction = dir.normalized()
	if shooter is CollisionObject3D:
		_shooter_rid = (shooter as CollisionObject3D).get_rid()
	if core:
		var basis := core.transform.basis
		_start_size = basis.get_scale().x
		_size = _start_size
		_start_basis = Basis(basis.orthonormalized().get_rotation_quaternion())
		_flight_basis = _disk_facing(direction)
		add_child(core)
		core.transform = Transform3D(_start_basis * _start_size, Vector3.ZERO)
	_vfx = BlackHoleFlightVfx.new()
	_vfx.follow = self
	_vfx.projectile = self
	if _shooter_rid.is_valid():
		_vfx.exclude = [_shooter_rid]
	_vfx.size = _start_size
	add_child(_vfx)
	if gravity_wells_enabled:
		_make_well()
	_hum = Sfx.emitter(self, Sfx.BH_LOOP, loop_volume_db, loop_near, loop_far)
	_hum.play()
	state = State.TRAVELLING


## Core's disk lies in its local XZ plane (normal +Y): point the normal back
## along the flight path, then tilt it so the disk is seen at an angle.
func _disk_facing(dir: Vector3) -> Basis:
	var normal := -dir
	var side := normal.cross(Vector3.UP)
	if side.length_squared() < 1e-4:
		side = Vector3.RIGHT
	side = side.normalized()
	var fwd := side.cross(normal).normalized()
	var b := Basis(side, normal, -fwd).orthonormalized()
	return Basis(side, deg_to_rad(flight_tilt_degrees)) * b


func _physics_process(delta: float) -> void:
	_age += delta
	_state_t += delta
	match state:
		State.TRAVELLING:
			_travel(delta)
		State.STUCK_GRAVITY_WELL:
			_stuck(delta)
		State.COLLAPSING:
			_collapse()
		State.SUPERNOVA:
			if _state_t > 1.2 and (well == null or well.is_done()):
				_finish()
		State.FINISHED:
			pass


# --- TRAVELLING ---

func _travel(delta: float) -> void:
	# Small while leaving the gun, then a fast, overshooting surge.
	if _expand_t < 0.0 and _travelled >= clear_distance:
		_expand_t = 0.0
		ImpactBurst.spawn(get_parent(), global_position, flight_size * 0.55)
	_set_size(_expansion_size(delta))
	if well and not well.active and _expand_t >= 0.0:
		well.active = true
	var from := global_position
	var motion := direction * speed * delta
	var hit := _sweep(from, motion)
	# It flies on through enemies that die (from the hit or already torn
	# apart by its gravity); a survivor stops it as usual.
	var guard := 0
	while not hit.is_empty() and _is_enemy(hit.collider) and guard < 6:
		guard += 1
		if not _hit_enemy_dies(hit.collider):
			break
		hit = _sweep(from, motion)
	if not hit.is_empty():
		global_position = hit.position
		_stick(hit)
		return
	global_position = from + motion
	_travelled += motion.length()
	if _travelled >= max_distance:
		_fizzle = true
		_enter(State.COLLAPSING)


func _expansion_size(delta: float) -> float:
	if _expand_t < 0.0:
		return _start_size
	_expand_t += delta
	var k := clampf(_expand_t / expand_time, 0.0, 1.0)
	return lerpf(_start_size, flight_size, _ease_out_back(k))


func _ease_out_back(k: float) -> float:
	var c := expand_overshoot
	var t := k - 1.0
	return 1.0 + (c + 1.0) * t * t * t + c * t * t


static func _is_enemy(o: Variant) -> bool:
	return is_instance_valid(o) and o is Node and (o as Node).is_in_group(&"enemies")


## Direct hit on an enemy in flight; true if it died (then it is ignored
## from now on and the black hole carries on through).
func _hit_enemy_dies(e: Object) -> bool:
	if e.has_method("apply_damage"):
		e.apply_damage(DamageInfo.make(impact_damage, DamageInfo.Type.ENERGY, global_position, direction, impact_force, 0.0, self))
	var dead: bool = "alive" in e and not e.alive
	if dead:
		_pass_through.append((e as CollisionObject3D).get_rid())
		impacted.emit(global_position, e)
	return dead


## Sphere sweep with the current collision radius (one query per tick).
func _sweep(from: Vector3, motion: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	_sphere.radius = maxf(collision_radius, 0.05)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _sphere
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = motion
	q.collision_mask = 1  # world, props, enemies (not debris pieces)
	var ex: Array[RID] = _pass_through.duplicate()
	if _shooter_rid.is_valid():
		ex.append(_shooter_rid)
	q.exclude = ex
	var frac := space.cast_motion(q)
	if frac.is_empty() or frac[1] >= 1.0:
		return {}
	q.transform.origin = from + motion * frac[1]
	q.motion = Vector3.ZERO
	var info := space.get_rest_info(q)
	if info.is_empty():
		return {}
	return {"position": from + motion * frac[0], "collider": instance_from_id(info.collider_id), "normal": info.normal}


# --- STUCK_GRAVITY_WELL ---

func _stick(hit: Dictionary) -> void:
	var collider: Object = hit.collider
	_surface_normal = hit.normal if hit.normal.length_squared() > 0.1 else -direction
	ImpactBurst.spawn(get_parent(), global_position, maxf(_size, 0.6) * 0.8)
	if collider and collider.has_method("apply_damage"):
		if not _is_enemy(collider):  # enemies were already hit in flight
			collider.apply_damage(DamageInfo.make(impact_damage, DamageInfo.Type.ENERGY, global_position, direction, impact_force, 0.0, self))
	elif collider and collider.has_method("on_projectile_hit"):
		collider.on_projectile_hit(self)
	impacted.emit(global_position, collider)
	if not gravity_wells_enabled:
		_fizzle = true
		_enter(State.COLLAPSING)
		return
	# Finish expanding if it hit before fully surging out.
	if _expand_t < 0.0:
		_expand_t = 0.0
	if well == null:
		_make_well()
	# The flying field becomes the stationary well.
	well.moving = false
	well.active = true
	well.exclude = []  # the stuck well pulls everyone, shooter included
	well.surface_normal = _surface_normal
	well.gravity_radius = gravity_radius
	_enter(State.STUCK_GRAVITY_WELL)
	_schedule_charge_sound()
	_active_wells.append(self)
	while _active_wells.size() > max_active_wells:
		var oldest: BlackHoleProjectile = _active_wells.pop_front()
		if is_instance_valid(oldest) and oldest.state == State.STUCK_GRAVITY_WELL:
			oldest._enter(State.COLLAPSING)


func _stuck(delta: float) -> void:
	var k := clampf(_state_t / gravity_well_duration, 0.0, 1.0)  # instability
	var base := _expansion_size(delta)
	# Irregular, building pulse: three incommensurate waves + slow drift.
	var t := _state_t * pulse_speed * (1.0 + k * 0.8) + _pulse_seed
	var wave := sin(t) * 0.6 + sin(t * 1.73 + 1.3) * 0.28 + sin(t * 2.91 + 0.4) * 0.12
	wave += (sin(_state_t * 0.9 + _pulse_seed) * 0.5 + 0.5) * 0.3 * k
	_set_size(base * (1.0 + pulse_amount * (1.0 + k * 1.6) * wave))
	if well:
		well.intensity = k
	_set_anim_speed(1.0 + k * 2.5)
	if _vfx:
		_vfx.set_instability(k)
	if _charge_start_t >= 0.0 and _state_t >= _charge_start_t:
		_charge_start_t = -1.0
		_start_charge_sound(0.0)
	if _state_t >= _time_to_supernova() - burst_lead_time:
		_play_burst()
	if _state_t >= gravity_well_duration:
		_enter(State.COLLAPSING)


## Seconds from sticking to the supernova (when the well runs its course).
func _time_to_supernova() -> float:
	return gravity_well_duration + collapse_time + compression_hold


## The black hole's gravity field: created on launch (moving with it, pulling
## things into its wake), it becomes the stationary well where it sticks.
func _make_well() -> void:
	well = GravityWell.new()
	well.moving = true
	well.active = false  # armed once clear of the gun
	well.set_axis(direction)
	if _shooter_rid.is_valid():
		well.exclude = [_shooter_rid]
	well.gravity_radius = flight_gravity_radius
	well.gravity_strength = gravity_strength
	well.player_gravity_strength = player_gravity_strength
	well.capture_radius = capture_radius
	well.orbit_strength = orbit_strength
	well.shrink_rate = shrink_rate
	well.max_affected_objects = maximum_affected_objects
	well.max_captured_objects = maximum_captured_objects
	well.supernova_radius = supernova_radius
	well.supernova_damage = supernova_damage
	well.supernova_launch_force = supernova_launch_force
	add_child(well)


## The charge sound must finish just before the explosion: if it is longer
## than the time left, start it part-way through; otherwise delay it.
func _schedule_charge_sound() -> void:
	var length := Sfx.BH_CHARGE.get_length()
	var lead := _time_to_supernova() - charge_end_gap
	if lead >= length:
		_charge_start_t = lead - length
	else:
		_start_charge_sound(length - lead)


func _start_charge_sound(from: float) -> void:
	_charge_snd = Sfx.emitter(self, Sfx.BH_CHARGE, charge_volume_db, charge_near, charge_far)
	_charge_snd.finished.connect(_charge_snd.queue_free)
	_charge_snd.play(from)


## Seconds until the charge sound ends (for tests); -1 when not playing.
func charge_sound_remaining() -> float:
	if _charge_snd == null or not is_instance_valid(_charge_snd) or not _charge_snd.playing:
		return -1.0
	return Sfx.BH_CHARGE.get_length() - _charge_snd.get_playback_position()


func _play_burst() -> void:
	if _burst_played:
		return
	_burst_played = true
	# Lightning erupts the instant the energy burst is heard.
	if _vfx:
		_vfx.erupt()
	Sfx.play_at(get_parent(), Sfx.BH_BURST, global_position, burst_volume_db, burst_near, burst_far)


# --- COLLAPSING ---

func _collapse() -> void:
	if _fizzle:
		var f := 1.0 - clampf(_state_t / fizzle_time, 0.0, 1.0)
		_set_size(_collapse_from * f)
		if f <= 0.0:
			_finish()
		return
	# Everything rushes inward to a point, a brief moment of extreme
	# compression (bright pinpoint), then the supernova.
	var k := clampf(_state_t / collapse_time, 0.0, 1.0)
	_set_size(lerpf(_collapse_from, 0.03, k * k * k))
	_set_anim_speed(4.0 + k * 6.0)
	if _star:
		var glow := clampf((_state_t - collapse_time * 0.5) / (collapse_time * 0.5 + compression_hold), 0.0, 1.0)
		_star.visible = glow > 0.0
		Vfx.face_camera(_star, 0.4 + glow * 0.9, _state_t * 8.0)
		Vfx.set_alpha(_star, glow)
	if _state_t >= collapse_time + compression_hold:
		_enter(State.SUPERNOVA)


func _enter(s: State) -> void:
	state = s
	_state_t = 0.0
	match s:
		State.COLLAPSING:
			_collapse_from = _size
			_active_wells.erase(self)
			if well:
				well.intensity = 1.0
			if not _fizzle:
				# Cut short (e.g. too many wells): still warn before blowing,
				# and clear the charge sound out of the explosion's way.
				_play_burst()
				_charge_start_t = -1.0
				if _charge_snd and is_instance_valid(_charge_snd) and charge_sound_remaining() > collapse_time + compression_hold:
					Sfx.fade_out(_charge_snd, collapse_time, true)
				_star = Vfx.quad("star", Vfx.HOT, Vector2.ONE)
				_star.top_level = true
				_star.visible = false
				add_child(_star)
				_star.global_position = global_position
			else:
				Sfx.fade_out(_hum, fizzle_time)
				if well:
					well.active = false
				if _vfx:
					_vfx.fade_out(fizzle_time)
		State.SUPERNOVA:
			_supernova()


# --- SUPERNOVA ---

func _supernova() -> void:
	var at := global_position
	if core:
		core.visible = false
	if _star:
		_star.queue_free()
		_star = null
	if _vfx:
		_vfx.fade_out(0.15)
		_vfx = null
	SupernovaBlast.spawn(get_parent(), at, supernova_radius, _surface_normal)
	# Expanding plasma burst, reaching just past the damage radius.
	SupernovaFinish.spawn(get_parent(), at, supernova_radius + supernova_finish_margin)
	if _hum:
		_hum.stop()
	if _charge_snd and is_instance_valid(_charge_snd):
		_charge_snd.stop()
	Sfx.play_at(get_parent(), Sfx.BH_EXPLODE, at, explode_volume_db, explode_near, explode_far)
	if well:
		well.supernova()
	get_tree().call_group("camera_rigs", "supernova_feedback", at, supernova_radius)
	supernova_exploded.emit(at)


func _finish() -> void:
	state = State.FINISHED
	if well and not well.is_done():
		well.release_all_now()
	queue_free()


func _exit_tree() -> void:
	_active_wells.erase(self)
	# Never leave bodies captured if we're removed unexpectedly.
	if well and is_instance_valid(well) and not well.is_done():
		well.release_all_now()


func _set_anim_speed(s: float) -> void:
	if core:
		var ap := core.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			ap.speed_scale = s


func _set_size(size: float) -> void:
	_size = size
	if _vfx:
		_vfx.set_size(size)
	if core:
		var k := clampf(_age / turn_time, 0.0, 1.0)
		var q := _start_basis.get_rotation_quaternion().slerp(_flight_basis.get_rotation_quaternion(), smoothstep(0.0, 1.0, k))
		core.transform.basis = Basis(q) * maxf(size, 0.001)
