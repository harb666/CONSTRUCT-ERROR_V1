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
## `gun_player`. The barrel spins up and down smoothly (`set_spin`), and the
## chaingun fires one round each time a barrel passes (5 barrels), so the
## spin, cadence and muzzle flashes are one weapon; `BossGunAim` turns the
## arm at the shoulder so the barrels point where the rounds go.
##
## Size: the whole model is scaled by `model_scale` at the Visual node; the
## collider, aim point, tap area and death collider are scaled with it.
## Walking: Heavy_Walk (authored in place for WALK_CLIP_SPEED model units/s)
## plays at the body's real ground speed, so planted feet don't slide;
## Heavy_Step stamps round on the spot while it turns.

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
const WALK_CLIP := &"Heavy_Walk"
const STEP_CLIP := &"Heavy_Step"
## Turning on the spot: heavy two-step turns of TURN_STEP_DEG each
## (tools/author_boss_walk.gd), chained for bigger turns.
const TURN_LEFT := &"Heavy_Turn_L"
const TURN_RIGHT := &"Heavy_Turn_R"
const TURN_STEP_DEG := 45.0
const WORN_SHADER := preload("res://scripts/vfx/worn_armour.gdshader")
## Heavy_Walk's in-place speed at playback 1 (model units/s, at scale 1;
## from tools/author_boss_walk.gd: 2 * STEP / CYCLE).
const WALK_CLIP_SPEED := 0.6 / 1.8
## Chaingun: 5 barrels, Chaingun_Fire turns 2 revolutions per second, so at
## playback 1 a barrel passes 10 times a second.
const BARRELS := 5
const CLIP_REVS_PER_S := 2.0
const FULL_CLIP_RATE := BARRELS * CLIP_REVS_PER_S
## Chaingun rotor spin axis in the rotor's own space (from the asset) and
## how far along it the barrel tips are.
const ROTOR_AXIS := Vector3(-0.0200662, 0.9543148, 0.2981285)
## Launcher silo (model units, from tools/build_robot_boss.py): Missile_Spawn
## is the loaded missile's centre; the nozzle mouth is SILO_MOUTH further
## along its +Z; the bore is SILO_RADIUS wide.
const SILO_MOUTH := 0.285
const SILO_RADIUS := 0.135
## Reactor core radius (model units).
const CORE_RADIUS := 0.052
## Joints the dying robot's arcs jump between.
const ARC_BONES := ["Hips", "Spine", "Spine2", "Neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand", "LeftUpLeg", "LeftLeg", "RightUpLeg", "RightLeg"]
const BULLET_COLOR := Color(1.0, 0.55, 0.1)
const BULLET_HOT := Color(1.0, 0.9, 0.5)

@export_group("Size")
## In-game size (the asset is ~1.7 m tall at 1).
@export var model_scale := 4.0

@export_group("Health")
@export var max_health := 60.0
## Damage scale for hits anywhere but the exposed core (armour).
@export var armour_damage_scale := 0.1
@export_group("Stagger")
## Concentrated fire / heavy hits fill a stagger meter (StaggerMeter); when
## full the boss malfunctions for `stagger_duration` s: chaingun and missile
## interrupted, it stops walking, and its armour takes
## `stagger_armour_scale` x more damage. 0 threshold = off.
@export var stagger_threshold := 9.0
@export var stagger_duration := 1.25
@export var stagger_armour_scale := 3.0
@export_group("")
## Damage scale for hits on the exposed core.
@export var core_damage_scale := 1.0
## A shot hits the core if its line passes this close to it (m).
@export var core_hit_radius := 0.6
@export var respawn_time := 12.0

@export_group("Movement")
## Walking speed (m/s). The walk animation's speed follows the actual
## ground speed, so the feet always match the distance travelled.
@export var walk_speed := 1.6
## Speeding up / slowing down (m/s per s): heavy.
@export var walk_accel := 2.2
## Heading corrections while walking (rad/s; standing turns are steps).
@export var turn_speed := 1.1
## Standing: the legs step round once the player is this far off to the
## side (deg); smaller corrections are the upper body twisting.
@export var turn_start_deg := 30.0
## Playback speed of the turn steps (1 = 45 deg per second).
@export var turn_step_rate := 1.2
## Footprint radius for ground support (m): it only stands on surfaces that
## hold most of its footprint, never on small boxes / props.
@export var footprint_radius := 0.8
## Highest believable step up / down (m).
@export var max_step := 0.5
@export var detect_range := 45.0
## Tries to stay this far from the player (m).
@export var preferred_range := Vector2(12.0, 26.0)
## Never wanders further than this from where it was placed (m).
@export var home_radius := 3.0
## Fights even while robot AI is switched off globally (tests, cutscenes).
@export var always_active := false

