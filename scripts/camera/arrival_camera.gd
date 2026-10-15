class_name ArrivalCamera
extends Camera3D
## The squad's arrival in the next part of a level (owner asked, Toxic
## Works: "start panned out in a corner then zooms behind the player", then
## "a bit closer but still a dynamic, amazing level opening"): it rides down
## the shaft just above the squad, breaks out through the roof with them and
## pulls out into a crane shot circling the lift as it comes down; as the
## lift nears the floor it swoops in behind the local player and hands over
## to their normal follow camera as the lift lands.

@export var lift_path: NodePath = ^"../ElevatorLift"
## The crane's circle round the shaft: its angle at the start (degrees,
## from +X towards +Z; 45 = towards the hall's (+X, +Z) corner) and how far
## it turns while the lift comes down.
@export var orbit_start_deg := 45.0
@export var orbit_sweep_deg := 100.0
## Distance from the shaft: from wide to close as it comes down (m).
@export var radius_from := 11.0
@export var radius_to := 9.0
## Height above the deck (m): always looking down on the squad.
@export var height_from := 3.5
@export var height_to := 6.0
@export var fov_from := 60.0
@export var fov_to := 52.0
## In the shaft: how far above the deck and out from its centre the camera
## rides (m; the shaft is 5.6 m in radius), and its wider lens.
@export var ride_height := 3.0
@export var ride_out := 3.2
@export var ride_fov := 70.0
## The beams and ducts under the roof hang down to ~21.6 m: the camera
## stays in the shaft's column until it's below `clutter_y`, pulls out
## while it comes down to `pulled_y`, and never goes above `clutter_y` out
## in the hall (m).
@export var clutter_y := 21.0
@export var pulled_y := 15.5
## The swoop in to the player's camera (s); it starts so it ends as the
## lift lands.
@export var swoop_time := 1.8
## Finished: the player's camera has taken over.
var done := false
var _rig: CameraRig
var _swoop_t := -1.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fov = ride_fov
	far = 800.0


func _lift() -> ElevatorLift:
	return get_node_or_null(lift_path) as ElevatorLift


## How far through the lift's descent (0..1).
func _progress(lift: ElevatorLift) -> float:
	return clampf(lift._t / lift.arrival_time, 0.0, 1.0) if lift.arriving() else 1.0


## How far out of the shaft's column (0 riding it, 1 on the crane's circle).
func _out(lift: ElevatorLift) -> float:
	return 1.0 - smoothstep(pulled_y, clutter_y, lift._deck.y + ride_height)


## The camera's pose at `k` through the descent: riding the shaft above the
## squad, then pulled out onto the crane's circle round the shaft (under
## the ceiling's beams), always looking at the squad (or the deck before
## anyone's aboard).
func crane_pose(lift: ElevatorLift, k: float) -> Transform3D:
	var e := k * k * (3.0 - 2.0 * k)
	var a := deg_to_rad(orbit_start_deg + orbit_sweep_deg * e)
	var out := Vector3(cos(a), 0.0, sin(a))
	var b := _out(lift)
	var pos := lift._top + out * lerpf(ride_out, lerpf(radius_from, radius_to, e), b)
	var y := lift._deck.y + lerpf(ride_height, lerpf(height_from, height_to, e), b)
	pos.y = lerpf(y, minf(y, clutter_y - 0.5), b)
	return Transform3D(Basis.looking_at(_aim(lift) - pos), pos)


## The lens: wide in the shaft, then the crane's.
func crane_fov(lift: ElevatorLift, k: float) -> float:
	return lerpf(ride_fov, lerpf(fov_from, fov_to, k), _out(lift))


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
	if not current:
		make_current()
	var k := _progress(lift)
	var crane := crane_pose(lift, k)
	if _swoop_t < 0.0:
		global_transform = _clear_view(crane, _aim(lift), delta)
		fov = crane_fov(lift, k)
		var left := lift.arrival_time - lift._t if lift.arriving() else 0.0
		if left <= swoop_time:
			_swoop_t = 0.0
		return
	# The swoop: eased from the crane (still moving) to the player's camera
	# (riding down with them), always on the player; the last part turns to
	# the player's camera's own view, which then takes over.
	_swoop_t += delta
	var s := clampf(_swoop_t / swoop_time, 0.0, 1.0)
	var e := s * s * (3.0 - 2.0 * s)
	# Round the player, not over them: the camera's bearing, distance and
	# height from the player each ease from the crane's to their camera's.
	var to := _rig.camera.global_transform
	var aim := _aim(lift)
	var a := crane.origin - aim
	var b := to.origin - aim
	var ha := Vector2(a.x, a.z)
	var hb := Vector2(b.x, b.z)
	var ang := lerp_angle(ha.angle(), hb.angle(), e)
	var pos := aim + Vector3(cos(ang), 0.0, sin(ang)) * lerpf(ha.length(), hb.length(), e) + Vector3.UP * lerpf(a.y, b.y, e)
	var watch := crane.basis
	if pos.distance_to(aim) > 0.5:
		watch = Basis.looking_at(aim - pos)
	var view := Transform3D(watch.slerp(to.basis.orthonormalized(), smoothstep(0.6, 1.0, s)).orthonormalized(), pos)
	global_transform = _clear_view(view, aim, delta) if s < 0.9 else view
	fov = lerpf(crane_fov(lift, k), _rig.camera.fov, e)
	if s >= 1.0 and not lift.arriving():
		_finish()


## What the camera looks at: the local player (or the deck before anyone's
## aboard).
func _aim(lift: ElevatorLift) -> Vector3:
	if _rig and is_instance_valid(_rig) and _rig.target:
		return _rig.target.global_position + Vector3.UP * 1.2
	return lift._deck + Vector3.UP * 1.2


## Never behind scenery (a pipe, a column...): pulled in towards what it's
## looking at, quickly, and let back out gently, like the player's camera.
var _reach := INF


func _clear_view(xf: Transform3D, aim: Vector3, delta: float) -> Transform3D:
	var full := aim.distance_to(xf.origin)
	if full < 0.5:
		return xf
	var q := PhysicsRayQueryParameters3D.create(aim, xf.origin, 1)
	var skip: Array[RID] = []
	for n in get_tree().get_nodes_in_group(&"players"):
		if n is CollisionObject3D:
			skip.append((n as CollisionObject3D).get_rid())
	var lift := _lift()
	if lift:
		skip.append(lift.get_rid())
	q.exclude = skip
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var allowed := full
	if not hit.is_empty():
		allowed = maxf(aim.distance_to(hit["position"]) - 0.4, 0.8)
	_reach = allowed if allowed < _reach else minf(move_toward(_reach, allowed, delta * 6.0), full)
	if _reach >= full:
		return xf
	return Transform3D(xf.basis, aim + (xf.origin - aim).normalized() * _reach)


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
