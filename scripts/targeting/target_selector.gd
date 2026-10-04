class_name TargetSelector
extends Node
## Local-player tap targeting. Turns a screen tap into a target choice with
## forgiving, screen-space hit areas, and applies the toggle rules:
##   tap enemy = lock, tap same enemy = unlock, tap other enemy = switch.
## Only decides *what* is selected; TargetLock validates, weapons fire.

signal selection_changed(target: Targetable)

## Minimum tap radius in UI pixels around each enemy, however far away it is.
@export var min_tap_radius := 70.0
@export var max_range := 40.0

var camera: Camera3D
## Where range is measured from (the player).
var origin_node: Node3D
var selected: Targetable


## Handle a tap at `pos` (viewport/UI coordinates). Returns true if the tap
## hit an enemy (so callers can ignore it for anything else).
func handle_tap(pos: Vector2) -> bool:
	var t := pick(pos)
	if t == null:
		return false
	if t == selected:
		clear()
	else:
		selected = t
		selection_changed.emit(selected)
	return true


func clear() -> void:
	if selected != null:
		selected = null
		selection_changed.emit(null)


func selected_id() -> int:
	if selected and is_instance_valid(selected):
		return selected.target_id
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
