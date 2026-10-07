class_name RobotEnemy
extends RigidBody3D
## The robot enemy. A heavy upright physics body (gravity wells can pull and
## throw it) carrying the robot model, which walks a short patrol.
##
## Damage arrives as DamageInfo (apply_damage). At 0 health it dies: all
## behaviour stops, one of the model's own fall/death clips plays, and
## depending mainly on the killing hit it stays whole (with a little
## electrical failure) or breaks into its prepared sections (BreakApart).

signal died(info: DamageInfo)
signal hit(count: int)

const MODEL := preload("res://assets/characters/robot/robot_enemy.glb")
## Seals the model's cut sections (its own interior caps made opaque, plus
## caps for the few cuts it lacks) so no part is see-through when broken.
const CAPS := preload("res://assets/characters/robot/robot_caps.res")

@export var max_health := 2.0
@export var section_set: BreakSectionSet = preload("res://resources/enemies/robot_break_sections.tres")

@export_group("Patrol")
@export var walk_speed := 1.1
## Walking clip plays at 1x at this speed (m/s).
@export var walk_anim_speed := 1.2
## Walks back and forth this far (m) along `patrol_axis` (0 = stands still).
@export var patrol_distance := 4.0
@export var patrol_axis := Vector3.RIGHT
@export var turn_speed := 4.0
@export var walk_accel := 6.0

@export_group("Combat")
## Engages players: pursues, strafes, faces/aims and fires its hand cannons.
@export var combat_enabled := true
@export var detect_range := 28.0
## Gives up beyond this distance.
@export var lose_range := 40.0
## Distance band it tries to fight from (advances / backs off outside it).
@export var preferred_range := Vector2(7.0, 14.0)
@export var combat_speed := 2.6
@export var run_anim_speed := 3.4
## Most the upper body turns from the legs before it walks backwards
## (facing the target) instead.
@export var max_twist_deg := 105.0
@export var backpedal_speed_factor := 0.6
## Seconds between strafe direction decisions.
@export var strafe_time := Vector2(1.0, 2.4)
@export var fire_range := 26.0
## Shots per burst (alternating cannons), time between shots, pause between
## bursts, and the delay before the first burst after spotting a player.
@export var burst_count := Vector2i(3, 4)
@export var burst_interval := 0.12
@export var burst_cooldown := Vector2(1.3, 2.3)
@export var reaction_time := Vector2(0.5, 1.0)
@export var aim_spread_deg := 2.0
@export var bolt_speed := 30.0
@export var bolt_damage := 1.0

@export_group("Death")
## Death clips (must exist in the model). The killing hit picks one of seven
## deaths: the model's four clips (electrocuted, falls backwards, falls
## forwards, shot in the back) and three procedural ones layered on them
## (source clips untouched): BLOWN_BACK (heavy frontal hit: launched off its
## feet), SPIN (hit from the side: spins round as it drops) and STAGGER
## (staggers backwards, then topples). Never the same death twice in a row.
@export var death_anim_electric := &"Electrocuted_Fall"
@export var death_anim_from_front := &"Shot_and_Fall_Backward"
@export var death_anims_from_behind: Array[StringName] = [&"Shot_in_the_Back_and_Fall", &"Shot_and_Fall_Forward"]
## Chance an energy kill uses the electrocuted death.
@export var electric_death_chance := 0.3
## Killing-hit force (impact + explosive) that can blow it off its feet.
@export var blown_back_force := 6.0
@export var blown_back_speed := Vector2(3.9, 2.8)  # back, up (m/s)
@export var spin_degrees := 220.0
@export var stagger_time := 0.75
## Seconds into the death before parts detach (strong hits break sooner).
@export var break_delay := Vector2(0.06, 0.4)
## Extra delay between successive breaks (a rapid cascade, not all at once).
@export var break_stagger := 0.05
## Subtle sparks on an intact corpse: how many, over how long.
@export var failure_sparks := Vector2i(3, 5)
@export var failure_spark_time := 3.0
@export var corpse_time := 14.0
## Respawn at the start position this long after the corpse is cleared
## (testing convenience; < 0 = never).
@export var respawn_time := 5.0
## Torn apart by a black hole's core: blast force (sets how completely it
## breaks) and how hard the pieces are thrown (gently, they get pulled back).
@export var swallow_force := 45.0
@export var swallow_launch_scale := 0.3

var health := 0.0
var hits := 0
var alive := true
var last_destruction := BreakApart.Level.NONE
var last_death_anim := &""
## "clip", "blown_back", "spin" or "stagger".
var last_death_style := ""
static var _prev_death := ""
## Tests/previews: force a death style ("clip"/"blown_back"/"spin"/"stagger").
var force_death_style := ""
var _stagger_vel := Vector3.ZERO

