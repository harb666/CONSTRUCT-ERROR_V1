class_name TargetLock
extends Node
## Lives on a player. Holds the locked target requested in the player's
## commands (by target_id) and drops it when it dies, becomes invalid or goes
## out of range. Weapons and upper-body aiming read `current` from here.

signal target_locked(target: Targetable)
signal target_lost(reason: String)

@export var max_range := 40.0

var current: Targetable
var _player: Node3D


func _ready() -> void:
	_player = get_parent() as Node3D
	var pc := _player as PlayerController
	if pc:
		pc.command_processed.connect(_on_command)


func _on_command(cmd: PlayerCommand, _delta: float) -> void:
	var wanted := Targetable.find_by_id(cmd.target_id) if cmd.target_id != 0 else null
	if wanted != current:
		if wanted == null:
			_set_target(null, "released")
		elif _usable(wanted):
			_set_target(wanted, "")
	if current != null:
		var reason := _invalid_reason(current)
		if reason != "":
			_set_target(null, reason)


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
	current = t
	if t:
		target_locked.emit(t)
	else:
		target_lost.emit(reason)
