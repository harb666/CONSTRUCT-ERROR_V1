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

var shots_fired := 0
var _cool := 0.0
var _muzzle: Node3D


func _ready() -> void:
	_muzzle = find_marker(MUZZLE_MARKER)


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
	PlasmaBolt.fire(get_tree(), from, dir, shooter, bolt_speed, damage, bolt_color, bolt_hot_color, pass_group)
	PlasmaFx.muzzle_flash(get_tree(), from, dir, bolt_color, bolt_hot_color)
	shots_fired += 1
	recoiled.emit(recoil_strength)
	return true
