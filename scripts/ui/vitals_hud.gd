class_name VitalsHud
extends Control
## Player panel, top-left (Ratchet: Gladiator layout, owner's cyan frame
## style): the character's portrait in a ring gauge, name plate with the
## player number, segmented health (green) and armour (blue) bars with
## their values, then COUNTER / RECOVERY +25% tags while they run. Lost
## health / armour shows as a white chunk that drains away; bars flash when
## a shard is collected. Other players (online co-op) get a compact row each
## underneath.

const HEALTH := HudStyle.HEALTH
const ARMOUR := HudStyle.ARMOUR
## Health / armour bar size.
const BAR := Vector2(196, 16)
const ARMOUR_BAR := Vector2(196, 10)
const RING_R := 40.0

var player: PlayerController
var _flash := [0.0, 0.0]
## Damage trails: [shown value, hold time] for health and armour.
var _trail := [[1.0, 0.0], [0.0, 0.0]]
var _t := 0.0
var _circle_uv := PackedVector2Array()
var _circle := PackedVector2Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	size = Vector2(360, 230)
	for i in 32:
		var v := Vector2.from_angle(TAU * i / 32.0)
		_circle.append(v)
		_circle_uv.append(Vector2(0.5, 0.5) + v * 0.5)
	_place()
	get_viewport().size_changed.connect(_place)


## Top-left, clear of the notch (same inset as the touch controls).
func _place() -> void:
	var w := get_viewport_rect().size.x
	position = Vector2(maxf(40.0, w * 0.03), 12.0)


func _process(delta: float) -> void:
	_t += delta
	for i in 2:
		_flash[i] = maxf(_flash[i] - delta * 3.0, 0.0)
	if player:
		_update_trail(0, player.health / maxf(player.max_health, 1.0), delta)
		_update_trail(1, player.armour / maxf(player.max_armour, 1.0), delta)
	var drops := RecoveryDrops.get_for(get_tree()) if is_inside_tree() else null
	if drops and not drops.collected.is_connected(_on_collected):
		drops.collected.connect(_on_collected)
	queue_redraw()


func _update_trail(i: int, frac: float, delta: float) -> void:
	var tr: Array = _trail[i]
	if frac >= tr[0]:
		tr[0] = frac
		tr[1] = 0.0
	else:
		tr[1] += delta
		if tr[1] > 0.45:
			tr[0] = maxf(tr[0] - delta * 0.8, frac)


func _on_collected(kind: int, _amount: float) -> void:
	_flash[kind] = 1.0


func _draw() -> void:
	if player == null:
		return
	var lf := HudStyle.label_font()
	var nf := HudStyle.num_font()
	var def := player.character
	# Portrait ring.
	var c := Vector2(RING_R + 4, RING_R + 6)
	HudStyle.emblem(self, c, RING_R, _t)
	if def and def.portrait:
		var pts := PackedVector2Array()
		for v in _circle:
			pts.append(c + v * RING_R * 0.66)
		draw_colored_polygon(pts, Color.WHITE, _circle_uv, def.portrait)
	else:
		HudStyle.text(self, nf, c + Vector2(0, 8), "P%d" % player.player_id, 22, HudStyle.TEXT, 0.5)
	# Name plate.
	var x0 := RING_R * 2 + 16
	var plate := Rect2(x0, 4, BAR.x + 58, 26)
	HudStyle.panel(self, plate, HudStyle.CYAN, HudStyle.FILL, 8.0)
	HudStyle.text(self, lf, Vector2(x0 + 12, 24), def.display_name if def else "PLAYER", 21, HudStyle.TEXT)
	var chip := Rect2(plate.end.x - 40, 8, 32, 18)
	draw_colored_polygon(HudStyle.chamfer(chip, [5.0, 0.0, 5.0, 0.0]), HudStyle.CYAN)
	HudStyle.text(self, nf, Vector2(chip.get_center().x, 23), "P%d" % player.player_id, 13, HudStyle.BG, 0.5)
	# Bars.
	var h := player.health / maxf(player.max_health, 1.0)
	var a := player.armour / maxf(player.max_armour, 1.0)
	HudStyle.seg_bar(self, Rect2(Vector2(x0, 38), BAR), h, HEALTH, 20, _trail[0][0], _flash[0])
	HudStyle.text(self, nf, Vector2(x0 + BAR.x + 8, 38 + BAR.y - 1), "%d" % ceili(player.health), 16, HEALTH.lerp(HudStyle.DANGER, 0.6) if h <= 0.25 else HEALTH, 0.0, 3)
	HudStyle.seg_bar(self, Rect2(Vector2(x0, 60), ARMOUR_BAR), a, ARMOUR, 20, _trail[1][0], _flash[1])
	HudStyle.text(self, nf, Vector2(x0 + BAR.x + 8, 60 + ARMOUR_BAR.y + 1), "%d" % ceili(player.armour), 12, ARMOUR, 0.0, 3)
	# Status tags.
	var tag_x := x0
	var pd := player.get_node_or_null("PerfectDodge") as PerfectDodge
	if pd and pd.counter_active():
		tag_x = _tag(tag_x, "COUNTER", Color(0.55, 0.95, 1.0))
	var drops := get_tree().get_first_node_in_group(RecoveryDrops.GROUP) as RecoveryDrops
	if drops and drops.bonus_active():
		_tag(tag_x, "RECOVERY +%d%%" % roundi(drops.streak_bonus * 100.0), Color(1.0, 0.85, 0.3))
	# Teammates (online co-op).
	var y := 104.0
	for n in get_tree().get_nodes_in_group(&"players"):
		var mate := n as PlayerController
		if mate == null or mate == player:
			continue
		_mate_row(mate, Vector2(4, y))
		y += 28.0


## A small status chip; returns the x after it.
func _tag(x: float, s: String, col: Color) -> float:
	var lf := HudStyle.label_font()
	var w := lf.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 18
	var r := Rect2(x, 78, w, 20)
	draw_colored_polygon(HudStyle.chamfer(r, [6.0, 0.0, 6.0, 0.0]), Color(col, 0.22))
	var pts := HudStyle.chamfer(r, [6.0, 0.0, 6.0, 0.0])
	pts.append(pts[0])
	draw_polyline(pts, col, 1.5, true)
	HudStyle.text(self, lf, Vector2(x + 9, 94), s, 15, col)
	return x + w + 8


func _mate_row(mate: PlayerController, at: Vector2) -> void:
	var lf := HudStyle.label_font()
	var r := Rect2(at, Vector2(250, 22))
	HudStyle.panel(self, r, HudStyle.CYAN_DIM, HudStyle.FILL_DARK, 6.0)
	var nm := mate.character.display_name if mate.character else "PLAYER"
	HudStyle.text(self, lf, at + Vector2(8, 17), "P%d  %s" % [mate.player_id, nm], 15, HudStyle.TEXT)
	HudStyle.seg_bar(self, Rect2(at + Vector2(118, 6), Vector2(120, 10)), mate.health / maxf(mate.max_health, 1.0), HEALTH, 12)
