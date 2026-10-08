class_name RobotSkirmisher
extends RobotEnemy
## The skirmisher: a light, fast, agile robot with a plasma cannon on each
## forearm. Built on RobotEnemy (same physics body, targeting, line of
## sight, spacing, damage, death styles, break-apart, debris, corpse and
## respawn) - only its model, movement, evasion and weapons differ.
##
## Dangerous through mobility, not toughness: it keeps running between
## firing positions round the player, changes direction with sharp
## mechanical run-turns, and fires short bursts of the player's own yellow
## machine-gun plasma (weaker, slower) from the muzzles of its arm cannons
## while it moves. Incoming fire sometimes makes it sidestep, jump or dive
## away - after an imperfect reaction delay, with cooldowns, never spammed.
##
## Moving away from the target it keeps facing it and runs backwards, like
## the first robot backs off; it picks firing positions in and out at a
## slant rather than strafing sideways, and its body only ever moves along
## its legs - so the chest stays on the target with the waist barely
## twisted and the feet never slide sideways.
##
## Clips: Running / Walking are the first robot's, retargeted onto this
## body by the build tool (the model's own were captured for other
## proportions and looked broken on it); the rest are the model's own:
## Run_Turn_* and Idle_Turn_* / Walk_Turn_* (direction changes - the build tool moved their
## heading change out into RobotSkirmisherMotion so the body turns in step),
## Jump_Run (jump; the height is added here, the clip is in place),
## Jumping_Punch (the dive: a leaping lunge whose travel the body follows),
## Fall3 (killed in the air) and five ground deaths.

const SKIRMISHER_MODEL := preload("res://assets/enemies/robot_skirmisher/robot_skirmisher.glb")
const SKIRMISHER_FAR := preload("res://assets/enemies/robot_skirmisher/robot_skirmisher_far.glb")
const SKIRMISHER_SECTIONS := preload("res://resources/enemies/robot_skirmisher_sections.tres")
## Cannon muzzles (the open barrel ends of the forearm cannons), hand space.
const SKIRMISHER_MUZZLES := {"Left": Vector3(0.0554, 0.3019, 0.0656), "Right": Vector3(0.0631, 0.4998, 0.0862)}
## The player's machine-gun plasma.
const PLASMA_YELLOW := Color(1.0, 0.82, 0.06)
const PLASMA_HOT := Color(1.0, 0.97, 0.62)
const PLASMA_TRAIL := Color(1.0, 0.55, 0.05)
const FLASH_POOL := 6

enum Act { NONE, SIDESTEP, JUMP, DIVE, TURN, STAGGER }

@export_group("Mobility")
## Seconds between picking a new firing position round the target.
@export var reposition_time := Vector2(0.9, 2.0)
## Running and asked to change direction by more than this: a run-turn.
@export var run_turn_deg := 110.0
## Seconds after a run-turn before the next one.
@export var run_turn_cooldown := Vector2(1.6, 2.6)
@export var run_turn_time := 0.42
## Legs turn at this constant rate (rad/s): mechanical, not eased.
@export var leg_turn_rate := 11.0
## How fast sideways momentum dies (1/s): the feet grip the floor.
@export var grip := 14.0
## Moving more than this far from straight at the target (deg), it keeps
## facing the target and runs backwards (like the first robot backs off),
## so the upper body never twists far round from the legs.
@export var backpedal_deg := 95.0
## Top speed running backwards (m/s).
@export var backpedal_speed := 3.6
## Firing positions are reached moving at most this far off straight
## towards / away from the target (deg): an in-and-out zig-zag, never a
## long sideways strafe (that needs a 90-degree twist at the waist).
@export var approach_slant_deg := Vector2(20.0, 55.0)
@export var acceleration := 16.0
@export var sidestep_speed := 7.5
@export var sidestep_time := 0.3
@export var jump_height := 0.8
@export var jump_speed := 5.0
@export var jump_anim_speed := 1.3
## Dive: Jumping_Punch from `dive_clip_range.x` to `.y` s (leap to
## recovered), played this much faster, the body following its travel.
@export var dive_clip_range := Vector2(0.2, 2.45)
@export var dive_anim_speed := 1.45
@export var dive_travel_scale := 1.15

@export_group("Evasion")
## Chance it reacts to a shot that will pass close (else it gets hit).
@export var evade_chance := 0.55
## Reaction delay (s): not instant, so close/fast shots still land.
@export var evade_reaction := Vector2(0.12, 0.38)
@export var evade_cooldown := Vector2(1.4, 2.6)
@export var jump_cooldown := Vector2(3.0, 5.5)
@export var dive_cooldown := Vector2(7.0, 11.0)
## Chance a hit that doesn't kill it makes it evade.
@export var hit_evade_chance := 0.35
## A player's bolt arriving within this time and passing within this
## distance is a threat.
@export var threat_time := 0.7
@export var threat_radius := 1.3
## Unprompted hops / dives / sidesteps every so often while fighting.
@export var hop_time := Vector2(3.5, 7.0)

@export_group("Cannons")
## Within this angle of the target a round goes straight at it; otherwise
## it flies where the cannon points.
@export var cannon_aim_snap_deg := 7.0
@export var flash_intensity := 1.35
## Burst sound (the machine gun's): full within `fire_sound_near` m of the
## player, fading with real distance to silence at `fire_sound_far`.
@export var fire_sound_db := -5.0
@export var fire_sound_near := 3.0
@export var fire_sound_far := 48.0
## Glowing yellow cannon tips (hide the open barrel ends): radius of the
## solid hot core and size of the soft halo round it (m).
@export var barrel_glow_core := 0.075
@export var barrel_glow_halo := 0.3
## How much the halo grows with each shot / the wind-up (1 = doubles).
@export var barrel_glow_swell := 0.5
## The cannon glow swells this long before each burst (a readable tell).
@export var windup_glow_time := 0.35

