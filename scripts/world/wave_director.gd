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
]

@export var targets_path: NodePath = ^"../Targets"
@export var spawns_path: NodePath = ^"../WaveSpawns"
## The waves after the first (the placed robots): x grunts, y skirmishers.
@export var waves: Array[Vector2i] = [Vector2i(6, 2), Vector2i(7, 4)]
## Most robots alive on the map at once.
@export var max_active := 8
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
var _queue: Array[int] = []
var _t := 0.0
var _counts := {}


func total_waves() -> int:
	return waves.size() + 1


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
	return active_count() + _queue.size()


func _physics_process(delta: float) -> void:
	if not Net.is_authority():
		return
	match state:
		State.WAITING:
			# Starts once someone is in the level (after DEPLOY).
			if not get_tree().get_nodes_in_group(&"players").is_empty():
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
	_queue.clear()
	_t = 0.0
	if index >= 2:
		var w := waves[index - 2]
		for i in w.x:
			_queue.append(0)
		for i in w.y:
			_queue.append(1)
		_queue.shuffle()
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


## Teleport one robot in. False if no spawn point is free.
func _spawn(scene_index: int) -> bool:
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
	var visual := r.get(&"_visual") as Node3D
	Hologram.teleport_in(visual, 0.0, Color(1.0, 0.35, 0.3))
	spawned += 1
	robot_spawned.emit(r, scene_index)
	return true


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
	var good: Array[Vector3] = []
	var ok: Array[Vector3] = []
	for m in spawns.get_children():
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
