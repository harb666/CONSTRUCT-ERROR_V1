class_name CameraRig
extends Node3D
## Third-person orbit camera for one local player. Follows a target and owns
## the view yaw/pitch that movement is made relative to.

@export var target: Node3D
@export var height := 1.35
@export var distance := 3.9
@export var pitch_min_deg := -70.0
@export var pitch_max_deg := 45.0
@export var start_pitch_deg := -14.0
## Over-the-shoulder offset used while armed (x = right, in camera yaw space),
## so the character doesn't sit on the crosshair.
@export var aim_offset := Vector3(-0.65, 0.15, 0.0)
@export var aim_offset_rate := 6.0

## Recoil camera impulse: short push back + decaying shake + FOV pop.
## Never touches yaw/pitch, so aiming isn't disturbed.
@export var kick_push := 0.35
@export var kick_shake := 0.07
@export var kick_fov := 6.0
@export var kick_time := 0.24

## Melee: the camera swings a little round to the side and closer in while
## the punch plays, and is back in place by the end (aim yaw untouched).
@export var melee_yaw := 0.3
@export var melee_pitch := -0.06
@export var melee_close := 0.85
## Impact: a quick zoom-in punch (FOV), no shake.
@export var melee_impact_fov := 9.0
@export var melee_impact_time := 0.22
var _melee_t := 99.0
var _melee_len := 0.0
var _melee_hit_t := 99.0
var _kick_t := 99.0
var _kick_strength := 0.0
var _base_fov := 75.0

## 0..1: how much of aim_offset is applied (eased towards `aiming`).
var aim_blend := 0.0
var aiming := false

@onready var arm: SpringArm3D = $Arm
@onready var camera: Camera3D = $Arm/Camera3D

var yaw := 0.0
var pitch := 0.0


func _ready() -> void:
	add_to_group("camera_rigs")
	top_level = true
	# Moved every rendered frame from the target's interpolated transform,
	# so it must not be physics-interpolated itself.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	pitch = deg_to_rad(start_pitch_deg)
	arm.spring_length = distance
	if target:
		yaw = target.global_rotation.y
		if target is CollisionObject3D:
			arm.add_excluded_object(target.get_rid())
	camera.current = true
	_base_fov = camera.fov
	_update_transform()


func add_look(radians: Vector2) -> void:
	yaw = wrapf(yaw - radians.x, -PI, PI)
	pitch = clampf(pitch - radians.y, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))


## Supernova: strong but brief kick, fading with distance to the blast.
func supernova_feedback(at: Vector3, radius: float) -> void:
	if target == null:
		return
	var d := target.global_position.distance_to(at)
	var s := clampf(1.6 - d / (radius * 2.5), 0.0, 1.4)
	if s > 0.05:
		kick(s)


func melee_camera(length: float) -> void:
	_melee_t = 0.0
	_melee_len = maxf(length, 0.1)


func melee_impact() -> void:
	_melee_hit_t = 0.0


## 0..1 swing of the melee camera (eases out and back in time).
func melee_amount() -> float:
	if _melee_t >= _melee_len:
		return 0.0
	var k := _melee_t / _melee_len
	return smoothstep(0.0, 0.3, k) * (1.0 - smoothstep(0.62, 1.0, k))


func kick(strength := 1.0) -> void:
	_kick_t = 0.0
	_kick_strength = strength


func _process(delta: float) -> void:
	aim_blend = move_toward(aim_blend, 1.0 if aiming else 0.0, delta * aim_offset_rate * 0.5)
	_melee_t += delta
	_melee_hit_t += delta
	_update_transform()
	_kick_t += delta
	if _kick_t < kick_time:
		var k := 1.0 - _kick_t / kick_time
		var punch := k * k * _kick_strength
		# Push back via the spring arm (keeps its wall collision), shake via
		# the camera's view offsets, plus a short FOV pop.
		arm.spring_length = distance + kick_push * punch
		camera.h_offset = randf_range(-1, 1) * kick_shake * punch
		camera.v_offset = randf_range(-1, 1) * kick_shake * punch
		camera.fov = _base_fov + kick_fov * punch
	elif _melee_t < _melee_len or _melee_hit_t < melee_impact_time:
		var m := melee_amount()
		arm.spring_length = distance - melee_close * m
		var hk := 1.0 - clampf(_melee_hit_t / melee_impact_time, 0.0, 1.0)
		camera.fov = _base_fov - melee_impact_fov * hk * hk
	elif camera.h_offset != 0.0 or camera.fov != _base_fov or arm.spring_length != distance:
		arm.spring_length = distance
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		camera.fov = _base_fov


func _update_transform() -> void:
	if target:
		var offset := Basis(Vector3.UP, yaw) * aim_offset * smoothstep(0.0, 1.0, aim_blend)
		global_position = target.get_global_transform_interpolated().origin + Vector3.UP * height + offset
	var m := melee_amount()
	rotation = Vector3(pitch + melee_pitch * m, yaw + melee_yaw * m, 0.0)