var _visual: Node3D
var _model: Node3D
var _skeleton: Skeleton3D
var _anim: AnimationPlayer
var _breaker: BreakApart
var _targetable: Targetable
var _spawn_xf: Transform3D
var _layers := 0
var _mask := 0
var _dir := 1.0
var _yaw := 0.0
var _phase := 0.0
var _dead_t := 0.0
var _settled := false
var _pulled_frame := -100

## Global switch (tests turn robot AI off for deterministic checks).
static var ai_enabled := true
## Cannon muzzles (the green tips) in each hand bone's space.
const MUZZLES := {"Left": Vector3(-0.035, 0.185, 0.016), "Right": Vector3(0.017, 0.146, 0.009)}
## Current combat target (a player) or null.
var target: Node3D
var shots_fired := 0
var _aim: RobotArmAim
var _think_t := 0.0
var _los := false
var _strafe_dir := 1.0
var _strafe_t := 0.0
var _burst_left := 0
var _shot_t := 0.0
var _cool_t := 0.0
var _next_cannon := 0
var _sep := Vector3.ZERO
var _move_anim := &"Walking"
var _anim_backwards := false
var _backing := false


func _ready() -> void:
	mass = 120.0
	lock_rotation = true
	can_sleep = false  # it drives itself every tick while alive
	# Walking drives the body's velocity itself, so no ground friction while
	# alive (the corpse gets friction back).
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.0
	collision_layer |= GravityWell.MOVABLE_LAYER
	add_to_group(&"enemies")
	_layers = collision_layer
	_mask = collision_mask
	set_meta("gravity_center_y", 0.9)
	_targetable = get_node_or_null("Targetable") as Targetable
	_spawn_xf = global_transform
	_phase = randf()
	_dir = 1.0 if randf() < 0.5 else -1.0
	_build_model()
	health = max_health


func _build_model() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_model = _model_scene().instantiate()
	_model.name = "Model"
	_visual.add_child(_model)
	_model.position = _model_offset()
	_skeleton = _model.find_child("Skeleton3D", true, false) as Skeleton3D
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var caps := _mesh_caps()
	if caps:
		caps.apply(_model)
	_use_whole_mesh()
	for a in [&"Walking", &"Running"]:
		if _anim.has_animation(a):
			_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_anim.play(&"Walking")
	_anim.seek(_phase * _anim.current_animation_length, true)
	_move_anim = &"Walking"
	_anim_backwards = false
	_aim = RobotArmAim.new()
	_aim.name = "ArmAim"
	_skeleton.add_child(_aim)
	_aim.setup(_skeleton, _muzzle_offsets())
	if _breaker:
		_breaker.queue_free()
	_breaker = BreakApart.new()
	_breaker.name = "BreakApart"
	_breaker.section_set = section_set
	_breaker.skeleton = _skeleton
	add_child(_breaker)
	_yaw = atan2(patrol_axis.x * _dir, patrol_axis.z * _dir)
	_visual.rotation.y = _yaw


# --- Model (a robot with another model overrides these) ---

func _model_scene() -> PackedScene:
	return MODEL


## Simplified, untextured copy of the model for distant views.
func _far_scene() -> PackedScene:
	return FAR_MODEL


## Seals cut sections (null = the model's sections are already sealed).
func _mesh_caps() -> MeshCaps:
	return CAPS


## Cannon muzzles in each hand bone's space ({"Left": .., "Right": ..}).
func _muzzle_offsets() -> Dictionary:
	return MUZZLES


func _model_offset() -> Vector3:
	# The model's hips sit 0.245 m behind its origin; centre them.
	return Vector3(0, 0, 0.245)


## True when the far model carries its own textured material (its own UV
## layout); otherwise it is drawn with the main model's material.
func _far_own_material() -> bool:
	return false


## Surfaces of this material are left out of the merged living mesh (e.g.
## cut caps that are only ever seen once a section has broken off).
func _whole_mesh_skips(_mat: Material) -> bool:
	return false


# --- One mesh while alive (performance) ---
#
# The 15 body sections are only needed when the robot breaks apart. While
# it's alive it draws ONE mesh made of all of them (identical geometry,
# skin and materials on the same skeleton): 2 draw calls instead of ~28.

