class_name GravityWell
extends Node3D
## Gravity field around a stuck black hole. Pulls movable bodies (RigidBody3D)
## and players (via `apply_gravity_pull`) inward with a tangential swirl so
## they spiral in; shrinks/spins their visuals as they near the centre;
## captures them in the core (collision off, kinematic, tiny). `supernova()`
## releases everything with ONE capped outward launch each and radial damage.
##
## Stability: velocity changes are clamped (inward / orbital / total / launch
## caps), bodies are found with one sphere query every `query_interval`
## (not every frame, never the whole level), captured bodies have collisions
## disabled and are released one per physics tick at spread-out, ray-checked
## positions.

@export_group("Field")
@export var gravity_radius := 9.0
## Inward acceleration (m/s²) for a reference-mass body, scaled by closeness.
@export var gravity_strength := 26.0
@export var orbit_strength := 12.0
@export var capture_radius := 1.0
## Visual shrink starts inside this fraction of the radius; >1 = sharper.
@export var shrink_start := 0.45
@export var shrink_rate := 1.6
@export var min_visual_scale := 0.05
@export var max_spin_speed := 14.0  # rad/s visual spin near the core

@export_group("Enemies")
## Enemies (group "enemies") are pulled this much harder than props, and
## their weight resists the pull at most this much.
@export var enemy_pull_multiplier := 2.6
@export var enemy_max_resist := 1.3
## Enemies are always captured (and shrunk away) once inside the event
## horizon, even when the prop capture limit is reached.
@export var max_captured_enemies := 12

@export_group("Player")
@export var player_gravity_strength := 20.0
## Max pull speed added to a player (sprint 11.5 m/s can still escape).
@export var max_player_pull_speed := 8.0

@export_group("Limits")
@export var max_affected_objects := 12
@export var max_captured_objects := 6
@export var max_inward_speed := 10.0
@export var max_orbit_speed := 9.0
@export var max_speed := 14.0
## Mass that counts as "light"; heavier bodies resist by sqrt(mass/ref).
@export var reference_mass := 8.0
@export var max_mass_resist := 4.0
@export var query_interval := 0.15
## Physics layer that movable things (props, enemies, players) are also on,
## so queries skip static level geometry entirely.
const MOVABLE_LAYER := 2

@export_group("Supernova")
@export var supernova_radius := 11.0
@export var supernova_damage := 3.0
@export var supernova_launch_force := 24.0
@export var max_launch_speed := 24.0
@export var player_supernova_push := 14.0
## Blast force reported to damaged targets at point blank (DamageInfo
## explosive_force, scaled by distance); drives how violently enemies die.
@export var supernova_explosive_force := 42.0

## 0..1 instability ramp (set by the projectile): strengthens suction.
var intensity := 0.0
## Surface normal where it stuck (supernova throws into this hemisphere).
var surface_normal := Vector3.UP
## Bodies never affected (e.g. none by default; players are pulled).
var exclude: Array[RID] = []
var active := true

var _bodies: Array = []
var _captured: Array = []      # [{body, layer, mask, angle, radius, phase}]
var _release_queue: Array = []
var _query_t := 0.0
var _spin := {}                # instance id -> accumulated visual spin
var _sphere := SphereShape3D.new()
var _axis := Vector3.UP


func _ready() -> void:
	# Swirl axis: the surface normal (things orbit across the surface).
	_axis = surface_normal.normalized() if surface_normal.length_squared() > 0.1 else Vector3.UP


func _physics_process(delta: float) -> void:
	if active:
		_query_t -= delta
		if _query_t <= 0.0:
			_query_t = query_interval
			_refresh()
		for b in _bodies:
			if not is_instance_valid(b) or _is_captured(b):
				continue
			if b is RigidBody3D:
				_pull_body(b, delta)
			elif b.has_method("apply_gravity_pull"):
				_pull_player(b, delta)
	_update_captured(delta)
	# Staggered release: one body per physics tick.
	if not _release_queue.is_empty():
		_release_one(_release_queue.pop_front())