@export_group("Effects")
## Beyond this camera distance: no muzzle flashes, sparks or death arcs.
@export var fx_distance := 32.0
## Beyond this camera distance it thinks half as often and skips the
## threat scan.
@export var far_logic_distance := 40.0

var action := Act.NONE
var evades := 0
var jumps := 0
var dives := 0
var turns := 0
var sidesteps := 0
## Death while airborne (jump/dive) uses the Fall3 clip.
var died_airborne := false

var _act_t := 0.0
var _act_len := 0.0
var _act_dir := Vector3.ZERO
var _act_clip := &""
var _turn_from := 0.0
var _turn_amount := 0.0
var _turn_window := Vector2.ZERO
var _prev_ct := 0.0
var _pending := -1.0
var _pending_dir := Vector3.ZERO
var _evade_cd := 0.0
var _jump_cd := 0.0
var _dive_cd := 0.0
var _turn_cd := 0.0
var _hop_t := 4.0
var _repos := Vector3.ZERO
var _repos_t := 0.0
var _steer := Vector3.ZERO
var _steer_t := 0.0
var _air_y := 0.0
var _lift := 0.0
var _land_dip := 0.0
var _lean := Vector2.ZERO  # pitch, roll (visual)
var _jolt := Vector2.ZERO  # hit jolt: pitch, yaw
var _recoil := 0.0
var _spark_t := 2.0
var _cam_d := 0.0
var _engaged := false
var _col: CollisionShape3D
var _col_y := 0.85
var _hips := -1
var _hips_rest_y := 0.79

static var _flashes: Array[MachineGunFlash] = []
static var _core_mesh: Mesh
var _glows: Array = []
var _glow_pulse: Array[float] = [0.0, 0.0]
var _glow_power := 1.0
var _fire_snd: DynamicSound
## Burst sounds started (tests).
var fire_sounds := 0
static var _flash_next := 0


func _init() -> void:
	max_health = 1.4
	section_set = SKIRMISHER_SECTIONS
	walk_speed = 1.4
	# Ground speeds (m/s) of the planted feet in the walk/run clips at 1x
	# (tools/measure_gait.gd), so the feet keep pace with the ground.
	walk_anim_speed = 0.94
	run_anim_speed = 2.12
	run_above = 1.4
	runs_backwards = true
	anim_rate_limits = Vector2(0.4, 1.75)
	combat_speed = 4.6
	detect_range = 30.0
	lose_range = 42.0
	preferred_range = Vector2(7.0, 15.0)
	max_twist_deg = 115.0
	turn_speed = 6.0
	walk_accel = 9.0
	burst_count = Vector2i(4, 6)
	burst_interval = 0.1
	burst_cooldown = Vector2(1.0, 1.9)
	reaction_time = Vector2(0.45, 0.85)
	aim_spread_deg = 2.4
	bolt_speed = 40.0
	bolt_damage = 0.4
	death_anim_electric = &"Electrocuted_Fall"
	death_anim_from_front = &"Shot_and_Fall_Backward"
	death_anims_from_behind = [&"Shot_and_Fall_Forward", &"Fall_Dead_from_Abdominal_Injury"]
	blown_back_force = 5.0
	blown_back_speed = Vector2(4.4, 3.0)
	failure_sparks = Vector2i(2, 4)


func _ready() -> void:
	super._ready()
	mass = 85.0
	_col = get_node_or_null("Collision") as CollisionShape3D
	if _col:
		_col_y = _col.position.y
	_hop_t = randf_range(hop_time.x, hop_time.y)


# --- Model ---

func _model_scene() -> PackedScene:
	return SKIRMISHER_MODEL


## Measured on the re-fitted rig (tools/measure_gait.gd).
func _gaits() -> Dictionary:
	return {
		&"Walking": {"speed": walk_anim_speed, "ankle_min": 0.29},
		&"Running": {"speed": run_anim_speed, "ankle_min": 0.327},
		&"Stand": {"stand": true, "ankle_min": 0.29},
	}


func _stand_time() -> float:
	return 0.852


## Procedural legs: the retargeted walk / run clips don't fit its legs
## (bowed, crossing, rolling feet), so the legs step on their own; the clips
## still drive the hips, torso and arms.
func _make_legs() -> SkeletonModifier3D:
	return RobotWalker.new()


func _far_scene() -> PackedScene:
	return SKIRMISHER_FAR


## The far model has its own small baked texture (its own UV layout).
func _far_own_material() -> bool:
	return true


## Its sections carry their own sealed caps (build tool).
func _mesh_caps() -> MeshCaps:
	return null


func _muzzle_offsets() -> Dictionary:
	return SKIRMISHER_MUZZLES


func _model_offset() -> Vector3:
	# Centre the hips (rest at x 0.007, z -0.303 on the re-fitted rig) over
	# the body.
	return Vector3(-0.0072, 0, 0.3031)


## The cut caps are only seen once a section is gone.
func _whole_mesh_skips(mat: Material) -> bool:
	return mat != null and mat.resource_name == "Interior"


func _build_model() -> void:
	super._build_model()
	_hips = _skeleton.find_bone(&"mixamorig_Hips")
	if _hips >= 0:
		_hips_rest_y = _skeleton.get_bone_global_rest(_hips).origin.y
	# Fewer, bigger pieces than the first robot: a normal kill mostly stays
	# whole, heavy hits take off one or two parts, explosions several.
	_breaker.light_breaks = Vector2i(0, 1)
	_breaker.medium_breaks = Vector2i(1, 2)
	_breaker.heavy_breaks = Vector2i(2, 3)
	_breaker.extreme_keep = 1
	_reset_action()
	_engaged = false
	_make_barrel_glows()
	if _fire_snd == null:
		_fire_snd = Sfx.emitter(self, Sfx.MG_FIRE, fire_sound_db, fire_sound_near, fire_sound_far)
		_fire_snd.name = "FireSound"
		_fire_snd.max_polyphony = 2
		_fire_snd.position = Vector3(0, 1.1, 0)


