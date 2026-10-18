class_name RobotSentinel
extends RobotEnemy
## The Neon Sentinel (owner's model, owner asked): a flying robot. It hovers
## and swoops round the players like a Halo sentinel - circling its target
## at range and changing height and side - and often dodges their fire
## (shots coming its way, hits, and unprompted jukes) with quick banking
## side-dashes. Two of the grunts' cannons are mounted on its arms (the
## grunt's own forearm cannon meshes, firing the grunt's green bolts with
## the owner's grunt cannon sound), fired less often than a grunt's.
##
## Moves: its own flight clips (Hover, Fly_Forward, Steer_Left / Right,
## Brake) blended by how it's moving (AnimationTree), springy wings and
## antennae on top (SentinelFlex), banking into its turns. The first time it
## sees a player it's startled - Startled_See_Player: wings, arms and
## antennae flare out - before it attacks. Plasma trail from its booster
## (PlasmaTrail). Its arms aren't left straight out: SentinelArms bends
## them at the shoulders and elbows to aim its cannons, with sway, lag and
## recoil.
##
## Dies: the eye smashes and bursts (Death_Eye_Burst + SentinelEyeBurst: the
## glass flies out, a flash, a puff of smoke, electric discharge crackling
## out of the socket), the wings break apart into their pieces and the
## antennae snap off (BreakApart), and the wreck drops out of the air,
## tumbling, trailing smoke. Its death sound: one of three made from the
## owner's explosion and electric sounds (Sfx.SENTINEL_DEATH_*), a mini
## blast as the eye bursts then electric crackle dying away with the
## discharge, following the wreck down.
##
## Expressions (owner asked): its red wing covers flick right up or down
## every few seconds, uncovering the yellow back plates, and tie into what
## it's doing - tipping with its flight, flaring when startled, bristling
## up before a volley, splitting up / down as it dodges, slamming about
## when hit - and its eye (a plasma ball in the middle of the eye, swirling
## yellow gas round it) burns brighter as it gets worked up (`_express`).

const SENTINEL_MODEL := preload("res://assets/enemies/sentinel/sentinel.glb")
const GAS_SHADER := preload("res://scripts/vfx/sentinel_plasma_gas.gdshader")
const CORE_SHADER := preload("res://scripts/vfx/sentinel_plasma_core.gdshader")
const GLOW_SHADER := preload("res://scripts/vfx/sentinel_eye_glow.gdshader")
## The energy ball's centre in the model (tools/build_sentinel.py puts it
## in the middle of the eye, behind the pupil).
const EYE_CORE := Vector3(0.0, -0.035, 0.33)
## The grunt's cannon muzzle in each hand bone's space.
const GRUNT_MUZZLES := RobotEnemy.MUZZLES

@export_group("Size")
@export var model_scale := 1.3
## The grunt cannons' size on its arms, and how far back over the arm's
## end they sit (m, model scale).
@export var cannon_scale := 0.8
@export var cannon_inset := 0.12

@export_group("Flight")
## Height above the floor below it it keeps to (m), and how high over its
## target it likes to fly.
@export var hover_height := Vector2(2.6, 5.0)
@export var height_over_target := Vector2(1.6, 3.8)
@export var cruise_speed := 5.5
@export var acceleration := 9.0
## Distance it circles its target at (m), and how far round ahead it aims.
@export var orbit_range := Vector2(7.0, 13.0)
@export var orbit_lead := 0.7
## How often it picks a new distance / height / side (s).
@export var reposition_time := Vector2(2.2, 4.5)
## Patrolling (no target): drifts in a loop this wide round its home.
@export var patrol_radius := 3.0
@export var turn_rate := 6.0
@export var max_bank_deg := 32.0
@export var max_pitch_deg := 35.0

@export_group("Evasion")
## Chance it dodges a player's shot coming its way; after a hit; and how
## often it jukes on its own while fighting (s).
@export var evade_chance := 0.75
@export var hit_evade_chance := 0.55
@export var juke_time := Vector2(1.4, 3.2)
@export var evade_speed := 12.0
@export var evade_time := 0.3
@export var evade_cooldown := Vector2(0.6, 1.3)
@export var threat_time := 0.8
@export var threat_radius := 1.8

@export_group("Startled")
## Plays the startled clip this much faster than authored (s of 4.2).
@export var startle_speed := 1.6

@export_group("Cannons")
## Both cannons fire one bolt each per volley (a grunt fires 3-4 every
## 1.3-2.3 s).
@export var volley_cooldown := Vector2(3.2, 4.8)
@export_group("Expressions")
## How often the red covers flick up / down: on patrol, in a fight.
@export var flutter_time := Vector2(2.2, 4.2)
@export var fight_flutter_time := Vector2(1.1, 2.4)
## How long before a volley it bristles (covers up, eye brightening).
@export var windup_time := 0.8
@export_group("")

## Seconds left of the startled reaction (tests); engaged = it has seen a
## player and finished being startled.
var startle_left := 0.0
var engaged := false
var startles := 0
var dashes := 0
var trail: PlasmaTrail
var flex: SentinelFlex
var arms: SentinelArms
var tree: AnimationTree
var cannons: Array[Node3D] = []
## What its face is doing now (tests): calm, flick, startled, windup,
## firing, dodge, flinch.
var expression := &"calm"
var flicks := 0
## How bright its eye plasma burns (1 = calm in a fight).
var eye_energy := 1.0
var eye_glow: MeshInstance3D

var _blend := Vector2.ZERO
var _prev_v := Vector3.ZERO
var _acc := Vector3.ZERO
var _pitch := 0.0
var _roll := 0.0
var _roll_kick := 0.0
var _home := Vector3.ZERO
var _floor_y := -INF
var _ceil_y := INF
var _radius := 10.0
var _alt := 2.5
var _orbit_dir := 1.0
var _repos_t := 0.0
var _juke_t := 2.0
var _evade_cd := 0.0
var _dash_t := 0.0
var _dash_v := Vector3.ZERO
var _patrol_t := 0.0
var _muzzles: Array[Transform3D] = []
var _tips: Array[Node3D] = []
var _eye_bone := -1
var _eye_mats: Array[ShaderMaterial] = []
var _flick := Vector2.ZERO
var _flick_t := 0.0
var _flutter_t := 1.5
var _flick_up := false
var _flinch_t := 0.0
var _dodge_side := 0.0
var _dodge_t := 0.0
var _eye_flash := 0.0

