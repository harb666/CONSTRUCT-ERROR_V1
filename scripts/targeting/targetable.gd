class_name Targetable
extends Node3D
## Marks its parent as something players can lock onto. Place it at the
## point weapons should aim at (e.g. chest height). Reusable for any enemy.
## `target_id` is a stable number a network layer can send instead of a node.

signal died
signal became_invalid

## Generous tap area: radius (m) around the vertical span below/above the aim
## point that counts as "tapping this enemy" (screen-space, see TargetSelector).
@export var select_radius := 0.9
@export var select_half_height := 1.0

static var _registry := {}
static var _next_id := 1

var target_id := 0
var alive := true


func _enter_tree() -> void:
	if target_id == 0:
		target_id = _next_id
		_next_id += 1
	_registry[target_id] = self


func _exit_tree() -> void:
	_registry.erase(target_id)
	became_invalid.emit()


static func all() -> Array:
	return _registry.values()


static func find_by_id(id: int) -> Targetable:
	var t: Targetable = _registry.get(id)
	return t if t and is_instance_valid(t) else null


func is_valid_target() -> bool:
	return alive and is_inside_tree() and is_visible_in_tree()


func get_aim_point() -> Vector3:
	return global_position


## Call from the owner when it dies.
func kill() -> void:
	if alive:
		alive = false
		died.emit()


func revive() -> void:
	alive = true
