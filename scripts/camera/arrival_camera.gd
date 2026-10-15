class_name ArrivalCamera
extends Camera3D
## The squad's arrival in the next part of a level (owner asked, Toxic
## Works): the view starts pulled back in a corner of the hall, watching
## the lift come down through the roof, then swoops in behind the local
## player and hands over to their normal follow camera as the lift lands.

@export var lift_path: NodePath = ^"../ElevatorLift"
## Where the wide shot is taken from (a corner of the hall, up high).
@export var corner := Vector3(42, 21, 40)
## The swoop in to the player's camera (s); it starts so it ends as the
## lift lands.
@export var swoop_time := 1.8
## Still looking around the hall after the swoop starts?
var done := false
var _rig: CameraRig
var _swoop_t := -1.0
var _from: Transform3D


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fov = 62.0
	far = 800.0


func _lift() -> ElevatorLift:
	return get_node_or_null(lift_path) as ElevatorLift


func _process(delta: float) -> void:
	if done:
		return
	var lift := _lift()
	if lift == null or not lift.arrival:
		_finish()
		return
	if _rig == null or not is_instance_valid(_rig):
		_rig = _local_rig()
		if _rig == null:
			return  # nobody here yet (character select)
	if _swoop_t < 0.0:
		# The wide shot: from the corner, following the lift down.
		global_position = corner
		look_at(lift.global_position + Vector3.UP * 1.2)
		if not current:
			make_current()
		var left := lift.arrival_time - lift._t if lift.arriving() else 0.0
		if left <= swoop_time:
			_swoop_t = 0.0
			_from = global_transform
		return
	# The swoop: eased from the corner to the player's camera (which keeps
	# moving with the lift), always looking at the player; the last part
	# turns to the player's camera's own view, which then takes over.
	_swoop_t += delta
	var k := clampf(_swoop_t / swoop_time, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	var to := _rig.camera.global_transform
	var pos := _from.origin.lerp(to.origin, e)
	var aim := (_rig.target as Node3D).global_position + Vector3.UP * 1.0
	var watch := _from.basis
	if pos.distance_to(aim) > 0.5:
		watch = Basis.looking_at(aim - pos)
	var turn := smoothstep(0.6, 1.0, k)
	var face := _from.basis.slerp(watch, smoothstep(0.0, 0.25, k))
	global_transform = Transform3D(face.slerp(to.basis.orthonormalized(), turn).orthonormalized(), pos)
	fov = lerpf(62.0, _rig.camera.fov, e)
	if k >= 1.0 and not lift.arriving():
		_finish()


func _local_rig() -> CameraRig:
	for r in get_tree().get_nodes_in_group(&"camera_rigs"):
		var rig := r as CameraRig
		if rig and rig.target and rig.target.is_in_group(&"local_player"):
			return rig
	return null


func _finish() -> void:
	done = true
	if _rig and is_instance_valid(_rig):
		_rig.camera.make_current()
	queue_free()
