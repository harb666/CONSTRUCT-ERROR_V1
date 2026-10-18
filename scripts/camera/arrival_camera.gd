class_name ArrivalCamera
extends Camera3D
## The squad's arrival in the next part of a level (Toxic Works; owner
## asked: "start in a far lower corner and pan round the player before
## smoothly emerging into gameplay"): it starts low in a far corner of the
## hall looking up at the lift coming down through the roof, and as the
## lift comes down it pans round the squad, closing in and rising to them;
## as the lift nears the floor it swoops in behind the local player (who
## faces the laser gate) and hands over to their normal follow camera as
## the lift lands.

@export var lift_path: NodePath = ^"../ElevatorLift"
## Its circle round the lift: the bearing at the start (degrees, from +X
## towards +Z; -60 = the hall's far (+X, -Z) corner by the gate, off the player's
## front right) and how far it pans round while the lift comes down
## (ending behind the player, towards +Z).
@export var orbit_start_deg := -60.0
@export var orbit_sweep_deg := 150.0
## Distance from the lift: from the far corner to close (m).
@export var radius_from := 48.0
@export var radius_to := 9.0
## Height above the hall floor (the lift's landing): from low down to
## looking down on the squad (m).
@export var height_from := 1.6
@export var height_to := 5.0
@export var fov_from := 46.0
@export var fov_to := 54.0
## Never above this (the beams and ducts under the roof, ~21.6 m).
@export var clutter_y := 21.0
## Scenery between it and the squad pulls it in only within this (m).
@export var clear_within := 24.0
## The swoop in to the player's camera (s); it starts so it ends as the
## lift lands.
@export var swoop_time := 2.2
## Finished: the player's camera has taken over.
var done := false
var _rig: CameraRig
var _swoop_t := -1.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fov = fov_from
	far = 800.0


func _lift() -> ElevatorLift:
	return get_node_or_null(lift_path) as ElevatorLift


## How far through the lift's descent (0..1).
func _progress(lift: ElevatorLift) -> float:
	return clampf(lift._t / lift.arrival_time, 0.0, 1.0) if lift.arriving() else 1.0


## The camera's pose at `k` through the descent: from low in the far corner
## round the lift and in, rising, always looking at the squad (or the deck
## before anyone's aboard).
func crane_pose(lift: ElevatorLift, k: float) -> Transform3D:
	var e := k * k * (3.0 - 2.0 * k)
	var a := deg_to_rad(orbit_start_deg + orbit_sweep_deg * e)
	# Comes in quickly at first, then circles close.
	var r := lerpf(radius_from, radius_to, 1.0 - pow(1.0 - k, 2.2))
	var pos := lift._top + Vector3(cos(a), 0.0, sin(a)) * r
	pos.y = minf(lift._top.y + lerpf(height_from, height_to, e), clutter_y - 0.5)
	return Transform3D(Basis.looking_at(_aim(lift) - pos), pos)


func crane_fov(_lift_node: ElevatorLift, k: float) -> float:
	return lerpf(fov_from, fov_to, k)


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
		# (Far off it's only kept clear of scenery once close: it looks up
		# at the squad from across the hall.)
		var near := crane.origin.distance_to(_aim(lift)) < clear_within
		global_transform = _clear_view(crane, _aim(lift), delta) if near else crane
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
## (Up in the roof's shaft, out of sight from the hall: just under the
## roof's beams, where the squad will appear.)
func _aim(lift: ElevatorLift) -> Vector3:
	var at := lift._deck + Vector3.UP * 1.2
	if _rig and is_instance_valid(_rig) and _rig.target:
		at = _rig.target.global_position + Vector3.UP * 1.2
	at.y = minf(at.y, clutter_y)
	return at


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
