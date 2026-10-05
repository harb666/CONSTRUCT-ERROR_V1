extends Control
## Draws lock-on rings around the local player's locked targets: one per
## weapon slot (RIGHT magenta, LEFT cyan). A target both slots share gets
## both rings (the left one just outside the right one).

const RIGHT_COLOR := Color(1.0, 0.35, 0.95, 0.95)
const LEFT_COLOR := Color(0.25, 0.9, 1.0, 0.95)

var lock: TargetLock
var lock_left: TargetLock
var camera: Camera3D
var _spin := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_spin += delta * 1.5
	queue_redraw()


func _draw() -> void:
	if camera == null:
		return
	var shared := lock != null and lock_left != null and lock.has_target() and lock.current == lock_left.current
	_ring(lock, RIGHT_COLOR, 1.0, 1.0)
	_ring(lock_left, LEFT_COLOR, 1.28 if shared else 1.0, -1.0)


func _ring(l: TargetLock, col: Color, scale: float, dir: float) -> void:
	if l == null or not l.has_target():
		return
	var p := l.get_aim_point()
	if camera.is_position_behind(p):
		return
	var c := camera.unproject_position(p)
	var edge := camera.unproject_position(p + camera.global_basis.x * l.current.select_radius)
	var r := clampf(c.distance_to(edge), 28.0, 140.0) * scale
	for k in 4:
		var a := _spin * dir + k * TAU / 4.0
		draw_arc(c, r, a, a + 0.9, 12, col, 3.0, true)
	draw_circle(c, 3.0, col)
