class_name RecoveryDrops
extends Node3D
## Pick-ups dropped by robots (DOOM-style recovery loop). One pooled manager
## per scene: pick-ups are plain meshes moved in code (no physics bodies,
## no lights), at most `max_active`.
##  - Health: a 3D cross "+"; armour: a 3D green shield (owner asked). Every
##    kill drops one (whichever the player is lower on).
##  - Ammo: a 3D bullet in the weapon's colour, its icon over it (owner
##    asked), worth its `ammo_pack`. DOOM Eternal style (owner asked: "only
##    drop when the player melees and kills the enemy" - else a weapon
##    never runs down): only a player's MELEE kill drops ammo -
##    `melee_ammo_packs` (grunt 2, skirmisher / sentinel 3) for the local
##    player's weapons that aren't full, emptiest first.
##  - Bitcoin tokens (owner asked: an in-game currency): small gold coins
##    that burst out of every robot killed - more from stronger ones
##    (`token_count`: grunt 4, skirmisher 7, sentinel 9, boss 30) - and go
##    sooner (`token_lifetime`). Each is 1 to the player's
##    `PlayerController.bitcoins`.
## All of them bob, spin and glitch now and then (a jump sideways, a
## stretch and a cyan / magenta flash), and are pulled in to the player
## from `magnet_radius` (7 m - owner asked: "more magnetic", so ones that
## fall off an edge still come). Ammo and tokens are only taken by this
## device's own player (each device drops its own; co-op).
##
## RobotEnemy.die() calls `RecoveryDrops.on_enemy_killed(robot, info)`.
## Killing `streak_kills` enemies within `streak_window` s boosts shard
## value by `streak_bonus` for `streak_duration` s.

signal collected(kind: int, amount: float)
signal ammo_collected(definition: WeaponDefinition, amount: int)
signal streak_started

enum Kind { HEALTH, ARMOUR, AMMO, TOKEN }

const GROUP := &"recovery_drops"
const COLORS := [Color(0.25, 1.0, 0.35), Color(0.1, 0.8, 0.45), Color(1.0, 0.8, 0.3), Color(1.0, 0.76, 0.18)]
const COIN_FACE := preload("res://assets/ui/pickups/bitcoin_face.png")
const GLITCH := [Color(0.0, 0.95, 1.0), Color(1.0, 0.1, 0.85)]

@export var health_value := 8.0
@export var armour_value := 6.0
@export var drops_per_kill := 1
@export var magnet_radius := 7.0
@export var collect_radius := 1.6
@export var lifetime := 10.0
## Tokens go sooner than the other pick-ups.
@export var token_lifetime := 5.0
@export var max_active := 80
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
## Dropped (tests).
var ammo_dropped := 0
var tokens_dropped := 0
static var _meshes := {}
static var _glitch_mats: Array[StandardMaterial3D] = []
static var _glow_quad: QuadMesh


class Shard:
	var node: Node3D
	var core: MeshInstance3D
	var glow: MeshInstance3D
	var kind := 0
	var value := 0.0
	var vel := Vector3.ZERO
	var floor_y := 0.0
	var age := 0.0
	var life := 10.0
	var active := false
	var magnet := false
	## Ammo: the weapon it's for, and its icon over it.
	var weapon: WeaponDefinition
	var icon: Sprite3D
	## Glitching: seconds until the next one, and left of this one.
	var glitch_in := 1.0
	var glitch_left := 0.0
	var spin0 := 0.0


## The scene's manager (created on first use).
static func get_for(tree: SceneTree) -> RecoveryDrops:
	var m := tree.get_first_node_in_group(GROUP) as RecoveryDrops
	if m == null:
		m = RecoveryDrops.new()
		m.name = "RecoveryDrops"
		(tree.current_scene if tree.current_scene else tree.root).add_child(m)
	return m


