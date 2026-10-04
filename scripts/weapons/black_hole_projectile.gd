class_name BlackHoleProjectile
extends Node3D
## A fired black hole: carries the BlackHoleCore that left the gun's chamber
## (its own spin animation keeps playing), flies straight, and stops on the
## first thing it hits. Gravity pull, damage and the supernova hook in at
## `impacted` later; for now it just collapses and disappears.

signal impacted(position: Vector3, collider: Object)

@export var speed := 18.0
@export var max_distance := 80.0
## Size it surges to once clear of the gun (m across; ~1.75x player height).
@export var flight_size := 3.0
## Distance travelled at chamber size before it expands (clears the barrel).
@export var clear_distance := 1.4
## Duration of the expansion surge (ease-out with a slight overshoot).
@export var expand_time := 0.32
@export var expand_overshoot := 1.4
## Solid collision radius as a fraction of the visible diameter (the dark
## core, not the faint outer disk), so it can skim along at chest height.
@export var collision_fraction := 0.22
@export var collapse_time := 0.35
## In flight the accretion disk faces back towards the shooter, tilted by this
## much so it reads as a 3D disk rather than a flat circle.
@export var flight_tilt_degrees := 30.0
## Seconds to turn from its chamber orientation to the flight orientation.
@export var turn_time := 0.15

var core: BlackHoleCore
var direction := Vector3.FORWARD
var _shooter_rid: RID
var _travelled := 0.0
var _age := 0.0
var _start_size := 0.28
var _collapsing := -1.0
var _start_basis := Basis.IDENTITY
var _vfx: BlackHoleFlightVfx
var _flight_basis := Basis.IDENTITY
var _size := 0.28
var _expand_t := -1.0
var _sphere := SphereShape3D.new()
var _collapse_from := 0.0

## Current solid radius (m) and the wider radius of its influence (used by
## the electricity now, gravity later). Both scale with the expansion.
var collision_radius: float:
	get: return _size * collision_fraction
var influence_radius: float:
	get: return _size * 1.2


func launch(c: BlackHoleCore, dir: Vector3, shooter: Node3D) -> void:
	core = c
	direction = dir.normalized()
	if shooter is CollisionObject3D:
		_shooter_rid = (shooter as CollisionObject3D).get_rid()
	if core:
		var basis := core.transform.basis
		_start_size = basis.get_scale().x
		_size = _start_size
		_start_basis = Basis(basis.orthonormalized().get_rotation_quaternion())
		_flight_basis = _disk_facing(direction)
		add_child(core)
		core.transform = Transform3D(_start_basis * _start_size, Vector3.ZERO)
	_vfx = BlackHoleFlightVfx.new()
	_vfx.follow = self
	_vfx.projectile = self
	if shooter is CollisionObject3D:
		_vfx.exclude = [(shooter as CollisionObject3D).get_rid()]
	_vfx.size = _start_size
	add_child(_vfx)


## Core's disk lies in its local XZ plane (normal +Y): point the normal back
## along the flight path, then tilt it so the disk is seen at an angle.
func _disk_facing(dir: Vector3) -> Basis:
	var normal := -dir
	var side := normal.cross(Vector3.UP)
	if side.length_squared() < 1e-4:
		side = Vector3.RIGHT
	side = side.normalized()
	var fwd := side.cross(normal).normalized()
	var b := Basis(side, normal, -fwd).orthonormalized()
	return Basis(side, deg_to_rad(flight_tilt_degrees)) * b


func _physics_process(delta: float) -> void:
	_age += delta
	if _collapsing >= 0.0:
		_collapsing += delta
		var k := 1.0 - clampf(_collapsing / collapse_time, 0.0, 1.0)
		_set_size(_collapse_from * k)
		if k <= 0.0:
			queue_free()
		return

	# Small while leaving the gun, then a fast, overshooting surge.
	if _expand_t < 0.0 and _travelled >= clear_distance:
		_expand_t = 0.0
		ImpactBurst.spawn(get_parent(), global_position, flight_size * 0.55)
	if _expand_t >= 0.0:
		_expand_t += delta
		var k := clampf(_expand_t / expand_time, 0.0, 1.0)
		_set_size(lerpf(_start_size, flight_size, _ease_out_back(k)))
	else:
		_set_size(_start_size)

	var from := global_position
	var motion := direction * speed * delta
	var hit := _sweep(from, motion)
	if not hit.is_empty():
		global_position = hit.position
		_impact(hit.collider)
		return
	global_position = from + motion
	_travelled += motion.length()
	if _travelled >= max_distance:
		_impact(null)


func _ease_out_back(k: float) -> float:
	var c := expand_overshoot
	var t := k - 1.0
	return 1.0 + (c + 1.0) * t * t * t + c * t * t


## Sphere sweep with the current collision radius (one query per tick).
func _sweep(from: Vector3, motion: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	_sphere.radius = maxf(collision_radius, 0.05)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _sphere
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = motion
	if _shooter_rid.is_valid():
		q.exclude = [_shooter_rid]
	var frac := space.cast_motion(q)
	if frac.is_empty() or frac[1] >= 1.0:
		return {}
	q.transform.origin = from + motion * frac[1]
	q.motion = Vector3.ZERO
	var info := space.get_rest_info(q)
	if info.is_empty():
		return {}
	return {"position": from + motion * frac[0], "collider": instance_from_id(info.collider_id)}


func _impact(collider: Object) -> void:
	_collapsing = 0.0
	_collapse_from = _size
	ImpactBurst.spawn(get_parent(), global_position, maxf(_size, 0.6) * 1.1)
	if _vfx:
		_vfx.fade_out(collapse_time)
	if collider and collider.has_method("on_projectile_hit"):
		collider.on_projectile_hit(self)
	impacted.emit(global_position, collider)


func _set_size(size: float) -> void:
	_size = size
	if _vfx and _collapsing < 0.0:
		_vfx.set_size(size)
	if core:
		var k := clampf(_age / turn_time, 0.0, 1.0)
		var q := _start_basis.get_rotation_quaternion().slerp(_flight_basis.get_rotation_quaternion(), smoothstep(0.0, 1.0, k))
		core.transform.basis = Basis(q) * maxf(size, 0.001)
