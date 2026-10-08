class_name RecoveryDrops
extends Node3D
## Health / armour energy shards dropped by light robots (DOOM-style
## recovery loop). One pooled manager per scene: shards are plain meshes
## moved in code (no physics bodies, no lights), at most `max_active`.
##
## RobotEnemy.die() calls `RecoveryDrops.on_enemy_killed(robot, info)`.
## Killing `streak_kills` enemies within `streak_window` s boosts shard
## value by `streak_bonus` for `streak_duration` s.

signal collected(kind: int, amount: float)
signal streak_started

enum Kind { HEALTH, ARMOUR }

const GROUP := &"recovery_drops"
const COLORS := [Color(0.25, 1.0, 0.35), Color(0.3, 0.6, 1.0)]

@export var health_value := 8.0
@export var armour_value := 6.0
@export var drops_per_kill := 1
@export var magnet_radius := 3.0
@export var collect_radius := 1.5
@export var lifetime := 10.0
@export var max_active := 16
@export_group("Kill streak")
@export var streak_kills := 3
@export var streak_window := 5.0
@export var streak_bonus := 0.25
@export var streak_duration := 6.0
@export_group("")

var _pool: Array[Shard] = []
var _kill_times: Array[float] = []
var _bonus_until := -1.0
var _clock := 0.0
static var _mesh: Mesh
static var _mats: Array[StandardMaterial3D] = []


class Shard:
	var node: Node3D
	var core: MeshInstance3D
	var glow: MeshInstance3D
	var kind := 0
	var value := 0.0
	var vel := Vector3.ZERO
	var floor_y := 0.0
	var age := 0.0
	var active := false
	var magnet := false


## The scene's manager (created on first use).
static func get_for(tree: SceneTree) -> RecoveryDrops:
	var m := tree.get_first_node_in_group(GROUP) as RecoveryDrops
	if m == null:
		m = RecoveryDrops.new()
		m.name = "RecoveryDrops"
		(tree.current_scene if tree.current_scene else tree.root).add_child(m)
	return m


static func on_enemy_killed(enemy: Node3D, info: DamageInfo) -> void:
	if enemy.is_inside_tree():
		var m := get_for(enemy.get_tree())
		if m:
			m.enemy_killed(enemy.global_position, info)


## Player respawn / level restart: remove every shard.
static func clear_all(tree: SceneTree) -> void:
	var m := tree.get_first_node_in_group(GROUP) as RecoveryDrops
	if m:
		m.clear()


func _ready() -> void:
	add_to_group(GROUP)
	top_level = true


func bonus_active() -> bool:
	return _clock < _bonus_until


func active_count() -> int:
	var n := 0
	for s in _pool:
		n += int(s.active)
	return n


func clear() -> void:
	for s in _pool:
		_release(s)


func enemy_killed(at: Vector3, info: DamageInfo) -> void:
	# Rolling kill window -> temporary value bonus.
	_kill_times.append(_clock)
	while not _kill_times.is_empty() and _clock - _kill_times[0] > streak_window:
		_kill_times.pop_front()
	if _kill_times.size() >= streak_kills:
		if not bonus_active():
			streak_started.emit()
		_bonus_until = _clock + streak_duration
		_kill_times.clear()
	var player := _player_for(at, info)
	var mult := 1.0 + (streak_bonus if bonus_active() else 0.0)
	for i in drops_per_kill:
		var kind := _choose_kind(player)
		spawn(kind, at + Vector3.UP * 1.0, (health_value if kind == Kind.HEALTH else armour_value) * mult)


## Lower of health / armour (as a share of its maximum) wins; ties -> health.
func _choose_kind(player: PlayerController) -> int:
	if player == null:
		return Kind.HEALTH
	var h := player.health / maxf(player.max_health, 1.0)
	var a := player.armour / maxf(player.max_armour, 1.0)
	return Kind.ARMOUR if a < h else Kind.HEALTH


func _player_for(at: Vector3, info: DamageInfo) -> PlayerController:
	if info and info.source is PlayerController:
		return info.source
	var best: PlayerController = null
	var bd := INF
	for p in get_tree().get_nodes_in_group(&"players"):
		var pc := p as PlayerController
		if pc:
			var d := pc.global_position.distance_squared_to(at)
			if d < bd:
				bd = d
				best = pc
	return best