## Per cannon: [core (solid, unshaded), halo (additive billboard)].
func _make_barrel_glows() -> void:
	for g in _glows:
		if is_instance_valid(g[0]):
			g[0].queue_free()
	_glows.clear()
	# Built at its real size (scaled only by the small pulse, at most 1.35x),
	# so it can never be drawn big whatever happens to its transform.
	if _core_mesh == null or not is_equal_approx((_core_mesh as SphereMesh).radius, barrel_glow_core):
		var sm := SphereMesh.new()
		sm.radius = barrel_glow_core
		sm.height = barrel_glow_core * 2.0
		sm.radial_segments = 10
		sm.rings = 5
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.95, 0.78, 0.3)
		m.disable_receive_shadows = true
		sm.material = m
		_core_mesh = sm
	for i in 2:
		var core := MeshInstance3D.new()
		core.name = "BarrelGlow%d" % i
		core.mesh = _core_mesh
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		core.top_level = true
		# Hidden until first placed on its barrel.
		core.visible = false
		# Placed every frame: physics interpolation off (like every other
		# per-frame effect), or it draws them smeared from stale, full-size
		# transforms - big yellow balls far off the barrels.
		core.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(core)
		var halo := Vfx.quad("glow", Color(1.0, 0.78, 0.15, 0.35), Vector2.ONE * barrel_glow_halo, BaseMaterial3D.BILLBOARD_ENABLED, false)
		halo.top_level = true
		halo.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		core.add_child(halo)
		_glows.append([core, halo])
	_glow_pulse = [0.0, 0.0]
	# Placed the moment the arms are posed, so they sit exactly on the
	# barrel ends however the arms move.
	if _aim and not _aim.posed.is_connected(_place_barrel_glows):
		_aim.posed.connect(_place_barrel_glows)


func _process(delta: float) -> void:
	_update_barrel_glows(delta)


func _update_barrel_glows(delta: float) -> void:
	if _glows.is_empty() or _aim == null:
		return
	# Dead: the glow drains away over a second, then it's gone.
	_glow_power = move_toward(_glow_power, 1.0 if alive else 0.0, delta * (4.0 if alive else 1.0))
	var on := _glow_power > 0.01 and _visual.is_visible_in_tree()
	for i in _glows.size():
		var core: MeshInstance3D = _glows[i][0]
		if not on:
			core.visible = false
			continue
		_glow_pulse[i] = maxf(_glow_pulse[i] - delta * 6.0, 0.0)
		# Readable wind-up: the cannons swell just before a burst.
		if alive and target and _burst_left == 0 and _cool_t < windup_glow_time and _aim.weight > 0.6:
			_glow_pulse[i] = maxf(_glow_pulse[i], 0.55 * (1.0 - _cool_t / windup_glow_time))
	_place_barrel_glows()


func _place_barrel_glows() -> void:
	if _glows.is_empty() or _aim == null:
		return
	for i in _glows.size():
		var core: MeshInstance3D = _glows[i][0]
		var halo: MeshInstance3D = _glows[i][1]
		if not is_instance_valid(core) or _glow_power <= 0.01 or not _visual.is_visible_in_tree():
			continue
		var tip := _aim.muzzle_position(i)
		var axis := (tip - _aim.elbow_position(i))
		axis = axis.normalized() if axis.length_squared() > 1e-6 else Vector3.FORWARD
		var flick := 1.0 + randf_range(-0.06, 0.06)
		var k := (0.6 + 0.4 * _glow_power) * (1.0 + 0.35 * _glow_pulse[i])
		var r := barrel_glow_core * k
		core.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * k), tip - axis * r * 0.45)
		halo.global_position = tip + axis * r * 0.3
		halo.scale = Vector3.ONE * _glow_power * flick * (1.0 + barrel_glow_swell * _glow_pulse[i])
		core.visible = true  # only once it's sized and on the barrel


func _on_burst_start() -> void:
	if _fire_snd and _fire_snd.is_inside_tree():
		_fire_snd.pitch_scale = randf_range(0.95, 1.08)
		_fire_snd.play()
		fire_sounds += 1


# --- Behaviour ---

func _behave(delta: float) -> void:
	if freeze or Engine.get_physics_frames() - _pulled_frame < 6:
		if action != Act.NONE:
			_end_action()
		super._behave(delta)
		_apply_visual(delta)
		return
	_evade_cd -= delta
	_jump_cd -= delta
	_dive_cd -= delta
	_turn_cd -= delta
	if _pending >= 0.0:
		_pending -= delta
		if _pending < 0.0 and target and (action == Act.NONE or action == Act.TURN):
			if action == Act.TURN:
				_yaw = _turn_from + _turn_amount  # cut the turn short
				_end_action()
			_evade(_pending_dir)
	if action != Act.NONE:
		_think_t -= delta
		if _think_t <= 0.0:
			_think_t = 0.25 + randf() * 0.05
			_think()
		_update_action(delta)
	else:
		super._behave(delta)
	_damage_sparks(delta)
	_apply_visual(delta)


func _think() -> void:
	super._think()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	_cam_d = cam.global_position.distance_to(global_position) if cam else 0.0
	if _cam_d > far_logic_distance:
		_think_t += 0.25  # distant: decide half as often
		return
	if target and alive:
		_scan_threats()