@export_group("Chaingun")
@export var chaingun_spin_up := 0.6
@export var chaingun_spin_down := 1.2
@export var chaingun_burst_time := 2.2
@export var chaingun_cooldown := 1.6
## Rounds per second at full spin; the barrels spin to match (one round per
## barrel passing).
@export var chaingun_fire_rate := 10.0
## Chaingun sound (Sfx.MINI_BOSS_MG, the owner's recording of continuous
## fire, ~7 shots/s): every round fired plays ONE shot cut from it (a clean
## shot at one of `chaingun_shot_starts` s into the file, `chaingun_shot_len`
## s long with a short fade), so the sound always matches the real rate of
## fire - spin-up, full rate and spin-down alike.
@export var chaingun_sound_db := 0.0
@export var chaingun_sound_near := 8.0
@export var chaingun_sound_far := 70.0
@export var chaingun_shot_starts: Array[float] = [2.631, 3.519, 4.005, 4.175, 4.475, 4.831]
@export var chaingun_shot_len := 0.13
@export var chaingun_shot_fade := 0.03
## Footsteps (Sfx.MINI_BOSS_WALKING, the owner's recording of three heavy
## stomps): every time one of its feet lands - walking, turning on the
## spot, any speed - it plays ONE stomp cut from the file (at one of
## `step_sound_starts` s, just before the stomp's hit, `step_sound_len` s
## long with its servo whine, fading at the end), so each stomp lands
## exactly with a foot. A foot has landed when it comes back down to within
## `foot_plant_height` m of its lowest point after lifting more than
## `foot_lift_height` m.
@export var step_sound_db := 0.0
@export var step_sound_near := 8.0
@export var step_sound_far := 60.0
@export var step_sound_starts: Array[float] = [0.065, 1.065, 2.065]
@export var step_sound_len := 0.92
@export var step_sound_fade := 0.15
@export var foot_lift_height := 0.12
@export var foot_plant_height := 0.03
## Projectile speed (m/s).
@export var chaingun_bullet_speed := 46.0
@export var chaingun_damage := 0.4
## Small scatter around the barrel direction.
@export var chaingun_spread_deg := 1.2
## Only fires while the barrels point within this angle of the target.
@export var chaingun_fire_cone_deg := 6.0
## How long a round's orange scorch mark glows where it hits (s).
@export var chaingun_impact_lifetime := 0.45
## Size of the orange rounds / tracers (1 = the robots' plasma bolts).
@export var chaingun_tracer_size := 1.8
@export var chaingun_range := 40.0

@export_group("Missile")
## Seconds between missile attacks.
@export var missile_interval := 7.0
## First missile this long after it spots the player.
@export var missile_first_delay := 3.0
## Telegraph: stops shooting and squares up before the launch.
@export var missile_windup := 0.7
## Missile speed through the climb / at the end of its dive (m/s).
@export var missile_speed := 20.0
@export var missile_dive_speed := 42.0
## How high the missile climbs above the launcher before arcing over (m).
@export var missile_climb_height := 16.0
@export var missile_damage := 3.0
@export var missile_blast_radius := 2.6
## Missile length (m); a loaded one sits in the launcher's silo.
@export var missile_length := 1.8
## Missile launch sound (the owner's recording). It is played from
## `missile_sound_start` s in: the launch blast's onset (before it is ~1 s of
## near-silence), so the blast is heard the moment the missile fires.
@export var missile_sound_start := 1.03
@export var missile_sound_db := 0.0
@export var missile_sound_near := 8.0
@export var missile_sound_far := 80.0
## After a launch the next missile is loaded this much later (s).
@export var missile_reload_time := 1.6

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

@export_group("Death")
## Core overloads this long, then blows; the robot collapses at
## `death_collapse_time` (s after the killing hit).
@export var death_overload_time := 0.55
## Machine-death sound (Sfx.MACHINE_DEATH, the owner's own sound) as it
## starts to die: loudness, full within `death_sound_near` m, silent beyond
## `death_sound_far` m.
@export var death_sound_db := 0.0
@export var death_sound_near := 8.0
@export var death_sound_far := 80.0
## Death sounds started (tests).
var death_sounds := 0
@export var death_collapse_time := 1.05
## Visor glow (emission energy) while it's alive.
@export var visor_glow := 2.5

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
## Chaingun shot sounds started (tests).
var chaingun_sounds := 0
var missile_sounds := 0
var _mg_voices: Array[DynamicSound] = []
var _mg_left: Array[float] = []
## Footsteps: stomps played (tests), voices, their time left, and per foot
## [bone, lowest height seen, lifted?].
var step_sounds := 0
var last_step_foot := -1
var _step_voices: Array[DynamicSound] = []
var _step_left: Array[float] = []
var _step_next := 0
var _step_pick := -1
var _feet: Array = []
var _mg_next := 0
var _mg_shot := 0
## Direction of the last chaingun round (tests).
var last_shot_dir := Vector3.ZERO
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
var chaingun_muzzle: Node3D
var gun_aim: BossGunAim
var missile_socket: Node3D
var flap: Node3D
## The missile waiting in the silo (hidden while reloading).
var loaded_missile: Node3D
var core_fx: BossCoreFx
var hit_react: BossHitReact
var launch_fx: LauncherBlast
## Seconds since the killing hit (-1 while alive).
var dying_t := -1.0
var torso_twist: BossTorsoTwist
var cables: BossCoreCables
var gun_flash: MachineGunFlash
## Turn step in progress: +1 left, -1 right, 0 none; steps taken (tests).
var turn_dir := 0
var turn_steps := 0
## Ground under its footprint, and whether the way ahead was blocked.
var ground_y := 0.0
var path_blocked := false

var _visual: Node3D
var _targetable: Targetable
var _target_rest := Vector3.ZERO
var _spawn_xf: Transform3D
var _yaw := 0.0
var _spin := 0.0
var _gun_phase := 0  # 0 cooldown, 1 spin up, 2 firing
var _gun_t := 0.0
var _last_barrel := -1
var _speed := 0.0
var _turning := false
var _missile_t := 0.0
var stagger: StaggerMeter
var _windup_t := 0.0
var _chest_open_t := -1.0
var _exposed_t := 0.0
var _core_mat: StandardMaterial3D
var _core_glow: MeshInstance3D
var _move_anim := &""
var _collision: CollisionShape3D
var _collision_rest: Transform3D
var _reload_t := 0.0
var _load_slide := 0.0
var _sk: Skeleton3D
var _arc_bones: Array[int] = []
var _visor_mat: StandardMaterial3D
var _visor_albedo := Color.WHITE
var _core_rest: StandardMaterial3D
var _collapsed := false
var _want_yaw := 0.0
var _last_turn := 0
var _detour_t := 0.0
var _detour_yaw := 0.0
var _flash_pivot: Node3D

static var _lib_cache: AnimationLibrary
static var _chest_lib: AnimationLibrary
static var _gun_lib: AnimationLibrary


