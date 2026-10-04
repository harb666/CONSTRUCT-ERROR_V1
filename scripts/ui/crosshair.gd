extends Control
## Centre-screen crosshair, shown while the local player is armed.


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	resized.connect(queue_redraw)
	visibility_changed.connect(queue_redraw)


func _draw() -> void:
	var c := size * 0.5
	var col := Color(1, 1, 1, 0.85)
	draw_arc(c, 14.0, 0, TAU, 32, col, 2.0, true)
	draw_circle(c, 2.5, Color(0.9, 0.4, 1.0, 0.95))
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + d * 18.0, c + d * 26.0, col, 2.0, true)
