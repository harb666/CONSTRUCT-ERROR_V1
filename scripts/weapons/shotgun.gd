class_name Shotgun
extends Weapon
## Five-barrel energy shotgun. Every shot fires all five barrels at once:
## one extremely fast spiral energy stream per barrel (ShotgunStream), a
## combined flaming muzzle flash across the barrel cluster (ShotgunFlash) and
## orange impacts (pooled PlasmaFx). Self-contained: any WeaponSlot can hold
## it (either arm, alongside any other weapon); all behaviour lives here.
##
## Shotgun behaviour: the streams leave in a pattern around the aim line whose
## angle grows smoothly with distance (tight up close, separating further
## out), so fewer streams reach the locked enemy the further away it is, and
## each stream's damage also falls from `close_range_damage` to
## `damage_per_stream`. At medium range the outer streams may bend slightly
## (`assist_strength`) towards other enemies standing near the locked one,
## for reduced damage (`secondary_damage_multiplier`).
##
## Hits are decided by one ray per stream at the moment of firing; the damage
## lands when the visible stream arrives (distance / `stream_speed`).

## Barrel markers in the scene (Muzzle_1..Muzzle_5), +X = firing direction.
const BARREL_MARKERS := ["Muzzle_1", "Muzzle_2", "Muzzle_3", "Muzzle_4", "Muzzle_5"]

@export_group("Damage")
## Damage of one stream at long range.
@export var damage_per_stream := 0.25
## Damage of one stream at point blank (up to `close_range`).
@export var close_range_damage := 0.6
## Up to this distance (m) streams do full close-range damage and stay tight.
@export var close_range := 4.0
## Streams fade out here (m); damage reaches `damage_per_stream` by then.
@export var max_range := 26.0
## Impact force of one stream up close (knock/break-apart power), long range.
@export var close_impact_force := 9.0
@export var far_impact_force := 2.0

@export_group("Spread")
## Spread angle (degrees, outer streams) inside `close_range`.
@export var spread_deg := 1.0
## Extra spread per metre beyond `close_range` (degrees/m).
@export var spread_growth_deg_per_m := 0.9
@export var max_spread_deg := 14.0
## How far out each stream sits in the pattern (0 = on the aim line, 1 =
## full spread): the first stays central, the others ring around it.
@export var stream_spread_scale: PackedFloat32Array = [0.05, 0.14, 0.25, 0.43, 0.95]
## Random wobble of the pattern per shot (fraction of the spread).
@export var spread_jitter := 0.25

@export_group("Secondary targets")
## Outer streams may bend towards other enemies within this radius (m) of
## the locked enemy, from `assist_min_range` out.
@export var secondary_search_radius := 4.0
@export var assist_min_range := 6.0
## 0 = no assistance, 1 = bends fully onto the secondary enemy. Only the
## outer streams (pattern scale >= `assist_min_scale`) whose own direction
## already passes within `assist_cone_deg` of an enemy are bent, at most one
## per enemy per shot, so it stays a spread, not homing.
@export_range(0.0, 1.0) var assist_strength := 0.85
@export var assist_cone_deg := 12.0
@export var assist_min_scale := 0.4
## Damage multiplier for assisted streams hitting a secondary enemy.
@export var secondary_damage_multiplier := 0.3

@export_group("Firing")
## Shots per second.
@export var fire_rate := 1.1
## Visible stream speed (m/s): fast enough to feel instant, slow enough to see.
@export var stream_speed := 170.0
@export var stream_color := Color(1.0, 0.36, 0.03)
@export var stream_hot_color := Color(1.0, 0.85, 0.5)
## Bodies in this group are passed through (no friendly fire).
@export var pass_group := &"players"

@export_group("Muzzle flash")
## Overall brightness/size of the muzzle flash and its light (1 = default).
@export var muzzle_flash_intensity := 1.0

var shots_fired := 0
## Per stream of the last shot: {from, to, collider, target, assisted, damage}.
var last_shot: Array = []

var _cool := 0.0
var _barrels: Array[Node3D] = []
var _flash: ShotgunFlash


