class_name PlayerController
extends CharacterBody3D
## Movement for one player. Reads intent only from a PlayerInput node, never
## from global Input, so the same code can run for any local or remote player.

signal jumped(is_air_jump: bool)
signal dodged(direction: Vector3)
## The dodge / slide finished (not cancelled by a jump). on_floor: it ended
## on the ground (feet kick up dust).
signal dodge_ended(direction: Vector3, on_floor: bool)
## impact_speed: downward speed (m/s) just before touching the ground.
signal landed(impact_speed: float)
## Emitted after each movement tick with the command used (weapons etc. hook here).
signal command_processed(cmd: PlayerCommand, delta: float)

@export var player_id := 1
## The character this player picked (HUD name / portrait); null = default.
var character: CharacterDefinition

@export_group("Ground")
## How far the move stick is pushed picks the gait (0..1 after the dead zone):
## a light push walks (up to `walk_speed`), a firmer push runs (`run_min_speed`
## .. `run_speed`) and pushing it (nearly) all the way sprints, for as long as
## it is held there (from `sprint_zone`, until it drops below `sprint_exit`).
## The sprint key (Shift / RT, desktop) also sprints.
@export var walk_speed := 4.0
@export var run_min_speed := 6.2
@export var run_speed := 8.5
@export var sprint_speed := 11.5
@export var walk_zone := 0.5
## Stick span over which walking speeds up into a run (no dead step).
@export var walk_to_run_blend := 0.08
@export var sprint_zone := 0.9
@export var sprint_exit := 0.82
@export var ground_accel := 70.0
@export var ground_decel := 55.0
## Extra acceleration when pushing against current velocity (snappy direction changes).
@export var turnaround_accel := 60.0

@export_group("Air")
@export var air_accel := 32.0
@export var air_decel := 6.0

@export_group("Jump")
@export var jump_height := 1.9
@export var air_jump_height := 1.5
@export var time_to_apex := 0.36
@export var fall_gravity_multiplier := 1.6
## Gravity multiplier while rising with jump released (>1 = variable jump height).
## Off by default: fixed-height jumps are more consistent with touch buttons.
@export var jump_release_gravity_multiplier := 1.0
@export var max_fall_speed := 40.0
@export var max_air_jumps := 1
@export var coyote_time := 0.1
@export var jump_buffer_time := 0.12

@export_group("Dodge")
@export var dodge_speed := 17.0
@export var dodge_duration := 0.34
@export var dodge_cooldown := 0.45
@export var max_air_dodges := 1

@export_group("Rotation")
## Higher = snappier facing. Exponential smoothing rate.
@export var turn_rate := 16.0
## Facing speed while aiming/shooting.
@export var aim_turn_rate := 22.0

var input: PlayerInput
var spawn_transform: Transform3D

var is_sprinting := false
var is_dodging := false
## Sprint held by pushing the stick all the way (hysteresis, see sprint_exit).
var _stick_sprint := false

var _gravity := 0.0
var _jump_velocity := 0.0
var _air_jump_velocity := 0.0
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _air_jumps_left := 0
var _air_dodges_left := 0
var _dodge_timer := 0.0
var _dodge_cooldown_timer := 0.0
var _dodge_dir := Vector3.FORWARD
var _was_on_floor := true
var _aim_face_timer := 0.0
var _idle_face_timer := 0.0

## Velocity from outside forces (gravity wells, blasts), added on top of the
## player's own movement so input, jumping and escaping always still work.
## Zero normally; decays when nothing keeps pushing.
## Hits taken. Armour soaks damage before health; at 0 health the player
## respawns at spawn with full health.
signal damaged(info: DamageInfo)
## Health or armour changed (damage, pickups, respawn).
signal vitals_changed
signal died
## Back at the spawn point (after dying or falling out of the level).
signal respawned
var damage_taken := 0.0