func _ready() -> void:
	mass = 2000.0
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
	if stagger_threshold > 0.0:
		stagger = StaggerMeter.new()
		stagger.threshold = stagger_threshold
		stagger.duration = stagger_duration
		stagger.staggered.connect(_on_staggered)
	# Never lifted onto obstacles by its collider: height follows the ground
	# under its footprint (_update_ground).
	axis_lock_linear_y = true
	ground_y = global_position.y
	_build_model()
	_apply_scale()
	health = max_health
	_yaw = _visual.rotation.y
	_want_yaw = _yaw
	_missile_t = missile_first_delay


## Everything that has a size follows `model_scale`.
func _apply_scale() -> void:
	_visual.scale = Vector3.ONE * model_scale
	if _collision and _collision.shape is CapsuleShape3D:
		# Resized in place (the scene's shape is local to each boss).
		# (Height first: a capsule is kept at least 2 x radius tall.)
		var cap := _collision.shape as CapsuleShape3D
		cap.height *= model_scale
		cap.radius *= model_scale
		_collision.position *= model_scale
		_collision_rest = _collision.transform
	if _targetable:
		_target_rest *= model_scale
		_targetable.position = _target_rest
		_targetable.select_radius *= model_scale
		_targetable.select_half_height *= model_scale
	_flash_pivot.scale = Vector3.ONE / model_scale
	# The loaded missile is `missile_length` long in the world.
	loaded_missile.scale = Vector3.ONE * missile_length / model_scale
	# Effects reach well beyond the small core so they read at range.
	core_fx.radius = CORE_RADIUS * model_scale * 2.6


func _build_model() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	model = MODEL.instantiate()
	model.name = "Model"
	_visual.add_child(model)
	# Its hips sit 0.125 m to the side of and 0.22 m in front of the model's
	# origin: put them over the body's origin (it turns about them, as do
	# the turn-step clips).
	model.position = Vector3(0.12508, 0.0, -0.221)
	anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	core = model.find_child("Reactor_Core", true, false) as MeshInstance3D
	rotor = model.find_child("Chaingun_Barrel_Rotor", true, false) as Node3D
	missile_socket = model.find_child("Missile_Spawn", true, false) as Node3D
	chaingun_muzzle = model.find_child("Chaingun_Muzzle", true, false) as Node3D
	flap = model.find_child("Chest_Frown_Plate_Hinge", true, false) as Node3D
	_setup_animation()
	var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D
	_sk = sk
	# Torso leads turns, hit reactions on top, then the chaingun aim (keeps
	# aiming true).
	torso_twist = BossTorsoTwist.new()
	torso_twist.name = "TorsoTwist"
	sk.add_child(torso_twist)
	torso_twist.setup(sk)
	hit_react = BossHitReact.new()
	hit_react.name = "HitReact"
	sk.add_child(hit_react)
	hit_react.setup(sk)
	for b in ARC_BONES:
		var bi := sk.find_bone("mixamorig_" + b)
		if bi >= 0:
			_arc_bones.append(bi)
	gun_aim = BossGunAim.new()
	gun_aim.name = "GunAim"
	sk.add_child(gun_aim)
	gun_aim.setup(sk, "Left", chaingun_muzzle.transform)
	# Core: its own glowing material (pulses while exposed) and a soft glow.
	_core_mat = (core.get_active_material(0) as StandardMaterial3D).duplicate()
	_core_mat.emission_enabled = true
	_core_mat.emission = Color(1.0, 0.05, 0.02)
	_core_mat.emission_energy_multiplier = core_glow_energy * 0.35
	core.material_override = _core_mat
	_core_glow = Vfx.quad("glow", Color(1.0, 0.1, 0.05), Vector2.ONE * 0.5, BaseMaterial3D.BILLBOARD_ENABLED)
	_core_glow.visible = false
	core.add_child(_core_glow)
	_core_rest = _core_mat.duplicate()
	# Visor: its own red emissive material (per boss, it flickers out at death).
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if m and m.resource_name == "Visor_Emissive":
				_visor_mat = (m as StandardMaterial3D).duplicate()
				_visor_mat.emission_energy_multiplier = visor_glow
				_visor_mat.emission = Color(1.0, 0.07, 0.04)
				_visor_mat.albedo_color = Color(1.0, 0.2, 0.15)
				_visor_albedo = _visor_mat.albedo_color
				mi.set_surface_override_material(si, _visor_mat)
	# A missile loaded in the silo (the shared missile model).
	loaded_missile = BossMissileModel.create(1.0)
	loaded_missile.name = "LoadedMissile"
	missile_socket.add_child(loaded_missile)
	core_fx = BossCoreFx.new()
	core_fx.name = "CoreFx"
	core_fx.points = arc_points
	add_child(core_fx)
	launch_fx = LauncherBlast.new()
	launch_fx.name = "LaunchFx"
	add_child(launch_fx)
	_worn_materials()
	# Core power cables (in the core socket's space).
	var socket := core.get_parent() as Node3D
	cables = BossCoreCables.new()
	cables.name = "CoreCables"
	var spine2 := sk.find_bone("mixamorig_Spine2")
	var sk_in_model := model.global_transform.affine_inverse() * sk.global_transform
	cables.socket_in_model = sk_in_model * sk.get_bone_global_rest(spine2) * socket.transform
	cables.core_radius = CORE_RADIUS
	socket.add_child(cables)
	core_fx.cable_ends = cables.broken_ends
	# Chaingun muzzle flash: big, orange, one per boss, restarted per round
	# (+X of the flash = the muzzle's +Z, the way the rounds go).
	_flash_pivot = Node3D.new()
	_flash_pivot.name = "FlashPivot"
	_flash_pivot.transform = Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), Vector3.ZERO)
	chaingun_muzzle.add_child(_flash_pivot)
	gun_flash = MachineGunFlash.new()
	gun_flash.name = "MuzzleFlash"
	gun_flash.length = 3.2
	gun_flash.flash_life = 0.05
	gun_flash.light_energy = 8.0
	gun_flash.light_range = 11.0
	gun_flash.flame_color = Color(1.0, 0.55, 0.12)
	gun_flash.hot_color = Color(1.0, 0.93, 0.65)
	gun_flash.spark_color = Color(1.0, 0.62, 0.18)
	gun_flash.light_color = Color(1.0, 0.6, 0.25)
	gun_flash.size = 5.5
	gun_flash.smoke = true
	_flash_pivot.add_child(gun_flash)