## Much simpler copy for when it's far away (only a few pixels tall).
const FAR_MODEL := preload("res://assets/characters/robot/robot_enemy_far.glb")
## Per model (scene path): [whole mesh, whole skin, far mesh, far skin],
## built once and shared by every robot using that model.
static var _mesh_cache := {}
var _whole_mesh: ArrayMesh
var _whole_skin: Skin
var _far_mesh: ArrayMesh
var _far_skin: Skin
## Camera distance (m) where it swaps to the far mesh, and the hysteresis.
@export var far_distance := 30.0
@export var far_margin := 2.0
var _whole: MeshInstance3D
var _whole_far: MeshInstance3D
## Casts the robot's shadow using the simple mesh (a shadow is a soft
## silhouette; the full-detail body itself doesn't need to cast it).
var _shadow_proxy: MeshInstance3D
var _sections: Array[MeshInstance3D] = []


## All section surfaces merged per material (built once per model, shared
## by the robots using it).
func _build_whole_mesh(skel: Skeleton3D) -> void:
	var key := _model_scene().resource_path
	if _mesh_cache.has(key):
		var c: Array = _mesh_cache[key]
		_whole_mesh = c[0]
		_whole_skin = c[1]
		_far_mesh = c[2]
		_far_skin = c[3]
		return
	var r := _merge_sections(skel, _whole_mesh_skips)
	_whole_mesh = r[0]
	_whole_skin = r[1]
	# Distant version: same merge of the simplified model, using the main
	# robot's materials (it carries no textures of its own).
	var far: Node3D = _far_scene().instantiate()
	var far_skel := far.find_child("Skeleton3D", true, false) as Skeleton3D
	var rf := _merge_sections(far_skel)
	var simple: ArrayMesh = rf[0]
	_far_skin = rf[1]
	# Simplified main body + the full-detail small glow-detail surface (tiny,
	# and the part that would otherwise visibly vanish).
	_far_mesh = ArrayMesh.new()
	_far_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, simple.surface_get_arrays(0))
	_far_mesh.surface_set_material(0, simple.surface_get_material(0) if _far_own_material() else _whole_mesh.surface_get_material(0))
	for k in range(1, _whole_mesh.get_surface_count()):
		_far_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _whole_mesh.surface_get_arrays(k))
		_far_mesh.surface_set_material(k, _whole_mesh.surface_get_material(k))
	far.free()
	_mesh_cache[key] = [_whole_mesh, _whole_skin, _far_mesh, _far_skin]


## [merged ArrayMesh, Skin] of every section mesh under `skel`.
static func _merge_sections(skel: Skeleton3D, skip := Callable()) -> Array:
	var skin: Skin
	var by_mat := {}  # material -> [arrays parts]
	var order: Array = []
	for mi in skel.get_children():
		if not (mi is MeshInstance3D):
			continue
		var m: Mesh = (mi as MeshInstance3D).mesh
		skin = (mi as MeshInstance3D).skin
		for k in m.get_surface_count():
			var mat := m.surface_get_material(k)
			if skip.is_valid() and skip.call(mat):
				continue
			if not by_mat.has(mat):
				by_mat[mat] = []
				order.append(mat)
			by_mat[mat].append(m.surface_get_arrays(k))
	var out := ArrayMesh.new()
	for mat in order:
		var merged := []
		merged.resize(Mesh.ARRAY_MAX)
		var base := 0
		for arr: Array in by_mat[mat]:
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
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return [out, skin]


func _use_whole_mesh() -> void:
	_sections.clear()
	for c in _skeleton.get_children():
		if c is MeshInstance3D:
			_sections.append(c)
	_build_whole_mesh(_skeleton)
	_whole = MeshInstance3D.new()
	_whole.name = "WholeBody"
	_whole.mesh = _whole_mesh
	_whole.skin = _whole_skin
	_skeleton.add_child(_whole)
	_whole.skeleton = NodePath("..")
	_whole.visibility_range_end = far_distance
	_whole.visibility_range_end_margin = far_margin
	_whole_far = MeshInstance3D.new()
	_whole_far.name = "WholeBodyFar"
	_whole_far.mesh = _far_mesh
	_whole_far.skin = _far_skin
	_skeleton.add_child(_whole_far)
	_whole_far.skeleton = NodePath("..")
	_whole_far.visibility_range_begin = far_distance
	_whole_far.visibility_range_begin_margin = far_margin
	_whole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_whole_far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow_proxy = MeshInstance3D.new()
	_shadow_proxy.name = "ShadowProxy"
	_shadow_proxy.mesh = _far_mesh
	_shadow_proxy.skin = _far_skin
	_shadow_proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_skeleton.add_child(_shadow_proxy)
	_shadow_proxy.skeleton = NodePath("..")
	for s in _sections:
		s.visible = false