static func on_enemy_killed(enemy: Node3D, info: DamageInfo, shards := true) -> void:
	if enemy.is_inside_tree():
		var m := get_for(enemy.get_tree())
		if m:
			var at := enemy.global_position
			if shards:
				m.enemy_killed(at, info)
			if info and info.weapon == &"melee":
				m.drop_ammo(at, melee_ammo_packs(enemy))
			m.drop_tokens(at, token_count(enemy))


## Ammo bullets a melee kill drops: bigger enemies, more.
static func melee_ammo_packs(enemy: Node) -> int:
	if enemy is RobotSentinel or enemy is RobotSkirmisher:
		return 3
	return 2


## Bitcoin tokens a robot bursts into: the stronger, the more.
static func token_count(enemy: Node) -> int:
	if enemy is RobotBoss:
		return 30
	if enemy is RobotSentinel:
		return 9
	if enemy is RobotSkirmisher:
		return 7
	return 4


## Ammo for the local player's weapons that want it, emptiest first
## (several bullets go round them).
func drop_ammo(at: Vector3, packs: int) -> void:
	var player := get_tree().get_first_node_in_group(&"local_player") as PlayerController
	var lo := player.get_node_or_null("WeaponLoadout") as WeaponLoadout if player else null
	if lo == null:
		return
	var wanted := lo.ammo_wanted()
	if wanted.is_empty():
		return
	for i in packs:
		var def: WeaponDefinition = wanted[i % wanted.size()]
		spawn_ammo(def, at + Vector3.UP * 1.0)


func spawn_ammo(def: WeaponDefinition, at: Vector3) -> void:
	spawn(Kind.AMMO, at, def.ammo_pack)
	var s := _last
	s.weapon = def
	s.core.mesh = _bullet_mesh(def.accent_color)
	s.glow.material_override = Vfx.material("glow", def.accent_color * 0.6, BaseMaterial3D.BILLBOARD_ENABLED)
	var icon := _icon_of(s)
	icon.texture = def.icon
	icon.visible = def.icon != null
	ammo_dropped += 1


## A burst of bitcoin tokens out of a dead robot.
func drop_tokens(at: Vector3, n: int) -> void:
	for i in n:
		spawn(Kind.TOKEN, at + Vector3.UP * 1.0, 1.0)
		var a := randf() * TAU
		_last.vel = Vector3(cos(a), 0.0, sin(a)) * randf_range(2.5, 6.0) + Vector3.UP * randf_range(4.0, 8.0)
		tokens_dropped += 1


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


## Pick-ups out (of one kind, or all).
func active_count(kind := -1) -> int:
	var n := 0
	for s in _pool:
		n += int(s.active and (kind < 0 or s.kind == kind))
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


var _last: Shard


func spawn(kind: int, at: Vector3, value: float) -> void:
	var s := _take()
	_last = s
	s.kind = kind
	s.value = value
	s.age = 0.0
	s.life = token_lifetime if kind == Kind.TOKEN else lifetime
	s.magnet = false
	s.active = true
	s.weapon = null
	if s.icon:
		s.icon.visible = false
	s.core.mesh = _mesh_for(kind)
	s.core.material_override = null
	s.core.rotation = Vector3.ZERO
	s.core.position = Vector3.ZERO
	s.core.scale = Vector3.ONE
	s.glitch_in = randf_range(0.4, 1.6)
	s.glitch_left = 0.0
	s.spin0 = randf() * TAU
	var a := randf() * TAU
	s.vel = Vector3(cos(a), 0.0, sin(a)) * randf_range(1.8, 3.2) + Vector3.UP * randf_range(3.5, 4.5)
	var glow_size := 0.45 if kind == Kind.TOKEN else 1.0
	s.glow.scale = Vector3.ONE * glow_size
	s.glow.material_override = Vfx.material("glow", COLORS[kind] * (0.4 if kind == Kind.TOKEN else 0.55), BaseMaterial3D.BILLBOARD_ENABLED)
	var big := 1.0
	if kind == Kind.HEALTH or kind == Kind.ARMOUR:
		big = 1.0 + clampf(value / (health_value if kind == Kind.HEALTH else armour_value) - 1.0, 0.0, 1.0)
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
	var s := Shard.new()
	s.node = Node3D.new()
	add_child(s.node)
	s.core = MeshInstance3D.new()
	s.core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.node.add_child(s.core)
	s.glow = MeshInstance3D.new()
	if _glow_quad == null:
		_glow_quad = QuadMesh.new()  # one for all of them
		_glow_quad.size = Vector2(0.75, 0.75)
	s.glow.mesh = _glow_quad
	s.glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.node.add_child(s.glow)
	s.node.visible = false
	return s


