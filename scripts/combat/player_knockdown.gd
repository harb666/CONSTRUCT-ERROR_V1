class_name PlayerKnockdown
extends Node
## Knocked flying (the robot boss's stomp and its missiles, owner asked):
## the player is
## launched way back and up, tips over backwards in the air, lands flat on
## their back (a bounce, a skid and a puff of dust), lies there a beat, then
## kips up - knees tucked to the chest, a quick hop - and is back on their
## feet. Movement input, jumps, dodges and melee wait until then; the guns
## keep firing at locked targets. A missile caught close turns the player
## head over heels backwards in the air (`somersaults`) before they slam
## down on their back. The body pose is KnockdownPoseModifier's
## (CharacterAnimator), from this node's `phase` / timers.

signal knocked_down
signal got_up

enum Phase { NONE, FLYING, DOWN, GETUP }

## Seconds lying on the back, and the kip-up.
@export var down_time := 0.32
@export var getup_time := 0.42
## The hop as it springs up (m/s), when in the kip-up.
@export var getup_hop := 5.0
@export var getup_hop_at := 0.13
## Level drag in the air, and the skid along the floor after landing.
@export var air_drag := 0.6
@export var skid_decel := 26.0

var phase := Phase.NONE
var active: bool:
	get: return phase != Phase.NONE
## Seconds in the current phase, and since launch.
var phase_t := 0.0
var flight_t := 0.0
## Facing kept while down (towards what knocked it), and level velocity.
var face_yaw := 0.0
var horiz := Vector2.ZERO
## Times knocked down / got up (tests).
var knockdowns := 0
var getups := 0
## Backwards tip (rad, 0 standing -> -PI/2 flat on the back), smoothed here
## so the pose stays continuous whatever the flight time.
var pitch := 0.0
## Backward somersaults this knock turns in the air before landing.
var somersaults := 0
var _flip_rate := deg_to_rad(230.0)
var _down_pitch := -PI * 0.5
var _hopped := false
var _player: PlayerController


func _ready() -> void:
	_player = get_parent() as PlayerController


## Launch it away from `from` at `speed` level and `up` upward (m/s),
## turning `flips` backward somersaults on the way.
func knock(from: Vector3, speed: float, up: float, flips := 0) -> void:
	if _player == null:
		return
	if _player.melee:
		_player.melee.cancel()
	var away := _player.global_position - from
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 1e-4 else _player.global_basis.z
	horiz = Vector2(away.x, away.z) * speed
	face_yaw = atan2(away.x, away.z)  # looking back at it: flies backwards
	_player.rotation.y = face_yaw
	_player.velocity.y = up
	_player.is_dodging = false
	phase = Phase.FLYING
	phase_t = 0.0
	flight_t = 0.0
	_hopped = false
	somersaults = flips
	# Turn fast enough to finish the somersaults (and tip onto the back)
	# a little before it lands.
	var g: float = _player._gravity if _player._gravity > 0.0 else 29.0
	var air := up / g + sqrt(up * up / g / (g * _player.fall_gravity_multiplier))
	_flip_rate = maxf(deg_to_rad(230.0), (deg_to_rad(80.0) + TAU * flips) / maxf(air * 0.8, 0.2))
	knockdowns += 1
	knocked_down.emit()


## PlayerController.simulate, every tick (before gravity).
func tick(delta: float, on_floor: bool) -> void:
	if phase == Phase.NONE:
		return
	phase_t += delta
	flight_t += delta
	match phase:
		Phase.FLYING:
			horiz = horiz.move_toward(Vector2.ZERO, horiz.length() * air_drag * delta)
			# Tips over backwards on the way (somersaulting first, if blasted).
			pitch = move_toward(pitch, -deg_to_rad(80.0) - TAU * somersaults, _flip_rate * delta)
			if on_floor and phase_t > 0.12:
				_enter(Phase.DOWN)
				# Onto its back: still turning backwards if it landed mid-
				# somersault (on a ledge), then the same pose a turn round.
				_down_pitch = -PI * 0.5
				while _down_pitch > pitch + 0.5:
					_down_pitch -= TAU
				var host := _player.get_parent()
				if host:
					DodgeDust.spawn(host, _player.global_position, Vector3(horiz.x, 0, horiz.y).normalized())
		Phase.DOWN:
			horiz = horiz.move_toward(Vector2.ZERO, skid_decel * delta)
			pitch = move_toward(pitch, _down_pitch, deg_to_rad(600.0) * delta)
			if phase_t >= down_time:
				_enter(Phase.GETUP)
				pitch = -PI * 0.5
		Phase.GETUP:
			horiz = Vector2.ZERO
			if not _hopped and phase_t >= getup_hop_at:
				_hopped = true
				_player.velocity.y = getup_hop
			if phase_t >= getup_time:
				phase = Phase.NONE
				pitch = 0.0
				getups += 1
				got_up.emit()


func _enter(p: Phase) -> void:
	phase = p
	phase_t = 0.0


func cancel() -> void:
	phase = Phase.NONE
	somersaults = 0
	pitch = 0.0
	horiz = Vector2.ZERO