func _use_section_meshes() -> void:
	for s in _sections:
		if is_instance_valid(s):
			s.visible = true
	for w in [_whole, _whole_far, _shadow_proxy]:
		if w and is_instance_valid(w):
			w.visible = false  # never drawn together with the sections
			w.queue_free()
	_whole = null
	_whole_far = null
	_shadow_proxy = null


## True while drawn as the single merged mesh (tests/debug).
func is_whole_mesh() -> bool:
	return _whole != null and is_instance_valid(_whole) and _whole.visible


## Gravity wells shrink/spin these; a living robot stays full size (it is
## torn apart near the core and its pieces are what shrink).
func gravity_visual_nodes() -> Array:
	return []


## Got too close to a black hole's core: torn apart on the spot. The pieces
## burst out only gently so the black hole can pull them back in.
func on_swallowed(well: Node3D) -> void:
	if not alive:
		return
	var info := DamageInfo.make(max_health + 1.0, DamageInfo.Type.SUPERNOVA, well.global_position,
		global_position - well.global_position, 0.0, swallow_force, well)
	info.launch_scale = swallow_launch_scale
	die(info)


func get_breaker() -> BreakApart:
	return _breaker


func get_skeleton() -> Skeleton3D:
	return _skeleton


# --- Behaviour ---

func _physics_process(delta: float) -> void:
	if alive:
		_behave(delta)
	else:
		_corpse(delta)


func _behave(delta: float) -> void:
	# Held, or being dragged into a black hole: helpless.
	if freeze or Engine.get_physics_frames() - _pulled_frame < 6:
		_anim.speed_scale = 0.4
		if _aim:
			_aim.target_weight = 0.0
		return
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = 0.25 + randf() * 0.05
		_think()
	if target:
		_combat(delta)
	else:
		if _aim:
			_aim.target_weight = 0.0
		_patrol(delta)


## Periodic (cheap) decisions: target, line of sight, spacing from others.
func _think() -> void:
	var best: Node3D = null
	if ai_enabled and combat_enabled:
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
	if best and best != target:
		_cool_t = randf_range(reaction_time.x, reaction_time.y)
		_burst_left = 0
	target = best
	if target == null:
		return
	# Line of sight (other robots don't block: bolts pass through them).
	var from := global_position + Vector3.UP * 1.5
	var q := PhysicsRayQueryParameters3D.create(from, _aim_point())
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	_los = hit.is_empty() or hit.collider == target or (hit.collider is Node and (hit.collider as Node).is_in_group(&"enemies"))
	# Keep a little space from other robots.
	_sep = Vector3.ZERO
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if e == self or not (e is RobotEnemy and (e as RobotEnemy).alive):
			continue
		var off: Vector3 = global_position - (e as Node3D).global_position
		off.y = 0.0
		var d := off.length()
		if d > 0.01 and d < 1.8:
			_sep += off / d * (1.8 - d)


func _aim_point() -> Vector3:
	return target.global_position + Vector3.UP * 1.1 if target else global_position


