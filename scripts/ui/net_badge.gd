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


func _draw() -> void:
	if not Net.is_online():
		return
	var n := Net.instance
	var lf := HudStyle.label_font()
	var s := "ROOM %s   -   %d / %d" % [n.room, maxi(n.roster.size(), 1), CharacterRoster.MAX_PLAYERS]
	var fs := 16
	var tw := lf.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var r := Rect2(Vector2(size.x * 0.5 - tw * 0.5 - 14.0, 80.0), Vector2(tw + 28.0, 24.0))
	HudStyle.panel(self, r, HudStyle.CYAN_DIM, HudStyle.FILL_DARK, 6.0, 0.9)
	HudStyle.text(self, lf, Vector2(r.get_center().x, r.position.y + 17), s, fs, Color(HudStyle.TEXT, 0.9), 0.5)
