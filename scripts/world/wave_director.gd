class_name WaveDirector
extends Node
## Enemy waves for a level (owner asked, Skyforge: "a few waves of
## lightweight enemies spawning, max 8 active on the map at once").
## Wave 1 is the robots already placed in the level; each later wave's
## grunts and skirmishers teleport in (red hologram, like respawning robots)
## at the level's wave spawn points, away from the players, never more than
## `max_active` alive at once - the rest wait and come in as others fall.
## When the last wave is cleared it emits `all_cleared` (Skyforge: the lift
## rises). Runs on the peer that owns the world (offline: always; online:
## the host); `robot_spawned` lets the network copy each spawn.

signal wave_started(index: int, total: int)
signal wave_cleared(index: int, total: int)
signal all_cleared
signal robot_spawned(robot: RobotEnemy, scene_index: int)

## Robot types a wave can hold (index = scene_index in `robot_spawned`).
const SCENES: Array[PackedScene] = [
	preload("res://scenes/enemies/robot_enemy.tscn"),
	preload("res://scenes/enemies/robot_skirmisher.tscn"),
	preload("res://scenes/enemies/robot_sentinel.tscn"),
]
const SENTINEL := 2
## (Queue entry: a grunt teleporting in at one of the posts, `wave_posts`.)
const POST := 3

@export var targets_path: NodePath = ^"../Targets"
@export var spawns_path: NodePath = ^"../WaveSpawns"
## The waves after the first (the placed robots): x grunts, y skirmishers.
## With `first_wave_placed` off, every wave is listed here (wave 1 too).
@export var waves: Array[Vector2i] = [Vector2i(6, 2), Vector2i(7, 4)]
## Wave 1 is the robots already placed under the targets (Skyforge). Off:
## wave 1 teleports in too (`waves[0]`; the Toxic Works hall).
@export var first_wave_placed := true
## Starts by itself once someone is in the level. Off: waits for `begin()`
## (the Toxic Works: once the lift has landed).
@export var auto_start := true
## Neon Sentinels per wave (same order as `waves`; missing = none): they
## fly in from outside through the windows (`window_entries`), first in
## their wave (owner asked: the Toxic Works hall's last wave).
@export var wave_sentinels: Array[int] = []
## Marker3Ds outside the windows, -Z pointing into the level: a sentinel
## starts at one and flies `entry_depth` m in through the window.
@export var window_entries_path: NodePath = ^"../WindowEntries"
@export var entry_depth := 16.0
## Grunts per wave (same order as `waves`) teleporting in at fixed posts
## (`posts_path`'s Marker3Ds, e.g. the Toxic Works hall's high catwalks)
## with the wave's first; they hold their post and engage from afar.
@export var wave_posts: Array[int] = []
@export var posts_path: NodePath = ^"../WavePosts"
@export var post_detect_range := 70.0
@export var post_fire_range := 45.0
@export var post_combat_speed := 1.4
## Most robots alive on the map at once.
@export var max_active := 8
## Per later wave (same order as `waves`): the spawn points (WaveSpawns
## marker names) its robots teleport in at, so each wave comes from its own
## part of the map. Empty / missing: any. Falls back to any free point.
@export var wave_spawn_sets: Array[PackedStringArray] = []
## Robots go straight for the players wherever they are (owner asked for
## Skyforge: a small map, the fighting never stops) instead of waiting
## until someone comes within their usual range.
@export var hunt_players := false
@export var hunt_range := 400.0
## Pause between one wave cleared and the next starting (s).
@export var wave_gap := 4.0
## Between one robot teleporting in and the next (s).
@export var spawn_gap := 0.7
## Robots don't teleport in closer than this to a player (m)...
@export var min_player_distance := 16.0
## ...and preferably not further than this from the nearest one.
@export var max_player_distance := 50.0

enum State { WAITING, FIGHTING, BREAK, DONE }

