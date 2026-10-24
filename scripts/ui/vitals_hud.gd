class_name VitalsHud
extends Control
## Player panel, top-left (Ratchet: Gladiator layout, owner's cyan frame
## style): the character's portrait in a ring gauge, name plate with the
## player number, segmented health (green) and armour (blue) bars with
## their values, then COUNTER / RECOVERY +25% tags while they run. Lost
## health / armour shows as a white chunk that drains away; bars flash when
## a shard is collected. Other players (online co-op) get a compact row each
## underneath.
## Health (owner asked: "more visible"): a big framed bar of 10 chunky bars
## (PlayerController.HEALTH_BARS - a fall costs one), lit with a highlight,
## green -> amber at half -> red at 3 bars, lost bars dark red, its value
## large beside it; at 3 bars or fewer a red glow pulses round it (a layer
## faded in and out - the panel itself isn't redrawn for it).
## Bitcoins (owner asked: an in-game currency): a gold coin and the count
## under the bars, popping bigger as tokens are picked up.

const HEALTH := HudStyle.HEALTH
const ARMOUR := HudStyle.ARMOUR
## Health / armour bar size.
const BAR := Vector2(236, 28)
const ARMOUR_BAR := Vector2(236, 10)
const BAR_Y := 38.0
const ARMOUR_Y := 74.0
## Health at or under this share is low (red, pulsing): 3 bars.
const LOW := 0.3
const RING_R := 40.0

var player: PlayerController
var _flash := [0.0, 0.0]
## Damage trails: [shown value, hold time] for health and armour.
var _trail := [[1.0, 0.0], [0.0, 0.0]]
var _t := 0.0
var _circle_uv := PackedVector2Array()
var _circle := PackedVector2Array()
## The portrait ring's turning layers (drawn once, rotated each frame).
var _emblem: Array[HudSpinLayer] = []
## What the panel showed when last drawn: it's redrawn only when that
## changes (every redraw remakes its graphics buffers - see HudStyle.fill).
var _shown := []
## The low-health glow round the bar (drawn once, faded in and out).
var _low_glow: Control
## The bitcoin count's pop as tokens come in.
var _coin_pop := 0.0
var _coin_hooked: PlayerController


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	size = Vector2(400, 240)
	for i in 32:
		var v := Vector2.from_angle(TAU * i / 32.0)
		_circle.append(v)
		_circle_uv.append(Vector2(0.5, 0.5) + v * 0.5)
	_emblem = HudStyle.emblem_layers(self, Vector2(RING_R + 4, RING_R + 6), RING_R)
	_low_glow = Control.new()
	_low_glow.name = "LowHealthGlow"
	_low_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_low_glow.show_behind_parent = true
	_low_glow.size = size
	_low_glow.draw.connect(_draw_low_glow)
	_low_glow.modulate.a = 0.0
	add_child(_low_glow)
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
	if player and _coin_hooked != player:
		_coin_hooked = player
		player.bitcoins_changed.connect(func(_t: int, added: int) -> void:
			if added > 0:
				_coin_pop = 1.0)
	_coin_pop = maxf(_coin_pop - delta * 4.0, 0.0)
	for l in _emblem:
		l.visible = player != null
	HudStyle.spin_layers(_emblem, _t)
	var low := player != null and player.health / maxf(player.max_health, 1.0) <= LOW
	_low_glow.visible = low
	if low:
		_low_glow.modulate.a = 0.45 + 0.55 * absf(sin(_t * (5.0 if player.health / maxf(player.max_health, 1.0) <= 0.1 else 3.2)))
	var now := _state()
	if now != _shown:
		_shown = now
		queue_redraw()


## Everything `_draw` shows (besides the turning ring).
func _state() -> Array:
	if player == null:
		return []
	var pd := player.get_node_or_null("PerfectDodge") as PerfectDodge
	var drops := get_tree().get_first_node_in_group(RecoveryDrops.GROUP) as RecoveryDrops
	var st := [player, player.character, player.player_id, player.health, player.max_health, player.armour, player.max_armour,
		_trail[0][0], _trail[1][0], _flash[0], _flash[1], pd != null and pd.counter_active(),
		drops != null and drops.bonus_active(), drops.streak_bonus if drops else 0.0, player.bitcoins, snappedf(_coin_pop, 0.1)]
	for n in get_tree().get_nodes_in_group(&"players"):
		var mate := n as PlayerController
		if mate == null or mate == player:
			continue
		st.append_array([mate, mate.character, mate.player_id, mate.health, mate.max_health])
	return st


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
	if kind < _flash.size():
		_flash[kind] = 1.0


