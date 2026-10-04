class_name DebrisPiece
extends RigidBody3D
## A detached body section flying free. Keeps its exact posed look (its
## meshes stay skinned to a frozen copy of the skeleton, `pose`), collides
## with simple box shapes, and is kept physically calm: launch, spin and
## bounce are clamped, freshly separated pieces ignore each other briefly,
## settled pieces are frozen (no ongoing cost), and old pieces shrink away.

const DEBRIS_LAYER := 4  # physics layer 3 "debris"

## Max debris pieces alive at once (mobile); the oldest go first.
static var max_active := 36
static var _active: Array[DebrisPiece] = []

@export var max_linear_speed := 16.0
@export var max_angular_speed := 14.0
## Seconds before freshly detached pieces collide with each other.
@export var self_collision_delay := 0.4
## Settled for this long (slow) -> frozen solid, no further processing.
@export var settle_time := 1.5
@export var settle_speed := 0.25
## Seconds before the piece shrinks away and is removed.
@export var lifetime := 20.0
@export var despawn_time := 0.6

## Frozen skeleton the meshes are skinned to (child of this body).
var pose: Skeleton3D
## Section it broke off at (with any children that came along).
var section: StringName
var _age := 0.0
var _slow_t := 0.0
var _despawning := false


func _init() -> void:
	collision_layer = DEBRIS_LAYER
	collision_mask = 1  # world/props only at first
	continuous_cd = false
	can_sleep = true
	linear_damp = 0.05
	angular_damp = 0.6
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.12
	pm.friction = 0.9
	physics_material_override = pm


func _ready() -> void:
	_active.append(self)
	while _active.size() > max_active:
		var old: DebrisPiece = _active.pop_front()
		if is_instance_valid(old) and old != self:
			old.despawn()
	get_tree().create_timer(self_collision_delay, false, true).timeout.connect(func() -> void:
		if is_instance_valid(self) and not _despawning:
			collision_mask |= DEBRIS_LAYER)


func _exit_tree() -> void:
	_active.erase(self)


static func active_count() -> int:
	return _active.size()


## Launch: velocities are clamped here and every physics tick after.
func launch(v: Vector3, w: Vector3) -> void:
	linear_velocity = v.limit_length(max_linear_speed)
	angular_velocity = w.limit_length(max_angular_speed)


func _physics_process(delta: float) -> void:
	_age += delta
	if not freeze:
		# Never let contacts pump energy in.
		if linear_velocity.length_squared() > max_linear_speed * max_linear_speed:
			linear_velocity = linear_velocity.limit_length(max_linear_speed)
		if angular_velocity.length_squared() > max_angular_speed * max_angular_speed:
			angular_velocity = angular_velocity.limit_length(max_angular_speed)
		if linear_velocity.length() < settle_speed and angular_velocity.length() < settle_speed * 2.0:
			_slow_t += delta
			if _slow_t > settle_time:
				# Resting: make it static and stop processing until despawn.
				freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
				freeze = true
				set_physics_process(false)
				get_tree().create_timer(maxf(lifetime - _age, 0.1), false, true).timeout.connect(despawn)
				return
		else:
			_slow_t = 0.0
	if _age > lifetime:
		despawn()


func despawn() -> void:
	if _despawning or not is_inside_tree():
		return
	_despawning = true
	_active.erase(self)
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	freeze = true
	var tw := create_tween()
	if pose:
		tw.tween_property(pose, "scale", pose.scale * 0.01, despawn_time).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
