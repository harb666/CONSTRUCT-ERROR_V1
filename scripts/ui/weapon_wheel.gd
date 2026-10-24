class_name WeaponWheel
extends Control
## Dual-wield weapon wheel. Hold the weapon button: the wheel opens in the
## middle of the screen (game slows a little, movement keeps working with the
## other thumb). The LEFT half holds the weapons for the LEFT ARM, the RIGHT
## half those for the RIGHT ARM; the centre shows what each arm has now.
## Drag your thumb towards a weapon (direction from where it went down) and
## release to put it on that arm: one hold -> drag -> release. Releasing near
## the start (dead zone) changes nothing.
##
## Everything comes from the player's WeaponLoadout / WeaponRegistry (icons,
## names, colours, allowed arms), so new weapons appear without UI changes.
## Desktop: hold Tab and move the mouse.
##
## Heavy weapons (WeaponDefinition.heavy: right arm only, owner asked) carry
## a gold HEAVY tag. They also show, ghosted, in the LEFT half: pick one
## there and an arrow swings across to the right arm, the RIGHT half lights
## up, and it goes on the right arm (the left arm keeps its weapon).

signal opened
signal closed
signal selected(side: String, definition: WeaponDefinition)

## Game speed while the wheel is open (1 = no slow-down).
@export var slow_time_scale := 0.5
## Drag distance (px) before anything is picked (stops mis-selection).
@export var dead_zone := 48.0
## Sideways drag (px) needed to pick an arm when dragging up/down.
@export var side_dead_band := 20.0
## Angle bonus (degrees) the hovered item keeps over its neighbours.
@export var hysteresis_deg := 6.0
## Wheel radius as a fraction of the screen's smaller side.
@export var radius_fraction := 0.3
@export var item_radius := 52.0
## Most degrees one arm's half of the wheel spans.
@export var max_half_span := 150.0

var loadout: WeaponLoadout
var touch: TouchControls
var is_open := false
var hover_side := ""
var hover_def: WeaponDefinition
## The arm the hovered weapon will actually go on (a heavy weapon picked in
## the left half: the right arm).
var hover_target := ""

var _start := Vector2.ZERO
var _cursor := Vector2.ZERO
var _open_amount := 0.0
var _items := {}  # side -> Array of [WeaponDefinition, angle]
var _font: Font
var _last_us := 0
var _key_open := false

const SIDES := ["Left", "Right"]
const ARM_LABEL := {"Left": "LEFT ARM", "Right": "RIGHT ARM"}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_font = ThemeDB.fallback_font
	_last_us = Time.get_ticks_usec()
	if touch:
		touch.wheel_enabled = true
		touch.wheel_pressed.connect(open_at)
		touch.wheel_dragged.connect(drag_to)
		touch.wheel_released.connect(release_at)
	if loadout:
		loadout.unlocked.connect(func(_d: WeaponDefinition) -> void: _layout())
		loadout.loadout_changed.connect(func(_s: String, _d: WeaponDefinition) -> void: queue_redraw())


func _exit_tree() -> void:
	if is_open:
		Engine.time_scale = 1.0


# --- Interaction ---

## Open the wheel with the finger/cursor at `pos`.
func open_at(pos: Vector2) -> void:
	if loadout == null:
		return
	is_open = true
	_start = pos
	_cursor = pos
	hover_side = ""
	hover_def = null
	hover_target = ""
	_layout()
	opened.emit()
	queue_redraw()


func drag_to(pos: Vector2) -> void:
	if not is_open:
		return
	_cursor = pos
	_update_hover()
	queue_redraw()


## Release: equip the hovered weapon on the hovered arm (if any), close.
func release_at(pos: Vector2) -> void:
	if not is_open:
		return
	drag_to(pos)
	var side := hover_target
	var def := hover_def
	close()
	if def and side != "" and loadout.equipped(side) != def:
		if loadout.equip(side, def):
			selected.emit(side, def)


func close() -> void:
	if not is_open:
		return
	is_open = false
	hover_side = ""
	hover_def = null
	hover_target = ""
	closed.emit()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	# Desktop testing: hold Tab, move the mouse, release Tab.
	if event is InputEventKey and event.keycode == KEY_TAB and not event.echo:
		if event.pressed and not is_open:
			_key_open = true
			open_at(get_viewport().get_mouse_position())
		elif not event.pressed and _key_open:
			_key_open = false
			release_at(get_viewport().get_mouse_position())
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _key_open:
		drag_to(event.position)