func _draw() -> void:
	if player == null:
		return
	var lf := HudStyle.label_font()
	var nf := HudStyle.num_font()
	var def := player.character
	# Portrait ring (its turning layers are drawn underneath, see _emblem).
	var c := Vector2(RING_R + 4, RING_R + 6)
	if def and def.portrait:
		var pts := PackedVector2Array()
		for v in _circle:
			pts.append(c + v * RING_R * 0.66)
		HudStyle.fill(self, pts, Color.WHITE, _circle_uv, def.portrait)
	else:
		HudStyle.text(self, nf, c + Vector2(0, 8), "P%d" % player.player_id, 22, HudStyle.TEXT, 0.5)
	# Name plate.
	var x0 := RING_R * 2 + 16
	var plate := Rect2(x0, 4, BAR.x + 58, 26)
	HudStyle.panel(self, plate, HudStyle.CYAN, HudStyle.FILL, 8.0)
	HudStyle.text(self, lf, Vector2(x0 + 12, 24), def.display_name if def else "PLAYER", 21, HudStyle.TEXT)
	var chip := Rect2(plate.end.x - 40, 8, 32, 18)
	HudStyle.fill(self, HudStyle.chamfer(chip, [5.0, 0.0, 5.0, 0.0]), HudStyle.CYAN)
	HudStyle.text(self, nf, Vector2(chip.get_center().x, 23), "P%d" % player.player_id, 13, HudStyle.BG, 0.5)
	# Bars.
	var h := player.health / maxf(player.max_health, 1.0)
	var a := player.armour / maxf(player.max_armour, 1.0)
	var hc := health_color(h)
	_health_bar(Rect2(Vector2(x0, BAR_Y), BAR), h, hc, _trail[0][0], _flash[0])
	HudStyle.text(self, nf, Vector2(x0 + BAR.x + 12, BAR_Y + BAR.y - 3), "%d" % ceili(player.health), 26, hc, 0.0, 4)
	HudStyle.seg_bar(self, Rect2(Vector2(x0, ARMOUR_Y), ARMOUR_BAR), a, ARMOUR, 20, _trail[1][0], _flash[1])
	HudStyle.text(self, nf, Vector2(x0 + BAR.x + 12, ARMOUR_Y + ARMOUR_BAR.y + 1), "%d" % ceili(player.armour), 12, ARMOUR, 0.0, 3)
	# Bitcoins.
	var cs := 22.0 + 6.0 * _coin_pop
	var cc := Vector2(x0 + 11.0, 101.0)
	draw_texture_rect(RecoveryDrops.COIN_FACE, Rect2(cc - Vector2(cs, cs) * 0.5, Vector2(cs, cs)), false)
	var gold := Color(1.0, 0.82, 0.3).lerp(Color.WHITE, _coin_pop * 0.6)
	var count := "%d" % player.bitcoins
	HudStyle.text(self, nf, Vector2(x0 + 28.0, 109.0), count, 20 + roundi(_coin_pop * 4.0), gold, 0.0, 3)
	# Status tags.
	var tag_x := x0 + 40.0 + nf.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var pd := player.get_node_or_null("PerfectDodge") as PerfectDodge
	if pd and pd.counter_active():
		tag_x = _tag(tag_x, "COUNTER", Color(0.55, 0.95, 1.0))
	var drops := get_tree().get_first_node_in_group(RecoveryDrops.GROUP) as RecoveryDrops
	if drops and drops.bonus_active():
		_tag(tag_x, "RECOVERY +%d%%" % roundi(drops.streak_bonus * 100.0), Color(1.0, 0.85, 0.3))
	# Teammates (online co-op).
	var y := 124.0
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
	var r := Rect2(x, 92, w, 20)
	HudStyle.fill(self, HudStyle.chamfer(r, [6.0, 0.0, 6.0, 0.0]), Color(col, 0.22))
	var pts := HudStyle.chamfer(r, [6.0, 0.0, 6.0, 0.0])
	pts.append(pts[0])
	draw_polyline(pts, col, 1.5, true)
	HudStyle.text(self, lf, Vector2(x + 9, 108), s, 15, col)
	return x + w + 8