## Worn, chipped armour (robot's own atlas + procedural wear) on the
## launcher housing, the chest flap (plain back restyled as dark plate with
## a red trim) and the core pocket.
func _worn_materials() -> void:
	var src: StandardMaterial3D = null
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if m and m.resource_name == "BakedMaterial" and m.albedo_texture:
			src = m
			break
	for n in ["Rocket_Launcher_Housing", "Chest_Frown_Plate_Hinge", "Chest_Core_Housing"]:
		var mi := model.find_child(n, true, false) as MeshInstance3D
		if mi == null or src == null:
			continue
		var m := ShaderMaterial.new()
		m.shader = WORN_SHADER
		m.set_shader_parameter("albedo_tex", src.albedo_texture)
		m.set_shader_parameter("normal_tex", src.normal_texture)
		if n == "Chest_Frown_Plate_Hinge":
			var box := mi.mesh.get_aabb()
			m.set_shader_parameter("restyle", 1.0)
			m.set_shader_parameter("box_min", box.position)
			m.set_shader_parameter("box_size", box.size)
		elif n == "Chest_Core_Housing":
			m.set_shader_parameter("wear", 0.5)
		mi.material_override = m


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
				if n in LOCOMOTION or n == WALK_CLIP or n == STEP_CLIP:
					a.loop_mode = Animation.LOOP_LINEAR
				if n in LOCOMOTION:
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
		_update_death(delta)
		return
	if stagger:
		stagger.update(delta)
		if stagger.is_staggered():
			_update_stagger(delta)
			return
	_update_reload(delta)
	_update_ground(delta)
	core_fx.instability = clampf(1.0 - health / max_health, 0.0, 1.0)
	_find_target()
	_update_chest(delta)
	match state:
		State.COMBAT:
			_combat(delta)
		State.WINDUP:
			_windup(delta)
	_update_gun(delta)
	_update_twist()
	_update_targetable()


func _find_target() -> void:
	target = null
	if not RobotEnemy.ai_enabled and not always_active:
		return
	var best := detect_range
	for p in get_tree().get_nodes_in_group(&"players"):
		var d := global_position.distance_to((p as Node3D).global_position)
		if d < best:
			best = d
			target = p


func _combat(delta: float) -> void:
	var want := 0.0  # speed along its facing (m/s, negative = backing up)
	var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
	if target:
		var to := target.global_position - global_position
		to.y = 0.0
		var d := to.length()
		# Detour round an obstacle for a moment, then face the player again.
		_detour_t = maxf(_detour_t - delta, 0.0)
		var head := to.rotated(Vector3.UP, _detour_yaw) if _detour_t > 0.0 else to
		_face(head, delta)
		# Walks straight at / away from the player once it faces them.
		var facing := fwd.dot(head / maxf(head.length(), 0.01)) > 0.85
		if d > preferred_range.y and facing:
			want = walk_speed
		elif d < preferred_range.x and facing:
			want = -walk_speed
		# Never walks into / onto an obstacle it can't step over: stops, and
		# (going forward) picks the clearer side to go round.
		path_blocked = want != 0.0 and _blocked(fwd * signf(want))
		if path_blocked:
			if want > 0.0 and _detour_t <= 0.0:
				var l := not _blocked(fwd.rotated(Vector3.UP, deg_to_rad(50.0)))
				var r := not _blocked(fwd.rotated(Vector3.UP, deg_to_rad(-50.0)))
				if l or r:
					_detour_yaw = deg_to_rad(50.0 if l else -50.0)
					_detour_t = 3.0
			want = 0.0
		_missile_t -= delta
		if _missile_t <= 0.0 and not exposed and _chest_open_t < 0.0:
			_start_windup()
	else:
		_turning = false
		_missile_t = maxf(_missile_t, missile_first_delay)
	# Stay near home: no step that takes it further out.
	var away := global_position - _spawn_xf.origin
	away.y = 0.0
	if away.length() > home_radius * 0.8 and signf(want) * fwd.dot(away) > 0.0:
		want = 0.0
	_move(want, delta)


## Staggered: stands malfunctioning, guns quiet, then picks up again.
func _update_stagger(delta: float) -> void:
	_update_reload(delta)
	_update_ground(delta)
	_update_chest(delta)
	_move(0.0, delta)
	set_spin(move_toward(_spin, 0.0, delta / maxf(chaingun_spin_down, 0.01)))
	_gun_phase = 0
	_gun_t = maxf(_gun_t, 0.4)
	_update_twist()
	_update_targetable()
	# Shudders and crackles while it lasts.
	if randf() < delta * 10.0:
		hit_react.kick(0.25, Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)))
		core_fx.core_pos = core.global_position
		core_fx.hit(0.3, Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)))


func _on_staggered(_d: float) -> void:
	# Interrupt: a missile being wound up is cancelled (and comes later).
	if state == State.WINDUP:
		state = State.COMBAT
		_missile_t = maxf(_missile_t, 2.0)
	hit_react.kick(1.4, -global_basis.z)
	core_fx.core_pos = core.global_position
	core_fx.hit(1.0, -global_basis.z)
	if _skeleton_node():
		var sk := _skeleton_node()
		for b in ["mixamorig_Spine2", "mixamorig_LeftArm", "mixamorig_RightArm", "mixamorig_Neck"]:
			var i := sk.find_bone(b)
			if i >= 0:
				JointSparks.play_on_bone(sk, i, 1.0)