func _ready() -> void:
	for n in BARREL_MARKERS:
		var m := find_marker(n)
		if m:
			_barrels.append(m)
	# One flash per gun, restarted every shot (no allocations while firing).
	var locals: Array[Vector3] = []
	for b in _barrels:
		locals.append(b.position)  # markers are direct children
	_flash = ShotgunFlash.new()
	_flash.name = "MuzzleFlash"
	_flash.barrels = locals
	add_child(_flash)


func _process(delta: float) -> void:
	_cool = maxf(_cool - delta, 0.0)


func can_fire() -> bool:
	return _cool <= 0.0


func barrel_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for b in _barrels:
		out.append(b.global_position)
	return out


## Spread angle (radians) for a target `dist` metres away.
func spread_at(dist: float) -> float:
	var deg := spread_deg + spread_growth_deg_per_m * maxf(dist - close_range, 0.0)
	return deg_to_rad(minf(deg, max_spread_deg))


## Damage of one stream that travelled `dist` metres.
func damage_at(dist: float) -> float:
	var t := clampf((dist - close_range) / maxf(max_range - close_range, 0.01), 0.0, 1.0)
	return lerpf(close_range_damage, damage_per_stream, t)


func fire_at(shooter: Node3D, target_point: Vector3) -> bool:
	if not can_fire() or _barrels.is_empty():
		return false
	_cool = 1.0 / maxf(fire_rate, 0.01)
	var centre := _cluster_centre()
	var aim := (target_point - centre)
	var dist := aim.length()
	var aim_dir := aim / dist if dist > 0.01 else get_barrel_direction()
	var primary := _target_near(target_point)
	var spread := spread_at(dist)
	# Pattern basis around the aim line, rolled with the gun so the pattern
	# matches the barrel layout (top barrel up, etc.).
	var up := global_basis.y.normalized()
	var side := aim_dir.cross(up).normalized()
	if side.length_squared() < 0.5:
		side = aim_dir.cross(Vector3.UP).normalized()
	up = side.cross(aim_dir).normalized()
	var roll := randf_range(-0.4, 0.4)
	var others := _secondary_candidates(primary, dist)
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if shooter is CollisionObject3D:
		exclude.append((shooter as CollisionObject3D).get_rid())
	last_shot.clear()
	for i in _barrels.size():
		var from := _barrels[i].global_position
		# Each stream's slot in the pattern follows its barrel's position
		# around the cluster (so streams never cross), scaled per stream.
		var off := _barrels[i].global_position - centre
		var ang := atan2(off.dot(up), off.dot(side)) + roll
		var k: float = stream_spread_scale[i] if i < stream_spread_scale.size() else 1.0
		k *= 1.0 + randf_range(-spread_jitter, spread_jitter)
		var tilt := spread * k
		var radial := (side * cos(ang) + up * sin(ang)).normalized()
		var dir := (aim_dir * cos(tilt) + radial * sin(tilt)).normalized()
		# From its own barrel, converge on the aim line's pattern point.
		var goal := centre + dir * dist
		dir = (goal - from).normalized() if goal.distance_to(from) > 0.05 else dir
		var leave := dir
		var assisted: Targetable = null
		if (stream_spread_scale[i] if i < stream_spread_scale.size() else 1.0) >= assist_min_scale and not others.is_empty():
			assisted = _assist_target(from, dir, others)
			if assisted:
				others.erase(assisted)  # one assisted stream per enemy
				var to_sec := (assisted.get_aim_point() - from).normalized()
				dir = dir.slerp(to_sec, assist_strength).normalized()
		_fire_stream(space, exclude, shooter, from, dir, leave, primary, assisted)
	_flash.play(muzzle_flash_intensity)
	shots_fired += 1
	recoiled.emit(recoil_strength)
	return true


