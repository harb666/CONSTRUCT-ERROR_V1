class_name RobotBoss
extends RigidBody3D
## Heavy robot boss (assets/enemies/robot_boss/robot_boss.glb, built by
## tools/build_robot_boss.py). Holds its ground near where it was placed,
## faces the player, sprays its chaingun in bursts and every so often fires
## a missile at the spot where the player is standing. Each missile launch
## opens its chest flap: the red reactor core behind it is exposed (and the
## only place real damage lands) for `core_exposed_time` seconds, then the
## flap closes again.
##
## Animation layers (separate AnimationPlayers on the same model, so they
## play on top of each other): body clips on the model's own player, the
## chest flap (Chest_Open / Chest_Close / Chest_Open_Hold / Chest_Closed) on
## `chest_player`, the chaingun barrel (Chaingun_Fire, looping) on
## `gun_player`. The barrel spins at `gun_player.speed_scale` (0..1), so it
## spins up and down smoothly.

signal missile_launched(target: Vector3)
signal core_exposed
signal core_protected
signal core_hit(amount: float)
signal died

const MODEL := preload("res://assets/enemies/robot_boss/robot_boss.glb")
const LOCOMOTION := [&"Idle", &"Walking", &"Running", &"Walk_Fight_Back", &"Walk_Turn_Left", &"Walk_Turn_Right"]
const CHEST_CLIPS := [&"Chest_Open", &"Chest_Close", &"Chest_Open_Hold", &"Chest_Closed"]
const GUN_CLIP := &"Chaingun_Fire"
const DEATH_CLIP := &"Heavy_Death"
## Chaingun rotor spin axis in the rotor's own space (from the asset) and
## how far along it the barrel tips are.
const ROTOR_AXIS := Vector3(-0.0200662, 0.9543148, 0.2981285)
const ROTOR_MUZZLE := 0.29
const BULLET_COLOR := Color(1.0, 0.55, 0.1)
const BULLET_HOT := Color(1.0, 0.9, 0.5)

@export_group("Health")
@export var max_health := 60.0
## Damage scale for hits anywhere but the exposed core (armour).
@export var armour_damage_scale := 0.1
## Damage scale for hits on the exposed core.
@export var core_damage_scale := 1.0
## A shot hits the core if its line passes this close to it (m).
@export var core_hit_radius := 0.22
@export var respawn_time := 12.0

@export_group("Movement")
@export var walk_speed := 1.3
## Ground speed the Walking clip is authored for (anim speed follows).
@export var walk_anim_speed := 1.1
@export var turn_speed := 2.4
@export var detect_range := 34.0
## Tries to stay this far from the player (m).
@export var preferred_range := Vector2(7.0, 15.0)
## Never wanders further than this from where it was placed (m).
@export var home_radius := 3.5

@export_group("Chaingun")
@export var chaingun_spin_up := 0.6
@export var chaingun_spin_down := 1.2
@export var chaingun_burst_time := 2.2
@export var chaingun_cooldown := 1.6
@export var chaingun_fire_rate := 11.0
@export var chaingun_bullet_speed := 42.0
@export var chaingun_damage := 0.4
@export var chaingun_spread_deg := 3.5
@export var chaingun_range := 30.0

@export_group("Missile")
## Seconds between missile attacks.
@export var missile_interval := 7.0
## First missile this long after it spots the player.
@export var missile_first_delay := 3.0
## Telegraph: stops shooting and squares up before the launch.
@export var missile_windup := 0.7
@export var missile_speed := 15.0
@export var missile_damage := 3.0
@export var missile_blast_radius := 2.6

@export_group("Chest core")
## Delay from the missile launch to the flap starting to open.
@export var chest_open_delay := 0.1
## How long the core stays exposed / vulnerable (s).
@export var core_exposed_time := 3.0
## The core counts as exposed this far into Chest_Open (s).
@export var core_expose_lead := 0.2
## Shoots its chaingun while the core is exposed.
@export var fire_while_exposed := false
@export var core_glow_energy := 3.0

enum State { COMBAT, WINDUP, DEAD }