## The weapon icon over an ammo bullet (made the first time this pick-up
## is ammo - tokens and the others never need one).
func _icon_of(s: Shard) -> Sprite3D:
	if s.icon == null:
		s.icon = Sprite3D.new()
		s.icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.icon.pixel_size = 0.0022
		s.icon.position.y = 0.5
		s.icon.shaded = false
		s.icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.node.add_child(s.icon)
	return s.icon


# --- The pick-ups' models (built once, shared) ---

static func _material(col: Color, glow := 0.45) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.35
	m.roughness = 0.3
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = glow
	m.rim_enabled = true
	m.rim = 0.6
	return m


static func _mesh_for(kind: int) -> Mesh:
	var key := "kind%d" % kind
	if _meshes.has(key):
		return _meshes[key]
	var m: Mesh = null
	match kind:
		Kind.HEALTH:
			m = _cross_mesh()
		Kind.ARMOUR:
			m = _shield_mesh()
		Kind.TOKEN:
			m = _coin_mesh()
		_:
			m = _bullet_mesh(COLORS[Kind.AMMO])
	_meshes[key] = m
	return m


## Health: a chunky 3D "+" (the old crystal's size).
static func _cross_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sz: Vector3 in [Vector3(0.32, 0.11, 0.11), Vector3(0.11, 0.32, 0.11)]:
		var b := BoxMesh.new()
		b.size = sz
		st.append_from(b, 0, Transform3D.IDENTITY)
	st.set_material(_material(COLORS[Kind.HEALTH].lerp(Color.WHITE, 0.15), 0.6))
	return st.commit()


## Armour: a green heater shield, a raised lighter boss on its front.
static func _shield_mesh() -> Mesh:
	var outline := PackedVector2Array([Vector2(-0.13, 0.14), Vector2(0.13, 0.14), Vector2(0.135, 0.03),
		Vector2(0.115, -0.05), Vector2(0.07, -0.115), Vector2(0.0, -0.165), Vector2(-0.07, -0.115),
		Vector2(-0.115, -0.05), Vector2(-0.135, 0.03)])
	var mesh := ArrayMesh.new()
	_extrude(mesh, outline, 0.05, 0.0, _material(COLORS[Kind.ARMOUR], 0.5))
	var inner := PackedVector2Array()
	for v in outline:
		inner.append(v * 0.62 + Vector2(0, 0.012))
	_extrude(mesh, inner, 0.02, 0.03, _material(COLORS[Kind.ARMOUR].lerp(Color.WHITE, 0.55), 0.8))
	return mesh