func _fire_stream(space: PhysicsDirectSpaceState3D, exclude: Array[RID], shooter: Node3D,
		from: Vector3, dir: Vector3, leave_dir: Vector3, primary: Targetable, assisted: Targetable) -> void:
	var end := from + dir * max_range
	var hit := {}
	var ex := exclude.duplicate()
	for guard in 4:
		var q := PhysicsRayQueryParameters3D.create(from, end)
		q.collision_mask = 1  # world, props, players, enemies (not debris)
		q.exclude = ex
		hit = space.intersect_ray(q)
		if hit.is_empty():
			break
		var col: Object = hit.collider
		if col is Node and (col as Node).is_in_group(pass_group):
			ex.append(hit.rid)
			hit = {}
			continue
		break
	var to: Vector3 = hit.position if not hit.is_empty() else end
	var col: Object = hit.collider if not hit.is_empty() else null
	var normal: Vector3 = hit.normal if not hit.is_empty() else -dir
	var travelled := from.distance_to(to)
	var dmg := damage_at(travelled)
	var target_hit := _targetable_of(col)
	var secondary := assisted != null and target_hit != null and target_hit != primary
	if secondary:
		dmg *= secondary_damage_multiplier
	var t := clampf((travelled - close_range) / maxf(max_range - close_range, 0.01), 0.0, 1.0)
	var force := lerpf(close_impact_force, far_impact_force, t)
	last_shot.append({"from": from, "to": to, "collider": col, "target": target_hit,
		"assisted": assisted != null, "secondary": secondary, "damage": dmg if col else 0.0})
	# Visible stream; the hit (plain data, so it still lands if this gun is
	# unequipped meanwhile) is applied when the stream arrives.
	ShotgunStream.fire(get_tree(), from, to, leave_dir, stream_speed, stream_color, stream_hot_color, {
		"collider": col, "at": to, "normal": normal, "dir": dir, "damage": dmg, "force": force,
		"shooter": shooter, "color": stream_color, "hot": stream_hot_color})


## Apply one stream's hit (called by ShotgunStream when it arrives).
static func land_stream(tree: SceneTree, hit: Dictionary) -> void:
	# The target may have been freed while the stream was in flight.
	if not is_instance_valid(hit.get("collider")):
		return
	var col: Object = hit.collider
	var at: Vector3 = hit.at
	var dir: Vector3 = hit.dir
	var force: float = hit.force
	if col.has_method("apply_damage"):
		var shooter: Node = hit.shooter if is_instance_valid(hit.get("shooter")) else null
		var info := DamageInfo.make(hit.damage, DamageInfo.Type.ENERGY, at, dir, force, 0.0, shooter)
		info.weapon = &"shotgun"
		col.apply_damage(info)
	elif col is RigidBody3D and not (col as RigidBody3D).freeze:
		(col as RigidBody3D).apply_impulse(dir * force * 0.6, at - (col as RigidBody3D).global_position)
	PlasmaFx.impact(tree, at, hit.normal, col is StaticBody3D, hit.color, hit.hot)


## Centre of the barrel cluster (the hub between the five barrels).
func _cluster_centre() -> Vector3:
	var c := Vector3.ZERO
	for b in _barrels:
		c += b.global_position
	return c / maxf(_barrels.size(), 1)


func _target_near(point: Vector3) -> Targetable:
	var best: Targetable = null
	var best_d := 0.75
	for t: Targetable in Targetable.all():
		var d := t.get_aim_point().distance_to(point)
		if d < best_d:
			best_d = d
			best = t
	return best


## Enemies near the locked one, when it is far enough for assistance.
func _secondary_candidates(primary: Targetable, dist: float) -> Array[Targetable]:
	var out: Array[Targetable] = []
	if primary == null or assist_strength <= 0.0 or dist < assist_min_range:
		return out
	var c := primary.get_aim_point()
	for t: Targetable in Targetable.all():
		if t == primary or not t.is_valid_target():
			continue
		if t.get_aim_point().distance_to(c) <= secondary_search_radius:
			out.append(t)
	return out


## The secondary enemy this stream already nearly points at, if any.
func _assist_target(from: Vector3, dir: Vector3, others: Array[Targetable]) -> Targetable:
	var best: Targetable = null
	var best_a := deg_to_rad(assist_cone_deg)
	for t in others:
		var a := dir.angle_to(t.get_aim_point() - from)
		if a < best_a:
			best_a = a
			best = t
	return best


static func _targetable_of(col: Object) -> Targetable:
	if col is Node:
		var n := col as Node
		var t := n.get_node_or_null("Targetable") as Targetable
		if t:
			return t
		for c in n.get_children():
			if c is Targetable:
				return c
	return null


func on_displayed() -> void:
	super.on_displayed()
	set_process(false)