@export_group("Health")
@export var max_health := 100.0
@export var max_armour := 100.0
## Armour on spawn/respawn.
@export var start_armour := 0.0
## Share of each hit armour absorbs while it lasts (1 = all of it).
@export_range(0.0, 1.0) var armour_absorb := 1.0
## Enemy weapon damage is in robot-health units (a robot has 1.4-2); this
## turns it into player HP (grunt bolt 1.0 -> 5 HP).
@export var incoming_damage_scale := 5.0
## Off = hits only count and flash (the old behaviour).
@export var can_die := true
@export_group("")
var health := 100.0
var armour := 0.0


## Target ground speed for a stick push of `amount` (0..1): walk, run or sprint.
func gait_speed(amount: float, sprinting: bool) -> float:
	if amount <= 0.001:
		return 0.0
	if sprinting:
		return sprint_speed
	if amount <= walk_zone:
		return walk_speed * amount / walk_zone
	var blend_end := walk_zone + walk_to_run_blend
	if amount <= blend_end:
		return lerpf(walk_speed, run_min_speed, (amount - walk_zone) / walk_to_run_blend)
	return lerpf(run_min_speed, run_speed, clampf((amount - blend_end) / maxf(sprint_zone - blend_end, 0.01), 0.0, 1.0))


## Called by enemy weapons (DamageInfo.apply).
func apply_damage(info: DamageInfo) -> void:
	damage_taken += info.damage_amount
	# The player's own black hole never hurts them (it never did).
	if info.damage_type != DamageInfo.Type.SUPERNOVA and info.source != self:
		var amount := info.damage_amount * incoming_damage_scale
		var soak := minf(armour, amount * armour_absorb)
		armour -= soak
		health = maxf(health - (amount - soak), 0.0)
		vitals_changed.emit()
	damaged.emit(info)
	if can_die and health <= 0.0:
		died.emit()
		respawn()


## Pickups: add up to the maximum. Returns how much was actually added.
func heal(amount: float) -> float:
	var add := clampf(amount, 0.0, max_health - health)
	health += add
	if add > 0.0:
		vitals_changed.emit()
	return add


func add_armour(amount: float) -> float:
	var add := clampf(amount, 0.0, max_armour - armour)
	armour += add
	if add > 0.0:
		vitals_changed.emit()
	return add


## Pistol-cannon punch-shot (PlayerMelee): while it plays it drives the
## lunge and facing; movement input, jumps and dodges wait.
var melee: PlayerMelee
var external_velocity := Vector3.ZERO
@export var external_decay := 5.0
## Sideways speed (m/s per frame of contact) given to a black-hole-pulled
## prop the player is pressed against, so it can't pin them.
@export var pulled_prop_shove := 1.5
var _idle_face_yaw := 0.0
var _fall_speed := 0.0


func _ready() -> void:
	health = max_health
	armour = minf(start_armour, max_armour)
	if get_node_or_null("Melee") == null:
		melee = PlayerMelee.new()
		melee.name = "Melee"
		add_child(melee)
	else:
		melee = get_node("Melee") as PlayerMelee
	if get_node_or_null("PerfectDodge") == null:
		var pd := PerfectDodge.new()
		pd.name = "PerfectDodge"
		add_child(pd)
	_gravity = 2.0 * jump_height / (time_to_apex * time_to_apex)
	_jump_velocity = _gravity * time_to_apex
	_air_jump_velocity = sqrt(2.0 * _gravity * air_jump_height)
	spawn_transform = global_transform
	_air_jumps_left = max_air_jumps
	_air_dodges_left = max_air_dodges


func _physics_process(delta: float) -> void:
	var cmd := input.get_command() if input else PlayerCommand.new()
	simulate(cmd, delta)
	command_processed.emit(cmd, delta)