func _combat(delta: float) -> void:
	var to := target.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var dir_to := to / d if d > 0.01 else -_visual.global_basis.z
	# Strafe, switching sides now and then.
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(strafe_time.x, strafe_time.y)
		if randf() < 0.6:
			_strafe_dir = -_strafe_dir
	var side := Vector3.UP.cross(dir_to) * _strafe_dir
	var want := side * 0.8
	if d > preferred_range.y or not _los:
		want += dir_to * 1.1
	elif d < preferred_range.x:
		want -= dir_to * 0.9
	want += _sep * 1.5
	# Don't walk into walls: flip the strafe when blocked.
	if want.length_squared() > 0.01:
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.9, global_position + Vector3.UP * 0.9 + want.normalized() * 1.3)
		q.collision_mask = 1
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and hit.collider != target and not (hit.collider is Node and (hit.collider as Node).is_in_group(&"enemies")):
			_strafe_dir = -_strafe_dir
			_strafe_t = randf_range(strafe_time.x, strafe_time.y)
			want = Vector3.UP.cross(dir_to) * _strafe_dir * 0.8 + _sep * 1.5
	var spd_want := combat_speed * (backpedal_speed_factor if _backing else 1.0)
	want = want.normalized() * spd_want if want.length_squared() > 0.01 else Vector3.ZERO
	var v := linear_velocity
	var hv := Vector3(v.x, 0, v.z)
	# Like the player character: legs face where it's going, the upper body
	# twists to keep the chest and cannons on the target. Moving away from
	# the target it faces it and walks backwards instead. Reversing (e.g. a
	# strafe switching sides) it first brakes with the legs still facing the
	# old way, then turns the legs and sets off; while the legs turn it holds
	# back, so it never slides sideways.
	var player_yaw := atan2(dir_to.x, dir_to.z)
	var reversing := hv.length() > 0.6 and want.length_squared() > 0.01 and hv.dot(want) < 0.0
	var heading := hv if reversing or want.length_squared() <= 0.01 else want
	var legs_yaw := player_yaw
	var backwards := _backing if reversing else false
	if heading.length() > 0.4:
		var move_yaw := atan2(heading.x, heading.z)
		# Hysteresis so it doesn't flip between forwards/backwards.
		var limit := max_twist_deg + (-12.0 if _backing else 12.0)
		if absf(wrapf(move_yaw - player_yaw, -PI, PI)) > deg_to_rad(limit):
			legs_yaw = move_yaw + PI
			backwards = true
		else:
			legs_yaw = move_yaw
	# Turn the legs the way round that keeps facing the target side (never
	# swinging through its back, which would whip the upper-body twist).
	var turn := wrapf(legs_yaw - _yaw, -PI, PI)
	var rel := wrapf(_yaw - player_yaw, -PI, PI)
	if absf(rel + turn) > PI:
		turn -= signf(turn) * TAU
	_yaw += turn * clampf(turn_speed * 3.5 * delta, 0.0, 1.0)
	_visual.rotation.y = _yaw
	var leg_err := absf(wrapf(legs_yaw - _yaw, -PI, PI))
	if reversing:
		want = Vector3.ZERO
	else:
		want *= clampf(1.0 - (leg_err - deg_to_rad(25.0)) / deg_to_rad(45.0), 0.0, 1.0)
	if (hv - want).length() < 4.0:
		hv += (want - hv).limit_length(walk_accel * 1.8 * delta)
		linear_velocity = Vector3(hv.x, v.y, hv.z)
	var spd := hv.length()
	_aim.twist = clampf(wrapf(player_yaw - _yaw, -PI, PI), -deg_to_rad(max_twist_deg), deg_to_rad(max_twist_deg))
	_backing = backwards
	_set_move_anim(spd, backwards)
	# Aim both cannons at the player.
	_aim.target_point = _aim_point()
	_aim.target_weight = 1.0
	_update_fire(delta, d)


func _set_move_anim(speed: float, backwards := false) -> void:
	var run := speed > 1.9 and not backwards
	var a := &"Running" if run else &"Walking"
	if a != _move_anim or backwards != _anim_backwards:
		_move_anim = a
		_anim_backwards = backwards
		_anim.play(a, 0.2, -1.0 if backwards else 1.0)
	_anim.speed_scale = clampf(speed / (run_anim_speed if run else walk_anim_speed), 0.5, 1.6)


func _update_fire(delta: float, dist: float) -> void:
	if not _los or dist > fire_range:
		_burst_left = 0
		return
	if _burst_left > 0:
		_shot_t -= delta
		if _shot_t <= 0.0:
			_fire_one()
			_burst_left -= 1
			_shot_t = burst_interval
			if _burst_left == 0:
				_cool_t = randf_range(burst_cooldown.x, burst_cooldown.y)
		return
	_cool_t -= delta
	if _cool_t <= 0.0 and _aim.weight > 0.6:
		_burst_left = randi_range(burst_count.x, burst_count.y)
		_shot_t = 0.0


## One plasma bolt from the next cannon (alternating left/right).
func _fire_one() -> void:
	var i := _next_cannon
	_next_cannon = 1 - _next_cannon
	var muzzle := _aim.muzzle_position(i)
	var aim := _aim_point()
	# Slight lead on a moving target, plus a little spread.
	if target is CharacterBody3D:
		var tv := (target as CharacterBody3D).velocity
		aim += Vector3(tv.x, 0, tv.z) * (muzzle.distance_to(aim) / bolt_speed) * 0.5
	var dir := (aim - muzzle).normalized()
	var spread := deg_to_rad(aim_spread_deg)
	dir = dir.rotated(Vector3.UP, randf_range(-spread, spread))
	var right := dir.cross(Vector3.UP)
	if right.length_squared() > 0.001:
		dir = dir.rotated(right.normalized(), randf_range(-spread, spread) * 0.6)
	PlasmaBolt.fire(get_tree(), muzzle, dir, self, bolt_speed, bolt_damage)
	PlasmaFx.muzzle_flash(get_tree(), muzzle, dir)
	shots_fired += 1