## A player's bolt that will pass close soon -> maybe evade (after a delay).
func _scan_threats() -> void:
	if _pending >= 0.0 or (action != Act.NONE and action != Act.TURN) or _evade_cd > 0.0:
		return
	var centre := global_position + Vector3.UP * 1.0
	for b in PlasmaBolt.in_flight():
		if not is_instance_valid(b.shooter) or not (b.shooter as Node).is_in_group(&"players"):
			continue
		var v := b.velocity
		var vv := v.length_squared()
		if vv < 1.0:
			continue
		var rel := centre - b.global_position
		var tca := rel.dot(v) / vv
		if tca < 0.0 or tca > threat_time:
			continue
		if (rel - v * tca).length() < threat_radius:
			_on_threat(v)
			return


func _on_threat(from_dir: Vector3) -> void:
	if randf() > evade_chance:
		_evade_cd = 0.5  # didn't react to this one
		return
	_pending = randf_range(evade_reaction.x, evade_reaction.y)
	_pending_dir = from_dir


func _combat(delta: float) -> void:
	var to := target.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var dir_to := to / d if d > 0.01 else -_visual.global_basis.z
	var player_yaw := atan2(dir_to.x, dir_to.z)
	# Just spotted: turn on the spot to face it first.
	if not _engaged:
		_engaged = true
		var off := wrapf(player_yaw - _yaw, -PI, PI)
		if absf(off) > deg_to_rad(70.0):
			_start_turn(&"Idle_Turn_Left" if off > 0.0 else &"Idle_Turn_Right", off, 0.55)
			return
	# Unprompted hops / dives keep it hard to pin down.
	_hop_t -= delta
	if _hop_t <= 0.0:
		_hop_t = randf_range(hop_time.x, hop_time.y)
		if _cam_d < far_logic_distance and _evade_cd <= 0.0:
			_evade(Vector3.ZERO, true)
			if action != Act.NONE:
				return
	# Firing positions round the target, re-picked often.
	_repos_t -= delta
	var flat := Vector3(global_position.x, 0, global_position.z)
	if _repos_t <= 0.0 or flat.distance_to(_repos) < 1.2:
		_pick_position(dir_to, d)
	var want := _repos - flat
	want = want.normalized() if want.length_squared() > 0.01 else Vector3.UP.cross(dir_to)
	if not _los:
		want = (want + dir_to).normalized()
	want += _sep * 1.2
	want = _steered(want.normalized() if want.length_squared() > 0.001 else want, delta)
	var v := linear_velocity
	var hv := Vector3(v.x, 0, v.z)
	# Sharp change of direction running forwards: a mechanical run-turn.
	if hv.length() > 2.6 and not _backing and _turn_cd <= 0.0 and want.length_squared() > 0.01:
		var legs: Array = _legs_for(atan2(want.x, want.z), player_yaw)
		var turn := _leg_turn(legs[0], player_yaw)
		if not legs[1] and absf(turn) > deg_to_rad(run_turn_deg):
			_start_turn(&"Run_Turn_Left" if turn > 0.0 else &"Run_Turn_Right", turn, run_turn_time)
			return
	var speed := combat_speed * (0.85 if _burst_left > 0 else 1.0)
	_drive(want * speed, delta, player_yaw)
	_aim_at_target(player_yaw)
	_update_fire(delta, d)


## A firing position: in or out towards the preferred range, slanted off
## the line to the target to one side or the other (it zig-zags and keeps
## changing sides), on solid floor. Reached running forwards or backwards
## with the chest on the target, never strafing far sideways.
func _pick_position(dir_to: Vector3, d: float) -> void:
	_repos_t = randf_range(reposition_time.x, reposition_time.y)
	var flat := Vector3(global_position.x, 0, global_position.z)
	# In or out: towards the preferred band, random inside it.
	var inward := d > preferred_range.y or (d >= preferred_range.x and randf() < 0.5)
	var base := dir_to if inward else -dir_to
	for attempt in 6:
		var ang := deg_to_rad(randf_range(approach_slant_deg.x, approach_slant_deg.y))
		ang *= 1.0 if randf() < 0.5 else -1.0
		var dist := randf_range(2.5, 5.0)
		var p := flat + base.rotated(Vector3.UP, ang) * dist
		if _floor_at(p) and _clear(global_position + Vector3.UP * 0.6, Vector3(p.x, global_position.y + 0.6, p.z)):
			_repos = p
			return
		inward = not inward if attempt == 2 else inward
		base = dir_to if inward else -dir_to
	_repos = flat + Vector3.UP.cross(dir_to) * (2.5 if randf() < 0.5 else -2.5)


## Steer round obstacles and away from drops (probes every 0.1 s).
func _steered(want: Vector3, delta: float) -> Vector3:
	_steer_t -= delta
	if _steer_t > 0.0 and _steer != Vector3.ZERO:
		return _steer
	_steer_t = 0.1
	_steer = want
	if want.length_squared() < 0.01:
		return want
	var from := global_position + Vector3.UP * 0.6
	for ang in [0.0, 0.7, -0.7, 1.4, -1.4, 2.1, -2.1]:
		var dir := want.rotated(Vector3.UP, ang)
		if _clear(from, from + dir * 1.6) and _floor_at(global_position + dir * 1.4):
			_steer = dir
			return dir
	_steer = -want
	return _steer


func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit.collider == target or (hit.collider is Node and (hit.collider as Node).is_in_group(&"enemies"))


func _floor_at(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, global_position.y + 1.0, p.z), Vector3(p.x, global_position.y - 1.2, p.z))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## [legs yaw, backwards] for moving along `move_yaw`: legs along the
## motion, or - moving away from the target - facing back towards it,
## running backwards (with hysteresis, so it doesn't flip-flop).
func _legs_for(move_yaw: float, player_yaw: float) -> Array:
	var limit := deg_to_rad(backpedal_deg + (-15.0 if _backing else 15.0))
	if absf(wrapf(move_yaw - player_yaw, -PI, PI)) > limit:
		return [move_yaw + PI, true]
	return [move_yaw, false]


