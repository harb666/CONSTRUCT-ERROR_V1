class_name PlasmaCannon
extends Weapon
## Arm-mounted plasma cannon (the player's default weapon in both hands).
## Fires fast cyan plasma bolts from its Muzzle_Exit (pooled PlasmaBolt, no
## physics body) with a muzzle flash; its own rate, damage, speed, colours and
## recoil are set here, so the weapon slot holds no cannon-specific logic.

## Shots per second.
@export var fire_rate := 4.0
@export var damage := 0.45
@export var bolt_speed := 42.0
## Small random spread (degrees).
@export var spread_deg := 0.6
@export var bolt_color := Color(0.1, 0.8, 1.0)
@export var bolt_hot_color := Color(0.75, 0.97, 1.0)
## Bolts fly through these bodies (no friendly fire).
@export var pass_group := &"players"
## Shot sound (Sfx.PISTOL_CANNON, the owner's own sound - keep it):
## loudness, full within `fire_sound_near` m,
## silent beyond `fire_sound_far` m, random pitch range.
@export var fire_sound_db := -2.0
@export var fire_sound_near := 5.0
@export var fire_sound_far := 45.0
@export var fire_sound_pitch := Vector2(0.94, 1.07)

var shots_fired := 0
## Shot sounds started (tests).
var fire_sounds := 0
var _voices: Array[DynamicSound] = []
var _voice := 0
var _cool := 0.0
var _muzzle: Node3D
## Extra cartoon cel flash over the usual muzzle flash (brighter shots).
var cel_flash: CelFlash


func _ready() -> void:
	_muzzle = find_marker(MUZZLE_MARKER)
	cel_flash = CelFlash.new()
	cel_flash.name = "CelFlash"
	cel_flash.size = 0.68
	cel_flash.cone_length = 2.0
	cel_flash.sparks = 5
	cel_flash.duration = 0.13
	add_child(cel_flash)
	cel_flash.setup(bolt_color, bolt_hot_color)
	# 4 voices: the 0.84 s shot overlaps itself at 4 shots/s.
	_voices = Sfx.voices(self, Sfx.PISTOL_CANNON, 4, fire_sound_db, fire_sound_near, fire_sound_far,
		_muzzle.position if _muzzle and _muzzle.get_parent() == self else Vector3.ZERO)


func _process(delta: float) -> void:
	_cool = maxf(_cool - delta, 0.0)


func can_fire() -> bool:
	return _cool <= 0.0


func muzzle_position() -> Vector3:
	return _muzzle.global_position if _muzzle else global_position


func fire_at(shooter: Node3D, target_point: Vector3) -> bool:
	if not can_fire():
		return false
	_cool = 1.0 / maxf(fire_rate, 0.01)
	var from := muzzle_position()
	var dir := (target_point - from).normalized()
	if dir.length_squared() < 0.5:
		dir = get_barrel_direction()
	var spread := deg_to_rad(spread_deg)
	dir = dir.rotated(Vector3.UP, randf_range(-spread, spread))
	var b := PlasmaBolt.fire(get_tree(), from, dir, shooter, bolt_speed, damage, bolt_color, bolt_hot_color, pass_group)
	if b:
		b.arm_side = arm_side
	PlasmaFx.muzzle_flash(get_tree(), from, dir, bolt_color, bolt_hot_color, true)
	cel_flash.fire(from, dir)
	_voice = Sfx.play_next(_voices, _voice, fire_sound_pitch)
	fire_sounds += 1
	shots_fired += 1
	recoiled.emit(recoil_strength)
	return true


## Point-blank shot for the melee punch (PlayerMelee): muzzle flash, a big
## cel flash, the shot sound and the kick - the punch itself does the damage.
func melee_shot(dir: Vector3, strength := 1.6) -> void:
	var from := muzzle_position()
	PlasmaFx.muzzle_flash(get_tree(), from, dir, bolt_color, bolt_hot_color, true)
	cel_flash.fire(from, dir, strength)
	_voice = Sfx.play_next(_voices, _voice, fire_sound_pitch)
	fire_sounds += 1
	recoiled.emit(recoil_strength * 1.8)