static var _section_res: BreakSectionSet
static var _merged := {}
static var _grunt_cannon := {}
## The death sound picked last by any sentinel (the next one differs).
static var _last_sentinel_pick := -1


func _init() -> void:
	section_set = _section_set()
	weapon_death_sound = false
	far_distance = 1000.0
	walk_speed = 0.0
	patrol_distance = 0.0
	ledge_drop = 0.0
	max_health = 2.0
	shot_sound_db = -6.0


func _ready() -> void:
	super._ready()
	gravity_scale = 0.0
	set_meta("gravity_center_y", 0.0)
	_home = global_position
	_radius = randf_range(orbit_range.x, orbit_range.y)
	_alt = randf_range(height_over_target.x, height_over_target.y)
	_orbit_dir = 1.0 if randf() < 0.5 else -1.0
	_juke_t = randf_range(juke_time.x, juke_time.y)
	_patrol_t = randf() * 10.0


# --- Model ---

## Its break-apart sections: the body, each wing in three pieces (the
## steering wing, the moving plate, its symbol cover), the antennae, the
## arms. Every mesh moves with exactly one bone.
static func _section_set() -> BreakSectionSet:
	if _section_res:
		return _section_res
	var s := BreakSectionSet.new()
	var add := func(n: StringName, meshes: Array, bone: StringName, parent: StringName, tier: int) -> void:
		var b := BreakSection.new()
		b.section_name = n
		b.mesh_names = PackedStringArray(meshes)
		b.bone = bone
		b.joint_bone = bone
		b.parent = parent
		b.tier = tier
		s.sections.append(b)
	add.call(&"Body", ["Original_Body", "Rebuilt_Metallic_Eye_Socket", "Optic_Retainer_00", "Optic_Retainer_01", "Optic_Retainer_02", "Optic_Retainer_03", "Optic_Retainer_04", "Optic_Retainer_05", "Optic_Retainer_06", "Optic_Retainer_07", "Wing_Fixed_Socket_L", "Wing_Fixed_Socket_R", "Antenna_Fixed_Socket_L", "Antenna_Fixed_Socket_R"], &"Body", &"", 2)
	for side in ["L", "R"]:
		var n := "2" if side == "L" else "3"
		add.call(StringName("Wing_" + side), ["Steering_Wing_" + side, "Wing_Ball_And_Coupling_" + side], StringName("Wing_" + side), &"Body", 1)
		add.call(StringName("Wing_Plate_" + side), ["Moving_Wing_Backing_" + n, "Wing_Recess_Frame_" + n, "Wing_Internal_" + n + "_1", "Wing_Internal_" + n + "_3"], StringName("Wing_Plate_" + side), StringName("Wing_" + side), 1)
		add.call(StringName("Wing_Cover_" + side), ["Opening_Symbol_Plate_" + side], StringName("Wing_Red_Cover_" + side), StringName("Wing_Plate_" + side), 0)
		add.call(StringName("Antenna_" + side), ["Head_Antenna_" + side, "Antenna_Moving_Joint_" + side], StringName("Antenna_" + side), &"Body", 0)
		add.call(StringName("Arm_" + side), ["Upper_Arm_" + side], StringName("Cannon_" + side), &"Body", 1)
		add.call(StringName("Forearm_" + side), ["Forearm_" + side], StringName("Elbow_" + side), StringName("Arm_" + side), 0)
	_section_res = s
	return s


## The pieces that fly off when it dies: both wings in all their pieces and
## both antennae (owner asked).
const DEATH_BREAKS := [&"Wing_Cover_L", &"Wing_Cover_R", &"Wing_Plate_L", &"Wing_Plate_R", &"Wing_L", &"Wing_R", &"Antenna_L", &"Antenna_R"]


func _model_scene() -> PackedScene:
	return SENTINEL_MODEL


func _mesh_caps() -> MeshCaps:
	return null


func _size_factor() -> float:
	return 1.4 * model_scale


func _build_model() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_model = SENTINEL_MODEL.instantiate()
	_model.name = "Model"
	_model.scale = Vector3.ONE * model_scale
	_visual.add_child(_model)
	_skeleton = _model.find_child("Skeleton3D", true, false) as Skeleton3D
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_eye_bone = _skeleton.find_bone(&"Eye_Plasma")
	for a in [&"Hover", &"Fly_Forward", &"Steer_Left", &"Steer_Right", &"Brake"]:
		_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_merge_body()
	TwoSided.apply(_model)
	_make_eye()
	_make_tree()
	flex = SentinelFlex.new()
	flex.name = "Flex"
	_skeleton.add_child(flex)
	flex.setup(_skeleton)
	arms = SentinelArms.new()
	arms.name = "Arms"
	_skeleton.add_child(arms)
	arms.setup(_skeleton)
	arms.flex = flex
	_mount_cannons()
	if hit_fx:
		hit_fx.queue_free()
	hit_fx = HitFeedback.new()
	hit_fx.name = "HitFeedback"
	add_child(hit_fx)
	var bodies: Array[GeometryInstance3D] = [_whole]
	hit_fx.setup(self, _skeleton, bodies)
	hit_fx.react.bone_name = &"Body"
	hit_fx.react.squash_bone = &"Body"
	hit_fx.react.setup(_skeleton)
	if _breaker:
		_breaker.queue_free()
	_breaker = BreakApart.new()
	_breaker.name = "BreakApart"
	_breaker.section_set = section_set
	_breaker.skeleton = _skeleton
	add_child(_breaker)
	if trail and is_instance_valid(trail):
		trail.queue_free()
	trail = PlasmaTrail.new()
	trail.name = "PlasmaTrail"
	trail.follow = _model.find_child("Booster_Exhaust", true, false) as Node3D
	trail.head_width *= model_scale
	trail.max_width *= model_scale
	trail.flare_size *= model_scale
	_visual.add_child(trail)
	_visual.rotation.y = _yaw


