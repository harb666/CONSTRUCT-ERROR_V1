class_name PlasmaBolt
extends Node3D
## Fast plasma projectile (robot hand cannons: green; the player's default
## cannons: cyan). Pooled; moves with one ray cast per physics tick (no
## physics body), passes through its shooter's own side (`pass_group`), and
## on impact deals DamageInfo, nudges props and spawns PlasmaFx.impact.
## Visual: a hot glowing core plus a camera-facing trail ribbon.

const POOL_SIZE := 64
const GREEN := Color(0.15, 1.0, 0.1)
const HOT := Color(0.6, 1.0, 0.45)

static var _pool: Array[PlasmaBolt] = []
static var _next := 0

var speed := 30.0
var damage := 1.0
var max_range := 45.0
var velocity := Vector3.ZERO
var shooter: Node
var active := false
## Bodies in this group are flown through (the shooter's own side).
var pass_group := &"enemies"
var color := GREEN
var hot := HOT
## Impact scorch: how long it glows, and whether it crackles (set after fire()).
var mark_life := 1.3
var crackle := true
## Visual size of the bolt and its trail (set after fire()).
var size := 1.0
## Electrical flicker of the glow/trail (0 = steady), and a brief light at
## the impact (shared PlasmaFx light pool); set after fire().
var flicker := 0.0
## Copied into the DamageInfo it delivers (DamageInfo.weapon).
var weapon_tag := &"plasma"
## Arm that fired it (player weapons set it after fire()).
var arm_side := &""
## Unique per launch (pooled bolts are reused, so the node isn't an id).
var serial := 0
static var _serials := 0
var impact_light := false
## Size of the impact splash (1 = standard).
var impact_scale := 1.0

var _core: MeshInstance3D
var _glow: MeshInstance3D
var _trail: MeshInstance3D
var _travelled := 0.0
var _exclude: Array[RID] = []
var _tail := Vector3.ZERO