## Advance this player by one tick. Kept self-contained so it can later be
## re-run for client-side prediction / server reconciliation.
func simulate(cmd: PlayerCommand, delta: float) -> void:
	var on_floor := is_on_floor()

	# --- timers ---
	_dodge_cooldown_timer = maxf(_dodge_cooldown_timer - delta, 0.0)
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	if on_floor:
		_coyote_timer = coyote_time
		_air_jumps_left = max_air_jumps
		_air_dodges_left = max_air_dodges
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)
	if cmd.jump_pressed:
		_jump_buffer_timer = jump_buffer_time

	# --- melee ---
	if melee:
		if cmd.melee_pressed and not is_dodging and on_floor:
			melee.try_start()
		melee.tick(delta)
	var meleeing := melee != null and melee.active
	if meleeing:
		_jump_buffer_timer = 0.0

	# --- wish direction (camera relative) ---
	var stick := cmd.move.limit_length(1.0)
	var wish := Vector3(stick.x, 0.0, stick.y).rotated(Vector3.UP, cmd.view_yaw)
	var wish_amount := wish.length()
	var wish_dir := wish / wish_amount if wish_amount > 0.001 else Vector3.ZERO

	if wish_amount >= sprint_zone:
		_stick_sprint = true
	elif wish_amount < sprint_exit:
		_stick_sprint = false
	is_sprinting = (cmd.sprint_held or _stick_sprint) and wish_amount > 0.1

	# --- dodge start ---
	if cmd.dodge_pressed and not meleeing and not is_dodging and _dodge_cooldown_timer <= 0.0 and (on_floor or _air_dodges_left > 0):
		_start_dodge(wish_dir, on_floor)

	# --- jump (cancels a dodge, keeping its momentum) ---
	if _jump_buffer_timer > 0.0:
		if on_floor or _coyote_timer > 0.0:
			_do_jump(_jump_velocity, false)
		elif _air_jumps_left > 0:
			_air_jumps_left -= 1
			_do_jump(_air_jump_velocity, true)

	# --- horizontal velocity ---
	var horiz := Vector2(velocity.x, velocity.z)
	if meleeing:
		horiz = melee.lunge
	elif is_dodging:
		_dodge_timer -= delta
		horiz = Vector2(_dodge_dir.x, _dodge_dir.z) * dodge_speed
		if _dodge_timer <= 0.0:
			is_dodging = false
			dodge_ended.emit(_dodge_dir, on_floor)
	else:
		var target := Vector2(wish_dir.x, wish_dir.z) * gait_speed(wish_amount, is_sprinting)
		var rate: float
		if on_floor:
			rate = ground_accel if wish_amount > 0.0 else ground_decel
			if wish_amount > 0.0 and horiz.dot(target) < 0.0:
				rate += turnaround_accel
		else:
			rate = air_accel if wish_amount > 0.0 else air_decel
		horiz = horiz.move_toward(target, rate * delta)
	velocity.x = horiz.x
	velocity.z = horiz.y

	# --- gravity ---
	if is_dodging and not on_floor:
		velocity.y = 0.0  # flat air dash
	elif not on_floor:
		var g := _gravity
		if velocity.y < 0.0:
			g *= fall_gravity_multiplier
		elif not cmd.jump_held:
			g *= jump_release_gravity_multiplier
		velocity.y = maxf(velocity.y - g * delta, -max_fall_speed)

	if not on_floor:
		_fall_speed = maxf(-velocity.y, 0.0)
	var ext := external_velocity
	velocity += ext
	move_and_slide()
	velocity -= ext
	_shove_pulled_props()
	if ext != Vector3.ZERO:
		if is_on_wall():
			external_velocity = external_velocity.slide(get_wall_normal())
		if is_on_floor() and external_velocity.y < 0.0:
			external_velocity.y = 0.0
		external_velocity = external_velocity.move_toward(Vector3.ZERO, external_decay * delta)

	# --- facing ---
	_aim_face_timer = maxf(_aim_face_timer - delta, 0.0)
	if meleeing:
		# Squared up to the enemy it's punching.
		rotation.y = lerp_angle(rotation.y, melee.face_yaw, 1.0 - exp(-40.0 * delta))
	elif _aim_face_timer > 0.0 and not is_dodging:
		# Shooting: face the camera's aim and strafe.
		rotation.y = lerp_angle(rotation.y, cmd.view_yaw, 1.0 - exp(-aim_turn_rate * delta))
	else:
		var face_dir := _dodge_dir if is_dodging else wish_dir
		if face_dir != Vector3.ZERO:
			var target_yaw := atan2(-face_dir.x, -face_dir.z)
			rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_rate * delta))
		elif _idle_face_timer > 0.0:
			# Standing still with a locked target: turn to face it.
			rotation.y = lerp_angle(rotation.y, _idle_face_yaw, 1.0 - exp(-turn_rate * 0.6 * delta))
	_idle_face_timer = maxf(_idle_face_timer - delta, 0.0)

	var now_on_floor := is_on_floor()
	if now_on_floor and not _was_on_floor:
		landed.emit(_fall_speed)
	_was_on_floor = now_on_floor

	if global_position.y < -30.0:
		respawn()