## One merged mesh while alive (all its parts share the skeleton; per
## material), like the other robots: ~20 draws instead of ~120. Shared by
## every sentinel. The parts get their meshes back when it dies.
func _merge_body() -> void:
	_sections.clear()
	for c in _skeleton.get_children():
		if c is MeshInstance3D:
			_sections.append(c)
	if not _merged.has(0):
		_merged[0] = _merge_parts(_skeleton)
	_whole_mesh = _merged[0][0]
	_whole_skin = _merged[0][1]
	_whole = MeshInstance3D.new()
	_whole.name = "WholeBody"
	_whole.mesh = _whole_mesh
	_whole.skin = _whole_skin
	_skeleton.add_child(_whole)
	_whole.skeleton = NodePath("..")
	_whole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for s in _sections:
		s.visible = false
		if s.mesh:
			_section_meshes[s] = s.mesh
			s.mesh = null


## The eye (owner asked to make the plasma ball better, more yellow plasma
## gas): the merged body's ball and gas surfaces get the plasma shaders
## (this sentinel's own copies: their brightness follows its mood), and a
## glow round the ball, inside the glass, on the eye's plasma bone.
func _make_eye() -> void:
	_eye_mats.clear()
	for k in _whole_mesh.get_surface_count():
		var m := _whole_mesh.surface_get_material(k)
		var shader: Shader = null
		if m and m.resource_name == "Yellow_Plasma_Gas":
			shader = GAS_SHADER
		elif m and m.resource_name == "Tiny_Yellow_Energy_Core":
			shader = CORE_SHADER
		if shader:
			var sm := ShaderMaterial.new()
			sm.shader = shader
			sm.render_priority = -1  # inside the glass: drawn before it
			_whole.set_surface_override_material(k, sm)
			_eye_mats.append(sm)
	var bone := _skeleton.find_bone(&"Eye_Plasma")
	if bone < 0:
		return
	var at := BoneAttachment3D.new()
	at.name = "EyeCore"
	_skeleton.add_child(at)
	at.bone_idx = bone
	eye_glow = MeshInstance3D.new()
	eye_glow.name = "EyeGlow"
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	eye_glow.mesh = q
	var gm := ShaderMaterial.new()
	gm.shader = GLOW_SHADER
	gm.set_shader_parameter("size", 0.42 * model_scale)
	eye_glow.material_override = gm
	eye_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	eye_glow.custom_aabb = AABB(Vector3.ONE * -0.4, Vector3.ONE * 0.8)
	at.add_child(eye_glow)
	eye_glow.position = _skeleton.get_bone_global_rest(bone).affine_inverse() * EYE_CORE
	_eye_mats.append(gm)
	eye_energy = 1.0


## Every part mesh under `skel` merged per material and vertex layout
## (surfaces of one material don't all carry the same arrays here: some have
## UVs / tangents, some don't). [ArrayMesh, Skin].
static func _merge_parts(skel: Skeleton3D) -> Array:
	var skin: Skin
	var groups := {}  # [material, layout] -> [arrays...]
	var order: Array = []
	for mi in skel.get_children():
		if not (mi is MeshInstance3D) or (mi as MeshInstance3D).mesh == null:
			continue
		var m: Mesh = (mi as MeshInstance3D).mesh
		skin = (mi as MeshInstance3D).skin
		for k in m.get_surface_count():
			var arr := m.surface_get_arrays(k)
			var layout := 0
			for t in Mesh.ARRAY_MAX:
				if arr[t] != null:
					layout |= 1 << t
			var key := [m.surface_get_material(k), layout]
			if not groups.has(key):
				groups[key] = []
				order.append(key)
			groups[key].append(arr)
	var out := ArrayMesh.new()
	for key in order:
		var merged := []
		merged.resize(Mesh.ARRAY_MAX)
		var base := 0
		for arr: Array in groups[key]:
			var n: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			for t in Mesh.ARRAY_MAX:
				if arr[t] == null:
					continue
				if t == Mesh.ARRAY_INDEX:
					var idx: PackedInt32Array = arr[t]
					var shifted := PackedInt32Array()
					shifted.resize(idx.size())
					for i in idx.size():
						shifted[i] = idx[i] + base
					merged[t] = shifted if merged[t] == null else merged[t] + shifted
				else:
					merged[t] = arr[t].duplicate() if merged[t] == null else merged[t] + arr[t]
			base += n
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged)
		out.surface_set_material(out.get_surface_count() - 1, key[0])
	return [out, skin]


## Flight clips blended by its movement (x: sideways, y: forward / back),
## with the startled reaction as a one-shot over them.
func _make_tree() -> void:
	tree = AnimationTree.new()
	tree.name = "FlightTree"
	var bs := AnimationNodeBlendSpace2D.new()
	bs.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	for p in [[&"Hover", Vector2.ZERO], [&"Fly_Forward", Vector2(0, 1)], [&"Brake", Vector2(0, -1)], [&"Steer_Left", Vector2(-1, 0)], [&"Steer_Right", Vector2(1, 0)]]:
		var n := AnimationNodeAnimation.new()
		n.animation = p[0]
		bs.add_blend_point(n, p[1], -1, p[0])
	var startle := AnimationNodeAnimation.new()
	startle.animation = &"Startled_See_Player"
	var speed := AnimationNodeTimeScale.new()
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.12
	shot.fadeout_time = 0.45
	var bt := AnimationNodeBlendTree.new()
	bt.add_node(&"fly", bs, Vector2(0, 0))
	bt.add_node(&"startle", startle, Vector2(0, 200))
	bt.add_node(&"startle_speed", speed, Vector2(200, 200))
	bt.add_node(&"shot", shot, Vector2(400, 0))
	bt.connect_node(&"startle_speed", 0, &"startle")
	bt.connect_node(&"shot", 0, &"fly")
	bt.connect_node(&"shot", 1, &"startle_speed")
	bt.connect_node(&"output", 0, &"shot")
	tree.tree_root = bt
	_model.add_child(tree)
	tree.anim_player = tree.get_path_to(_anim)
	tree.set(&"parameters/startle_speed/scale", startle_speed)
	tree.active = true