func _layout() -> void:
	_items.clear()
	if loadout == null:
		return
	for side in SIDES:
		# Each arm's weapons; the left half also shows the heavy weapons
		# (ghosted: picked there, they go on the right arm).
		var list := loadout.unlocked_weapons().filter(func(w: WeaponDefinition) -> bool:
			return w.can_go_on(side) or (w.heavy and w.can_go_on(WeaponDefinition.HEAVY_SIDE)))
		var n := list.size()
		var centre := PI if side == "Left" else 0.0
		var span := deg_to_rad(minf(max_half_span, 48.0 * maxf(n - 1, 0)))
		var arr: Array = []
		for i in n:
			var t := 0.5 if n == 1 else float(i) / (n - 1)
			# First weapon at the top of each half.
			var a := centre + span * (0.5 - t) if side == "Left" else centre + span * (t - 0.5)
			arr.append([list[i], a])
		_items[side] = arr
	queue_redraw()


func _update_hover() -> void:
	var v := _cursor - _start
	if v.length() < dead_zone:
		hover_side = ""
		hover_def = null
		hover_target = ""
		return
	if absf(v.x) < side_dead_band:
		return  # straight up/down: keep whatever was picked
	var side := "Left" if v.x < 0.0 else "Right"
	var phi := atan2(v.y, v.x)
	var best: WeaponDefinition = null
	var best_d := INF
	var cur_d := INF
	for it: Array in _items.get(side, []):
		var d := absf(wrapf(phi - (it[1] as float), -PI, PI))
		if d < best_d:
			best_d = d
			best = it[0]
		if side == hover_side and it[0] == hover_def:
			cur_d = d
	if best and side == hover_side and hover_def and best != hover_def and best_d + deg_to_rad(hysteresis_deg) > cur_d:
		return
	hover_side = side if best else ""
	hover_def = best
	hover_target = best.side_for(side) if best else ""


## A heavy weapon shown (ghosted) in an arm's half it can't go on.
func is_ghost(side: String, def: WeaponDefinition) -> bool:
	return def != null and def.heavy and not def.can_go_on(side)


# --- Slow motion / animation (real time) ---

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := minf((now - _last_us) / 1000000.0, 0.1)
	_last_us = now
	var target := 1.0 if is_open else 0.0
	var prev := _open_amount
	_open_amount = move_toward(_open_amount, target, dt / 0.09)
	var ts := lerpf(1.0, slow_time_scale, _open_amount)
	if Net.is_online():
		ts = 1.0  # online the world can't slow down for one player
	# Only while it's open or easing (closed, it leaves the game speed alone:
	# it used to reset the melee's hit-stop on the very next frame).
	if (_open_amount > 0.0 or prev > 0.0) and absf(Engine.time_scale - ts) > 0.0001:
		Engine.time_scale = ts
	if _open_amount != prev or is_open:
		queue_redraw()


# --- Drawing ---

func wheel_centre() -> Vector2:
	return size * 0.5 + Vector2(0, -size.y * 0.04)


func wheel_radius() -> float:
	return minf(size.x, size.y) * radius_fraction


## Screen position of a weapon's slot (for tests and highlights).
func item_position(side: String, def: WeaponDefinition) -> Vector2:
	for it: Array in _items.get(side, []):
		if it[0] == def:
			return wheel_centre() + Vector2.from_angle(it[1]) * wheel_radius()
	return Vector2.INF