func _refresh() -> void:
	var space := get_world_3d().direct_space_state
	_sphere.radius = gravity_radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _sphere
	q.transform = Transform3D(Basis.IDENTITY, global_position)
	q.exclude = exclude
	q.collision_mask = MOVABLE_LAYER
	var found: Array = []
	for r in space.intersect_shape(q, 48):
		var b: Object = r.collider
		if b is RigidBody3D and (not b.freeze or _is_captured(b)):
			found.append(b)
		elif b is CharacterBody3D and b.has_method("apply_gravity_pull"):
			found.append(b)
	var c := global_position
	# Nearest first, enemies ahead of props (they must never be left out).
	found.sort_custom(func(a, b): return _center_of(a).distance_squared_to(c) - (100.0 if _is_enemy(a) else 0.0) < _center_of(b).distance_squared_to(c) - (100.0 if _is_enemy(b) else 0.0))
	var keep := found.slice(0, max_affected_objects)
	# Anything that dropped out of the field gets its look back.
	for b in _bodies:
		if is_instance_valid(b) and not keep.has(b) and not _is_captured(b):
			_set_visual(b, 1.0, 0.0)
	_bodies = keep


static func _center_of(b: Node3D) -> Vector3:
	return b.global_position + Vector3.UP * float(b.get_meta("gravity_center_y", 0.0))


func _resist(b: RigidBody3D) -> float:
	var r := clampf(sqrt(b.mass / reference_mass), 1.0, max_mass_resist)
	if _is_enemy(b):
		r = minf(r, enemy_max_resist) / enemy_pull_multiplier
	return r


static func _is_enemy(b: Object) -> bool:
	return b is Node and (b as Node).is_in_group(&"enemies")


func _pull_body(b: RigidBody3D, delta: float) -> void:
	var to := global_position - _center_of(b)
	var d := to.length()
	if d < 0.001 or d > gravity_radius:
		return
	var dir := to / d
	var close := 1.0 - d / gravity_radius
	var boost := 1.0 + intensity
	var resist := _resist(b)
	var tangent := _axis.cross(dir)
	if tangent.length_squared() < 0.01:
		tangent = Vector3.RIGHT.cross(dir)
	tangent = tangent.normalized()
	var a_in := gravity_strength * boost * (0.15 + close * close * 1.3) / resist
	var a_t := orbit_strength * boost * close / resist
	var v := b.linear_velocity
	v += (dir * a_in + tangent * a_t) * delta
	# Lift against world gravity as it nears the core, so things rise in.
	v += Vector3.UP * 9.8 * clampf(close * 1.5, 0.0, 1.0) * delta
	# Clamp inward/outward and orbital speeds, then total speed.
	var vin := clampf(v.dot(dir), -max_inward_speed, max_inward_speed)
	var vt := v - dir * v.dot(dir)
	vt = vt.limit_length(max_orbit_speed)
	# Bleed some orbital energy near the core so the spiral tightens.
	vt *= 1.0 - clampf(close * 0.8 * delta, 0.0, 0.2)
	b.linear_velocity = (dir * vin + vt).limit_length(max_speed)
	b.sleeping = false
	# Visual: shrink + spin faster as it nears the centre.
	var id := b.get_instance_id()
	_spin[id] = float(_spin.get(id, 0.0)) + max_spin_speed * close * close * delta
	_set_visual(b, _shrink_for(d), _spin[id])
	if b.has_method("on_gravity_pull"):
		b.on_gravity_pull()  # e.g. enemies stop walking while caught
	if d < capture_radius:
		var enemy := _is_enemy(b)
		var props := _captured.filter(func(e: Dictionary) -> bool: return not _is_enemy(e.body)).size()
		if (enemy and _captured.size() - props < max_captured_enemies) or (not enemy and props < max_captured_objects):
			_capture(b)


func _shrink_for(d: float) -> float:
	var start := gravity_radius * shrink_start
	if d >= start:
		return 1.0
	var t := clampf((d - capture_radius) / maxf(start - capture_radius, 0.01), 0.0, 1.0)
	return maxf(pow(t, shrink_rate), min_visual_scale)


func _pull_player(p: Node3D, delta: float) -> void:
	var to := global_position - (p.global_position + Vector3.UP * 0.9)
	var d := to.length()
	if d < 0.001 or d > gravity_radius:
		return
	var close := 1.0 - d / gravity_radius
	var a := player_gravity_strength * (1.0 + intensity) * (0.15 + close * close * 1.8)
	p.apply_gravity_pull(to / d * a * delta, max_player_pull_speed)