## The grunt's two forearm cannons (its own meshes), mounted on the arm
## tips pointing forward. Their muzzles are the grunt's.
func _mount_cannons() -> void:
	cannons.clear()
	_tips.clear()
	_muzzles.clear()
	var g := _grunt_cannons()
	for side in ["L", "R"]:
		var tip := _model.find_child("ArmTip_" + side, true, false) as Node3D
		_tips.append(tip)
		var key := "Left" if side == "L" else "Right"
		var mount := Node3D.new()
		mount.name = "GruntCannon_" + side
		# Plugged into the end of the arm like the players' arm weapons: the
		# grunt's forearm cannon (along its bone's +Y) carries straight on
		# along the forearm (-X left, +X right), set back a little so it
		# sits over the arm's end.
		var s := 1.0 if side == "L" else -1.0
		mount.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5 * s).scaled(Vector3.ONE * cannon_scale), Vector3(cannon_inset * s, 0.0, 0.0))
		tip.add_child(mount)
		for m in g[key]["meshes"]:
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.transform = g[key]["bind"]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mount.add_child(mi)
		cannons.append(mount)
		_muzzles.append(Transform3D(Basis.IDENTITY, mount.transform * (g[key]["muzzle"] as Vector3)))


## The grunt model's forearm cannons (meshes in its forearm bones' space)
## and muzzles, taken once from its model.
static func _grunt_cannons() -> Dictionary:
	if not _grunt_cannon.is_empty():
		return _grunt_cannon
	var g: Node3D = RobotEnemy.MODEL.instantiate()
	var sk := g.find_child("Skeleton3D", true, false) as Skeleton3D
	for key in ["Left", "Right"]:
		var meshes: Array[Mesh] = []
		var bind := Transform3D.IDENTITY
		var bone := "mixamorig_%sForeArm" % key
		for n in ["%s_Forearm_Weapon" % key]:
			var mi := sk.get_node_or_null(n) as MeshInstance3D
			if mi == null:
				continue
			meshes.append(mi.mesh)
			if mi.skin:
				for i in mi.skin.get_bind_count():
					if mi.skin.get_bind_name(i) == StringName(bone):
						bind = mi.skin.get_bind_pose(i)
		var hand := sk.find_bone("mixamorig_%sHand" % key)
		var muzzle: Vector3 = sk.get_bone_rest(hand) * (GRUNT_MUZZLES[key] as Vector3)
		_grunt_cannon[key] = {"meshes": meshes, "bind": bind, "muzzle": muzzle}
	g.free()
	return _grunt_cannon


## Where cannon `i` fires from (world).
func muzzle_position(i: int) -> Vector3:
	return _tips[i].global_transform * _muzzles[i].origin


# --- Flying in (WaveDirector: through a window) ---

## Flies in from outside: straight for `to` at `entry_speed`, through the
## body in the way (`through`: the window's barrier, which keeps players in
## - not it), then its own AI (startled at the first player it sees).
@export var entry_speed := 9.0
## Hunting a player out of sight (WaveDirector's hunters): flies its way
## to them through the level's open air (FlightNav, where the level has
## one) at this speed.
@export var hunt_speed := 8.0
var _route := PackedVector3Array()
var _route_i := 0
var _route_t := 0.0
var _route_best := INF
var _route_stuck := 0.0
var entering := false
var _entry_to := Vector3.ZERO
var _entry_through: PhysicsBody3D
var _entry_left := 0.0


func fly_in(to: Vector3, through: PhysicsBody3D = null) -> void:
	entering = true
	_entry_to = to
	_entry_left = global_position.distance_to(to) / entry_speed + 3.0
	_entry_through = through
	if through:
		add_collision_exception_with(through)
	linear_velocity = (to - global_position).normalized() * entry_speed


func _fly_in_step(delta: float) -> void:
	_entry_left -= delta
	var off := _entry_to - global_position
	if off.length() < 1.5 or _entry_left <= 0.0:
		entering = false
		if is_instance_valid(_entry_through):
			remove_collision_exception_with(_entry_through)
		_entry_through = null
		if target and not engaged and startle_left <= 0.0:
			_startle()
		return
	# Eases off as it arrives.
	var want := off.normalized() * minf(entry_speed, maxf(off.length() * 1.6, 2.0))
	linear_velocity = linear_velocity.move_toward(want, acceleration * 1.5 * delta)


# --- Behaviour ---

func _behave(delta: float) -> void:
	if freeze or Engine.get_physics_frames() - _pulled_frame < 6:
		_feed_motion(delta)
		return  # held / dragged by a black hole: helpless
	if entering:
		_think_t -= delta
		if _think_t <= 0.0:
			_think_t = 0.25
			_think()
		_fly_in_step(delta)
		_face(delta)
		_feed_motion(delta)
		_express(delta)
		return
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = 0.25 + randf() * 0.05
		_think()
	_evade_cd -= delta
	var want := Vector3.ZERO
	if startle_left > 0.0:
		# Startled: brakes to a stop, staring at the player.
		startle_left -= delta
		if startle_left <= 0.0:
			_finish_startle()
	elif target:
		want = _combat_velocity(delta)
	else:
		want = _patrol_velocity(delta)
	if _dash_t > 0.0:
		_dash_t -= delta
		linear_velocity = _dash_v * (0.4 + 0.6 * clampf(_dash_t / evade_time, 0.0, 1.0))
	else:
		linear_velocity = linear_velocity.move_toward(want, acceleration * delta)
	_face(delta)
	_feed_motion(delta)
	if target and engaged:
		_update_fire(delta, global_position.distance_to(target.global_position))
	_express(delta)


