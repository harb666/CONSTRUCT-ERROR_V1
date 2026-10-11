class_name LevelFlowHud
extends Control
## Top-centre level progress in the owner's cyan HUD style: a big banner
## that slides in for moments ("WAVE 2 / 3", "AREA SECURED", "LIFT
## ARRIVING"), a small status chip underneath that stays ("WAVE 2 / 3 -
## 5 LEFT", "GET TO THE LIFT  23 M", "GOING DOWN 3") and a marker over a
## place in the world (the lift), pinned to the screen edge with an arrow
## when it's off screen. Fed by WaveDirector / ElevatorLift.

const BANNER_TIME := 2.6
const MARKER_COL := Color(1.0, 0.36, 0.62)

var status := ""
var status_color := HudStyle.CYAN
## World point to mark (Vector3.INF: none) and its label.
var marker := Vector3.INF
var marker_label := ""
var banners := 0

var _title := ""
var _sub := ""
var _bt := 99.0
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func banner(title: String, sub := "") -> void:
	_title = title
	_sub = sub
	_bt = 0.0
	banners += 1


func banner_showing() -> bool:
	return _bt < BANNER_TIME


func _process(delta: float) -> void:
	_t += delta
	_bt += delta
	queue_redraw()


func _draw() -> void:
	var tf := HudStyle.title_font()
	var lf := HudStyle.label_font()
	var cx := size.x * 0.5
	_draw_marker()
	# Banner.
	if _bt < BANNER_TIME:
		var k_in := clampf(_bt / 0.22, 0.0, 1.0)
		var k_out := clampf((BANNER_TIME - _bt) / 0.35, 0.0, 1.0)
		var a := minf(k_in, k_out)
		var w := clampf(size.x * 0.5, 320.0, 620.0) * (0.85 + 0.15 * (1.0 - pow(1.0 - k_in, 3.0)))
		var r := Rect2(Vector2(cx - w * 0.5, size.y * 0.2), Vector2(w, 78 if _sub != "" else 60))
		HudStyle.panel(self, r, HudStyle.CYAN, HudStyle.FILL_DARK, 16.0, a)
		HudStyle.brackets(self, r.grow(6.0), Color(HudStyle.CYAN, a), 18.0, 5.0, 3.0)
		HudStyle.text(self, tf, Vector2(cx, r.position.y + 42), _title, HudStyle.fit(tf, _title, w - 40.0, 34), Color(HudStyle.TEXT, a), 0.5, 3)
		if _sub != "":
			HudStyle.text(self, lf, Vector2(cx, r.position.y + 66), _sub, 20, Color(HudStyle.CYAN, a), 0.5)
	# Status chip.
	if status != "":
		var fs := 19
		var tw := lf.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var r := Rect2(Vector2(cx - tw * 0.5 - 22.0, 44.0), Vector2(tw + 44.0, 30.0))
		HudStyle.panel(self, r, status_color, HudStyle.FILL, 8.0)
		HudStyle.text(self, lf, Vector2(cx, r.position.y + 22), status, fs, HudStyle.TEXT, 0.5)


func _draw_marker() -> void:
	if marker == Vector3.INF:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var lf := HudStyle.label_font()
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	var behind := cam.is_position_behind(marker)
	var p := cam.unproject_position(marker)
	if behind:
		p = size - p  # mirrored: points the right way round
	var margin := 46.0
	var inside := Rect2(Vector2.ZERO, size).grow(-margin)
	var on_screen := not behind and inside.has_point(p)
	var d := cam.global_position.distance_to(marker)
	if on_screen:
		# Downward chevrons bobbing over the spot, with the distance.
		var bob := sin(_t * 4.0) * 5.0
		for i in 2:
			var y := p.y - 30.0 - i * 13.0 + bob
			var pts := PackedVector2Array([Vector2(p.x - 16, y - 8), Vector2(p.x, y + 4), Vector2(p.x + 16, y - 8), Vector2(p.x + 16, y - 2), Vector2(p.x, y + 10), Vector2(p.x - 16, y - 2)])
			draw_colored_polygon(pts, Color(MARKER_COL, 0.55 + 0.45 * pulse * (1.0 - i * 0.4)))
		HudStyle.text(self, lf, Vector2(p.x, p.y - 64 + bob), "%s  %d M" % [marker_label, roundi(d)], 18, HudStyle.TEXT, 0.5, 3)
	else:
		# Pinned to the screen edge, an arrow pointing at it.
		var c := size * 0.5
		var dir := (p - c).normalized() if (p - c).length() > 1.0 else Vector2.DOWN
		var t := INF
		if absf(dir.x) > 0.001:
			t = minf(t, (inside.size.x * 0.5) / absf(dir.x))
		if absf(dir.y) > 0.001:
			t = minf(t, (inside.size.y * 0.5) / absf(dir.y))
		var e := c + dir * t
		var n := Vector2(-dir.y, dir.x)
		var tip := e + dir * 14.0
		draw_colored_polygon(PackedVector2Array([tip, e - dir * 6.0 + n * 14.0, e - dir * 6.0 - n * 14.0]), Color(MARKER_COL, 0.7 + 0.3 * pulse))
		HudStyle.text(self, lf, e - dir * 30.0 + Vector2(0, 6), "%s  %d M" % [marker_label, roundi(d)], 16, HudStyle.TEXT, 0.5, 3)