## Leg turn from the current heading to `legs_yaw`, taken the way round
## that keeps facing the target side (never swinging through its back,
## which would whip the upper-body twist round).
func _leg_turn(legs_yaw: float, player_yaw: float) -> float:
	var turn := wrapf(legs_yaw - _yaw, -PI, PI)
	if absf(wrapf(_yaw - player_yaw, -PI, PI) + turn) > PI:
		turn -= signf(turn) * TAU
	return turn


## Legs head for `want_v` (turning at a constant mechanical rate; it slows
## while they swing round), body velocity follows quickly. With the target
## known (`player_yaw`), moving away from it runs backwards facing it.
func _drive(want_v: Vector3, delta: float, player_yaw := NAN) -> void:
	var v := linear_velocity
	var hv := Vector3(v.x, 0, v.z)
	var backwards := false
	if want_v.length_squared() > 0.04:
		var move_yaw := atan2(want_v.x, want_v.z)
		var legs := move_yaw
		var err := wrapf(legs - _yaw, -PI, PI)
		if not is_nan(player_yaw):
			var lb: Array = _legs_for(move_yaw, player_yaw)
			legs = lb[0]
			backwards = lb[1]
			err = _leg_turn(legs, player_yaw)
			if backwards:
				want_v = want_v.limit_length(backpedal_speed)
		# Legs turn fast from a standstill, slower at speed (it curves round
		# like a runner rather than pivoting on the spot at full tilt).
		var rate := leg_turn_rate / (1.0 + 0.5 * hv.length())
		_yaw += clampf(err, -rate * delta, rate * delta)
		# The body only ever moves along the legs (forwards, or backwards
		# when backing off): while they swing round it curves with them
		# and slows, and the feet grip - sideways momentum dies at once, so
		# it never crabs sideways with the feet sliding.
		var axis := Vector3(sin(_yaw), 0, cos(_yaw)) * (-1.0 if backwards else 1.0)
		want_v = axis * maxf(want_v.dot(axis), 0.0)
		hv = hv.lerp(axis * maxf(hv.dot(axis), 0.0), clampf(grip * delta, 0.0, 1.0))
	elif not is_nan(player_yaw):
		backwards = _backing and hv.length() > 0.5
	_backing = backwards
	if (hv - want_v).length() < 9.0:
		var before := hv
		hv += (want_v - hv).limit_length(acceleration * delta)
		linear_velocity = Vector3(hv.x, v.y, hv.z)
		# Lean into hard acceleration (rigid body tilt, small).
		var acc := (hv - before) / maxf(delta, 1e-3)
		var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
		var right := Vector3(-fwd.z, 0, fwd.x)
		_lean = _lean.lerp(Vector2(clampf(acc.dot(fwd) * 0.012, -0.12, 0.12), clampf(-acc.dot(right) * 0.012, -0.14, 0.14)), clampf(10.0 * delta, 0.0, 1.0))
	# The clip runs at the speed the legs actually carry the body (along
	# them), so the feet don't slide.
	var along := absf(hv.dot(Vector3(sin(_yaw), 0, cos(_yaw))))
	_set_move_anim(along, backwards)


func _aim_at_target(player_yaw: float) -> void:
	_aim.twist = clampf(wrapf(player_yaw - _yaw, -PI, PI), -deg_to_rad(max_twist_deg), deg_to_rad(max_twist_deg))
	_aim.target_point = _aim_point()
	_aim.target_weight = 1.0


# --- Actions (sidestep / jump / dive / turn / stagger) ---

## Evade a threat (`from_dir` = the shot's travel, or ZERO) or, `unprompted`,
## just stay mobile. Picks a sidestep, jump or dive to a clear side.
func _evade(from_dir: Vector3, unprompted := false) -> void:
	if action != Act.NONE or target == null or not alive:
		return
	var to := target.global_position - global_position
	to.y = 0.0
	var dir_to := to.normalized() if to.length_squared() > 0.01 else Vector3.FORWARD
	var side := Vector3.UP.cross(dir_to)
	var s := 1.0 if randf() < 0.5 else -1.0
	if from_dir != Vector3.ZERO:
		# Away from the side the shot drifts towards; sometimes the "wrong"
		# way, so it isn't perfectly predictable.
		s = 1.0 if side.dot(from_dir) < 0.0 else -1.0
		if randf() < 0.25:
			s = -s
	var dir := side * s
	if not _side_free(dir, 2.4):
		dir = -dir
		if not _side_free(dir, 2.4):
			return
	_pending = -1.0
	var r := randf()
	if _dive_cd <= 0.0 and r < (0.2 if not unprompted else 0.3):
		# A diving lunge, slanted forward or back depending on range.
		var d := to.length()
		var slant := -0.35 if d < preferred_range.x else (0.4 if d > preferred_range.y * 0.8 else 0.0)
		var ddir := (dir + dir_to * slant).normalized()
		if _side_free(ddir, 3.4):
			_start_dive(ddir)
			return
	# Jumps and sidesteps go off at a slant (forwards or back), so the legs
	# never point far from where the chest faces: the jump clip only goes
	# forwards, a sidestep away from the target runs backwards.
	var slant := deg_to_rad(randf_range(30.0, 45.0))
	var fwd_dir := (dir * cos(slant) + dir_to * sin(slant)).normalized()
	var back_dir := (dir * cos(slant) - dir_to * sin(slant)).normalized()
	if _jump_cd <= 0.0 and r < (0.5 if not unprompted else 0.75) and _side_free(fwd_dir, 2.4):
		_start_jump(fwd_dir)
		return
	if unprompted and randf() < 0.5:
		return  # sometimes just keep running
	var d2 := to.length()
	var step := back_dir if d2 < preferred_range.x or (d2 <= preferred_range.y and randf() < 0.5) else fwd_dir
	_start_sidestep(step if _side_free(step, 2.4) else dir)