## Called by gravity wells every tick they pull on it.
func on_gravity_pull() -> void:
	_pulled_frame = Engine.get_physics_frames()


func _patrol(delta: float) -> void:
	# Held, or being dragged into a black hole: helpless, no walking.
	if freeze or Engine.get_physics_frames() - _pulled_frame < 6:
		_anim.speed_scale = 0.4
		return
	if freeze:
		return  # held by something (e.g. captured in a gravity well)
	if _move_anim != &"Walking" or _anim_backwards:
		_move_anim = &"Walking"
		_anim_backwards = false
		_anim.play(&"Walking", 0.25)
	if _aim:
		_aim.twist = 0.0
	var axis := Vector3(patrol_axis.x, 0, patrol_axis.z).normalized()
	var v := linear_velocity
	var hv := Vector3(v.x, 0, v.z)
	var want := Vector3.ZERO
	if patrol_distance > 0.01:
		var off := (global_position - _spawn_xf.origin).dot(axis)
		if off > patrol_distance * 0.5:
			_dir = -1.0
		elif off < -patrol_distance * 0.5:
			_dir = 1.0
		want = axis * _dir * walk_speed
	# Being dragged around (e.g. by a gravity well): don't fight it.
	if (hv - want).length() < 3.0:
		hv += (want - hv).limit_length(walk_accel * delta)
		linear_velocity = Vector3(hv.x, v.y, hv.z)
	var face := want if want.length_squared() > 0.01 else hv
	if face.length_squared() > 0.04:
		_yaw = lerp_angle(_yaw, atan2(face.x, face.z), clampf(turn_speed * delta, 0.0, 1.0))
		_visual.rotation.y = _yaw
	_anim.speed_scale = clampf(hv.length() / walk_anim_speed, 0.0, 1.6) if patrol_distance > 0.01 else 0.0


# --- Damage ---

func on_projectile_hit(projectile: Node) -> void:
	# Fallback for projectiles that don't send DamageInfo.
	var dir := Vector3.FORWARD
	if projectile is Node3D:
		dir = global_position - (projectile as Node3D).global_position
	apply_damage(DamageInfo.make(1.0, DamageInfo.Type.ENERGY, global_position + Vector3.UP, dir, 5.0, 0.0, projectile))


## Simple-damage entry point (amount + where it came from).
func take_damage(amount: float, from := Vector3.ZERO) -> void:
	var dir := global_position - from if from != Vector3.ZERO else -_visual.global_basis.z
	apply_damage(DamageInfo.make(amount, DamageInfo.Type.GENERIC, from, dir, amount * 2.0))


func apply_damage(info: DamageInfo) -> void:
	if not alive:
		return
	hits += 1
	hit.emit(hits)
	health -= info.damage_amount
	if health <= 0.0:
		die(info)
	elif _skeleton:
		# Wounded: a tiny crackle where it was hit.
		var b := _nearest_bone(info.impact_position)
		JointSparks.play_on_bone(_skeleton, b, 0.35)


func die(info: DamageInfo) -> void:
	if not alive:
		return
	# Back to the separate sections (same skeleton, same pose) so it can
	# break apart.
	_use_section_meshes()
	target = null
	_burst_left = 0
	if _aim:
		_aim.target_weight = 0.0
		_aim.weight = 0.0
		_aim.active = false
	alive = false
	health = 0.0
	if _targetable:
		_targetable.kill()
	# Back to full visual size at once (it may die while shrunk by a well).
	GravityWell.restore_visual(self)
	remove_meta("gw_visuals")
	_visual.transform = Transform3D(Basis(Vector3.UP, _yaw), Vector3.ZERO)
	# No longer an obstacle or something wells can grab; just settle.
	collision_layer = 0
	collision_mask = 1
	physics_material_override.friction = 1.0
	freeze = false
	_dead_t = 0.0
	_settled = false
	# Death reaction: one of the model's clips, or a procedural variation
	# layered on one.
	_anim.speed_scale = 1.0
	_play_death(info)
	# How violently it dies depends on the killing hit.
	last_destruction = _breaker.choose_level(info)
	if last_destruction == BreakApart.Level.NONE:
		_failure_sparks()
	else:
		_schedule_breakup(info)
	died.emit(info)