func spawn(kind: int, at: Vector3, value: float) -> void:
	var s := _take()
	s.kind = kind
	s.value = value
	s.age = 0.0
	s.magnet = false
	s.active = true
	var a := randf() * TAU
	s.vel = Vector3(cos(a), 0.0, sin(a)) * randf_range(1.8, 3.2) + Vector3.UP * randf_range(3.5, 4.5)
	s.core.material_override = _mats[kind]
	s.glow.material_override = Vfx.material("glow", COLORS[kind] * 0.55, BaseMaterial3D.BILLBOARD_ENABLED)
	var big := 1.0 + clampf(value / (health_value if kind == Kind.HEALTH else armour_value) - 1.0, 0.0, 1.0)
	s.node.scale = Vector3.ONE * big
	s.node.global_position = at
	s.node.visible = true
	# One ray for the floor under it; it bounces on that height.
	s.floor_y = at.y - 3.0
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 8.0, 1))
	if not hit.is_empty():
		s.floor_y = hit.position.y


func _take() -> Shard:
	for s in _pool:
		if not s.active:
			return s
	if _pool.size() < max_active:
		var s := _make()
		_pool.append(s)
		return s
	# Full: recycle the oldest.
	var oldest := _pool[0]
	for s in _pool:
		if s.age > oldest.age:
			oldest = s
	return oldest


func _make() -> Shard:
	if _mesh == null:
		var m := SphereMesh.new()  # 4 sides, 1 ring = a crystal (octahedron)
		m.radial_segments = 4
		m.rings = 1
		m.radius = 0.1
		m.height = 0.34
		_mesh = m
		for c: Color in COLORS:
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = c.lerp(Color.WHITE, 0.35)
			mat.disable_receive_shadows = true
			_mats.append(mat)
	var s := Shard.new()
	s.node = Node3D.new()
	add_child(s.node)
	s.core = MeshInstance3D.new()
	s.core.mesh = _mesh
	s.core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.node.add_child(s.core)
	s.glow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.75, 0.75)
	s.glow.mesh = q
	s.glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.node.add_child(s.glow)
	s.node.visible = false
	return s


func _release(s: Shard) -> void:
	s.active = false
	s.node.visible = false


func _physics_process(delta: float) -> void:
	_clock += delta
	var players := get_tree().get_nodes_in_group(&"players")
	for s in _pool:
		if s.active:
			_step(s, delta, players)


func _step(s: Shard, delta: float, players: Array) -> void:
	s.age += delta
	if s.age >= lifetime:
		_release(s)
		return
	var pos := s.node.global_position
	# Nearest player that can still use this kind.
	var target: PlayerController = null
	var td := INF
	for p in players:
		var pc := p as PlayerController
		if pc == null or _full(pc, s.kind):
			continue
		var d := pos.distance_to(pc.global_position + Vector3.UP * 0.9)
		if d < td:
			td = d
			target = pc
	if target and s.age > 0.35 and td <= collect_radius:
		var got := target.heal(s.value) if s.kind == Kind.HEALTH else target.add_armour(s.value)
		collected.emit(s.kind, got)
		_release(s)
		return
	if target and s.age > 0.35 and td <= magnet_radius:
		s.magnet = true
	if s.magnet and target:
		var to := target.global_position + Vector3.UP * 0.9 - pos
		var want := to.normalized() * lerpf(14.0, 6.0, clampf(to.length() / magnet_radius, 0.0, 1.0))
		s.vel = s.vel.lerp(want, 1.0 - exp(-10.0 * delta))
	else:
		s.magnet = false
		s.vel.y -= 14.0 * delta
		s.vel.x *= exp(-1.5 * delta)
		s.vel.z *= exp(-1.5 * delta)
	pos += s.vel * delta
	var rest := s.floor_y + 0.35
	if not s.magnet and pos.y < rest:
		pos.y = rest
		s.vel.y = absf(s.vel.y) * 0.35 if absf(s.vel.y) > 1.0 else 0.0
		# Skids to a stop on the floor.
		s.vel.x *= exp(-8.0 * delta)
		s.vel.z *= exp(-8.0 * delta)
	s.node.global_position = pos
	# Hover bob + spin once resting; blink out over the last 2 s.
	s.core.position.y = sin(s.age * 4.0) * 0.06
	s.core.rotation.y = s.age * 3.0
	s.glow.scale = Vector3.ONE * (1.0 + 0.15 * sin(s.age * 7.0))
	var left := lifetime - s.age
	s.node.visible = left > 2.0 or fmod(left, 0.25) > 0.1


func _full(p: PlayerController, kind: int) -> bool:
	return p.health >= p.max_health if kind == Kind.HEALTH else p.armour >= p.max_armour