var state := State.WAITING
## Current wave, 1-based (0 before the first starts).
var wave := 0
var spawned := 0
## Online, on a joined device: robots left as the host counts them.
var net_remaining := -1
var _queue: Array[int] = []
var _t := 0.0
var _counts := {}


func total_waves() -> int:
	return waves.size() + (1 if first_wave_placed else 0)


## Start the fight (with `auto_start` off).
func begin() -> void:
	if state == State.WAITING and Net.is_authority():
		_start_wave(1)


## Index into `waves` for wave `index` (1-based); -1 for the placed wave.
func _wave_slot(index: int) -> int:
	return index - 2 if first_wave_placed else index - 1


func targets() -> Node:
	return get_node_or_null(targets_path)


## Alive robots on the map (the boss doesn't count: not a wave robot).
func active_count() -> int:
	var n := 0
	var t := targets()
	if t:
		for c in t.get_children():
			if c is RobotEnemy and (c as RobotEnemy).alive:
				n += 1
	return n


## Robots of the current wave still to come or alive.
func remaining() -> int:
	if not Net.is_authority() and net_remaining >= 0:
		return net_remaining
	return active_count() + _queue.size()


func _physics_process(delta: float) -> void:
	if not Net.is_authority():
		return
	match state:
		State.WAITING:
			# Starts once someone is in the level (after DEPLOY).
			if auto_start and not get_tree().get_nodes_in_group(&"players").is_empty():
				_start_wave(1)
		State.FIGHTING:
			_t -= delta
			if not _queue.is_empty():
				if _t <= 0.0 and active_count() < max_active:
					if _spawn(_queue[0]):
						_queue.pop_front()
						_t = spawn_gap
					else:
						_t = 0.5  # nowhere free just now
			elif active_count() == 0:
				wave_cleared.emit(wave, total_waves())
				if wave >= total_waves():
					state = State.DONE
					all_cleared.emit()
				else:
					state = State.BREAK
					_t = wave_gap
		State.BREAK:
			_t -= delta
			if _t <= 0.0:
				_start_wave(wave + 1)


func _start_wave(index: int) -> void:
	wave = index
	state = State.FIGHTING
	_windows_used.clear()
	_posts_used.clear()
	var t := targets()
	if t and hunt_players:
		for c in t.get_children():
			if c is RobotEnemy:
				_hunt(c as RobotEnemy)
	_queue.clear()
	_t = 0.0
	var slot := _wave_slot(index)
	if slot >= 0 and slot < waves.size():
		var w := waves[slot]
		for i in w.x:
			_queue.append(0)
		for i in w.y:
			_queue.append(1)
		_queue.shuffle()
		for i in (wave_posts[slot] if slot < wave_posts.size() else 0):
			_queue.push_front(POST)
		for i in (wave_sentinels[slot] if slot < wave_sentinels.size() else 0):
			_queue.push_front(SENTINEL)
	wave_started.emit(wave, total_waves())


## Skip straight to the end (tests, debugging): every robot gone, done.
func finish_now() -> void:
	_queue.clear()
	var t := targets()
	if t:
		for c in t.get_children():
			if c is RobotEnemy:
				c.queue_free()
	wave = total_waves()
	state = State.DONE
	all_cleared.emit()


## Teleport one robot in (a sentinel flies in through a window). False if
## no spawn point is free.
func _spawn(scene_index: int) -> bool:
	if scene_index == SENTINEL:
		return spawn_sentinel() != null
	if scene_index == POST:
		return _spawn_post()
	var at := _pick_spot()
	if at == Vector3.INF:
		return false
	var t := targets()
	if t == null:
		return false
	var r := SCENES[scene_index].instantiate() as RobotEnemy
	_counts[scene_index] = int(_counts.get(scene_index, 0)) + 1
	r.name = "W%d_%s%d" % [wave, "Skirmisher" if scene_index == 1 else "Grunt", _counts[scene_index]]
	r.respawn_time = -1.0
	r.patrol_distance = 0.0
	var face := _nearest_player(at)
	var yaw := 0.0
	if face:
		var to := face.global_position - at
		yaw = atan2(to.x, to.z)
	r.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	t.add_child(r)
	if hunt_players:
		_hunt(r)
	var visual := r.get(&"_visual") as Node3D
	Hologram.teleport_in(visual, 0.0, Color(1.0, 0.35, 0.3))
	spawned += 1
	Net.robot_spawned(r, t)
	robot_spawned.emit(r, scene_index)
	return true


