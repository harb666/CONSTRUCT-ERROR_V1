extends Control
## Draws a lock-on ring around the local player's locked target.

var lock: TargetLock
var camera: Camera3D
var _spin := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_spin += delta * 1.5
	queue_redraw()


func _draw() -> void:
	if lock == null or camera == null or not lock.has_target():
		return
	var p := lock.get_aim_point()
	if camera.is_position_behind(p):
		return
	var c := camera.unproject_position(p)
	var edge := camera.unproject_position(p + camera.global_basis.x * lock.current.select_radius)
	var r := clampf(c.distance_to(edge), 28.0, 140.0)
	var col := Color(1.0, 0.35, 0.95, 0.95)
	for k in 4:
		var a := _spin + k * TAU / 4.0
		draw_arc(c, r, a, a + 0.9, 12, col, 3.0, true)
	draw_circle(c, 3.0, col)