var health := 0.0
var alive := true
var state := State.COMBAT
var target: Node3D
## The core is exposed and takes real damage.
var exposed := false
## Counters (tests / HUD).
var missiles_fired := 0
var bullets_fired := 0
var core_hits := 0
## The point the last missile was aimed at (fixed at launch).
var last_missile_target := Vector3.ZERO
var last_missile: BossMissile
var last_marker: MissileTargetMarker

var model: Node3D
var anim: AnimationPlayer
var chest_player: AnimationPlayer
var gun_player: AnimationPlayer
var core: MeshInstance3D
var rotor: Node3D
var missile_socket: Node3D
var flap: Node3D

var _visual: Node3D
var _targetable: Targetable
var _target_rest := Vector3.ZERO
var _spawn_xf: Transform3D
var _yaw := 0.0
var _spin := 0.0
var _gun_phase := 0  # 0 cooldown, 1 spin up, 2 firing
var _gun_t := 0.0
var _shot_acc := 0.0
var _missile_t := 0.0
var _windup_t := 0.0
var _chest_open_t := -1.0
var _exposed_t := 0.0
var _core_mat: StandardMaterial3D
var _core_glow: MeshInstance3D
var _move_anim := &""
var _collision: CollisionShape3D
var _collision_rest: Transform3D

static var _lib_cache: AnimationLibrary
static var _chest_lib: AnimationLibrary
static var _gun_lib: AnimationLibrary


func _ready() -> void:
	mass = 400.0
	lock_rotation = true
	can_sleep = false
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.0
	add_to_group(&"enemies")
	_targetable = get_node_or_null("Targetable") as Targetable
	if _targetable:
		_target_rest = _targetable.position
	_collision = get_node_or_null("Collision") as CollisionShape3D
	if _collision:
		_collision_rest = _collision.transform
	_spawn_xf = global_transform
	_build_model()
	health = max_health
	_yaw = _visual.rotation.y
	_missile_t = missile_first_delay


func _build_model() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	model = MODEL.instantiate()
	model.name = "Model"
	_visual.add_child(model)
	# Its hips sit 0.125 m to the side of and 0.2 m in front of the model's
	# origin: put them over the body's origin (it turns about them).
	model.position = Vector3(0.125, 0.0, -0.2)
	anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	core = model.find_child("Reactor_Core", true, false) as MeshInstance3D
	rotor = model.find_child("Chaingun_Barrel_Rotor", true, false) as Node3D
	missile_socket = model.find_child("Missile_Spawn", true, false) as Node3D
	flap = model.find_child("Chest_Frown_Plate_Hinge", true, false) as Node3D
	_setup_animation()
	# Core: its own glowing material (pulses while exposed) and a soft glow.
	_core_mat = (core.get_active_material(0) as StandardMaterial3D).duplicate()
	_core_mat.emission_enabled = true
	_core_mat.emission = Color(1.0, 0.05, 0.02)
	_core_mat.emission_energy_multiplier = core_glow_energy * 0.35
	core.material_override = _core_mat
	_core_glow = Vfx.quad("glow", Color(1.0, 0.1, 0.05), Vector2.ONE * 0.5, BaseMaterial3D.BILLBOARD_ENABLED)
	_core_glow.visible = false
	core.add_child(_core_glow)


## The model's clips split over three players: body (root motion removed
## from the locomotion clips), chest flap, chaingun barrel.
func _setup_animation() -> void:
	if _lib_cache == null:
		var src := anim.get_animation_library(&"")
		_lib_cache = AnimationLibrary.new()
		_chest_lib = AnimationLibrary.new()
		_gun_lib = AnimationLibrary.new()
		# The importer pads every clip with rest-pose tracks for every node
		# any clip animates; each layer keeps only its own nodes' tracks so
		# the layers don't reset each other.
		for n in src.get_animation_list():
			var a: Animation = src.get_animation(n).duplicate()
			if n in CHEST_CLIPS:
				_keep_tracks(a, "Chest_Frown_Plate_Hinge")
				_chest_lib.add_animation(n, a)
			elif n == GUN_CLIP:
				_keep_tracks(a, "Chaingun_Barrel_Rotor")
				a.loop_mode = Animation.LOOP_LINEAR
				_gun_lib.add_animation(n, a)
			else:
				_keep_tracks(a, "Skeleton3D:")
				if n in LOCOMOTION:
					a.loop_mode = Animation.LOOP_LINEAR
					_in_place(a)
				_lib_cache.add_animation(n, a)
	anim.remove_animation_library(&"")
	anim.add_animation_library(&"", _lib_cache)
	chest_player = _feature_player("ChestPlayer", _chest_lib)
	gun_player = _feature_player("GunPlayer", _gun_lib)
	anim.play(&"Idle")
	_move_anim = &"Idle"
	chest_player.play(&"Chest_Closed")
	gun_player.play(GUN_CLIP)
	gun_player.speed_scale = 0.0


