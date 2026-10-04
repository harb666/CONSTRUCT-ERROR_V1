class_name BlackHoleProjectile
extends Node3D
## A fired black hole: carries the BlackHoleCore that left the gun's chamber
## (its own spin animation keeps playing), flies straight, and stops on the
## first thing it hits. Gravity pull, damage and the supernova hook in at
## `impacted` later; for now it just collapses and disappears.

signal impacted(position: Vector3, collider: Object)

@export var speed := 18.0
@export var max_distance := 80.0
## Size it swells to after leaving the barrel (m across).
@export var flight_size := 1.0
@export var grow_time := 0.18
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


func launch(c: BlackHoleCore, dir: Vector3, shooter: Node3D) -> void:
	core = c
	direction = dir.normalized()
	if shooter is CollisionObject3D:
		_shooter_rid = (shooter as CollisionObject3D).get_rid()
	if core:
		var basis := core.transform.basis
		_start_size = basis.get_scale().x
		_start_basis = Basis(basis.orthonormalized().get_rotation_quaternion())
		_flight_basis = _disk_facing(direction)
		add_child(core)
		core.transform = Transform3D(_start_basis * _start_size, Vector3.ZERO)
	_vfx = BlackHoleFlightVfx.new()
	_vfx.follow = self
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
		_set_size(flight_size * k)
		if k <= 0.0:
			queue_free()
		return

	_set_size(lerpf(_start_size, flight_size, clampf(_age / grow_time, 0.0, 1.0)))
	var from := global_position
	var to := from + direction * speed * delta
	var q := PhysicsRayQueryParameters3D.create(from, to)
	if _shooter_rid.is_valid():
		q.exclude = [_shooter_rid]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		global_position = hit.position - direction * flight_size * 0.3
		_impact(hit.collider)
		return
	global_position = to
	_travelled += speed * delta
	if _travelled >= max_distance:
		_impact(null)


func _impact(collider: Object) -> void:
	_collapsing = 0.0
	ImpactBurst.spawn(get_parent(), global_position, flight_size * 1.1)
	if _vfx:
		_vfx.fade_out(collapse_time)
	if collider and collider.has_method("on_projectile_hit"):
		collider.on_projectile_hit(self)
	impacted.emit(global_position, collider)


func _set_size(size: float) -> void:
	if _vfx and _collapsing < 0.0:
		_vfx.set_size(size)
	if core:
		var k := clampf(_age / turn_time, 0.0, 1.0)
		var q := _start_basis.get_rotation_quaternion().slerp(_flight_basis.get_rotation_quaternion(), smoothstep(0.0, 1.0, k))
		core.transform.basis = Basis(q) * maxf(size, 0.001)