var _windows_used: Array[Node3D] = []
var _posts_used: Array[Node3D] = []


## A sentinel flying in through a window (`entries`' markers; default the
## wave windows): the one farthest from the players not used yet this wave
## (each comes in through its own) - or, `nearest`, the one nearest them (but
## not right on top of them). `hunt`: it goes for the players wherever they
## are. Null if there's nowhere to come in.
func spawn_sentinel(entries: Array = [], hunt := hunt_players, nearest := false) -> RobotSentinel:
	if entries.is_empty():
		var own := get_node_or_null(window_entries_path)
		entries = own.get_children() if own else []
	var t := targets()
	if t == null or entries.is_empty():
		return null
	var best: Node3D = null
	var best_d := INF if nearest else -1.0
	for m in entries:
		var n := m as Node3D
		if n == null or (not nearest and n in _windows_used):
			continue
		var near := _nearest_player(n.global_position)
		var d := near.global_position.distance_to(n.global_position) if near else 0.0
		if nearest:
			d = d if d > min_player_distance else d + 1000.0
		if (d < best_d) if nearest else (d > best_d):
			best_d = d
			best = n
	if best == null:
		_windows_used.clear()
		best = entries.pick_random() as Node3D
	_windows_used.append(best)
	var from := best.global_position
	var inward := -best.global_basis.z
	inward.y = 0.0
	inward = inward.normalized()
	var to := from + inward * entry_depth
	var r := SCENES[SENTINEL].instantiate() as RobotSentinel
	_counts[SENTINEL] = int(_counts.get(SENTINEL, 0)) + 1
	r.name = "W%d_Sentinel%d" % [wave, _counts[SENTINEL]]
	r.respawn_time = -1.0
	r.patrol_distance = 0.0
	r.transform = Transform3D(Basis(Vector3.UP, atan2(inward.x, inward.z)), from)
	t.add_child(r)
	if hunt:
		_hunt(r)
	# Whatever is in the way in (the window's barrier) lets it through.
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [r.get_rid()])
	var hit := r.get_world_3d().direct_space_state.intersect_ray(q)
	r.fly_in(to, hit.collider as PhysicsBody3D if not hit.is_empty() else null)
	spawned += 1
	Net.robot_spawned(r, t)
	robot_spawned.emit(r, SENTINEL)
	return r


## A grunt teleporting in at a post not used yet this wave: it holds it,
## engaging from afar (not hunting round the map).
func _spawn_post() -> bool:
	var posts := get_node_or_null(posts_path)
	if posts == null:
		return true  # (nothing to do)
	for m in posts.get_children():
		var n := m as Node3D
		if n == null or n in _posts_used:
			continue
		_posts_used.append(n)
		var r := spawn_robot_at(0, n.global_position, false)
		if r:
			r.name = "W%d_Post_%s" % [wave, n.name]
			r.detect_range = post_detect_range
			r.lose_range = post_detect_range + 20.0
			r.fire_range = post_fire_range
			r.combat_speed = post_combat_speed
			r.preferred_range = Vector2(2.0, post_detect_range + 20.0)
		return true
	return true