func _draw() -> void:
	_draw_button()
	if _open_amount <= 0.001 or loadout == null:
		return
	var a := _open_amount
	var c := wheel_centre()
	var r := wheel_radius() * (0.85 + 0.15 * a)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06, 0.45 * a))
	# Arm halves.
	for side in SIDES:
		var hot: bool = side == hover_target if hover_target != "" else side == hover_side
		var acc := hover_def.accent_color if hot and hover_def else Color(0.55, 0.75, 1.0)
		var centre := PI if side == "Left" else 0.0
		var half := deg_to_rad(84.0)
		draw_arc(c, r, centre - half, centre + half, 40, Color(acc.r, acc.g, acc.b, (0.28 if hot else 0.12) * a), item_radius * 2.3, true)
		draw_arc(c, r + item_radius * 1.15, centre - half, centre + half, 40, Color(acc.r, acc.g, acc.b, (0.9 if hot else 0.35) * a), 3.0, true)
		# Arm name outside its half, level with the centre.
		var label_pos := c + Vector2((-1.0 if side == "Left" else 1.0) * (r + item_radius * 1.3 + 80.0), 0)
		_text(label_pos, ARM_LABEL[side], 30 if hot else 26, Color(1, 1, 1, (1.0 if hot else 0.75) * a))
	# Weapons.
	var hover_label: Array = []
	for side in SIDES:
		var equipped := loadout.equipped(side)
		for it: Array in _items.get(side, []):
			var def: WeaponDefinition = it[0]
			var p := c + Vector2.from_angle(it[1]) * r
			var hovered: bool = side == hover_side and def == hover_def
			var ghost := is_ghost(side, def)
			var is_eq: bool = def == equipped
			var ir := item_radius * (1.22 if hovered else (0.86 if ghost else 1.0)) * (0.7 + 0.3 * a)
			var acc := def.accent_color
			var ga := (0.5 if ghost and not hovered else 1.0) * a
			draw_circle(p, ir, Color(acc.r * 0.25, acc.g * 0.25, acc.b * 0.25, 0.85 * a) if hovered else Color(0.06, 0.08, 0.12, 0.8 * ga))
			if hovered:
				draw_circle(p, ir, Color(acc.r, acc.g, acc.b, 0.35 * a))
			if ghost and not hovered:
				# Dashed ring: it lives on the other arm.
				for k in 12:
					var a0 := TAU * k / 12.0
					draw_arc(p, ir, a0, a0 + TAU / 24.0, 4, Color(acc.r, acc.g, acc.b, 0.7 * ga), 2.0, true)
			else:
				draw_arc(p, ir, 0, TAU, 40, Color(acc.r, acc.g, acc.b, (1.0 if hovered or is_eq else 0.35) * a), 5.0 if hovered else (3.0 if is_eq else 1.5), true)
			if def.heavy:
				_heavy_ring(p, ir, ga)
			# Ammo (weapons that use it): the count over it; empty = dimmed,
			# can't be picked.
			var ammo := loadout.ammo_of(def)
			if def.icon:
				var s := ir * 1.75
				draw_texture_rect(def.icon, Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), false, Color(1, 1, 1, ga * (0.3 if ammo == 0 else 1.0)))
			if ammo >= 0:
				var low := ammo <= ceili(def.max_ammo * 0.25)
				_text(p + Vector2(0, -ir - 10), "EMPTY" if ammo == 0 else "%d" % ammo, 16, Color(Color(1.0, 0.35, 0.3) if low else Color.WHITE, ga))
			if def.heavy:
				_heavy_tag(p + Vector2(0, ir * 0.98), "HEAVY  > R" if ghost else "HEAVY", ga)
			if is_eq:
				# "Equipped" tick on the arm's current weapon.
				var tp := p + Vector2(ir * 0.72, -ir * 0.72)
				draw_circle(tp, 12.0, Color(acc.r, acc.g, acc.b, a))
				draw_polyline(PackedVector2Array([tp + Vector2(-6, 0), tp + Vector2(-2, 5), tp + Vector2(6, -5)]), Color(0, 0, 0, a), 3.0, true)
			if hovered:
				hover_label = [p, ir, def, ghost]
	# A hovered ghost's hand-off arrow on top (no weapon names: owner asked).
	if not hover_label.is_empty():
		var p: Vector2 = hover_label[0]
		var ir: float = hover_label[1]
		var def: WeaponDefinition = hover_label[2]
		if loadout.ammo_of(def) == 0:
			_text(p + Vector2(0, ir + 30), "NO AMMO - KILL ENEMIES FOR MORE", 16, Color(1.0, 0.35, 0.3, a))
		elif hover_label[3]:
			_hand_off_arrow(p, item_position(hover_target, def), def.accent_color, a)
			_text(p + Vector2(0, ir + 30), "HEAVY - GOES ON RIGHT ARM", 16, Color(HEAVY_GOLD, a))
	# Centre: what each arm holds (the hovered arm previews its new weapon).
	draw_circle(c, item_radius * 1.25, Color(0.04, 0.05, 0.08, 0.85 * a))
	draw_line(c + Vector2(0, -item_radius), c + Vector2(0, item_radius), Color(1, 1, 1, 0.25 * a), 2.0)
	for side in SIDES:
		var sx := -1.0 if side == "Left" else 1.0
		var def: WeaponDefinition = hover_def if side == hover_target and hover_def else loadout.equipped(side)
		var p := c + Vector2(sx * item_radius * 0.62, 0)
		if def and def.icon:
			var s := item_radius * 1.05
			draw_texture_rect(def.icon, Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), false, Color(1, 1, 1, a))
		_text(p + Vector2(0, item_radius * 0.78), "L" if side == "Left" else "R", 18, Color(1, 1, 1, 0.8 * a))
	# Pointer showing where the thumb is aiming.
	var v := _cursor - _start
	if v.length() > 4.0 and is_open:
		var reach := minf(v.length() / dead_zone, 1.0)
		var tip := c + v.normalized() * r * 0.42 * reach
		var col := hover_def.accent_color if hover_def else Color(1, 1, 1, 0.6)
		draw_line(c, tip, Color(col.r, col.g, col.b, 0.8 * a), 4.0, true)
		draw_circle(tip, 9.0, Color(col.r, col.g, col.b, a))