func _side_free(dir: Vector3, dist: float) -> bool:
	var from := global_position + Vector3.UP * 0.6
	return _clear(from, from + dir * dist) and _floor_at(global_position + dir * dist)


func _begin(a: Act, length: float) -> void:
	action = a
	_act_t = 0.0
	_act_len = length
	_anim.speed_scale = 1.0
	_move_anim = &""


func _start_sidestep(dir: Vector3) -> void:
	_begin(Act.SIDESTEP, sidestep_time)
	_act_dir = dir
	sidesteps += 1
	evades += 1
	_evade_cd = randf_range(evade_cooldown.x, evade_cooldown.y)
	# Robotic: legs snap to the new direction (facing back towards the
	# target if it's stepping away - it runs backwards), a burst of speed.
	var player_yaw := _yaw
	if target:
		var to := target.global_position - global_position
		player_yaw = atan2(to.x, to.z)
	var legs: Array = _legs_for(atan2(dir.x, dir.z), player_yaw)
	_yaw = _yaw + _leg_turn(legs[0], player_yaw)
	_backing = legs[1]
	_anim.play(&"Running", 0.08, -2.4 if _backing else 2.4)
	var v := linear_velocity
	linear_velocity = Vector3(dir.x * sidestep_speed, v.y, dir.z * sidestep_speed)
	_lean = Vector2(0.1, 0.0)


func _start_jump(dir: Vector3) -> void:
	_backing = false
	_begin(Act.JUMP, 0.85 / jump_anim_speed)
	_act_dir = dir
	_act_clip = &"Jump_Run"
	jumps += 1
	evades += 1
	_evade_cd = randf_range(evade_cooldown.x, evade_cooldown.y)
	_jump_cd = randf_range(jump_cooldown.x, jump_cooldown.y)
	_yaw = atan2(dir.x, dir.z)
	_anim.play(&"Jump_Run", 0.1, jump_anim_speed)
	_anim.seek(0.0, true)
	_prev_ct = 0.0


func _start_dive(dir: Vector3) -> void:
	_begin(Act.DIVE, (dive_clip_range.y - dive_clip_range.x) / dive_anim_speed)
	_act_dir = dir
	_act_clip = &"Jumping_Punch"
	dives += 1
	evades += 1
	_evade_cd = randf_range(evade_cooldown.x, evade_cooldown.y) + 0.6
	_dive_cd = randf_range(dive_cooldown.x, dive_cooldown.y)
	_jump_cd = maxf(_jump_cd, 1.5)
	_yaw = atan2(dir.x, dir.z)
	_burst_left = 0
	_aim.target_weight = 0.0
	_anim.play(&"Jumping_Punch", 0.12, dive_anim_speed)
	_anim.seek(dive_clip_range.x, true)
	_prev_ct = dive_clip_range.x


## Turn by `amount` rad with a turn clip, in `time` s: the clip's own
## heading curve (taken out of the clip) drives the body, so the feet and
## the turn stay in step.
func _start_turn(clip: StringName, amount: float, time: float) -> void:
	var curve: Array = RobotSkirmisherMotion.TURN_YAW.get(clip, [])
	if curve.is_empty() or not _anim.has_animation(clip):
		_yaw += amount
		return
	var total: float = curve[curve.size() - 1]
	var t0 := 0.0
	var t1 := (curve.size() - 1) / RobotSkirmisherMotion.RATE
	for i in curve.size():
		if absf(curve[i]) > absf(total) * 0.06:
			t0 = maxf(0.0, (i - 2) / RobotSkirmisherMotion.RATE)
			break
	for i in curve.size():
		if absf(curve[i]) > absf(total) * 0.95:
			t1 = minf(t1, (i + 1) / RobotSkirmisherMotion.RATE)
			break
	if t1 <= t0 + 0.05:
		_yaw += amount
		return
	var spd := clampf((t1 - t0) / time, 0.8, 3.0)
	_begin(Act.TURN, (t1 - t0) / spd)
	_act_clip = clip
	_turn_from = _yaw
	_turn_amount = amount
	_turn_window = Vector2(t0, t1)
	_turn_cd = randf_range(run_turn_cooldown.x, run_turn_cooldown.y)
	turns += 1
	_anim.play(clip, 0.12, spd)
	_anim.seek(t0, true)


func _start_stagger() -> void:
	_begin(Act.STAGGER, 0.28)
	_burst_left = 0


