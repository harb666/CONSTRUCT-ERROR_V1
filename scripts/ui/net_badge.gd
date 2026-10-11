class_name NetBadge
extends Control
## Online co-op in game: a small chip under the top-centre status showing
## the room code and how many are in ("ROOM 4821  -  2 / 4"), so the host
## can still read the code out once playing. Hidden offline.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


## ?netlog=1: the network log, small, bottom-left (for screenshots when
## joining goes wrong).
static func show_log() -> bool:
	return StressTest._param("netlog") == "1"


static func draw_log(ci: CanvasItem, at: Vector2) -> void:
	if Net.instance == null:
		return
	var lf := HudStyle.label_font()
	var lines := Net.instance.log_lines
	var h := 16.0 * lines.size() + 10.0
	ci.draw_rect(Rect2(at - Vector2(6, h), Vector2(560, h + 4)), Color(0, 0, 0, 0.7))
	var y := at.y - h + 16.0
	for l in lines:
		ci.draw_string(lf, Vector2(at.x, y), l, HORIZONTAL_ALIGNMENT_LEFT, 550, 14, Color(0.7, 1.0, 0.8))
		y += 16.0


func _draw() -> void:
	if show_log():
		draw_log(self, Vector2(12, size.y * 0.62))
	if not Net.is_online():
		return
	var n := Net.instance
	var lf := HudStyle.label_font()
	var s := "ROOM %s   -   %d / %d" % [n.room, maxi(n.roster.size(), 1), CharacterRoster.MAX_PLAYERS]
	if n.hosting and n.status.ends_with("RECONNECTING..."):
		s = "ROOM %s   -   RECONNECTING..." % n.room
	elif n.hosting and n.host_note != "":
		s = "ROOM %s   -   %s" % [n.room, n.host_note]
	var fs := 16
	var tw := lf.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var r := Rect2(Vector2(size.x * 0.5 - tw * 0.5 - 14.0, 80.0), Vector2(tw + 28.0, 24.0))
	HudStyle.panel(self, r, HudStyle.CYAN_DIM, HudStyle.FILL_DARK, 6.0, 0.9)
	HudStyle.text(self, lf, Vector2(r.get_center().x, r.position.y + 17), s, fs, Color(HudStyle.TEXT, 0.9), 0.5)