func _feature_player(n: String, lib: AnimationLibrary) -> AnimationPlayer:
	var p := AnimationPlayer.new()
	p.name = n
	anim.get_parent().add_child(p)
	p.root_node = anim.root_node
	p.add_animation_library(&"", lib)
	return p


static func _keep_tracks(a: Animation, path_part: String) -> void:
	for t in range(a.get_track_count() - 1, -1, -1):
		if not String(a.track_get_path(t)).contains(path_part):
			a.remove_track(t)


## Keep the hips over the body's origin (the body moves, not the clip).
static func _in_place(a: Animation) -> void:
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D or not String(a.track_get_path(t)).ends_with("mixamorig_Hips"):
			continue
		if a.track_get_key_count(t) == 0:
			continue
		var k0: Vector3 = a.track_get_key_value(t, 0)
		for k in a.track_get_key_count(t):
			var v: Vector3 = a.track_get_key_value(t, k)
			a.track_set_key_value(t, k, Vector3(k0.x, v.y, k0.z))


# --- behaviour ---

func _physics_process(delta: float) -> void:
	if not alive:
		return
	_find_target()
	_update_chest(delta)
	match state:
		State.COMBAT:
			_combat(delta)
		State.WINDUP:
			_windup(delta)
	_update_gun(delta)
	_update_targetable()


func _find_target() -> void:
	target = null
	if not RobotEnemy.ai_enabled:
		return
	var best := detect_range
	for p in get_tree().get_nodes_in_group(&"players"):
		var d := global_position.distance_to((p as Node3D).global_position)
		if d < best:
			best = d
			target = p


func _combat(delta: float) -> void:
	var want := Vector3.ZERO
	if target:
		var to := target.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > preferred_range.y:
			want = to / d
		elif d < preferred_range.x:
			want = -to / d
		_face(to, delta)
		_missile_t -= delta
		if _missile_t <= 0.0 and not exposed and _chest_open_t < 0.0:
			_start_windup()
	else:
		_missile_t = maxf(_missile_t, missile_first_delay)
	# Stay near home.
	var home := _spawn_xf.origin - global_position
	home.y = 0.0
	if home.length() > home_radius:
		want = home.normalized()
	elif want != Vector3.ZERO and (global_position + want - _spawn_xf.origin).length() > home_radius:
		want = Vector3.ZERO
	_move(want * walk_speed, delta)


func _start_windup() -> void:
	state = State.WINDUP
	_windup_t = missile_windup


func _windup(delta: float) -> void:
	_move(Vector3.ZERO, delta)
	if target:
		var to := target.global_position - global_position
		to.y = 0.0
		_face(to, delta)
	_windup_t -= delta
	if _windup_t <= 0.0:
		state = State.COMBAT
		if target:
			fire_missile(target.global_position)
		_missile_t = missile_interval


func _move(v: Vector3, delta: float) -> void:
	var lv := linear_velocity
	var h := Vector3(lv.x, 0, lv.z).move_toward(v, 6.0 * delta)
	linear_velocity = Vector3(h.x, lv.y, h.z)
	var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
	var sp := h.length()
	var clip := &"Idle"
	if sp > 0.2:
		clip = &"Walking" if h.dot(fwd) >= 0.0 else &"Walk_Fight_Back"
	if clip != _move_anim:
		_move_anim = clip
		anim.play(clip, 0.3)
	anim.speed_scale = clampf(sp / walk_anim_speed, 0.6, 1.5) if clip != &"Idle" else 1.0