## A flat outline pushed out `depth` thick, centred `z` forward, as a new
## surface of `mesh` (flat-shaded).
static func _extrude(mesh: ArrayMesh, outline: PackedVector2Array, depth: float, z: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := Geometry2D.triangulate_polygon(outline)
	var f := z + depth * 0.5
	var b := z - depth * 0.5
	for i in range(0, tris.size(), 3):
		var p0 := outline[tris[i]]
		var p1 := outline[tris[i + 1]]
		var p2 := outline[tris[i + 2]]
		# Front (+Z) and back, each wound to face out.
		for v in [p0, p2, p1]:
			st.add_vertex(Vector3(v.x, v.y, f))
		for v in [p0, p1, p2]:
			st.add_vertex(Vector3(v.x, v.y, b))
	var n := outline.size()
	for i in n:
		var a := outline[i]
		var c := outline[(i + 1) % n]
		for v: Vector3 in [Vector3(a.x, a.y, f), Vector3(c.x, c.y, f), Vector3(c.x, c.y, b),
				Vector3(a.x, a.y, f), Vector3(c.x, c.y, b), Vector3(a.x, a.y, b)]:
			st.add_vertex(v)
	st.generate_normals()
	st.set_material(mat)
	st.commit(mesh)


## Ammo: a bullet standing on end - case and rim in the gun's colour, a
## lighter rounded tip (one per gun colour).
static func _bullet_mesh(col: Color) -> Mesh:
	var key := "bullet" + col.to_html()
	if _meshes.has(key):
		return _meshes[key]
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var case_ := CylinderMesh.new()
	case_.top_radius = 0.058
	case_.bottom_radius = 0.058
	case_.height = 0.2
	case_.radial_segments = 12
	case_.rings = 1
	st.append_from(case_, 0, Transform3D(Basis(), Vector3(0, -0.05, 0)))
	var rim := CylinderMesh.new()
	rim.top_radius = 0.066
	rim.bottom_radius = 0.066
	rim.height = 0.03
	rim.radial_segments = 12
	rim.rings = 1
	st.append_from(rim, 0, Transform3D(Basis(), Vector3(0, -0.155, 0)))
	st.set_material(_material(col, 0.55))
	st.commit(mesh)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.058
	tip.height = 0.13
	tip.radial_segments = 12
	tip.rings = 3
	st2.append_from(tip, 0, Transform3D(Basis(), Vector3(0, 0.115, 0)))
	st2.set_material(_material(col.lerp(Color.WHITE, 0.5), 0.7))
	st2.commit(mesh)
	_meshes[key] = mesh
	return mesh


## Bitcoin token: a small gold coin, the ₿ on both faces.
static func _coin_mesh() -> Mesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := CylinderMesh.new()
	body.top_radius = 0.085
	body.bottom_radius = 0.085
	body.height = 0.022
	body.radial_segments = 16
	body.rings = 1
	st.append_from(body, 0, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO))
	st.set_material(_material(COLORS[Kind.TOKEN], 0.5))
	st.commit(mesh)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var face := QuadMesh.new()
	face.size = Vector2.ONE * 0.17
	st2.append_from(face, 0, Transform3D(Basis(), Vector3(0, 0, 0.0115)))
	st2.append_from(face, 0, Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -0.0115)))
	var fm := _material(Color.WHITE, 0.35)
	fm.albedo_texture = COIN_FACE
	fm.emission_texture = COIN_FACE
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	st2.set_material(fm)
	st2.commit(mesh)
	return mesh


static func _glitch_material(i: int) -> StandardMaterial3D:
	if _glitch_mats.is_empty():
		for c: Color in GLITCH:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = c.lerp(Color.WHITE, 0.25)
			m.disable_receive_shadows = true
			_glitch_mats.append(m)
	return _glitch_mats[i % _glitch_mats.size()]