## Teleport a robot (SCENES index) in at `at` (snapped onto the floor),
## facing the nearest player. `hunt`: it goes for the players wherever they
## are. Null if there's no floor there.
func spawn_robot_at(scene_index: int, at: Vector3, hunt := hunt_players) -> RobotEnemy:
	var t := targets()
	var floor := _floor(at)
	if t == null or floor == Vector3.INF:
		return null
	floor += Vector3.UP * 0.05
	var r := SCENES[scene_index].instantiate() as RobotEnemy
	_counts[scene_index] = int(_counts.get(scene_index, 0)) + 1
	r.name = "%s%d" % [["Grunt", "Skirmisher", "Sentinel"][scene_index], _counts[scene_index]]
	r.respawn_time = -1.0
	r.patrol_distance = 0.0
	var face := _nearest_player(floor)
	var yaw := 0.0
	if face:
		var to := face.global_position - floor
		yaw = atan2(to.x, to.z)
	r.transform = Transform3D(Basis(Vector3.UP, yaw), floor)
	t.add_child(r)
	if hunt:
		_hunt(r)
	Hologram.teleport_in(r.get(&"_visual") as Node3D, 0.0, Color(1.0, 0.35, 0.3))
	spawned += 1
	Net.robot_spawned(r, t)
	robot_spawned.emit(r, scene_index)
	return r


## Make `r` hunt the players from anywhere on the map.
func _hunt(r: RobotEnemy) -> void:
	r.detect_range = hunt_range
	r.lose_range = hunt_range
	r.hunt_nav = true


## The current wave's spawn points (marker names), empty = any.
func _wave_set() -> PackedStringArray:
	var i := _wave_slot(wave)
	return wave_spawn_sets[i] if i >= 0 and i < wave_spawn_sets.size() else PackedStringArray()


func _nearest_player(at: Vector3) -> Node3D:
	var best: Node3D = null
	for p in get_tree().get_nodes_in_group(&"players"):
		var n := p as Node3D
		if n and (best == null or n.global_position.distance_to(at) < best.global_position.distance_to(at)):
			best = n
	return best


## A spawn point away from the players (but not too far), with nobody on
## it, snapped onto the floor. Vector3.INF if none.
func _pick_spot() -> Vector3:
	var spawns := get_node_or_null(spawns_path)
	if spawns == null:
		return Vector3.INF
	var allowed := _wave_set()
	if not allowed.is_empty():
		var at := _pick_from(spawns, allowed)
		if at != Vector3.INF:
			return at
	return _pick_from(spawns, PackedStringArray())


func _pick_from(spawns: Node, allowed: PackedStringArray) -> Vector3:
	var good: Array[Vector3] = []
	var ok: Array[Vector3] = []
	for m in spawns.get_children():
		if not allowed.is_empty() and not allowed.has(String(m.name)):
			continue
		var p := (m as Node3D).global_position
		var near := _nearest_player(p)
		var d := near.global_position.distance_to(p) if near else 999.0
		if d < min_player_distance or _crowded(p):
			continue
		var floor := _floor(p)
		if floor == Vector3.INF:
			continue
		if d <= max_player_distance:
			good.append(floor)
		else:
			ok.append(floor)
	var pool := good if not good.is_empty() else ok
	if pool.is_empty():
		return Vector3.INF
	var at: Vector3 = pool[randi() % pool.size()]
	# A little scatter so two in a row don't stand in each other.
	var j := at + Vector3(randf_range(-1.2, 1.2), 0.0, randf_range(-1.2, 1.2))
	var jf := _floor(j)
	return jf + Vector3.UP * 0.05 if jf != Vector3.INF and absf(jf.y - at.y) < 0.3 else at + Vector3.UP * 0.05


func _crowded(p: Vector3) -> bool:
	var t := targets()
	if t:
		for c in t.get_children():
			if c is RobotEnemy and (c as RobotEnemy).alive and (c as Node3D).global_position.distance_to(p) < 2.5:
				return true
	return false


func _floor(p: Vector3) -> Vector3:
	var space := get_viewport().find_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p + Vector3.DOWN * 3.0)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty() or not (hit.collider is StaticBody3D) or hit.collider is ToxicBarrel:
		return Vector3.INF
	return hit.position