## Periodic decisions: its target, line of sight, spacing, floor / ceiling,
## and threats (player shots) to dodge.
func _think() -> void:
	var prev := target
	var best: Node3D = null
	if net_puppet:
		best = _net_target if is_instance_valid(_net_target) and _net_target.is_inside_tree() else null
	elif ai_enabled and combat_enabled:
		var best_d := INF
		for p in get_tree().get_nodes_in_group(&"players"):
			var n := p as Node3D
			if n == null or not n.is_inside_tree():
				continue
			var d := n.global_position.distance_to(global_position)
			var limit := lose_range if n == target else detect_range
			if d < limit and d < best_d:
				best_d = d
				best = n
	target = best
	if target and prev == null and not engaged and startle_left <= 0.0 and not entering:
		_startle()
	var space := get_world_3d().direct_space_state
	var from := global_position
	if target:
		var q := PhysicsRayQueryParameters3D.create(from, _aim_point(), 1, [get_rid()])
		var hit := space.intersect_ray(q)
		_los = hit.is_empty() or hit.collider == target or (hit.collider is Node and (hit.collider as Node).is_in_group(&"enemies"))
	_update_route()
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 40.0, 1, [get_rid()]))
	_floor_y = (down["position"] as Vector3).y if not down.is_empty() else (target.global_position.y - 1.0 if target else _floor_y)
	var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 14.0, 1, [get_rid()]))
	_ceil_y = (up["position"] as Vector3).y if not up.is_empty() else INF
	_sep = Vector3.ZERO
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if e == self or not (e is RobotEnemy and (e as RobotEnemy).alive):
			continue
		var off: Vector3 = global_position - (e as Node3D).global_position
		var d := off.length()
		var room := 0.9 * (_size_factor() + (e as RobotEnemy)._size_factor())
		if d > 0.01 and d < room:
			_sep += off / d * (room - d)
	if target and engaged and not net_puppet:
		_scan_threats()


## A hunter out of sight of its target or far off: a route to it through
## the air (a clear line of sight isn't a clear way for its body), re-planned
## every 2 s, or sooner when the target moves well away from its end or it
## gets stuck. (The ground navigation mesh is no use to a flyer.)
func _update_route() -> void:
	var near := target != null and _los and Vector2(target.global_position.x - global_position.x, target.global_position.z - global_position.z).length() < orbit_range.y + 8.0
	if not hunt_nav or target == null or net_puppet or near:
		_route.clear()
		return
	_route_t -= 0.25
	var moved := _route.size() >= 2 and _route[_route.size() - 1].distance_to(target.global_position) > 6.0
	if _route_t > 0.0 and _route.size() >= 2 and not moved:
		return
	_route_t = 2.0
	var nav := get_tree().get_first_node_in_group(&"flight_nav") as FlightNav
	if nav == null:
		return
	_route = nav.route(get_world_3d().direct_space_state, global_position, _aim_point() + Vector3.UP * 1.5, [get_rid()])
	_route_i = 0
	_route_best = INF


## Height it should be at: over the floor below, under any ceiling.
func _clamp_height(y: float) -> float:
	var lo := _floor_y + hover_height.x if _floor_y > -INF else y
	var hi := _floor_y + hover_height.y + 6.0 if _floor_y > -INF else y
	hi = minf(hi, _ceil_y - 1.4 * model_scale)
	return clampf(y, lo, maxf(hi, lo))


func _combat_velocity(delta: float) -> Vector3:
	# Hunting a target out of sight or far off: along its route through
	# the air.
	if _route.size() >= 2:
		while _route_i < _route.size() - 1 and global_position.distance_to(_route[_route_i]) < 2.5:
			_route_i += 1
			_route_best = INF
		var to := _route[_route_i] - global_position
		# Not getting any closer to the next point: plan again.
		if to.length() < _route_best - 0.5:
			_route_best = to.length()
			_route_stuck = 0.0
		else:
			_route_stuck += delta
			if _route_stuck > 1.5:
				_route_stuck = 0.0
				_route_t = 0.0
		return (to.normalized() * hunt_speed + _sep * 2.5).limit_length(hunt_speed * 1.1)
	var tp := target.global_position
	var off := global_position - tp
	var flat := Vector2(off.x, off.z)
	var d := flat.length()
	_repos_t -= delta
	if _repos_t <= 0.0:
		_repos_t = randf_range(reposition_time.x, reposition_time.y)
		_radius = randf_range(orbit_range.x, orbit_range.y)
		_alt = randf_range(height_over_target.x, height_over_target.y)
		if randf() < 0.4:
			_orbit_dir = -_orbit_dir
	# Unprompted jukes while it fights.
	if engaged and not net_puppet:
		_juke_t -= delta
		if _juke_t <= 0.0:
			_juke_t = randf_range(juke_time.x, juke_time.y)
			_dash(Vector3.ZERO)
	# A point on its circle round the target, a little ahead the way it's
	# going round: it keeps swinging round at range.
	var bearing := atan2(flat.y, flat.x) if d > 0.1 else randf() * TAU
	var b := bearing + orbit_lead * _orbit_dir
	var goal := Vector3(tp.x + cos(b) * _radius, 0.0, tp.z + sin(b) * _radius)
	goal.y = _clamp_height(tp.y + 1.0 + _alt)
	var want := (goal - global_position) * 1.4
	want += _sep * 2.5
	want = want.limit_length(cruise_speed)
	# Never into a wall or pillar: swing round the other way and up.
	if want.length_squared() > 0.25 and not _clear_path(want.normalized(), 2.6 * model_scale):
		_orbit_dir = -_orbit_dir
		want = (want * -0.3 + Vector3.UP * cruise_speed * 0.6)
		if global_position.y > _ceil_y - 2.0 * model_scale:
			want.y = -cruise_speed * 0.4
	return want


func _patrol_velocity(delta: float) -> Vector3:
	_patrol_t += delta
	var goal := _home + Vector3(cos(_patrol_t * 0.35), 0.0, sin(_patrol_t * 0.5)) * patrol_radius
	goal.y = _clamp_height(_home.y + sin(_patrol_t * 0.8) * 0.4)
	return ((goal - global_position) * 1.2).limit_length(cruise_speed * 0.35)


func _clear_path(dir: Vector3, dist: float) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + dir * dist, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit.collider is Node and ((hit.collider as Node).is_in_group(&"players") or (hit.collider as Node).is_in_group(&"enemies")))


