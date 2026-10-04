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

@export_group("Death")
## Death clips (must exist in the model). Picked by the killing hit:
## electrical hits -> electrocuted; otherwise by the hit's direction.
@export var death_anim_electric := &"Electrocuted_Fall"
@export var death_anim_from_front := &"Shot_and_Fall_Backward"
@export var death_anims_from_behind: Array[StringName] = [&"Shot_in_the_Back_and_Fall", &"Shot_and_Fall_Forward"]
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
	_model = MODEL.instantiate()
	_model.name = "Model"
	_visual.add_child(_model)
	# The model's hips sit 0.245 m behind its origin; centre them.
	_model.position = Vector3(0, 0, 0.245)
	_skeleton = _model.find_child("Skeleton3D", true, false) as Skeleton3D
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for a in [&"Walking", &"Running"]:
		if _anim.has_animation(a):
			_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_anim.play(&"Walking")
	_anim.seek(_phase * _anim.current_animation_length, true)
	if _breaker:
		_breaker.queue_free()
	_breaker = BreakApart.new()
	_breaker.name = "BreakApart"
	_breaker.section_set = section_set
	_breaker.skeleton = _skeleton
	add_child(_breaker)
	_yaw = atan2(patrol_axis.x * _dir, patrol_axis.z * _dir)
	_visual.rotation.y = _yaw


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
		_patrol(delta)
	else:
		_corpse(delta)


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
	# Death reaction from the model's own clips.
	last_death_anim = _pick_death_anim(info)
	_anim.speed_scale = 1.0
	_anim.play(last_death_anim, 0.12)
	# How violently it dies depends on the killing hit.
	last_destruction = _breaker.choose_level(info)
	if last_destruction == BreakApart.Level.NONE:
		_failure_sparks()
	else:
		_schedule_breakup(info)
	died.emit(info)


func _pick_death_anim(info: DamageInfo) -> StringName:
	if info.damage_type == DamageInfo.Type.ENERGY and _anim.has_animation(death_anim_electric):
		return death_anim_electric
	var forward := _visual.global_basis.z  # the model faces +Z
	var push := Vector3(info.impact_direction.x, 0, info.impact_direction.z)
	if push.length_squared() < 0.01 or push.normalized().dot(forward) < 0.0:
		return death_anim_from_front  # pushed back -> falls backwards
	return death_anims_from_behind[randi() % death_anims_from_behind.size()]


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
