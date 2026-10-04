class_name PlayerController
extends CharacterBody3D
## Movement for one player. Reads intent only from a PlayerInput node, never
## from global Input, so the same code can run for any local or remote player.

signal jumped(is_air_jump: bool)
signal dodged(direction: Vector3)
## impact_speed: downward speed (m/s) just before touching the ground.
signal landed(impact_speed: float)
## Emitted after each movement tick with the command used (weapons etc. hook here).
signal command_processed(cmd: PlayerCommand, delta: float)

@export var player_id := 1

@export_group("Ground")
@export var walk_speed := 7.5
@export var sprint_speed := 11.5
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
@export var dodge_speed := 19.0
@export var dodge_duration := 0.24
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
var _idle_face_yaw := 0.0
var _fall_speed := 0.0


func _ready() -> void:
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

	# --- wish direction (camera relative) ---
	var stick := cmd.move.limit_length(1.0)
	var wish := Vector3(stick.x, 0.0, stick.y).rotated(Vector3.UP, cmd.view_yaw)
	var wish_amount := wish.length()
	var wish_dir := wish / wish_amount if wish_amount > 0.001 else Vector3.ZERO

	is_sprinting = cmd.sprint_held and wish_amount > 0.1

	# --- dodge start ---
	if cmd.dodge_pressed and not is_dodging and _dodge_cooldown_timer <= 0.0 and (on_floor or _air_dodges_left > 0):
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
	if is_dodging:
		_dodge_timer -= delta
		horiz = Vector2(_dodge_dir.x, _dodge_dir.z) * dodge_speed
		if _dodge_timer <= 0.0:
			is_dodging = false
	else:
		var speed := sprint_speed if is_sprinting else walk_speed
		var target := Vector2(wish.x, wish.z) * speed
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
	move_and_slide()

	# --- facing ---
	_aim_face_timer = maxf(_aim_face_timer - delta, 0.0)
	if _aim_face_timer > 0.0 and not is_dodging:
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


## Face the aim direction (camera yaw) for `seconds`, e.g. while shooting.
func face_aim_for(seconds: float) -> void:
	_aim_face_timer = maxf(_aim_face_timer, seconds)


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
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	is_dodging = false
	reset_physics_interpolation()
