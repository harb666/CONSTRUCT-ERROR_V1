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

## 0..1: how much of aim_offset is applied (eased towards `aiming`).
var aim_blend := 0.0
var aiming := false

@onready var arm: SpringArm3D = $Arm
@onready var camera: Camera3D = $Arm/Camera3D

var yaw := 0.0
var pitch := 0.0


func _ready() -> void:
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
	_update_transform()


func add_look(radians: Vector2) -> void:
	yaw = wrapf(yaw - radians.x, -PI, PI)
	pitch = clampf(pitch - radians.y, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))


func _process(delta: float) -> void:
	aim_blend = move_toward(aim_blend, 1.0 if aiming else 0.0, delta * aim_offset_rate * 0.5)
	_update_transform()


func _update_transform() -> void:
	if target:
		var offset := Basis(Vector3.UP, yaw) * aim_offset * smoothstep(0.0, 1.0, aim_blend)
		global_position = target.get_global_transform_interpolated().origin + Vector3.UP * height + offset
	rotation = Vector3(pitch, yaw, 0.0)