func _face(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.01:
		return
	_yaw = lerp_angle(_yaw, atan2(dir.x, dir.z), 1.0 - exp(-turn_speed * delta))
	_visual.rotation.y = _yaw


# --- chaingun ---

func _update_gun(delta: float) -> void:
	var can_fire := state == State.COMBAT and target != null and (fire_while_exposed or not exposed) \
		and global_position.distance_to(target.global_position) <= chaingun_range
	var want_spin := 0.0
	match _gun_phase:
		0:
			_gun_t -= delta
			if _gun_t <= 0.0 and can_fire:
				_gun_phase = 1
		1:
			want_spin = 1.0
			if not can_fire:
				_gun_phase = 0
			elif _spin >= 0.98:
				_gun_phase = 2
				_gun_t = chaingun_burst_time
		2:
			want_spin = 1.0
			_gun_t -= delta
			if not can_fire or _gun_t <= 0.0:
				_gun_phase = 0
				_gun_t = chaingun_cooldown
			else:
				_shot_acc += delta * chaingun_fire_rate
				while _shot_acc >= 1.0:
					_shot_acc -= 1.0
					_fire_bullet()
	var rate := (1.0 / chaingun_spin_up) if want_spin > _spin else (1.0 / chaingun_spin_down)
	set_spin(move_toward(_spin, want_spin, rate * delta))


## Barrel spin, 0 (still) .. 1 (full speed). Game code may drive it too.
func set_spin(v: float) -> void:
	_spin = clampf(v, 0.0, 1.0)
	gun_player.speed_scale = _spin


func get_spin() -> float:
	return _spin


func muzzle_position() -> Vector3:
	return rotor.global_transform * (ROTOR_AXIS * ROTOR_MUZZLE)


func _fire_bullet() -> void:
	var muzzle := muzzle_position()
	var aim := target.global_position + Vector3.UP * 1.0
	var dir := (aim - muzzle).normalized()
	var spread := deg_to_rad(chaingun_spread_deg)
	dir = dir.rotated(Vector3.UP, randf_range(-spread, spread))
	var right := dir.cross(Vector3.UP)
	if right.length_squared() > 0.001:
		dir = dir.rotated(right.normalized(), randf_range(-spread, spread) * 0.6)
	PlasmaBolt.fire(get_tree(), muzzle, dir, self, chaingun_bullet_speed, chaingun_damage, BULLET_COLOR, BULLET_HOT)
	PlasmaFx.muzzle_flash(get_tree(), muzzle, dir, BULLET_COLOR, BULLET_HOT)
	bullets_fired += 1


# --- missile ---

## Fire a missile at the point under `at` (the player's position NOW). The
## point is fixed: the missile does not follow the player afterwards.
func fire_missile(at: Vector3) -> BossMissile:
	var point := _ground_point(at)
	last_missile_target = point
	last_marker = MissileTargetMarker.spawn(get_parent(), point, missile_blast_radius)
	var from := missile_socket.global_transform
	last_missile = BossMissile.launch(get_parent(), from, point, self, last_marker)
	last_missile.speed = missile_speed
	last_missile.damage = missile_damage
	last_missile.blast_radius = missile_blast_radius
	missiles_fired += 1
	Sfx.play_at(get_parent(), Sfx.BH_FIRE, from.origin, -6.0, 5.0, 60.0)
	missile_launched.emit(point)
	_chest_open_t = chest_open_delay
	return last_missile


## The floor under a point (where the player stands, even mid-jump).
func _ground_point(at: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 40.0)
	q.collision_mask = 1
	var skip: Array[RID] = [get_rid()]
	for p in get_tree().get_nodes_in_group(&"players"):
		skip.append((p as CollisionObject3D).get_rid())
	q.exclude = skip
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else at


# --- chest / core ---

## Open the flap now (exposes the core); it closes by itself after
## `core_exposed_time`. Game code can also call open_chest / close_chest.
func open_chest() -> void:
	if exposed or not alive:
		return
	chest_player.play(&"Chest_Open")
	_chest_open_t = -1.0
	_exposed_t = -core_expose_lead  # counts up to 0 = core exposed


func close_chest() -> void:
	if exposed:
		exposed = false
		core_protected.emit()
	_exposed_t = 0.0
	if chest_player.current_animation != &"Chest_Closed":
		chest_player.play(&"Chest_Close")
	_core_glow.visible = false


func _update_chest(delta: float) -> void:
	if _chest_open_t >= 0.0:
		_chest_open_t -= delta
		if _chest_open_t < 0.0:
			open_chest()
	if chest_player.current_animation == &"Chest_Open" or exposed:
		if not exposed:
			_exposed_t += delta
			if _exposed_t >= 0.0:
				exposed = true
				_exposed_t = core_exposed_time
				_core_glow.visible = true
				core_exposed.emit()
	if exposed:
		_exposed_t -= delta
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 9.0)
		_core_mat.emission_energy_multiplier = core_glow_energy * (0.7 + 0.5 * pulse)
		Vfx.set_alpha(_core_glow, 0.45 + 0.35 * pulse)
		if _exposed_t <= 0.0:
			close_chest()
	elif _core_mat:
		_core_mat.emission_energy_multiplier = move_toward(_core_mat.emission_energy_multiplier, core_glow_energy * 0.35, delta * 6.0)