func _is_captured(b: Object) -> bool:
	for c in _captured:
		if c.body == b:
			return true
	return false


func _capture(b: RigidBody3D) -> void:
	_captured.append({"body": b, "layer": b.collision_layer, "mask": b.collision_mask,
		"angle": randf() * TAU, "radius": randf_range(0.12, 0.3), "phase": randf() * TAU})
	b.collision_layer = 0
	b.collision_mask = 0
	b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	b.freeze = true
	b.linear_velocity = Vector3.ZERO


## Captured bodies circle tightly inside the core, tiny and spinning.
func _update_captured(delta: float) -> void:
	var c := global_position
	for e in _captured:
		var b: RigidBody3D = e.body
		if not is_instance_valid(b):
			continue
		e.angle += 9.0 * delta
		var off: Vector3 = Vector3(cos(e.angle), sin(e.angle + e.phase) * 0.4, sin(e.angle)) * e.radius
		b.global_position = c + off - Vector3.UP * float(b.get_meta("gravity_center_y", 0.0)) * min_visual_scale
		var id := b.get_instance_id()
		_spin[id] = float(_spin.get(id, 0.0)) + max_spin_speed * delta
		_set_visual(b, min_visual_scale, _spin[id])


func captured_count() -> int:
	return _captured.size()


## Collapse finished: release captured bodies (staggered) and blast
## everything in range outward once, with radial damage.
func supernova() -> void:
	active = false
	var c := global_position
	var space := get_world_3d().direct_space_state
	_sphere.radius = supernova_radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _sphere
	q.transform = Transform3D(Basis.IDENTITY, c)
	q.exclude = exclude
	q.collision_mask = MOVABLE_LAYER
	for r in space.intersect_shape(q, 48):
		var b: Object = r.collider
		if b is RigidBody3D and not b.freeze and not _is_captured(b):
			var to: Vector3 = _center_of(b) - c
			var f := 1.0 - clampf(to.length() / supernova_radius, 0.0, 1.0)
			_set_visual(b, 1.0, 0.0)
			_launch(b, _away(to), f)
			_damage(b, f, _away(to))
		elif b is CharacterBody3D and b.has_method("apply_external_impulse"):
			var to2: Vector3 = b.global_position - c
			var f2 := 1.0 - clampf(to2.length() / supernova_radius, 0.0, 1.0)
			var push := _away(to2)
			push.y = maxf(push.y, 0.3)
			b.apply_external_impulse(push.normalized() * player_supernova_push * f2)
	# Captured ones come out spread over the open hemisphere, one per tick.
	var n := _captured.size()
	for i in n:
		_release_queue.append([_captured[i], _hemisphere_dir(i, n)])
	_captured.clear()
	_bodies.clear()


func _away(v: Vector3) -> Vector3:
	if v.length_squared() < 0.0001:
		return _hemisphere_dir(randi() % 8, 8)
	return v.normalized()


## Evenly spread directions in the hemisphere facing away from the surface.
func _hemisphere_dir(i: int, n: int) -> Vector3:
	var golden := PI * (3.0 - sqrt(5.0))
	var y := 1.0 - (float(i) + 0.5) / maxf(n, 1) * 0.85  # 1..0.15
	var r := sqrt(maxf(1.0 - y * y, 0.0))
	var a := golden * i + randf() * 0.4
	var local := Vector3(cos(a) * r, y, sin(a) * r)
	# Rotate local +Y onto the surface normal.
	var nrm := surface_normal.normalized()
	var basis := Basis.IDENTITY
	if absf(nrm.dot(Vector3.UP)) < 0.999:
		var axis := Vector3.UP.cross(nrm).normalized()
		basis = Basis(axis, Vector3.UP.angle_to(nrm))
	elif nrm.y < 0.0:
		basis = Basis(Vector3.RIGHT, PI)
	return (basis * local).normalized()