func _skeleton_node() -> Skeleton3D:
	var found := find_children("*", "Skeleton3D", true, false)
	return found[0] if not found.is_empty() else null


func is_staggered() -> bool:
	return stagger != null and stagger.is_staggered()


func _start_windup() -> void:
	state = State.WINDUP
	_windup_t = missile_windup


func _windup(delta: float) -> void:
	_move(0.0, delta)
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


## Heavy walk along its facing at `want` m/s (negative = backwards). The
## walk clip plays at exactly the ground speed (feet don't slide); it
## stamps round on the spot while turning; idles otherwise.
func _move(want: float, delta: float) -> void:
	_update_turn()
	if turn_dir != 0:
		want = 0.0
	_speed = move_toward(_speed, want, walk_accel * delta)
	var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
	var lv := linear_velocity
	linear_velocity = Vector3(fwd.x * _speed, lv.y, fwd.z * _speed)
	if turn_dir != 0:
		return  # the turn step owns the legs
	var clip := &"Idle"
	var rate := 1.0
	if absf(_speed) > 0.05:
		clip = WALK_CLIP
		rate = _speed / (WALK_CLIP_SPEED * model_scale)
	if clip != _move_anim:
		_move_anim = clip
		anim.play(clip, 0.4)
	anim.speed_scale = rate


## The ground speed the walk animation is showing (m/s).
func walk_anim_ground_speed() -> float:
	return anim.speed_scale * WALK_CLIP_SPEED * model_scale if _move_anim == WALK_CLIP else 0.0


## Faces `dir`. Walking: small heading corrections ride on its steps.
## Standing: the upper body twists towards it (BossTorsoTwist); once it is
## more than `turn_start_deg` off, the legs step round in heavy 45-degree
## turn steps (chained for bigger turns: ~4 steps for 180 degrees).
func _face(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.01:
		return
	_want_yaw = atan2(dir.x, dir.z)
	if turn_dir != 0:
		return
	var diff := wrapf(_want_yaw - _yaw, -PI, PI)
	if absf(_speed) > 0.05:
		_yaw += clampf(diff, -turn_speed * 0.35 * delta, turn_speed * 0.35 * delta)
		_visual.rotation.y = _yaw
		return
	if absf(diff) > deg_to_rad(turn_start_deg):
		var d := 1 if diff > 0.0 else -1
		# Right behind it: keep turning the way it last turned (no dithering).
		if absf(diff) > deg_to_rad(160.0) and _last_turn != 0:
			d = _last_turn
		_start_turn(d, false)


func _start_turn(dir: int, chained: bool) -> void:
	turn_dir = dir
	_last_turn = dir
	turn_steps += 1
	var clip := TURN_LEFT if dir > 0 else TURN_RIGHT
	anim.play(clip, 0.0 if chained else 0.25)
	if chained:
		anim.seek(0.0, true)
	anim.speed_scale = turn_step_rate
	_move_anim = clip
	_turning = true


## A turn step ends in the rest pose turned 45 degrees: hand the angle over
## to the body's yaw (same pose, no pop), then step again or stand.
func _update_turn() -> void:
	if turn_dir == 0:
		return
	if anim.current_animation == _move_anim and anim.is_playing() and anim.current_animation_position < anim.current_animation_length - 0.0005:
		return
	_yaw += turn_dir * deg_to_rad(TURN_STEP_DEG)
	_visual.rotation.y = _yaw
	var d := turn_dir
	turn_dir = 0
	_turning = false
	var diff := wrapf(_want_yaw - _yaw, -PI, PI)
	if alive and absf(diff) > deg_to_rad(turn_start_deg * 0.6) and ((1 if diff > 0.0 else -1) == d or absf(diff) > deg_to_rad(160.0)):
		_start_turn(d, true)
	else:
		anim.play(&"Idle", 0.0)
		anim.seek(0.0, true)
		anim.speed_scale = 1.0
		_move_anim = &"Idle"


## How far the body (incl. a turn step in progress) faces, and the upper
## body twisting the rest of the way towards the player.
func facing_yaw() -> float:
	var y := _yaw
	if turn_dir != 0 and anim.current_animation_length > 0.0:
		var u := anim.current_animation_position / anim.current_animation_length
		y += turn_dir * deg_to_rad(TURN_STEP_DEG) * smoothstep(0.06, 0.92, u)
	return y


func _update_twist() -> void:
	torso_twist.target_yaw = wrapf(_want_yaw - facing_yaw(), -PI, PI) if target != null and alive else 0.0


## Ground under its footprint: centre + 4 points `footprint_radius` round
## it. A surface counts only if it holds at least 4 of the 5 points (no
## standing on small boxes / props); the body's height follows it within
## `max_step`. Moving props and players are ignored (they get pushed).
func _update_ground(delta: float) -> void:
	var b := Basis(Vector3.UP, _yaw)
	var hs: Array[float] = []
	for off in [Vector3.ZERO, Vector3(footprint_radius, 0, 0), Vector3(-footprint_radius, 0, 0), Vector3(0, 0, footprint_radius), Vector3(0, 0, -footprint_radius)]:
		var h := _floor_at(global_position + b * off)
		if not is_nan(h):
			hs.append(h)
	var best := NAN
	for h in hs:
		var n := 0
		for o in hs:
			if absf(o - h) < 0.2:
				n += 1
		# (any drop is fine; stepping up only as far as `max_step`)
		if n >= 4 and (is_nan(best) or h > best) and h - global_position.y <= max_step:
			best = h
	if not is_nan(best):
		ground_y = best
		var p := global_position
		p.y = move_toward(p.y, ground_y, 4.0 * delta)
		global_position = p


func _floor_at(p: Vector3) -> float:
	var skip: Array[RID] = [get_rid()]
	var space := get_world_3d().direct_space_state
	for k in 4:
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * (max_step + 1.0), p + Vector3.DOWN * 3.0)
		q.collision_mask = 1
		q.exclude = skip
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return NAN
		var col: Object = hit.collider
		if col is CharacterBody3D or (col is RigidBody3D and not (col as RigidBody3D).freeze):
			skip.append(hit.rid)
			continue
		return hit.position.y
	return NAN