## Weapons aim at the core while it's exposed, the chest otherwise.
func _update_targetable() -> void:
	if _targetable == null:
		return
	if exposed:
		_targetable.global_position = core.global_position
	else:
		_targetable.position = _target_rest


# --- damage ---

func apply_damage(info: DamageInfo) -> void:
	if not alive:
		return
	var on_core := exposed and hits_core(info)
	var amount := info.damage_amount * (core_damage_scale if on_core else armour_damage_scale)
	health -= amount
	if on_core:
		core_hits += 1
		core_hit.emit(amount)
		_core_mat.emission_energy_multiplier = core_glow_energy * 2.5
	if health <= 0.0:
		die(info)


## Would this hit reach the core? Direct hits: the shot's line passes
## within `core_hit_radius` of it, just ahead of where it struck the armour.
## Blasts: they go off close to it.
func hits_core(info: DamageInfo) -> bool:
	var c := core.global_position
	if info.is_explosive():
		return info.impact_position.distance_to(c) < core_hit_radius + 0.4
	var d := info.impact_direction
	var t := (c - info.impact_position).dot(d)
	if t < -0.25 or t > 1.2:
		return false
	return (info.impact_position + d * t).distance_to(c) <= core_hit_radius


func die(_info: DamageInfo = null) -> void:
	if not alive:
		return
	alive = false
	state = State.DEAD
	exposed = false
	_chest_open_t = -1.0
	_core_glow.visible = false
	set_spin(0.0)
	close_chest()
	if _targetable:
		_targetable.kill()
	anim.speed_scale = 1.0
	anim.play(DEATH_CLIP, 0.15)
	_move_anim = DEATH_CLIP
	linear_velocity = Vector3.ZERO
	# Lying down: the capsule lies along the fallen body.
	if _collision:
		_collision.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0).rotated(Vector3.UP, _yaw), Vector3(0, 0.4, 0) + Vector3(sin(_yaw), 0, cos(_yaw)) * 0.6)
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	set_deferred("freeze", true)
	died.emit()
	if respawn_time >= 0.0:
		get_tree().create_timer(respawn_time, false).timeout.connect(_respawn)


func _respawn() -> void:
	if not is_inside_tree():
		return
	freeze = false
	global_transform = _spawn_xf
	linear_velocity = Vector3.ZERO
	if _collision:
		_collision.transform = _collision_rest
	health = max_health
	alive = true
	state = State.COMBAT
	_missile_t = missile_first_delay
	chest_player.play(&"Chest_Closed")
	anim.play(&"Idle")
	_move_anim = &"Idle"
	if _targetable:
		_targetable.revive()