## Warm-up items (Vfx.warm_up): each model and the glitch flash.
static func warm_up_items() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for k in [Kind.HEALTH, Kind.ARMOUR, Kind.AMMO, Kind.TOKEN]:
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh_for(k)
		out.append(mi)
	var g := MeshInstance3D.new()
	g.mesh = _mesh_for(Kind.HEALTH)
	g.material_override = _glitch_material(0)
	out.append(g)
	return out


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
	if s.age >= s.life:
		_release(s)
		return
	var pos := s.node.global_position
	# Nearest player that can still use this kind.
	var target: PlayerController = null
	var td := INF
	for p in players:
		var pc := p as PlayerController
		if pc == null or _full(pc, s):
			continue
		var d := pos.distance_to(pc.global_position + Vector3.UP * 0.9)
		if d < td:
			td = d
			target = pc
	if target and s.age > 0.35 and td <= collect_radius:
		_collect(s, target)
		_release(s)
		return
	if target and s.age > 0.35 and td <= magnet_radius:
		s.magnet = true
	if s.magnet and target:
		# Pulled in, up or down to the player too (off an edge, say).
		var to := target.global_position + Vector3.UP * 0.9 - pos
		var want := to.normalized() * lerpf(18.0, 8.0, clampf(to.length() / magnet_radius, 0.0, 1.0))
		s.vel = s.vel.lerp(want, 1.0 - exp(-10.0 * delta))
	else:
		s.magnet = false
		s.vel.y -= 14.0 * delta
		s.vel.x *= exp(-1.5 * delta)
		s.vel.z *= exp(-1.5 * delta)
	pos += s.vel * delta
	var rest := s.floor_y + (0.22 if s.kind == Kind.TOKEN else 0.35)
	if not s.magnet and pos.y < rest:
		pos.y = rest
		s.vel.y = absf(s.vel.y) * 0.35 if absf(s.vel.y) > 1.0 else 0.0
		# Skids to a stop on the floor.
		s.vel.x *= exp(-8.0 * delta)
		s.vel.z *= exp(-8.0 * delta)
	s.node.global_position = pos
	_animate(s, delta)
	# Blink out over the last 2 s (tokens: 1.5 s).
	var left := s.life - s.age
	s.node.visible = left > (1.5 if s.kind == Kind.TOKEN else 2.0) or fmod(left, 0.25) > 0.1


## Bob up and down, spin, and glitch now and then.
func _animate(s: Shard, delta: float) -> void:
	s.core.rotation.y = s.spin0 + s.age * (5.0 if s.kind == Kind.TOKEN else 3.0)
	if s.kind == Kind.AMMO:
		s.core.rotation.z = 0.3  # leaning a little as it turns
	var bob := sin(s.age * 4.0 + s.spin0) * (0.04 if s.kind == Kind.TOKEN else 0.06)
	s.glow.scale = Vector3.ONE * (0.45 if s.kind == Kind.TOKEN else 1.0) * (1.0 + 0.15 * sin(s.age * 7.0))
	s.glitch_in -= delta
	if s.glitch_in <= 0.0:
		s.glitch_in = randf_range(0.6, 1.8)
		s.glitch_left = randf_range(0.06, 0.12)
		s.core.material_override = _glitch_material(randi() % 2)
		s.core.scale = Vector3(randf_range(1.15, 1.4), randf_range(0.75, 0.95), 1.0)
		s.core.position.x = randf_range(-0.06, 0.06)
	if s.glitch_left > 0.0:
		s.glitch_left -= delta
		if s.glitch_left <= 0.0:
			s.core.material_override = null
			s.core.scale = Vector3.ONE
			s.core.position.x = 0.0
	s.core.position.y = bob


func _collect(s: Shard, target: PlayerController) -> void:
	match s.kind:
		Kind.AMMO:
			var lo := target.get_node_or_null("WeaponLoadout") as WeaponLoadout
			var n := lo.add_ammo(s.weapon, int(s.value)) if lo else 0
			ammo_collected.emit(s.weapon, n)
			collected.emit(s.kind, n)
		Kind.TOKEN:
			target.add_bitcoins(int(s.value))
			collected.emit(s.kind, s.value)
		_:
			var got := target.heal(s.value) if s.kind == Kind.HEALTH else target.add_armour(s.value)
			collected.emit(s.kind, got)


func _full(p: PlayerController, s: Shard) -> bool:
	# Ammo and tokens: only this device's own player takes them.
	var own := not p.is_remote and p.is_in_group(&"local_player")
	if s.kind == Kind.TOKEN:
		return not own
	if s.kind == Kind.AMMO:
		var lo := p.get_node_or_null("WeaponLoadout") as WeaponLoadout
		return not own or lo == null or not lo.is_unlocked(s.weapon) or lo.ammo_full(s.weapon)
	return p.health >= p.max_health if s.kind == Kind.HEALTH else p.armour >= p.max_armour