func _mate_row(mate: PlayerController, at: Vector2) -> void:
	var lf := HudStyle.label_font()
	var r := Rect2(at, Vector2(250, 22))
	HudStyle.panel(self, r, HudStyle.CYAN_DIM, HudStyle.FILL_DARK, 6.0)
	var nm := mate.character.display_name if mate.character else "PLAYER"
	HudStyle.text(self, lf, at + Vector2(8, 17), "P%d  %s" % [mate.player_id, nm], 15, HudStyle.TEXT)
	HudStyle.seg_bar(self, Rect2(at + Vector2(118, 6), Vector2(120, 10)), mate.health / maxf(mate.max_health, 1.0), HEALTH, 12)


## Health colour: green, amber from half, red at 3 bars or fewer.
static func health_color(h: float) -> Color:
	if h <= LOW:
		return HudStyle.DANGER
	if h <= 0.5:
		return HudStyle.WARN.lerp(HEALTH, (h - LOW) / (0.5 - LOW) * 0.35)
	return HEALTH


## The big health bar: a bright frame round 10 chunky slanted bars, each lit
## with a highlight across its top; lost bars dark red; the white chunk of
## recent damage drains away (`trail`).
func _health_bar(r: Rect2, frac: float, col: Color, trail: float, flash: float) -> void:
	var n := PlayerController.HEALTH_BARS
	frac = clampf(frac, 0.0, 1.0)
	trail = clampf(trail, frac, 1.0)
	var cut := r.size.y * 0.5
	HudStyle.fill(self, HudStyle.chamfer(r.grow(4.0), [0.0, cut + 2.0, 0.0, cut + 2.0]), Color(col, 0.9))
	HudStyle.fill(self, HudStyle.chamfer(r.grow(2.0), [0.0, cut + 1.0, 0.0, cut + 1.0]), Color(0.01, 0.03, 0.04, 0.92))
	var inner := r.grow(-2.0)
	var gap := 4.0
	var w := (inner.size.x - gap * (n - 1)) / n
	var sk := inner.size.y * 0.32
	var lit := col.lerp(Color.WHITE, flash * 0.6)
	var shine := lit.lerp(Color.WHITE, 0.5)
	for i in n:
		var x0 := inner.position.x + i * (w + gap)
		var seg := Rect2(x0, inner.position.y, w, inner.size.y)
		var poly := PackedVector2Array([seg.position + Vector2(sk, 0), Vector2(seg.end.x, seg.position.y),
			seg.end - Vector2(sk, 0), Vector2(seg.position.x, seg.end.y)])
		var s0 := float(i) / n
		var k := clampf((frac - s0) * n, 0.0, 1.0)
		var kt := clampf((trail - s0) * n, 0.0, 1.0)
		if k < 1.0:
			HudStyle.fill(self, poly, Color(0.45, 0.05, 0.04, 0.75))  # lost
		if k > 0.0:
			_seg_part(poly, 0.0, k, lit, 1.0)
			# Highlight across the top 40%.
			var top := PackedVector2Array([poly[0], poly[1], poly[1].lerp(poly[2], 0.4), poly[0].lerp(poly[3], 0.4)])
			_seg_part(top, 0.0, k, Color(shine, 0.55), 1.0)
		if kt > k:
			_seg_part(poly, k, kt, Color(1, 1, 1, 0.8), 1.0)


## The part of a slanted bar polygon from `a` to `b` (0..1 along it).
func _seg_part(poly: PackedVector2Array, a: float, b: float, col: Color, _alpha: float) -> void:
	if b - a < 0.02:
		return
	HudStyle.fill(self, PackedVector2Array([poly[0].lerp(poly[1], a), poly[0].lerp(poly[1], b),
		poly[3].lerp(poly[2], b), poly[3].lerp(poly[2], a)]), col)


## Low health: a red glow round the bar (faded in and out by _process).
func _draw_low_glow() -> void:
	var x0 := RING_R * 2 + 16
	var r := Rect2(Vector2(x0, BAR_Y), BAR)
	for i in 4:
		var g := 6.0 + i * 4.0
		HudStyle.fill(_low_glow, HudStyle.chamfer(r.grow(g), [0.0, r.size.y * 0.5 + g, 0.0, r.size.y * 0.5 + g]), Color(1.0, 0.15, 0.1, 0.16))
