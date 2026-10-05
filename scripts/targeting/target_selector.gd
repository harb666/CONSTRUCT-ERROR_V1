class_name TargetSelector
extends Node
## Local-player tap targeting for the two weapon slots (dual wield). Turns a
## screen tap into a target choice with forgiving, screen-space hit areas and
## applies the rules:
##   - tap an enemy: the RIGHT slot locks it if free, else the LEFT slot;
##     with both busy, the slot that locked longest ago switches to it.
##   - double tap an enemy (same enemy twice within `double_tap_window`):
##     BOTH slots lock it.
##   - tap an enemy both slots share: LEFT unlocks first, then RIGHT.
##   - tap an enemy only one slot has: only that slot unlocks.
## Only decides *what* is selected; each TargetLock validates, weapons fire.

signal selection_changed(side: String, target: Targetable)

## Minimum tap radius in UI pixels around each enemy, however far away it is.
@export var min_tap_radius := 70.0
@export var max_range := 40.0
## Two taps on the same enemy within this many seconds = double tap.
@export var double_tap_window := 0.35

var camera: Camera3D
## Where range is measured from (the player).
var origin_node: Node3D
## Selected target per slot. `selected` = RIGHT slot.
var selected: Targetable
var selected_left: Targetable

## Order slots were last assigned (oldest first), to pick which one switches.
var _order: Array[String] = []
var _last_tap_target: Targetable
var _last_tap_time := -100.0
var _before_last_tap: Array = [null, null]


## Handle a tap at `pos` (viewport/UI coordinates). Returns true if the tap
## hit an enemy (so callers can ignore it for anything else).
func handle_tap(pos: Vector2) -> bool:
	var t := pick(pos)
	if t == null:
		return false
	tap_target(t)
	return true


## Apply the tap rules to a picked target.
func tap_target(t: Targetable) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var prev: Array = [selected, selected_left]
	var shared_before: bool = _before_last_tap[0] == t and _before_last_tap[1] == t
	if t == _last_tap_target and now - _last_tap_time <= double_tap_window and not shared_before:
		# Double tap: undo the first tap's effect, then both slots lock it.
		_set_side("Right", t)
		_set_side("Left", t)
		_last_tap_target = null
		return
	_last_tap_target = t
	_last_tap_time = now
	_before_last_tap = prev
	if selected == t and selected_left == t:
		_set_side("Left", null)
	elif selected_left == t:
		_set_side("Left", null)
	elif selected == t:
		_set_side("Right", null)
	elif not _valid(selected):
		_set_side("Right", t)
	elif not _valid(selected_left):
		_set_side("Left", t)
	else:
		_set_side(_order[0] if not _order.is_empty() else "Right", t)


## Forget the last tap, so the next tap is never read as a double tap.
func forget_last_tap() -> void:
	_last_tap_target = null
	_last_tap_time = -100.0


func get_selected(side: String) -> Targetable:
	return selected if side == "Right" else selected_left


func _valid(t: Targetable) -> bool:
	return t != null and is_instance_valid(t)


func _set_side(side: String, t: Targetable) -> void:
	if get_selected(side) == t:
		if t != null:
			_touch(side)
		return
	if side == "Right":
		selected = t
	else:
		selected_left = t
	_order.erase(side)
	if t != null:
		_order.append(side)
	selection_changed.emit(side, t)


func _touch(side: String) -> void:
	_order.erase(side)
	_order.append(side)


## Clear one slot's selection (its lock lost the target).
func clear_side(side: String) -> void:
	if get_selected(side) != null:
		_set_side(side, null)


func clear() -> void:
	clear_side("Right")
	clear_side("Left")


func selected_id(side := "Right") -> int:
	var t := get_selected(side)
	if t and is_instance_valid(t):
		return t.target_id
	return 0


## Enemy under (or near) a screen position, or null. Each enemy gets a hit
## area around its projected vertical span, at least `min_tap_radius` wide;
## if several qualify, the one closest to the tap wins.
func pick(pos: Vector2) -> Targetable:
	if camera == null:
		return null
	var from := origin_node.global_position if origin_node else camera.global_position
	var best: Targetable = null
	var best_d := INF
	for t: Targetable in Targetable.all():
		if not t.is_valid_target():
			continue
		var p := t.get_aim_point()
		if from.distance_to(p) > max_range or camera.is_position_behind(p):
			continue
		var up := Vector3.UP * t.select_half_height
		var a := camera.unproject_position(p - up)
		var b := camera.unproject_position(p + up)
		var c := camera.unproject_position(p)
		var edge := camera.unproject_position(p + camera.global_basis.x * t.select_radius)
		var r := maxf(min_tap_radius, c.distance_to(edge))
		var d := Geometry2D.get_closest_point_to_segment(pos, a, b).distance_to(pos)
		if d <= r and d < best_d:
			best_d = d
			best = t
	return best