func _update_action(delta: float) -> void:
	_act_t += delta
	var v := linear_velocity
	var player_yaw := _yaw
	if target:
		var to := target.global_position - global_position
		player_yaw = atan2(to.x, to.z)
	match action:
		Act.SIDESTEP:
			# Hold the burst, then brake hard.
			var k := clampf(_act_t / _act_len, 0.0, 1.0)
			var spd := sidestep_speed * (1.0 - k * k * 0.6)
			linear_velocity = Vector3(_act_dir.x * spd, v.y, _act_dir.z * spd)
			if target:
				_aim_at_target(player_yaw)
				_update_fire(delta, (target.global_position - global_position).length())
			if _act_t >= _act_len:
				_landing_dust(_act_dir)
				_end_action()
		Act.JUMP:
			var ct := _anim.current_animation_position * (1.0 if _anim.current_animation == &"Jump_Run" else 0.0)
			# The clip jumps in place: lift between take-off and landing.
			var u := clampf((ct - 0.1) / 0.45, 0.0, 1.0)
			_air_y = jump_height * sin(PI * u)
			var spd := jump_speed * (0.6 if ct < 0.1 else 1.0)
			linear_velocity = Vector3(_act_dir.x * spd, v.y, _act_dir.z * spd)
			if target:
				_aim_at_target(player_yaw)
				_update_fire(delta, (target.global_position - global_position).length())
			if _prev_ct < 0.55 and ct >= 0.55:
				_land()
			_prev_ct = ct
			if _act_t >= _act_len:
				_air_y = 0.0
				_end_action()
		Act.DIVE:
			var ct := _anim.current_animation_position if _anim.current_animation == &"Jumping_Punch" else dive_clip_range.y
			# Follow the clip's own travel (taken out of it at build time).
			var tz: Array = RobotSkirmisherMotion.TRAVEL_Z.get(&"Jumping_Punch", [])
			var dz := RobotSkirmisherMotion.sample(tz, ct) - RobotSkirmisherMotion.sample(tz, _prev_ct)
			_prev_ct = ct
			var spd := clampf(dz / maxf(delta, 1e-3) * dive_travel_scale, 0.0, 9.0)
			if not _side_free(_act_dir, 0.9):
				spd = 0.0  # don't plough into a wall / off a ledge
			linear_velocity = Vector3(_act_dir.x * spd, v.y, _act_dir.z * spd)
			_aim.target_weight = 0.0
			if _act_t >= _act_len or ct >= dive_clip_range.y:
				_land()
				_end_action()
		Act.TURN:
			var curve: Array = RobotSkirmisherMotion.TURN_YAW.get(_act_clip, [])
			var ct := _anim.current_animation_position if _anim.current_animation == _act_clip else _turn_window.y
			var c0 := RobotSkirmisherMotion.sample(curve, _turn_window.x)
			var c1 := RobotSkirmisherMotion.sample(curve, _turn_window.y)
			var f := clampf((RobotSkirmisherMotion.sample(curve, ct) - c0) / (c1 - c0), 0.0, 1.0) if absf(c1 - c0) > 1e-3 else 1.0
			_yaw = _turn_from + _turn_amount * f
			# Momentum swings round with the body, slowed by the plant.
			var hv := Vector3(v.x, 0, v.z)
			var head := Vector3(sin(_yaw), 0, cos(_yaw)) * hv.length() * (1.0 - 1.8 * delta)
			linear_velocity = Vector3(head.x, v.y, head.z)
			if target:
				_aim_at_target(player_yaw)
				_update_fire(delta, (target.global_position - global_position).length())
			if _act_t >= _act_len or ct >= _turn_window.y:
				_yaw = _turn_from + _turn_amount
				_end_action()
		Act.STAGGER:
			var hv := Vector3(v.x, 0, v.z) * maxf(0.0, 1.0 - 8.0 * delta)
			linear_velocity = Vector3(hv.x, v.y, hv.z)
			if _act_t >= _act_len:
				_end_action()
	# The hitbox follows the body up (jump lift, the dive's leap).
	var hips_lift := 0.0
	if _hips >= 0 and action == Act.DIVE:
		hips_lift = maxf(0.0, _skeleton.get_bone_global_pose(_hips).origin.y - _hips_rest_y)
	_lift = _air_y + hips_lift
	if _col:
		_col.position.y = _col_y + _lift


func _land() -> void:
	_land_dip = 0.09
	_landing_dust(linear_velocity)


func _landing_dust(dir: Vector3) -> void:
	if _cam_d < fx_distance and is_inside_tree():
		DodgeDust.spawn(get_tree().current_scene if get_tree().current_scene else get_tree().root, global_position, dir)


func _end_action() -> void:
	action = Act.NONE
	_act_t = 0.0
	_air_y = 0.0
	_lift = 0.0
	if _col:
		_col.position.y = _col_y
	_anim.speed_scale = 1.0
	_move_anim = &""  # the move clip blends back in
	_steer_t = 0.0


func _reset_action() -> void:
	action = Act.NONE
	_pending = -1.0
	_air_y = 0.0
	_lift = 0.0
	_land_dip = 0.0
	_lean = Vector2.ZERO
	_jolt = Vector2.ZERO
	_recoil = 0.0
	if _col:
		_col.position.y = _col_y


## Rigid visual offsets on top of the body: jump height, landing dip,
## acceleration lean, hit jolt and firing recoil.
func _apply_visual(delta: float) -> void:
	if not alive or _visual == null:
		return
	_land_dip = maxf(_land_dip - delta * 0.6, 0.0)
	_jolt = _jolt.move_toward(Vector2.ZERO, delta * 1.6)
	_recoil = maxf(_recoil - delta * 9.0, 0.0)
	if action == Act.NONE:
		_lean = _lean.move_toward(Vector2.ZERO, delta * 0.5)
	var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
	_visual.position = Vector3(0, _air_y - _land_dip, 0) - fwd * _recoil * 0.035
	_visual.rotation = Vector3(_lean.x - _jolt.x - _recoil * 0.03, _yaw + _jolt.y, _lean.y)


# --- Cannons ---

func _update_fire(delta: float, dist: float) -> void:
	if action == Act.DIVE or action == Act.STAGGER:
		return
	super._update_fire(delta, dist)