## Candidate deaths for the killing hit as [key, style, clip, weight].
func _death_options(info: DamageInfo) -> Array:
	var forward := _visual.global_basis.z  # the model faces +Z
	var push := Vector3(info.impact_direction.x, 0, info.impact_direction.z)
	var front := push.length_squared() < 0.01 or push.normalized().dot(forward) < 0.0
	var side := push.length_squared() > 0.01 and absf(push.normalized().dot(forward)) < 0.6
	var force := info.total_force()
	var opts: Array = []
	if info.damage_type == DamageInfo.Type.SUPERNOVA:
		return [["clip_front", "clip", death_anim_from_front, 1.0]]
	if info.damage_type == DamageInfo.Type.ENERGY and _anim.has_animation(death_anim_electric):
		opts.append(["electric", "clip", death_anim_electric, electric_death_chance * 3.0])
	if front:
		opts.append(["clip_front", "clip", death_anim_from_front, 1.0])
		if force >= blown_back_force or info.is_explosive():
			opts.append(["blown_back", "blown_back", death_anim_from_front, 3.0])
		opts.append(["stagger", "stagger", &"Shot_and_Fall_Forward", 1.0 if force < blown_back_force else 0.3])
	else:
		for c in death_anims_from_behind:
			opts.append(["clip_" + String(c), "clip", c, 1.0])
	if side:
		opts.append(["spin", "spin", &"Shot_and_Fall_Forward", 2.0])
	if opts.size() > 1:
		opts = opts.filter(func(o: Array) -> bool: return o[0] != _prev_death)
	return opts.filter(func(o: Array) -> bool: return _anim.has_animation(o[2]))


func _play_death(info: DamageInfo) -> void:
	var opts := _death_options(info)
	if force_death_style != "":
		var forced: Array = [["forced", force_death_style, death_anim_from_front if force_death_style == "blown_back" else &"Shot_and_Fall_Forward", 1.0]]
		opts = forced
	if opts.is_empty():
		opts = [["clip_front", "clip", death_anim_from_front, 1.0]]
	var total := 0.0
	for o in opts:
		total += o[3]
	var r := randf() * total
	var pick: Array = opts[-1]
	for o in opts:
		r -= o[3]
		if r <= 0.0:
			pick = o
			break
	_prev_death = pick[0]
	last_death_style = pick[1]
	last_death_anim = pick[2]
	var push := Vector3(info.impact_direction.x, 0, info.impact_direction.z)
	push = push.normalized() if push.length_squared() > 0.01 else -_visual.global_basis.z
	match last_death_style:
		"blown_back":
			# Launched off its feet: the fall clip from where it loses its
			# footing, sped up, while the body flies back and the torso
			# whips back.
			_anim.play(last_death_anim, 0.06)
			_anim.seek(0.85, true)
			_anim.speed_scale = 1.35
			if not freeze:
				linear_velocity = push * blown_back_speed.x * randf_range(0.85, 1.15) + Vector3.UP * blown_back_speed.y
				linear_damp = 1.2  # lands and skids to a stop, no long slide
			var tw := create_tween()
			tw.tween_property(_visual, "rotation:x", -0.45, 0.12).set_ease(Tween.EASE_OUT)
			tw.tween_property(_visual, "rotation:x", 0.0, 0.5).set_ease(Tween.EASE_IN_OUT)
			tw.tween_callback(func() -> void: _anim.speed_scale = 1.0)
		"spin":
			# Spun round by a hit from the side, then drops.
			_anim.play(last_death_anim, 0.1)
			var turn := signf((-_visual.global_basis.x).dot(push)) * deg_to_rad(spin_degrees) * randf_range(0.85, 1.1)
			if turn == 0.0:
				turn = deg_to_rad(spin_degrees)
			if not freeze:
				linear_velocity = push * 1.6
			var tw := create_tween()
			tw.tween_property(_visual, "rotation:y", _yaw + turn, 0.75).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		"stagger":
			# Staggers a couple of steps backwards, wobbling, then topples.
			_anim.play(&"Walking", 0.1, -0.7, true)
			_stagger_vel = push * 1.3
			var tw := create_tween()
			var wob := randf_range(0.18, 0.3) * (1.0 if randf() < 0.5 else -1.0)
			tw.tween_property(_visual, "rotation:y", _yaw + wob, stagger_time * 0.4).set_trans(Tween.TRANS_SINE)
			tw.tween_property(_visual, "rotation:y", _yaw - wob * 0.6, stagger_time * 0.6).set_trans(Tween.TRANS_SINE)
			get_tree().create_timer(stagger_time, false, true).timeout.connect(func() -> void:
				if is_inside_tree() and not alive and _anim.has_animation(last_death_anim):
					_anim.play(last_death_anim, 0.2)
					_anim.seek(0.55, true))
		_:
			_anim.play(last_death_anim, 0.12)


