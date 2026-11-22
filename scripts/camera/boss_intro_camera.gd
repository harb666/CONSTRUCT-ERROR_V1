class_name BossIntroCamera
extends Camera3D
## Assembly Ascent's mini boss arriving (owner asked: "make sure the mini
## boss comes down on lift ... make it epic"): as the boss lift brings the
## robot boss down its shaft through the roof, this shot takes over the view
## of each player near the showcase deck - a crane shot from the player's
## side, level with the car as it comes out of the roof with the boss
## standing on it (from below, the car hid it), circling slowly, closing in
## and coming down with it to low on the deck looking up at the boss. It
## lands, stamps (its stomp:
## shockwave, the owner's stomp sound), the view punches in, holds, then
## swoops back to the player's own camera. While it shows, the player's
## controls are held (as riding a lift) and nothing hurts them.

## The level (its boss lift's state: `boss_lift_progress`, `boss_car_top`).
var level: AssemblyAscent
## The shaft's centre at the showcase deck's height.
var center := Vector3.ZERO
## A crane shot (m): its distance from the shaft at the start / landing,
## how far above the car's deck it rides (so the boss standing on it is in
## view all the way down - from below, the car hid it), never above
## `max_y` (under the roof) nor below `low` over the showcase deck, and how
## far it circles (deg) as the car comes down.
@export var radius_from := 24.0
@export var radius_to := 15.0
@export var above_car := 1.2
@export var max_y := 29.0
@export var low := 1.4
@export var orbit_deg := 32.0
@export var fov_from := 58.0
@export var fov_to := 50.0
## The boss's chest above the car's deck (the boss is ~7 m tall).
@export var aim_up := 3.6
## After it lands: held on the boss (its stomp), then the swoop back (s).
@export var hold_after := 1.8
@export var swoop_time := 1.3
var done := false
var _rig: CameraRig
var _player: PlayerController
var _bearing := 0.0
var _landed_t := -1.0
var _swoop_t := -1.0
var _damage_scale := 1.0
var _kick := 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fov = fov_from
	far = 800.0
	_rig = _local_rig()
	_player = _rig.target as PlayerController if _rig else null
	if _rig == null or _player == null:
		queue_free()
		done = true
		return
	# From the shaft towards the player: the player's side of the deck, them
	# in the foreground.
	var off := _player.global_position - center
	_bearing = atan2(off.z, off.x) if Vector2(off.x, off.z).length() > 0.5 else PI * 0.5
	_player.controls_locked = true
	_damage_scale = _player.incoming_damage_scale
	_player.incoming_damage_scale = 0.0
	make_current()
	DebugHud.note("boss intro")


## The car has landed: the stomp is coming - a punch in.
func landed() -> void:
	if _landed_t < 0.0:
		_landed_t = 0.0


func _process(delta: float) -> void:
	if done:
		return
	if level == null or not is_instance_valid(level) or _rig == null or not is_instance_valid(_rig):
		_finish()
		return
	var k := level.boss_lift_progress()
	var shot := _shot(k)
	if _landed_t >= 0.0:
		_landed_t += delta
		# The stomp lands ~0.6 s after: a kick of the view.
		if _landed_t > 0.55 and _landed_t - delta <= 0.55:
			_kick = 1.0
	_kick = move_toward(_kick, 0.0, delta * 2.5)
	if _swoop_t < 0.0:
		global_transform = _shake(shot)
		fov = _shot_fov(k)
		if _landed_t >= hold_after:
			_swoop_t = 0.0
		return
	# The swoop back to the player's own camera (eased round the player).
	_swoop_t += delta
	var s := clampf(_swoop_t / swoop_time, 0.0, 1.0)
	var e := s * s * (3.0 - 2.0 * s)
	var to := _rig.camera.global_transform
	global_transform = Transform3D(shot.basis.slerp(to.basis.orthonormalized(), e).orthonormalized(), shot.origin.lerp(to.origin, e))
	fov = lerpf(_shot_fov(k), _rig.camera.fov, e)
	if s >= 1.0:
		_finish()


## Where the shot is `k` through the descent (0 = parked up the shaft,
## 1 = landed): level with the car's deck, circling and closing in, on the
## boss's chest; low on the deck looking up at it once it's down.
func _shot(k: float) -> Transform3D:
	var e := k * k * (3.0 - 2.0 * k)
	var ang := _bearing + deg_to_rad(orbit_deg) * e
	var r := lerpf(radius_from, radius_to, e)
	var top := level.boss_car_top()
	var y := clampf(top.y + above_car * (1.0 - e), center.y + low, max_y)
	var pos := Vector3(center.x + cos(ang) * r, y, center.z + sin(ang) * r)
	var aim := Vector3(center.x, top.y + aim_up, center.z)
	pos = _clear(pos, aim)
	return Transform3D(Basis.looking_at(aim - pos), pos)


func _shot_fov(k: float) -> float:
	var f := lerpf(fov_from, fov_to, smoothstep(0.3, 1.0, k))
	if _landed_t >= 0.0:
		f -= 6.0 * smoothstep(0.4, 0.9, _landed_t)
	return f


## The stomp's kick: a short shake.
func _shake(xf: Transform3D) -> Transform3D:
	if _kick <= 0.0:
		return xf
	var t := Time.get_ticks_msec() * 0.001
	var o := Vector3(sin(t * 53.0), sin(t * 61.0 + 1.3), 0.0) * 0.18 * _kick
	return Transform3D(xf.basis, xf.origin + xf.basis * o)


## Never behind scenery: pulled in towards the shaft.
func _clear(pos: Vector3, aim: Vector3) -> Vector3:
	var from := Vector3(center.x, pos.y, center.z)
	var q := PhysicsRayQueryParameters3D.create(from, pos, 1)
	var skip: Array[RID] = []
	for n in get_tree().get_nodes_in_group(&"players"):
		if n is CollisionObject3D:
			skip.append((n as CollisionObject3D).get_rid())
	for n in get_tree().get_nodes_in_group(&"enemies"):
		if n is CollisionObject3D:
			skip.append((n as CollisionObject3D).get_rid())
	q.exclude = skip
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return pos
	return from + (pos - from).normalized() * maxf(from.distance_to(hit["position"]) - 0.6, 4.0)


func _local_rig() -> CameraRig:
	for r in get_tree().get_nodes_in_group(&"camera_rigs"):
		var rig := r as CameraRig
		if rig and rig.target and rig.target.is_in_group(&"local_player"):
			return rig
	return null


func _finish() -> void:
	if done:
		return
	done = true
	if _player and is_instance_valid(_player):
		_player.controls_locked = false
		_player.incoming_damage_scale = _damage_scale
	if _rig and is_instance_valid(_rig):
		_rig.camera.make_current()
	queue_free()


func _exit_tree() -> void:
	# (Freed some other way - a level change: hand back all the same.)
	if not done:
		_finish()