func _release_one(entry: Array) -> void:
	var e: Dictionary = entry[0]
	var dir: Vector3 = entry[1]
	var b: RigidBody3D = e.body
	if not is_instance_valid(b):
		return
	var c := global_position
	# Spawn spot spread out along its direction, pulled back from any wall.
	var want := capture_radius + 0.6 + 0.35 * randf()
	if is_inside_tree():
		var ray := PhysicsRayQueryParameters3D.create(c, c + dir * (want + 0.6))
		ray.exclude = exclude
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if hit:
			want = maxf(c.distance_to(hit.position) - 0.6, 0.2)
	b.global_position = c + dir * want - Vector3.UP * float(b.get_meta("gravity_center_y", 0.0))
	b.reset_physics_interpolation()
	b.freeze = false
	b.collision_layer = e.layer
	b.collision_mask = e.mask
	_launch(b, dir, 1.0)
	if b.is_inside_tree():
		_restore_visual_smooth(b)
	else:
		restore_visual(b)
	_damage(b, 1.0, dir)


## ONE controlled outward launch, capped, with a little lift.
func _launch(b: RigidBody3D, dir: Vector3, falloff: float) -> void:
	var d := (dir + Vector3.UP * 0.35).normalized()
	var speed := minf(supernova_launch_force * (0.4 + 0.6 * falloff) / _resist(b), max_launch_speed)
	b.linear_velocity = d * speed
	b.angular_velocity = Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))
	b.sleeping = false


func _damage(b: Object, falloff: float, dir: Vector3) -> void:
	var info := DamageInfo.make(supernova_damage * (0.5 + 0.5 * falloff), DamageInfo.Type.SUPERNOVA,
		global_position, dir, 0.0, supernova_explosive_force * falloff)
	info.impact_position = global_position  # blast centre
	DamageInfo.apply(b, info)


func release_all_now() -> void:
	# Safety: if the well is removed early, put everything back as it was.
	for e in _captured:
		_release_queue.append([e, _hemisphere_dir(0, 1)])
	_captured.clear()
	while not _release_queue.is_empty():
		_release_one(_release_queue.pop_front())
	for b in _bodies:
		if is_instance_valid(b):
			_set_visual(b, 1.0, 0.0)


func is_done() -> bool:
	return not active and _release_queue.is_empty()


# --- Visual shrink/spin without touching the body's real scale/collision ---

## Scale and spin the body's visual meshes about its origin. Original
## transforms are stored on first use so they can be restored exactly.
static func _visuals(b: Node3D) -> Array:
	if not b.has_meta("gw_visuals"):
		var vis: Array = []
		# Bodies can name their visual root(s); default: direct mesh children.
		var nodes: Array = b.gravity_visual_nodes() if b.has_method("gravity_visual_nodes") else b.get_children().filter(func(ch: Node) -> bool: return ch is GeometryInstance3D)
		for ch in nodes:
			vis.append([ch, (ch as Node3D).transform])
		b.set_meta("gw_visuals", vis)
	return b.get_meta("gw_visuals")


func _set_visual(b: Node3D, s: float, spin: float) -> void:
	if b is CharacterBody3D:
		return
	var rot := Basis(Vector3.UP, spin)
	for v in _visuals(b):
		var node: Node3D = v[0]
		var orig: Transform3D = v[1]
		if is_instance_valid(node):
			node.transform = Transform3D(rot * orig.basis.scaled(Vector3.ONE * s), rot * (orig.origin * s))
	if s >= 0.999 and spin == 0.0:
		_spin.erase(b.get_instance_id())


static func restore_visual(b: Node3D) -> void:
	if not b.has_meta("gw_visuals"):
		return
	for v in b.get_meta("gw_visuals"):
		if is_instance_valid(v[0]):
			(v[0] as Node3D).transform = v[1]


func _restore_visual_smooth(b: Node3D) -> void:
	var start_s := min_visual_scale
	var spin: float = _spin.get(b.get_instance_id(), 0.0)
	var tw := b.create_tween()
	tw.tween_method(func(k: float) -> void:
		var s := lerpf(start_s, 1.0, k)
		var rot := Basis(Vector3.UP, spin * (1.0 - k))
		for v in _visuals(b):
			if is_instance_valid(v[0]):
				var orig: Transform3D = v[1]
				(v[0] as Node3D).transform = Transform3D(rot * orig.basis.scaled(Vector3.ONE * s), rot * (orig.origin * s)),
		0.0, 1.0, 0.3)
	_spin.erase(b.get_instance_id())