func _schedule_breakup(info: DamageInfo) -> void:
	var cuts := _breaker.plan(last_destruction, info)
	if cuts.is_empty():
		_failure_sparks()
		return
	var p := clampf(_breaker.power_of(info), 0.0, 1.0)
	var t := lerpf(break_delay.y, break_delay.x, p) * randf_range(0.8, 1.2)
	# Break in a quick cascade (root-most first), in small batches.
	var batch: Array[BreakSection] = []
	var batch_size := maxi(1, cuts.size() / 3)
	for i in cuts.size():
		batch.append(cuts[i])
		if batch.size() >= batch_size or i == cuts.size() - 1:
			var these := batch.duplicate()
			get_tree().create_timer(t, false, true).timeout.connect(func() -> void: _break_now(these, info, cuts))
			batch = []
			t += break_stagger * randf_range(0.5, 1.5)


func _break_now(cuts: Array, info: DamageInfo, planned: Array[BreakSection]) -> void:
	if not is_inside_tree():
		return
	var typed: Array[BreakSection] = []
	typed.assign(cuts)
	_breaker.detach(typed, info, linear_velocity, planned)
	if _breaker.detached_count() >= section_set.sections.size():
		_visual.visible = false


func _failure_sparks() -> void:
	var n := randi_range(failure_sparks.x, failure_sparks.y)
	for i in n:
		# First fizz right as it goes down, the rest scattered after.
		var t := randf_range(0.1, 0.35) if i == 0 else randf_range(0.4, failure_spark_time)
		get_tree().create_timer(t, false, true).timeout.connect(func() -> void:
			if is_inside_tree() and not alive and _skeleton:
				var bones := [&"mixamorig_Head", &"mixamorig_Neck", &"mixamorig_Spine2", &"mixamorig_LeftArm", &"mixamorig_RightArm", &"mixamorig_LeftForeArm", &"mixamorig_RightForeArm"]
				var b := _skeleton.find_bone(bones[randi() % bones.size()])
				JointSparks.play_on_bone(_skeleton, b, randf_range(0.3, 0.5)))


func _nearest_bone(p: Vector3) -> int:
	var best := 0
	var bd := INF
	for i in _skeleton.get_bone_count():
		var d := (_skeleton.global_transform * _skeleton.get_bone_global_pose(i)).origin.distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


# --- Corpse ---

func _corpse(delta: float) -> void:
	_dead_t += delta
	if last_death_style == "stagger" and _dead_t < stagger_time and not freeze:
		# Stagger steps: driven back like walking (friction would stop it).
		linear_velocity = Vector3(_stagger_vel.x, linear_velocity.y, _stagger_vel.z) * (1.0 - _dead_t / stagger_time * 0.5)
		return
	if not _settled:
		var slow := linear_velocity.length() < 0.3
		if (slow and _dead_t > 0.5) or _dead_t > 6.0:
			# Lie still: no physics, and once the clip ends no animation cost.
			_settled = true
			freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			freeze = true
			collision_mask = 0
	if _dead_t >= corpse_time:
		set_physics_process(false)
		var tw := create_tween()
		tw.tween_property(_visual, "position:y", -1.2, 1.5).set_ease(Tween.EASE_IN)
		tw.tween_callback(_cleared)
	elif _settled and _dead_t > 0.5 and not _anim.is_playing():
		# Clip finished: skeleton no longer updates; nothing left to do
		# until the corpse is cleared.
		set_physics_process(false)
		get_tree().create_timer(corpse_time - _dead_t, false, true).timeout.connect(func() -> void:
			if is_inside_tree():
				_dead_t = corpse_time
				set_physics_process(true))


func _cleared() -> void:
	_visual.visible = false
	if respawn_time < 0.0:
		queue_free()
		return
	get_tree().create_timer(respawn_time, false, true).timeout.connect(_respawn)


func _respawn() -> void:
	if not is_inside_tree():
		return
	_visual.queue_free()
	_visual = null
	freeze = false
	collision_layer = _layers
	collision_mask = _mask
	physics_material_override.friction = 0.0
	linear_damp = 0.0
	global_transform = _spawn_xf
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	reset_physics_interpolation()
	alive = true
	health = max_health
	last_destruction = BreakApart.Level.NONE
	_build_model()
	set_physics_process(true)
	if _targetable:
		_targetable.revive()


## Angle (deg) between where the upper body faces and the target (tests).
func upper_body_facing_error() -> float:
	if target == null:
		return 0.0
	var to := target.global_position - global_position
	var chest_yaw := _yaw + (_aim.twist * _aim.weight if _aim else 0.0)
	return absf(rad_to_deg(wrapf(atan2(to.x, to.z) - chest_yaw, -PI, PI)))