## Is there something it can't step over within reach along `dir`? (static
## level geometry / frozen bodies above `max_step`; loose props get pushed.)
func _blocked(dir: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var side := dir.cross(Vector3.UP).normalized()
	var reach := 0.55 * model_scale + 1.2
	for h in [max_step + 0.15, 1.6]:
		for s in [-0.3, 0.0, 0.3]:
			var o: Vector3 = global_position + Vector3.UP * h + side * s * model_scale
			var q := PhysicsRayQueryParameters3D.create(o, o + dir * reach)
			q.collision_mask = 1
			q.exclude = [get_rid()]
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var col: Object = hit.collider
			if col is CharacterBody3D or (col is RigidBody3D and not (col as RigidBody3D).freeze):
				continue
			return true
	return false


# --- chaingun ---

func _update_gun(delta: float) -> void:
	var can_fire := state == State.COMBAT and target != null and (fire_while_exposed or not exposed) \
		and global_position.distance_to(target.global_position) <= chaingun_range
	# The arm tracks the player whenever it's fighting.
	gun_aim.target_weight = 1.0 if target != null and state != State.DEAD else 0.0
	if target:
		gun_aim.target_point = target.global_position + Vector3.UP * 1.0
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
	var rate := (1.0 / chaingun_spin_up) if want_spin > _spin else (1.0 / chaingun_spin_down)
	set_spin(move_toward(_spin, want_spin, rate * delta))
	# One round each time a barrel comes round (only while firing and on
	# target), so cadence = barrel rotation.
	var barrel := int(floor(gun_player.current_animation_position * FULL_CLIP_RATE))
	if _last_barrel >= 0 and barrel != _last_barrel and _gun_phase == 2:
		var passes := posmod(barrel - _last_barrel, int(FULL_CLIP_RATE))
		for i in passes:
			if gun_aim.aim_error_deg <= chaingun_fire_cone_deg:
				_fire_bullet()
	_last_barrel = barrel


## Barrel spin, 0 (still) .. 1 (full speed = `chaingun_fire_rate`).
func set_spin(v: float) -> void:
	_spin = clampf(v, 0.0, 1.0)
	gun_player.speed_scale = _spin * chaingun_fire_rate / FULL_CLIP_RATE


func get_spin() -> float:
	return _spin


func muzzle_position() -> Vector3:
	return chaingun_muzzle.global_position


## Rounds leave the barrel tips along the barrel axis.
func _fire_bullet() -> void:
	var m := chaingun_muzzle.global_transform
	var dir := m.basis.z.normalized()
	var spread := deg_to_rad(chaingun_spread_deg)
	dir = dir.rotated(Vector3.UP, randf_range(-spread, spread))
	var right := dir.cross(Vector3.UP)
	if right.length_squared() > 0.001:
		dir = dir.rotated(right.normalized(), randf_range(-spread, spread))
	var bolt := PlasmaBolt.fire(get_tree(), m.origin, dir, self, chaingun_bullet_speed, chaingun_damage, BULLET_COLOR, BULLET_HOT)
	if bolt:
		bolt.mark_life = chaingun_impact_lifetime
		bolt.crackle = false
		bolt.size = chaingun_tracer_size
		bolt.max_range = chaingun_range + 10.0
	gun_flash.fire(_spin, 1.0)
	_chaingun_sound()
	last_shot_dir = dir
	bullets_fired += 1


## One shot from the owner's chaingun recording for this round (voices in
## turn; each plays its short slice, then fades and stops in _process).
func _chaingun_sound() -> void:
	if _mg_voices.is_empty():
		for i in 4:
			var v := Sfx.emitter(chaingun_muzzle, Sfx.MINI_BOSS_MG, chaingun_sound_db, chaingun_sound_near, chaingun_sound_far)
			v.name = "ChaingunShot%d" % i
			_mg_voices.append(v)
			_mg_left.append(0.0)
	var v := _mg_voices[_mg_next]
	if is_instance_valid(v) and v.is_inside_tree() and not chaingun_shot_starts.is_empty():
		v.fade = 1.0
		v.play(chaingun_shot_starts[_mg_shot % chaingun_shot_starts.size()])
		_mg_left[_mg_next] = chaingun_shot_len
		_mg_shot += 1
		chaingun_sounds += 1
	_mg_next = (_mg_next + 1) % _mg_voices.size()


# --- missile ---

## Fire a missile at the point under `at` (the player's position NOW). The
## point is fixed: the missile does not follow the player afterwards.
func fire_missile(at: Vector3) -> BossMissile:
	var point := _ground_point(at)
	last_missile_target = point
	last_marker = MissileTargetMarker.spawn(get_parent(), point, missile_blast_radius)
	var from := missile_socket.global_transform
	last_missile = BossMissile.launch(get_parent(), from, point, self, last_marker, missile_length)
	last_missile.speed = missile_speed
	last_missile.dive_speed = missile_dive_speed
	last_missile.climb_height = missile_climb_height
	last_missile.damage = missile_damage
	last_missile.blast_radius = missile_blast_radius
	# The loaded round is the one that left; fire and smoke out of the silo.
	loaded_missile.visible = false
	_reload_t = missile_reload_time
	launch_fx.fire(silo_mouth(), SILO_RADIUS * 2.0 * model_scale)
	missiles_fired += 1
	# The owner's launch sound, from the instant the blast starts in the
	# recording, so the blast lands on the frame the missile leaves.
	var snd := Sfx.play_at(get_parent(), Sfx.MINI_BOSS_MISSILE, from.origin, missile_sound_db, missile_sound_near, missile_sound_far)
	if snd:
		snd.play(missile_sound_start)
		missile_sounds += 1
	missile_launched.emit(point)
	_chest_open_t = chest_open_delay
	return last_missile


## The launcher's nozzle mouth: +Z out of the silo.
func silo_mouth() -> Transform3D:
	var m := missile_socket.global_transform
	return Transform3D(m.basis.orthonormalized(), m.origin + m.basis.z * SILO_MOUTH)


## Reloading: the next missile appears in the silo and slides home.
func _update_reload(delta: float) -> void:
	if _reload_t > 0.0:
		_reload_t -= delta
		if _reload_t <= 0.0:
			loaded_missile.visible = true
			_load_slide = 1.0
	if _load_slide > 0.0:
		_load_slide = maxf(_load_slide - delta / 0.35, 0.0)
		loaded_missile.position = Vector3(0, 0, -0.06 * _load_slide * _load_slide)


func is_loaded() -> bool:
	return loaded_missile.visible


## Points on the robot's surface (over its joints and weapons) the death
## arcs jump between: each joint pushed out from the hips-neck axis to the
## armour, so the arcs run over the body, not inside it.
func arc_points() -> Array:
	var out := []
	if _sk == null:
		return out
	var g := _sk.global_transform
	var hips := g * _sk.get_bone_global_pose(_sk.find_bone("mixamorig_Hips")).origin
	var neck := g * _sk.get_bone_global_pose(_sk.find_bone("mixamorig_Neck")).origin
	var axis := (neck - hips).normalized()
	var skin := 0.16 * model_scale
	for b in _arc_bones:
		var p := g * _sk.get_bone_global_pose(b).origin
		var on_axis := hips + axis * (p - hips).dot(axis)
		var out_dir := p - on_axis
		if out_dir.length_squared() < 0.01:
			out_dir = _visual.global_basis.z
		out.append(p + out_dir.normalized() * skin)
	out.append(chaingun_muzzle.global_position)
	out.append(silo_mouth().origin)
	return out


func _process(_delta: float) -> void:
	_update_steps(_delta)
	for i in _mg_voices.size():
		if _mg_left[i] > 0.0:
			_mg_left[i] -= _delta
			var v := _mg_voices[i]
			if _mg_left[i] <= 0.0:
				v.stop()
				v.fade = 1.0
			elif _mg_left[i] < chaingun_shot_fade:
				v.fade = _mg_left[i] / chaingun_shot_fade
	if core_fx and core:
		core_fx.core_pos = core.global_position
		core_fx.forward = _visual.global_basis.z.normalized()


## Footsteps: watches both feet (relative to the body, so slopes and steps
## don't matter) and plays a stomp the moment one lands.
func _update_steps(delta: float) -> void:
	for i in _step_voices.size():
		if _step_left[i] > 0.0:
			_step_left[i] -= delta
			var v := _step_voices[i]
			if _step_left[i] <= 0.0:
				v.stop()
				v.fade = 1.0
			elif _step_left[i] < step_sound_fade:
				v.fade = _step_left[i] / step_sound_fade
	if not alive or _sk == null or not is_instance_valid(_sk):
		return
	if _feet.is_empty():
		for b in [&"mixamorig_LeftFoot", &"mixamorig_RightFoot"]:
			var bi := _sk.find_bone(b)
			if bi >= 0:
				_feet.append([bi, INF, false])
	var up := global_basis.y.normalized()
	for k in _feet.size():
		var f: Array = _feet[k]
		var h := ((_sk.global_transform * _sk.get_bone_global_pose(f[0])).origin - global_position).dot(up)
		f[1] = minf(f[1], h)
		if h > f[1] + foot_lift_height:
			f[2] = true
		elif f[2] and h <= f[1] + foot_plant_height:
			f[2] = false
			last_step_foot = k
			_step_sound()


## One stomp from the owner's walking recording (a different one from the
## last, voices in turn; each fades and stops in _update_steps).
func _step_sound() -> void:
	if step_sound_starts.is_empty():
		return
	if _step_voices.is_empty():
		for i in 3:
			var v := Sfx.emitter(self, Sfx.MINI_BOSS_WALKING, step_sound_db, step_sound_near, step_sound_far)
			v.name = "StepSound%d" % i
			_step_voices.append(v)
			_step_left.append(0.0)
	var v := _step_voices[_step_next]
	if is_instance_valid(v) and v.is_inside_tree():
		var pick := randi() % step_sound_starts.size()
		if pick == _step_pick and step_sound_starts.size() > 1:
			pick = (pick + 1) % step_sound_starts.size()
		_step_pick = pick
		v.fade = 1.0
		v.play(step_sound_starts[pick])
		_step_left[_step_next] = step_sound_len
		step_sounds += 1
	_step_next = (_step_next + 1) % _step_voices.size()


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

## Cartoon hit stars shown (tests).
var hit_stars := 0
var _last_star_ms := -1000


func apply_damage(info: DamageInfo) -> void:
	if not alive:
		return
	var on_core := exposed and hits_core(info)
	var armour := armour_damage_scale * (stagger_armour_scale if is_staggered() else 1.0)
	var amount := info.damage_amount * (core_damage_scale if on_core else armour)
	if stagger:
		stagger.add(info)
	health -= amount
	# Cartoon "POW" star where it was hit (bigger on the core), throttled.
	var now := Time.get_ticks_msec()
	if now - _last_star_ms >= 80:
		_last_star_ms = now
		hit_stars += 1
		HitStar.spawn(get_tree(), info.impact_position, HitFeedback.COLORS.get(HitFeedback.weapon_of(info), Color.WHITE), 1.1 if on_core else 0.6)
	if on_core:
		core_hits += 1
		core_hit.emit(amount)
		_core_mat.emission_energy_multiplier = core_glow_energy * 2.5
		# Red sparks / arcs, and a jerk of the upper body: small for a
		# bullet, stronger for heavy hits.
		var strength := clampf(amount / 1.5, 0.1, 1.0)
		core_fx.core_pos = core.global_position
		core_fx.hit(strength, info.impact_direction)
		hit_react.kick(strength, info.impact_direction)
	if health <= 0.0:
		die(info)


## Would this hit reach the core? Direct hits: the shot's line passes
## within `core_hit_radius` of it, just ahead of where it struck the armour.
## Blasts: they go off close to it.
func hits_core(info: DamageInfo) -> bool:
	var c := core.global_position
	if info.is_explosive():
		return info.impact_position.distance_to(c) < core_hit_radius + 0.4 * model_scale
	var d := info.impact_direction
	var t := (c - info.impact_position).dot(d)
	if t < -0.25 * model_scale or t > 1.2 * model_scale:
		return false
	return (info.impact_position + d * t).distance_to(c) <= core_hit_radius


## Killed: the core overloads, blows, the failure spreads over the robot,
## the visor dies, then it collapses (Heavy_Death). See _update_death.
func die(_info: DamageInfo = null) -> void:
	if not alive:
		return
	alive = false
	state = State.DEAD
	exposed = false
	_chest_open_t = -1.0
	set_spin(0.0)
	gun_aim.target_weight = 0.0
	_speed = 0.0
	turn_dir = 0
	_turning = false
	_collapsed = false
	dying_t = 0.0
	if _targetable:
		_targetable.kill()
	linear_velocity = Vector3.ZERO
	anim.speed_scale = 1.0
	if _move_anim != &"Idle":
		anim.play(&"Idle", 0.3)
		_move_anim = &"Idle"
	core_fx.core_pos = core.global_position
	# The owner's machine-death sound, right as it starts to die.
	Sfx.play_at(get_parent(), Sfx.MACHINE_DEATH, core.global_position, death_sound_db, death_sound_near, death_sound_far)
	death_sounds += 1
	core_fx.failure()
	_core_glow.visible = true
	died.emit()
	if respawn_time >= 0.0:
		get_tree().create_timer(respawn_time + death_collapse_time, false).timeout.connect(_respawn)


## CORE DESTROYED -> INTERNAL FAILURE -> THE WHOLE ROBOT LOSES POWER.
func _update_death(delta: float) -> void:
	if dying_t < 0.0:
		return
	var t0 := dying_t
	dying_t += delta
	if not _collapsed:
		linear_velocity = Vector3(0, linear_velocity.y, 0)
	if dying_t < death_overload_time:
		# Violently unstable: the core flares and the body shudders.
		_core_mat.emission_energy_multiplier = core_glow_energy * randf_range(1.0, 4.0)
		Vfx.set_alpha(_core_glow, randf_range(0.4, 1.0))
		if randf() < delta * 10.0:
			hit_react.kick(0.25, -_visual.global_basis.z)
		cables.set_power(randf_range(0.0, 2.5))
	elif t0 < death_overload_time:
		# Internal explosion: the core blows, the chest is thrown back.
		MissileBlast.spawn(get_parent(), core.global_position + _visual.global_basis.z * 0.15 * model_scale, 1.2, 0.7, false)
		cables.snap()
		core_fx.blow()
		hit_react.kick(1.4, -_visual.global_basis.z)
		_core_glow.visible = false
		_core_mat.emission_energy_multiplier = 0.0
		_core_mat.albedo_color = Color(0.08, 0.05, 0.05)
	# The visor (power) flickers and dies.
	if _visor_mat:
		var vk := (dying_t - death_overload_time) / (death_collapse_time + 0.4 - death_overload_time)
		if vk < 0.0:
			_visor_mat.emission_energy_multiplier = visor_glow * randf_range(0.8, 1.6)
		elif vk < 1.0:
			_visor_mat.emission_energy_multiplier = visor_glow * (1.2 if randf() < 0.45 * (1.0 - vk) else 0.05)
		else:
			_visor_mat.emission_energy_multiplier = 0.0
			_visor_mat.albedo_color = Color(0.25, 0.05, 0.05)
	if not _collapsed and dying_t >= death_collapse_time:
		_collapse()


## Power gone: the existing death fall.
func _collapse() -> void:
	_collapsed = true
	anim.speed_scale = 1.0
	anim.play(DEATH_CLIP, 0.15)
	_move_anim = DEATH_CLIP
	linear_velocity = Vector3.ZERO
	# Lying down: the capsule lies along the fallen body.
	if _collision:
		_collision.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0).rotated(Vector3.UP, _yaw), (Vector3(0, 0.4, 0) + Vector3(sin(_yaw), 0, cos(_yaw)) * 0.6) * model_scale)
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	set_deferred("freeze", true)


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
	dying_t = -1.0
	_collapsed = false
	_missile_t = missile_first_delay
	core_fx.reset()
	cables.reset()
	turn_dir = 0
	_detour_t = 0.0
	ground_y = global_position.y
	_core_mat.emission_energy_multiplier = _core_rest.emission_energy_multiplier
	_core_mat.albedo_color = _core_rest.albedo_color
	if _visor_mat:
		_visor_mat.emission_energy_multiplier = visor_glow
		_visor_mat.albedo_color = _visor_albedo
	loaded_missile.visible = true
	_reload_t = 0.0
	exposed = false
	chest_player.play(&"Chest_Closed")
	anim.play(&"Idle")
	_move_anim = &"Idle"
	if _targetable:
		_targetable.revive()