## A prop a black hole is dragging can be pressed into the player and pin
## them (the character can't push rigid bodies): when the player is moving
## into one that's being pulled right now, it's knocked aside out of the way.
func _shove_pulled_props() -> void:
	var move := Vector3(velocity.x, 0.0, velocity.z)
	if move.length_squared() < 1.0:
		return
	var dir := move.normalized()
	var frame := Engine.get_physics_frames()
	for k in get_slide_collision_count():
		var c := get_slide_collision(k)
		var b := c.get_collider() as RigidBody3D
		if b == null or b.freeze or b.is_in_group(&"enemies") or frame - int(b.get_meta(&"gw_pulled_frame", -100)) > 2:
			continue
		var n := c.get_normal()
		n.y = 0.0
		if n.length_squared() < 1e-4 or dir.dot(-n.normalized()) < 0.3:
			continue  # not in the way
		var off := b.global_position - global_position
		off.y = 0.0
		var side := off - dir * off.dot(dir)
		if side.length_squared() < 1e-4:
			side = dir.cross(Vector3.UP)
		b.linear_velocity += side.normalized() * pulled_prop_shove


## Face the aim direction (camera yaw) for `seconds`, e.g. while shooting.
func face_aim_for(seconds: float) -> void:
	_aim_face_timer = maxf(_aim_face_timer, seconds)


## Gravity-well pull: horizontal velocity added on top of movement, capped.
func apply_gravity_pull(dv: Vector3, max_speed: float) -> void:
	var add := Vector3(dv.x, 0.0, dv.z)
	external_velocity = (external_velocity + add).limit_length(maxf(max_speed, external_velocity.length()))


## One-off shove (e.g. supernova): capped, decays naturally.
func apply_external_impulse(v: Vector3) -> void:
	external_velocity = (external_velocity + Vector3(v.x, 0.0, v.z)).limit_length(16.0)
	if v.y > 0.0 and is_on_floor():
		velocity.y = maxf(velocity.y, v.y)


## While standing still (no move input), turn towards `yaw`.
func face_yaw_when_idle(yaw: float) -> void:
	_idle_face_yaw = yaw
	_idle_face_timer = 0.1


func is_facing_yaw(yaw: float, tolerance: float) -> bool:
	return absf(wrapf(rotation.y - yaw, -PI, PI)) <= tolerance


func _start_dodge(wish_dir: Vector3, on_floor: bool) -> void:
	var dir := wish_dir
	if dir == Vector3.ZERO:
		dir = -global_basis.z
		dir.y = 0.0
		dir = dir.normalized()
	_dodge_dir = dir
	is_dodging = true
	_dodge_timer = dodge_duration
	_dodge_cooldown_timer = dodge_cooldown
	if not on_floor:
		_air_dodges_left -= 1
	# Face the dodge direction instantly so the roll reads correctly.
	rotation.y = atan2(-dir.x, -dir.z)
	dodged.emit(dir)


func _do_jump(jump_velocity: float, is_air_jump: bool) -> void:
	velocity.y = jump_velocity
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	is_dodging = false
	jumped.emit(is_air_jump)


func respawn() -> void:
	if melee:
		melee.cancel()
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	is_dodging = false
	reset_physics_interpolation()
	health = max_health
	armour = minf(start_armour, max_armour)
	vitals_changed.emit()
	respawned.emit()
	RecoveryDrops.clear_all(get_tree())