## Faces its target (cannons on it, nose dipped towards it) - or where it's
## going - and banks into its turns and dashes.
func _face(delta: float) -> void:
	var look := Vector3.ZERO
	if target and (startle_left > 0.0 or engaged):
		look = _aim_point() - global_position
	else:
		look = Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var want_pitch := 0.0
	if look.length_squared() > 0.04:
		var want_yaw := atan2(look.x, look.z)
		_yaw = lerp_angle(_yaw, want_yaw, clampf(turn_rate * delta, 0.0, 1.0))
		if target and (startle_left > 0.0 or engaged):
			want_pitch = clampf(atan2(-look.y, Vector2(look.x, look.z).length()), -deg_to_rad(max_pitch_deg), deg_to_rad(max_pitch_deg))
	_pitch = lerpf(_pitch, want_pitch, clampf(5.0 * delta, 0.0, 1.0))
	# Bank: into the sideways acceleration (and a hard roll on a dash).
	var side := -Basis(Vector3.UP, _yaw).x  # its right
	var lat := _acc.dot(side)
	var want_roll := clampf(lat * 0.06, -1.0, 1.0) * deg_to_rad(max_bank_deg)
	_roll_kick = move_toward(_roll_kick, 0.0, delta * 3.0)
	_roll = lerpf(_roll, want_roll + _roll_kick, clampf(6.0 * delta, 0.0, 1.0))
	_visual.basis = Basis.from_euler(Vector3(_pitch, _yaw, _roll))


## Its acceleration (for the springy wings / antennae), the clip blend from
## its velocity, and the booster.
func _feed_motion(delta: float) -> void:
	var v := linear_velocity
	if delta > 0.0:
		_acc = _acc.lerp((v - _prev_v) / delta, clampf(10.0 * delta, 0.0, 1.0))
	_prev_v = v
	var inv := _visual.global_basis.orthonormalized().inverse()
	var lv := inv * v
	var la := inv * _acc
	if flex:
		flex.accel = la
		flex.bank = _roll
	if arms:
		arms.accel = la
		arms.startled = startle_left > 0.0
		arms.aim = _aim_point() if target and (engaged or startle_left > 0.0) else Vector3.INF
	# Model faces +Z; its right is -X.
	var want := Vector2(clampf(-lv.x / cruise_speed, -1.0, 1.0), clampf(lv.z / cruise_speed, -1.0, 1.0))
	_blend = _blend.lerp(want, clampf(4.0 * delta, 0.0, 1.0))
	if tree:
		tree.set(&"parameters/fly/blend_position", _blend)
	if trail:
		trail.back = -_visual.global_basis.z.normalized()
		trail.throttle = clampf(0.35 + v.length() / evade_speed, 0.0, 1.0)


# --- Expressions ---

## Its face: where the red wing covers and back plates go (SentinelFlex)
## and how bright the eye burns, from what it's doing.
##   - Every few seconds the covers flick right up or right down (mostly
##     taking turns), uncovering the yellow back plates, and hold a moment:
##     lazily on patrol, often and sharply in a fight; now and then one up
##     and one down.
##   - Flight: they tip up as it dives or speeds along, down as it climbs,
##     and lean with the bank.
##   - Startled: flared right out, the eye flaring and flickering.
##   - Winding up a volley: they swing up (bristling), the back plates flare
##     and the eye brightens; firing, each shot kicks that side's cover.
##   - Dodging: the cover on the side it darts to snaps up, the other down.
##   - Hit: both slam shut and shudder (a flinch), the eye flashes.
func _express(delta: float) -> void:
	if flex == null:
		return
	var fight := engaged and target != null
	_flutter_t -= delta
	_flick_t -= delta
	if _flick_t <= 0.0:
		_flick = Vector2.ZERO
	if _flutter_t <= 0.0:
		var r := fight_flutter_time if fight else flutter_time
		_flutter_t = randf_range(r.x, r.y)
		_flick_t = randf_range(0.45, 0.9) if fight else randf_range(0.8, 1.4)
		if randf() < 0.8:
			_flick_up = not _flick_up
		var v := -1.0 if _flick_up else 1.0
		_flick = Vector2(v, v)
		if randf() < (0.3 if fight else 0.15):
			_flick.y = -v
		flicks += 1
	var cover := _flick
	var plate := Vector2.ZERO
	var energy := 1.0 if fight else 0.85
	expression = &"flick" if _flick != Vector2.ZERO else &"calm"
	var speed := clampf(linear_velocity.length() / cruise_speed, 0.0, 1.5)
	var tilt := clampf(-flex.accel.y * 0.05, -0.35, 0.35) - 0.2 * speed
	cover += Vector2(tilt + _roll * 0.5, tilt - _roll * 0.5)
	if startle_left > 0.0:
		cover = Vector2(0.6, 0.6)
		energy = 1.8 + randf() * 0.7
		expression = &"startled"
	elif fight and _burst_left > 0:
		cover = Vector2(-1.0, -1.0)
		plate = Vector2.ONE * 0.6
		energy = 1.9
		expression = &"firing"
	elif fight and _los and _cool_t < windup_time:
		var w := 1.0 - clampf(_cool_t / windup_time, 0.0, 1.0)
		cover = cover.lerp(Vector2(-1.0, -1.0), w)
		plate = Vector2.ONE * 0.6 * w
		energy += 0.9 * w
		expression = &"windup"
	if _dodge_t > 0.0:
		_dodge_t -= delta
		cover = Vector2(_dodge_side, -_dodge_side)
		plate = Vector2.ONE * 0.4
		expression = &"dodge"
	if _flinch_t > 0.0:
		_flinch_t -= delta
		cover = Vector2.ZERO
		plate = Vector2(-0.4, -0.4)
		expression = &"flinch"
	flex.cover = cover
	flex.plate = plate
	_eye_flash = move_toward(_eye_flash, 0.0, delta * 3.0)
	_set_eye(energy + _eye_flash, delta)


func _set_eye(energy: float, delta: float) -> void:
	eye_energy = move_toward(eye_energy, energy, delta * 6.0)
	for m in _eye_mats:
		m.set_shader_parameter(&"energy", eye_energy)


# --- Startled ---