## The small HUD button (touch only): both arms' weapons at a glance.
func _draw_button() -> void:
	if touch == null or not touch.visible or not touch.wheel_enabled or loadout == null:
		return
	var c := touch.button_center("weapon_wheel")
	var rad := touch.button_radius("weapon_wheel")
	TouchControls.draw_button_ring(self, c, rad, is_open)
	for side in SIDES:
		var def := loadout.equipped(side)
		if def and def.icon:
			var s := rad * 1.05
			var p := c + Vector2((-1.0 if side == "Left" else 1.0) * rad * 0.42, -rad * 0.05)
			draw_texture_rect(def.icon, Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), false)
	_text(c + Vector2(0, rad * 0.62), "L    R", 14, Color(1, 1, 1, 0.75))


const HEAVY_GOLD := Color(1.0, 0.78, 0.25)


## Heavy weapons: a thick gold frame with four clamp notches.
func _heavy_ring(p: Vector2, ir: float, a: float) -> void:
	draw_arc(p, ir + 5.0, 0, TAU, 40, Color(HEAVY_GOLD, 0.85 * a), 3.0, true)
	for k in 4:
		var d := Vector2.from_angle(PI * 0.25 + PI * 0.5 * k)
		draw_line(p + d * (ir + 1.0), p + d * (ir + 11.0), Color(HEAVY_GOLD, a), 5.0, true)


## A small gold HEAVY plate under a heavy weapon.
func _heavy_tag(centre: Vector2, label: String, a: float) -> void:
	var fs := 12
	var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 14.0
	var r := Rect2(centre - Vector2(w * 0.5, 9.0), Vector2(w, 18.0))
	draw_rect(r, Color(0.12, 0.08, 0.0, 0.9 * a))
	draw_rect(r, Color(HEAVY_GOLD, a), false, 2.0)
	_text(centre + Vector2(0, -1), label, fs, Color(HEAVY_GOLD, a))


## Picked in the left half, a heavy weapon swings over to the right arm: a
## curved arrow from the ghost to its place in the right half.
func _hand_off_arrow(from: Vector2, to: Vector2, col: Color, a: float) -> void:
	if to == Vector2.INF:
		return
	var c := wheel_centre()
	var mid := (from + to) * 0.5
	# Bow the arrow away from the centre so it clears the middle disc.
	var bow := (mid - c)
	bow = bow.normalized() if bow.length() > 1.0 else Vector2.UP
	var ctrl := mid + bow * wheel_radius() * 0.3
	var pts := PackedVector2Array()
	var t_end := 0.8
	for i in 25:
		var t := t_end * i / 24.0
		pts.append(from.lerp(ctrl, t).lerp(ctrl.lerp(to, t), t))
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 90.0)
	var bright := col.lerp(Color.WHITE, 0.45)
	var tip := pts[pts.size() - 1]
	var dir := (tip - pts[pts.size() - 3]).normalized()
	var side_v := Vector2(-dir.y, dir.x)
	var head := PackedVector2Array([tip + dir * 20.0, tip - dir * 6.0 + side_v * 14.0, tip - dir * 6.0 - side_v * 14.0])
	# Dark outline under a bright line, so it reads over any weapon.
	draw_polyline(pts, Color(0, 0, 0, 0.6 * a), 10.0, true)
	draw_colored_polygon(PackedVector2Array([head[0] + dir * 3.0, head[1] - dir * 2.0 + side_v * 3.0, head[2] - dir * 2.0 - side_v * 3.0]), Color(0, 0, 0, 0.6 * a))
	draw_polyline(pts, Color(bright.r, bright.g, bright.b, a * pulse), 5.0, true)
	draw_colored_polygon(head, Color(bright.r, bright.g, bright.b, a * pulse))


func _text(centre: Vector2, text: String, fs: int, col: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := centre + Vector2(-w * 0.5, fs * 0.35)
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, col.a * 0.7))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
