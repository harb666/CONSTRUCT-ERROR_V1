class_name FrostByte
extends Weapon
## Frost Byte (owner's model): an arm cannon that fires a powerful cold
## blizzard every `fire_interval` seconds (owner asked: 10) - FrostBlizzard,
## a cone that widens further out, freezing the robots it reaches for 10 s.
## Only fires when the locked target is within the blizzard's reach. A big
## white / ice-blue cartoon flash and a cold puff at the muzzle, heavy
## recoil, and cold mist drifting from the muzzle while it waits.

@export var fire_interval := 10.0
## Fires only at targets this close (the blizzard's reach, a little over).
@export var max_range := 17.0

var _cool := 0.0
var _muzzle: Node3D
var cel_flash: CelFlash
var _mist: CPUParticles3D
var last_blizzard: FrostBlizzard
## Counters (tests).
var shots_fired := 0


func _ready() -> void:
	_muzzle = find_marker(MUZZLE_MARKER)
	cel_flash = CelFlash.new()
	cel_flash.name = "CelFlash"
	cel_flash.size = 1.25
	cel_flash.cone_length = 2.2
	cel_flash.cones = 4
	cel_flash.sparks = 12
	cel_flash.duration = 0.28
	cel_flash.glow_size = 3.0
	add_child(cel_flash)
	cel_flash.setup(Color(0.45, 0.82, 1.0), Color(0.95, 0.99, 1.0))


func on_equipped(owner_player: Node) -> void:
	super.on_equipped(owner_player)
	if _mist == null:
		_mist = _make_mist()
		add_child(_mist)


func _process(delta: float) -> void:
	_cool = maxf(_cool - delta, 0.0)
	if _mist and _muzzle:
		_mist.global_position = _muzzle.global_position
		# Only once charged and ready (a cue that it can fire).
		_mist.emitting = _cool <= 0.0


func can_fire() -> bool:
	return is_equipped and _cool <= 0.0


func muzzle_position() -> Vector3:
	return _muzzle.global_position if _muzzle else global_position


## Seconds until it can fire again (0 = charged).
func reload_left() -> float:
	return _cool


func fire_at(shooter: Node3D, target_point: Vector3) -> bool:
	if not can_fire():
		return false
	var from := muzzle_position()
	if from.distance_to(target_point) > max_range:
		return false  # out of the blizzard's reach: keep it charged
	_cool = fire_interval
	var dir := (target_point - from).normalized()
	if dir.length_squared() < 0.5:
		dir = get_barrel_direction()
	last_blizzard = FrostBlizzard.fire(get_tree(), from, dir, shooter)
	cel_flash.fire(from, dir, 1.3)
	PlasmaFx.muzzle_flash(get_tree(), from, dir, Color(0.5, 0.85, 1.0), Color(1, 1, 1), true)
	shots_fired += 1
	recoiled.emit(recoil_strength)
	return true


## Cold mist curling down from the muzzle (while charged).
func _make_mist() -> CPUParticles3D:
	var p := Vfx.particles("glow", 0.16, 14, 1.4)
	p.local_coords = false
	p.direction = Vector3(0, -1, 0)
	p.spread = 35.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.35
	p.gravity = Vector3(0, -0.4, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	p.color_ramp = Vfx.ramp([Color(0.85, 0.95, 1.0, 0.0), Color(0.85, 0.95, 1.0, 0.35), Color(0.85, 0.95, 1.0, 0.0)], [0.0, 0.3, 1.0])
	return p