func _startle() -> void:
	startles += 1
	var a := _anim.get_animation(&"Startled_See_Player")
	startle_left = a.length / startle_speed * 0.9
	if tree:
		tree.set(&"parameters/shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	# Jerks back and up as it notices them.
	if target:
		var away := global_position - target.global_position
		away.y = 0.0
		linear_velocity = away.normalized() * 2.5 + Vector3.UP * 1.5 if away.length_squared() > 0.01 else Vector3.UP * 1.5


func _finish_startle() -> void:
	startle_left = 0.0
	engaged = true
	_cool_t = randf_range(reaction_time.x, reaction_time.y)
	if tree:
		tree.set(&"parameters/shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


# --- Evasion ---

## A player's bolt that will pass close soon -> maybe dodge it.
func _scan_threats() -> void:
	if _dash_t > 0.0 or _evade_cd > 0.0:
		return
	for b in PlasmaBolt.in_flight():
		if not is_instance_valid(b.shooter) or not (b.shooter as Node).is_in_group(&"players"):
			continue
		var v := b.velocity
		var vv := v.length_squared()
		if vv < 1.0:
			continue
		var rel := global_position - b.global_position
		var tca := rel.dot(v) / vv
		if tca < 0.0 or tca > threat_time:
			continue
		if (rel - v * tca).length() < threat_radius * model_scale:
			if randf() < evade_chance:
				_dash(v)
			else:
				_evade_cd = 0.4
			return


## A quick banking side-dash out of the line of fire (`from_dir` = the
## shot's travel, or ZERO for a juke), with a little up or down in it.
func _dash(from_dir: Vector3) -> void:
	if not alive or net_puppet or _dash_t > 0.0 or startle_left > 0.0:
		return
	var face := -_visual.global_basis.z if target == null else (target.global_position - global_position)
	face.y = 0.0
	face = face.normalized() if face.length_squared() > 0.01 else Vector3.FORWARD
	var side := Vector3.UP.cross(face)
	var s := 1.0 if randf() < 0.5 else -1.0
	if from_dir != Vector3.ZERO:
		s = 1.0 if side.dot(from_dir) < 0.0 else -1.0
		if randf() < 0.2:
			s = -s
	var dir := (side * s + Vector3.UP * randf_range(-0.45, 0.55)).normalized()
	if not _clear_path(dir, evade_speed * evade_time + 1.0):
		dir = (-side * s + Vector3.UP * 0.3).normalized()
		if not _clear_path(dir, evade_speed * evade_time + 1.0):
			dir = Vector3.UP
	# Never dodges down near the floor: it stays well above the players.
	if dir.y < 0.0 and global_position.y + dir.y * evade_speed * evade_time * 0.7 < _floor_y + hover_height.x * 0.85:
		dir.y = -dir.y
		dir = dir.normalized()
	_start_dash(dir)


func _start_dash(dir: Vector3) -> void:
	Net.world_event(self, &"act", [dir])
	_dash_t = evade_time
	_dash_v = dir * evade_speed
	_evade_cd = randf_range(evade_cooldown.x, evade_cooldown.y)
	var side := -_visual.global_basis.x
	_roll_kick = -signf(dir.dot(side)) * deg_to_rad(55.0)
	_dodge_side = signf(dir.dot(side))
	_dodge_t = evade_time + 0.25
	dashes += 1


func net_event(kind: StringName, args: Array) -> void:
	if kind == &"act":
		if alive and not args.is_empty() and args[0] is Vector3:
			_dash_t = evade_time
			_dash_v = (args[0] as Vector3) * evade_speed
			_roll_kick = deg_to_rad(55.0) * (1.0 if randf() < 0.5 else -1.0)
			_dodge_side = signf(-_roll_kick)
			_dodge_t = evade_time + 0.25
		return
	super.net_event(kind, args)


## The host's position for it (height too: it flies).
func _net_correct(delta: float) -> void:
	if _net_pos == Vector3.INF or freeze:
		return
	var err := _net_pos - global_position
	if err.length() > 5.0:
		global_position = _net_pos
		linear_velocity = Vector3.ZERO
		reset_physics_interpolation()
	else:
		global_position += err * clampf(2.5 * delta, 0.0, 1.0)


# --- Cannons ---

func _aim_point() -> Vector3:
	return target.global_position + Vector3.UP * 1.1 if target else global_position


func _update_fire(delta: float, dist: float) -> void:
	if net_puppet:
		return  # the host says when (net_event "fire")
	if not _los or dist > fire_range or _dash_t > 0.0:
		_burst_left = 0
		return
	var to := (_aim_point() - global_position).normalized()
	var facing := _visual.global_basis.z.normalized()
	var on_target := facing.dot(to) > cos(deg_to_rad(28.0))
	if _burst_left > 0:
		_shot_t -= delta
		if _shot_t <= 0.0 and on_target:
			_fire_one()
			_burst_left -= 1
			_shot_t = burst_interval
			if _burst_left == 0:
				_cool_t = randf_range(volley_cooldown.x, volley_cooldown.y)
		return
	_cool_t -= delta
	if _cool_t <= 0.0 and on_target:
		_burst_left = 2  # one from each cannon
		_shot_t = 0.0


## One green bolt from the next cannon (left / right in turn).
func _fire_one() -> void:
	Net.world_event(self, &"fire")
	var i := _next_cannon
	_next_cannon = 1 - _next_cannon
	if arms:
		arms.recoil(i)
	if flex:
		flex.kick_cover(i, 7.0)
	var muzzle := muzzle_position(i)
	var aim := _aim_point()
	if target is CharacterBody3D:
		var tv := (target as CharacterBody3D).velocity
		aim += Vector3(tv.x, 0, tv.z) * (muzzle.distance_to(aim) / bolt_speed) * 0.5
	var dir := (aim - muzzle).normalized()
	var spread := deg_to_rad(aim_spread_deg * aim_spread_scale())
	dir = dir.rotated(Vector3.UP, randf_range(-spread, spread))
	var right := dir.cross(Vector3.UP)
	if right.length_squared() > 0.001:
		dir = dir.rotated(right.normalized(), randf_range(-spread, spread) * 0.6)
	PlasmaBolt.fire(get_tree(), muzzle, dir, self, bolt_speed, bolt_damage)
	PlasmaFx.muzzle_flash(get_tree(), muzzle, dir)
	_cel_flash(muzzle, dir)
	if _shot_voices.is_empty():
		_shot_voices = Sfx.voices(self, Sfx.ENEMY_TROOP_1_FIRING, 2, shot_sound_db, shot_sound_near, shot_sound_far)
	_shot_voice = Sfx.play_next(_shot_voices, _shot_voice, shot_sound_pitch)
	shot_sounds += 1
	shots_fired += 1


# --- Damage ---

func apply_damage(info: DamageInfo) -> void:
	var was := alive
	super.apply_damage(info)
	if not was or not alive or is_frozen():
		return
	# Flinch: the covers slam shut and shudder, the eye flashes.
	_flinch_t = 0.3
	_eye_flash = 1.3
	if flex:
		flex.kick_cover(0, randf_range(-9.0, 9.0))
		flex.kick_cover(1, randf_range(-9.0, 9.0))
	if net_puppet:
		return
	if startle_left > 0.0:
		_finish_startle()  # shot while startled: straight into the fight
	if randf() < hit_evade_chance:
		_dash(info.impact_direction if info else Vector3.ZERO)


func _suppressed() -> void:
	_burst_left = 0
	_cool_t = maxf(_cool_t, 0.0) + suppression.burst_delay
	if hit_fx and hit_fx.react:
		hit_fx.react.kick(0.5, -_visual.global_basis.z)


# --- Frost Byte ---

## Frozen: an ice sculpture that drops out of the air; it flies again when
## it thaws.
func frost_freeze(seconds: float) -> void:
	if not alive:
		return
	super.frost_freeze(seconds)
	if tree:
		tree.active = false
	gravity_scale = 1.0
	_dash_t = 0.0
	if arms:
		arms.frozen = true
	if flex:
		flex.hold = true
	if eye_glow:
		eye_glow.visible = false
	_set_eye(0.3, 1.0)
	if trail:
		trail.emitting = false


func on_thawed() -> void:
	super.on_thawed()
	if alive:
		if tree:
			tree.active = true
		gravity_scale = 0.0
		if arms:
			arms.frozen = false
		if flex:
			flex.hold = false
		if eye_glow:
			eye_glow.visible = true
		if trail:
			trail.emitting = true


# --- Death ---

func die(info: DamageInfo) -> void:
	if not alive:
		return
	Net.world_event(self, &"die", [info.to_net() if info else []])
	var shattering := _shattering
	_use_section_meshes()
	if eye_glow:
		eye_glow.visible = false
	_eye_mats.clear()
	target = null
	_burst_left = 0
	alive = false
	health = 0.0
	if _targetable:
		_targetable.kill()
	GravityWell.restore_visual(self)
	remove_meta("gw_visuals")
	collision_layer = 0
	collision_mask = 1
	physics_material_override.friction = 0.9
	physics_material_override.bounce = 0.2
	freeze = false
	gravity_scale = 1.0
	lock_rotation = false
	_dead_t = 0.0
	_settled = false
	last_destruction = BreakApart.Level.EXTREME if shattering else BreakApart.Level.HEAVY
	if trail:
		trail.emitting = false
	if tree:
		tree.active = false
	_death_sound()
	if shattering:
		_anim.speed_scale = 0.0
		_shatter_now(info)
	else:
		# The eye smashes: the burst from just before the glass goes.
		_anim.play(&"Death_Eye_Burst")
		_anim.seek(0.7, true)
		_anim.speed_scale = 1.4
		flex.dying = true
		flex.die_t = 0.0
		arms.dying = true
		for n in ["Yellow_Plasma_Gas_Volume", "Tiny_Electric_Energy_Ball"]:
			var mi := _skeleton.get_node_or_null(n) as MeshInstance3D
			if mi:
				mi.visible = false
		var face := _visual.global_basis.z
		get_tree().create_timer(0.07, false, true).timeout.connect(func() -> void:
			if is_inside_tree():
				SentinelEyeBurst.spawn(get_tree(), _skeleton, _eye_bone, _visual.global_basis.z if _visual else face, model_scale))
		# Knocked out of the air, tumbling.
		var push := info.impact_direction if info else Vector3.ZERO
		push = push.normalized() if push.length_squared() > 0.001 else -face
		linear_velocity = linear_velocity * 0.4 + push * randf_range(2.0, 3.5) + Vector3.UP * randf_range(1.0, 2.5)
		angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(3.0, 6.0)
		_break_wings(info)
	if hit_fx:
		hit_fx.on_death(info, true)
	if drops_recovery:
		RecoveryDrops.on_enemy_killed(self, info)
	died.emit(info)


## One of its three death sounds, not the one heard last; it follows the
## falling wreck.
func _death_sound() -> void:
	var sounds: Array[AudioStream] = [Sfx.SENTINEL_DEATH_1, Sfx.SENTINEL_DEATH_2, Sfx.SENTINEL_DEATH_3]
	var pick := randi() % sounds.size()
	if pick == _last_sentinel_pick:
		pick = (pick + 1 + randi() % (sounds.size() - 1)) % sounds.size()
	_last_sentinel_pick = pick
	last_death_sound = sounds[pick]
	var snd := Sfx.emitter(self, sounds[pick], death_sound_db, death_sound_near, death_sound_far)
	snd.finished.connect(snd.queue_free)
	snd.play()
	death_sounds += 1


## The wings break apart into all their pieces and the antennae snap off,
## in a quick crackle right after the eye goes.
func _break_wings(info: DamageInfo) -> void:
	var by_name := {}
	for s in section_set.sections:
		by_name[s.section_name] = s
	var planned: Array[BreakSection] = []
	for n in DEATH_BREAKS:
		planned.append(by_name[n])
	var centre := global_position
	var blast := DamageInfo.make(1.0, DamageInfo.Type.EXPLOSION, centre, info.impact_direction if info else Vector3.UP, 4.0, 9.0, info.source if info else null)
	var t := 0.05
	for group in [[&"Wing_Cover_L", &"Wing_Cover_R"], [&"Wing_Plate_L", &"Wing_Plate_R"], [&"Antenna_L", &"Antenna_R"], [&"Wing_L", &"Wing_R"]]:
		var cuts: Array[BreakSection] = []
		for n in group:
			cuts.append(by_name[n])
		get_tree().create_timer(t, false, true).timeout.connect(func() -> void:
			if is_inside_tree():
				_breaker.detach(cuts, blast, linear_velocity, planned))
		t += 0.06


func _respawn() -> void:
	gravity_scale = 0.0
	lock_rotation = true
	angular_velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	engaged = false
	startle_left = 0.0
	_dash_t = 0.0
	physics_material_override.bounce = 0.0
	super._respawn()
	_home = global_position