## One yellow plasma round from the next cannon's muzzle, along the line
## the cannon points (straight at the target when it's nearly on it).
func _fire_one() -> void:
	var i := _next_cannon
	_next_cannon = 1 - _next_cannon
	var muzzle := _aim.muzzle_position(i)
	var axis := (muzzle - _aim.elbow_position(i))
	axis = axis.normalized() if axis.length_squared() > 1e-4 else -_visual.global_basis.z
	var aim := _aim_point()
	if target is CharacterBody3D:
		var tv := (target as CharacterBody3D).velocity
		aim += Vector3(tv.x, 0, tv.z) * (muzzle.distance_to(aim) / bolt_speed) * 0.4
	var to := (aim - muzzle).normalized()
	var dir := to if axis.angle_to(to) <= deg_to_rad(cannon_aim_snap_deg) else axis
	var spread := deg_to_rad(aim_spread_deg * aim_spread_scale())
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
	dir = dir.rotated(side.rotated(dir, randf() * TAU), spread * sqrt(randf()))
	var b := PlasmaBolt.fire(get_tree(), muzzle, dir, self, bolt_speed, bolt_damage, PLASMA_YELLOW, PLASMA_HOT)
	if b:
		b.mark_life = 0.35
		b.crackle = true
		b.size = 0.45
		b.flicker = 0.35
		b.impact_light = shots_fired % 3 == 0
		b.impact_scale = 0.5
		b.set_trail_color(PLASMA_TRAIL)
	shots_fired += 1
	# Mechanical recoil: that arm jerks, the body rocks back a touch.
	_aim.kick[i] = 1.0
	_recoil = 1.0
	if i < _glow_pulse.size():
		_glow_pulse[i] = 1.0
	if _cam_d < fx_distance:
		_flash(muzzle, dir)


## Shared pool of machine-gun muzzle flashes (the player's yellow flash).
func _flash(at: Vector3, dir: Vector3) -> void:
	_flashes = _flashes.filter(func(f: MachineGunFlash) -> bool: return is_instance_valid(f) and f.is_inside_tree())
	var f: MachineGunFlash
	if _flashes.size() < FLASH_POOL:
		f = MachineGunFlash.new()
		f.top_level = true
		f.length = 0.42
		f.size = 1.3
		f.flash_life = 0.05
		f.light_energy = 2.8
		f.light_range = 3.4
		var host: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
		host.add_child(f)
		_flashes.append(f)
	else:
		_flash_next = (_flash_next + 1) % _flashes.size()
		f = _flashes[_flash_next]
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var z := dir.cross(up).normalized()
	f.global_transform = Transform3D(Basis(dir, z.cross(dir), z), at)
	f.fire(0.3, flash_intensity)


# --- Damage ---

## Heavy hit (HitFeedback): a short stagger, if it isn't mid-move.
func _hit_stagger() -> void:
	if alive and action == Act.NONE:
		_start_stagger()


func apply_damage(info: DamageInfo) -> void:
	var was_alive := alive
	super.apply_damage(info)
	if not was_alive or not alive:
		return
	# Hit reaction: a rigid jolt away from the hit, a check in its stride.
	var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
	var push := Vector3(info.impact_direction.x, 0, info.impact_direction.z)
	push = push.normalized() if push.length_squared() > 1e-4 else -fwd
	var right := Vector3(-fwd.z, 0, fwd.x)
	var k := clampf(0.5 + info.total_force() * 0.05, 0.5, 1.2)
	# Light hits (machine-gun rounds) barely check its stride, so it keeps
	# running under automatic fire; heavier hits knock it about more.
	var sev := clampf(hit_fx.severity(info, max_health) / hit_fx.heavy_at, 0.15, 1.0) if hit_fx else 1.0
	_jolt = _jolt.lerp(Vector2(push.dot(fwd) * 0.14, -push.dot(right) * 0.12) * k, sev)
	var v := linear_velocity
	var keep := lerpf(1.0, 0.55, sev)
	linear_velocity = Vector3(v.x * keep, v.y, v.z * keep) + push * 0.8 * k * sev
	if action == Act.NONE and info.total_force() > 9.0:
		_start_stagger()
	elif action == Act.NONE and _evade_cd <= 0.0 and randf() < hit_evade_chance:
		_pending = randf_range(evade_reaction.x, evade_reaction.y) + 0.1
		_pending_dir = info.impact_direction


## Damaged (under half health): intermittent crackles from its joints.
func _damage_sparks(delta: float) -> void:
	if health > max_health * 0.5 or _cam_d > fx_distance:
		return
	_spark_t -= delta
	if _spark_t <= 0.0:
		_spark_t = randf_range(1.0, 2.6)
		var bones := [&"mixamorig_Neck", &"mixamorig_LeftArm", &"mixamorig_RightArm", &"mixamorig_Spine2", &"mixamorig_LeftForeArm", &"mixamorig_RightForeArm"]
		JointSparks.play_on_bone(_skeleton, _skeleton.find_bone(bones[randi() % bones.size()]), 0.3)


func die(info: DamageInfo) -> void:
	if not alive:
		return
	died_airborne = (action == Act.JUMP and _air_y > 0.2) or (action == Act.DIVE and _lift > 0.2)
	var air := _lift
	_reset_action()
	if _visual:
		_visual.position = Vector3.ZERO
		_visual.rotation = Vector3(0, _yaw, 0)
	super.die(info)
	if died_airborne and _visual:
		# Falls the rest of the way from where it was hit.
		_visual.position.y = maxf(air - 0.6, 0.0)
		create_tween().tween_property(_visual, "position:y", 0.0, 0.25).set_ease(Tween.EASE_IN)
	# Electrical failure, kill burst and scrap: RobotEnemy.die() -> HitFeedback.


func _death_options(info: DamageInfo) -> Array:
	if died_airborne and _anim.has_animation(&"Fall3"):
		return [["air", "clip", &"Fall3", 1.0]]
	var opts := super._death_options(info)
	# Its own extra fall: crumples sideways/back.
	if info.damage_type != DamageInfo.Type.SUPERNOVA and _anim.has_animation(&"falling_down") and _prev_death != "falling_down":
		opts.append(["falling_down", "clip", &"falling_down", 1.0])
	return opts
