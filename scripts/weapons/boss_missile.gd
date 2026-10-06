class_name BossMissile
extends Node3D
## The robot boss's missile. Leaves the launcher along its spawn socket's
## +Z and homes onto a FIXED world point (where the player stood at launch),
## never onto the player, so it can be dodged. Explodes on reaching that
## point or on hitting anything on the way; the blast damages and shoves
## everything nearby. Ray-cast movement (no physics body); one small mesh,
## a flame sprite and a smoke trail.

signal exploded(at: Vector3)

## Speed builds up from `launch_speed` to `speed` (m/s).
@export var launch_speed := 7.0
@export var speed := 15.0
@export var acceleration := 14.0
## How hard it steers (rad/s), growing over the flight so it always arrives.
@export var turn_rate := Vector2(1.8, 9.0)
@export var damage := 3.0
@export var blast_radius := 2.6
@export var blast_force := 9.0
@export var max_life := 8.0

var target := Vector3.ZERO
var shooter: Node
var marker: MissileTargetMarker
var velocity := Vector3.ZERO
var done := false

var _life := 0.0
var _expected := 1.0
var _exclude: Array[RID] = []
var _flame: MeshInstance3D
var _smoke: CPUParticles3D


## Launch from `from` (its +Z is the launch direction) towards `at`.
static func launch(parent: Node, from: Transform3D, at: Vector3, by: Node, target_marker: MissileTargetMarker = null) -> BossMissile:
	var m := BossMissile.new()
	m.target = at
	m.shooter = by
	m.marker = target_marker
	parent.add_child(m)
	m.global_transform = Transform3D(from.basis.orthonormalized(), from.origin)
	m.velocity = from.basis.z.normalized() * m.launch_speed
	if by is CollisionObject3D:
		m._exclude.append((by as CollisionObject3D).get_rid())
	m._expected = maxf(from.origin.distance_to(at) / ((m.launch_speed + m.speed) * 0.5), 0.3)
	return m


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.07
	cm.height = 0.5
	cm.radial_segments = 8
	cm.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.22, 0.24)
	mat.metallic = 0.6
	mat.roughness = 0.4
	cm.material = mat
	body.mesh = cm
	body.rotation.x = PI / 2.0  # cylinder along +Z
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	var tip := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.16
	sm.radial_segments = 8
	sm.rings = 4
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.9, 0.08, 0.05)
	tm.emission_enabled = true
	tm.emission = Color(1.0, 0.1, 0.05)
	tm.emission_energy_multiplier = 2.0
	sm.material = tm
	tip.mesh = sm
	tip.position = Vector3(0, 0, 0.26)
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tip)
	_flame = Vfx.quad("flame_a", Color(1.0, 0.55, 0.15), Vector2(0.35, 0.35), BaseMaterial3D.BILLBOARD_ENABLED)
	_flame.position = Vector3(0, 0, -0.32)
	add_child(_flame)
	_smoke = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.35
	q.material = Vfx.mix_material("smoke")
	_smoke.mesh = q
	_smoke.amount = 24
	_smoke.lifetime = 0.7
	_smoke.local_coords = false
	_smoke.position = Vector3(0, 0, -0.3)
	_smoke.direction = Vector3(0, 0, -1)
	_smoke.spread = 12.0
	_smoke.initial_velocity_min = 0.3
	_smoke.initial_velocity_max = 0.8
	_smoke.gravity = Vector3(0, 0.4, 0)
	_smoke.scale_amount_curve = Vfx.curve([Vector2(0, 0.4), Vector2(1, 1.4)])
	_smoke.color_ramp = Vfx.ramp([Color(0.55, 0.5, 0.48, 0.55), Color(0.35, 0.33, 0.32, 0.0)], [0.0, 1.0])
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_smoke)
	_smoke.emitting = true


func _physics_process(delta: float) -> void:
	if done:
		return
	_life += delta
	var from := global_position
	var to_target := target - from
	var dist := to_target.length()
	# Speed up and steer towards the fixed target point.
	var spd := minf(velocity.length() + acceleration * delta, speed)
	var turn := lerpf(turn_rate.x, turn_rate.y, clampf(_life / _expected, 0.0, 1.0)) * delta
	var dir := velocity.normalized()
	var want := to_target / maxf(dist, 1e-4)
	var ang := dir.angle_to(want)
	if ang > 1e-4:
		var axis := dir.cross(want)
		if axis.length_squared() < 1e-8:
			axis = Vector3.UP
		dir = dir.rotated(axis.normalized(), minf(ang, turn))
	velocity = dir * spd
	var motion := velocity * delta
	if marker and is_instance_valid(marker):
		marker.progress = clampf(_life / _expected, 0.0, 1.0)
	# Arrived (this step reaches or passes the point)?
	if dist <= motion.length() + 0.15 or (to_target.dot(velocity) < 0.0 and dist < 1.0):
		_explode(target)
		return
	var q := PhysicsRayQueryParameters3D.create(from, from + motion)
	q.collision_mask = 1
	q.exclude = _exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_explode(hit.position)
		return
	global_position = from + motion
	look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.RIGHT)
	rotate_object_local(Vector3.UP, PI)  # look_at faces -Z; the missile's nose is +Z
	Vfx.face_camera(_flame, 0.35 + 0.08 * sin(_life * 40.0))
	if _life >= max_life:
		_explode(global_position)


func _explode(at: Vector3) -> void:
	done = true
	global_position = at
	if marker and is_instance_valid(marker):
		marker.finish()
	_blast(at)
	MissileBlast.spawn(get_parent(), at, blast_radius)
	Sfx.play_at(get_parent(), Sfx.BH_EXPLODE, at, -3.0, 6.0, 70.0)
	exploded.emit(at)
	# Let the smoke trail die away, then go.
	_smoke.emitting = false
	for c in get_children():
		if c != _smoke:
			c.queue_free()
	get_tree().create_timer(_smoke.lifetime + 0.1, false).timeout.connect(queue_free)


## Damage and push everything within the blast radius (not the shooter).
func _blast(at: Vector3) -> void:
	var shape := SphereShape3D.new()
	shape.radius = blast_radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), at)
	q.collision_mask = 1
	q.exclude = _exclude
	var seen := {}
	for r in get_world_3d().direct_space_state.intersect_shape(q, 32):
		var col: Object = r.collider
		if col == null or seen.has(col) or col == shooter:
			continue
		seen[col] = true
		var body := col as Node3D
		var off := body.global_position + Vector3.UP * 0.8 - at
		var k := clampf(1.0 - off.length() / (blast_radius + 0.8), 0.15, 1.0)
		var push_dir := (off + Vector3.UP * 0.6).normalized()
		if col.has_method("apply_damage"):
			col.apply_damage(DamageInfo.make(damage * k, DamageInfo.Type.EXPLOSION, at, push_dir, 0.0, blast_force * k, shooter))
		if col is PlayerController:
			(col as PlayerController).apply_external_impulse(push_dir * blast_force * k)
		elif col is RigidBody3D and not (col as RigidBody3D).freeze:
			var rb := col as RigidBody3D
			rb.apply_central_impulse(push_dir * blast_force * k * minf(rb.mass, 20.0) * 0.5)
