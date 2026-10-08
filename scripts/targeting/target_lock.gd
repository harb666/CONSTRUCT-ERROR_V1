class_name TargetLock
extends Node
## Lives on a player. Holds the locked target requested in the player's
## commands (by target_id) and drops it when it dies, becomes invalid or goes
## out of range. Weapons and upper-body aiming read `current` from here.

signal target_locked(target: Targetable)
signal target_lost(reason: String)

@export var max_range := 40.0
## Which weapon slot's target this lock holds (dual wield): "Right" reads the
## command's target_id, "Left" its target_id_left.
@export var side := "Right"

## Line of sight: the lock is kept while the target is behind cover, but
## weapons hold fire (no firing solution). Hidden longer than
## `cover_memory` s, the lock is dropped ("obstructed").
@export var line_of_sight := true
@export var cover_memory := 1.25
## Seconds between line-of-sight rays (one short ray per lock).
@export var los_interval := 0.1
## Eye height the line of sight is checked from (m above the player's feet).
@export var eye_height := 1.4

var current: Targetable
var _player: Node3D
## False while level geometry blocks the line to the target.
var clear := true
## Seconds the current target has been hidden.
var obstructed_for := 0.0
var _los_t := 0.0
## Target dropped for being hidden: not re-locked until the player taps again.
var _dropped_id := 0
## Where the last target was when the lock was lost (for the HUD).
var last_lost_point := Vector3.ZERO


func _ready() -> void:
	_player = get_parent() as Node3D
	var pc := _player as PlayerController
	if pc:
		pc.command_processed.connect(_on_command)


func _on_command(cmd: PlayerCommand, _delta: float) -> void:
	var id := cmd.target_id if side == "Right" else cmd.target_id_left
	if id != _dropped_id:
		_dropped_id = 0
	elif id != 0:
		id = 0
	var wanted := Targetable.find_by_id(id) if id != 0 else null
	if wanted != current:
		if wanted == null:
			_set_target(null, "released")
		elif _usable(wanted):
			_set_target(wanted, "")
	if current != null:
		var reason := _invalid_reason(current)
		if reason != "":
			_set_target(null, reason)
	if current != null and line_of_sight:
		_los_t -= _delta
		if _los_t <= 0.0:
			_los_t = los_interval
			clear = _line_clear(current.get_aim_point())
		obstructed_for = 0.0 if clear else obstructed_for + _delta
		if obstructed_for > cover_memory:
			_dropped_id = current.target_id
			_set_target(null, "obstructed")


## A firing solution exists (target held and not behind cover).
func has_clear_shot() -> bool:
	return has_target() and clear


## Only level geometry (static bodies) counts as cover: other robots,
## props and players don't break the line.
func _line_clear(to: Vector3) -> bool:
	if _player == null or not _player.is_inside_tree():
		return true
	var from := _player.global_position + Vector3.UP * eye_height
	var space := _player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var ex: Array[RID] = []
	if _player is CollisionObject3D:
		ex.append((_player as CollisionObject3D).get_rid())
	for i in 4:
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
		if hit.collider is StaticBody3D:
			return false
		ex.append(hit.rid)
	return true


func has_target() -> bool:
	return current != null and is_instance_valid(current)


func get_aim_point() -> Vector3:
	return current.get_aim_point() if has_target() else Vector3.ZERO


func _usable(t: Targetable) -> bool:
	return _invalid_reason(t) == ""


func _invalid_reason(t: Targetable) -> String:
	if t == null or not is_instance_valid(t) or not t.is_inside_tree():
		return "invalid"
	if not t.alive:
		return "died"
	if not t.is_valid_target():
		return "invalid"
	if _player and _player.global_position.distance_to(t.get_aim_point()) > max_range:
		return "out_of_range"
	return ""


func _set_target(t: Targetable, reason: String) -> void:
	if t == null and current != null and is_instance_valid(current):
		last_lost_point = current.get_aim_point()
	current = t
	clear = true
	obstructed_for = 0.0
	_los_t = 0.0
	if t:
		target_locked.emit(t)
	else:
		target_lost.emit(reason)