## Tint the trail ribbon separately from the glow (call after fire()).
func set_trail_color(c: Color) -> void:
	((_trail as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = c


## Fire a bolt from `from` along `dir`.
static func fire(tree: SceneTree, from: Vector3, dir: Vector3, by: Node, bolt_speed := 30.0, dmg := 1.0,
		col := GREEN, hot_col := HOT, through := &"enemies") -> PlasmaBolt:
	var b := _take(tree)
	if b == null:
		return null
	b.pass_group = through
	b.weapon_tag = &"plasma"
	b.arm_side = &""
	_serials += 1
	b.serial = _serials
	b._set_colors(col, hot_col)
	b._launch(from, dir.normalized(), by, bolt_speed, dmg)
	return b


static func _take(tree: SceneTree) -> PlasmaBolt:
	var host: Node = tree.current_scene if tree.current_scene else tree.root
	_pool = _pool.filter(func(p: PlasmaBolt) -> bool: return is_instance_valid(p) and p.is_inside_tree())
	for p in _pool:
		if not p.active:
			return p
	if _pool.size() < POOL_SIZE:
		var b := PlasmaBolt.new()
		host.add_child(b)
		_pool.append(b)
		return b
	# All busy: recycle the oldest in flight.
	_next = (_next + 1) % _pool.size()
	return _pool[_next]


## Bolts in flight (e.g. for enemies that react to incoming fire).
static func in_flight() -> Array[PlasmaBolt]:
	var out: Array[PlasmaBolt] = []
	for p in _pool:
		if is_instance_valid(p) and p.active:
			out.append(p)
	return out


static func active_count() -> int:
	var n := 0
	for p in _pool:
		if is_instance_valid(p) and p.active:
			n += 1
	return n


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_trail = Vfx.quad("glow", color, Vector2.ONE)
	_trail.top_level = true
	add_child(_trail)
	_glow = Vfx.quad("glow", color, Vector2.ONE)
	_glow.top_level = true
	add_child(_glow)
	_core = Vfx.quad("glow", hot, Vector2.ONE)
	_core.top_level = true
	add_child(_core)
	for q in [_trail, _glow, _core]:
		(q as MeshInstance3D).extra_cull_margin = 4.0
	visible = false
	set_physics_process(false)
	set_process(false)


func _set_colors(c: Color, h: Color) -> void:
	color = c
	hot = h
	if _trail == null:
		return  # not ready yet: _ready() builds with these colours
	for q in [_trail, _glow]:
		((q as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = c
	(_core.material_override as StandardMaterial3D).albedo_color = h


func _launch(from: Vector3, dir: Vector3, by: Node, bolt_speed: float, dmg: float) -> void:
	shooter = by
	mark_life = 1.3
	crackle = true
	size = 1.0
	flicker = 0.0
	impact_light = false
	impact_scale = 1.0
	speed = bolt_speed
	damage = dmg
	velocity = dir * speed
	global_position = from
	_tail = from
	_travelled = 0.0
	_exclude.clear()
	if by is CollisionObject3D:
		_exclude.append((by as CollisionObject3D).get_rid())
	active = true
	visible = true
	set_physics_process(true)
	set_process(true)


func _physics_process(delta: float) -> void:
	var from := global_position
	var motion := velocity * delta
	var space := get_world_3d().direct_space_state
	var guard := 0
	while guard < 4:
		guard += 1
		var q := PhysicsRayQueryParameters3D.create(from, from + motion)
		q.collision_mask = 1  # world, props, players, enemies (not debris)
		q.exclude = _exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var col: Object = hit.collider
		if col is Node and (col as Node).is_in_group(pass_group):
			# No friendly fire: fly on through.
			_exclude.append(hit.rid)
			continue
		_impact(hit.position, hit.normal, col)
		return
	global_position = from + motion
	_travelled += motion.length()
	if _travelled >= max_range:
		_stop()


func _impact(at: Vector3, normal: Vector3, col: Object) -> void:
	if col and col.has_method("apply_damage"):
		# The shooter may be gone by the time the bolt lands.
		var src: Node = shooter if is_instance_valid(shooter) else null
		var info := DamageInfo.make(damage, DamageInfo.Type.ENERGY, at, velocity.normalized(), 2.0, 0.0, src)
		info.weapon = weapon_tag
		info.arm = arm_side
		info.projectile_serial = serial
		col.apply_damage(info)
	elif col is RigidBody3D and not (col as RigidBody3D).freeze:
		(col as RigidBody3D).apply_impulse(velocity.normalized() * 2.5, at - (col as RigidBody3D).global_position)
	# Scorch marks only on solid level geometry (they don't follow movers).
	PlasmaFx.impact(get_tree(), at, normal, col is StaticBody3D, color, hot, mark_life, crackle, impact_scale)
	if impact_light:
		PlasmaFx.flash_light(get_tree(), at + normal * 0.25, color, 1.6)
	_stop()


func _stop() -> void:
	active = false
	visible = false
	set_physics_process(false)
	set_process(false)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var head := global_position
	var fl := 1.0 + (randf_range(-flicker, flicker) if flicker > 0.0 else 0.0)
	Vfx.face_camera(_core, 0.3 * size)
	Vfx.face_camera(_glow, 0.85 * size * fl, randf() * TAU if flicker > 0.0 else 0.0)
	_core.global_position = head
	_glow.global_position = head
	# Trail: a ribbon from the head back along the flight path.
	var dir := velocity.normalized()
	var length := minf(_travelled + 0.05, 1.6 * size)
	var a := head
	var b := head - dir * length
	var axis := b - a
	var y := axis / maxf(length, 0.001)
	var x := y.cross((cam.global_position - (a + b) * 0.5).normalized()).normalized()
	var z := x.cross(y)
	_trail.global_transform = Transform3D(Basis(x * 0.3 * size * fl, y * length, z), (a + b) * 0.5)
