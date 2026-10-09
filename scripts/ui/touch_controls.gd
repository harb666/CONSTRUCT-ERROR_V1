class_name TouchControls
extends Control
## Multi-touch controls: floating move stick (left), drag-to-look (right),
## and Jump / Dodge / Sprint buttons. Each finger is tracked by its touch index.
## Buttons and the stick drive regular input actions; look is sent via signal.

signal look_dragged(radians: Vector2)
## A quick touch with almost no movement (used for tap-to-target).
signal tapped(position: Vector2)
## Weapon-wheel button: held (finger down), dragged, released. The finger is
## owned by the wheel (no look, no tap) until it lifts.
signal wheel_pressed(position: Vector2)
signal wheel_dragged(position: Vector2)
signal wheel_released(position: Vector2)

## A touch counts as a tap if released within this time and distance.
@export var tap_max_time := 0.35
@export var tap_max_move := 22.0

@export var stick_radius := 80.0
## Radians of camera rotation per logical pixel dragged.
@export var look_sensitivity := Vector2(0.0075, 0.006)
## Fraction of screen width (from the left) that starts the move stick.
@export var move_zone := 0.42

const BUTTONS := [
	{"action": "jump", "label": "JUMP", "radius": 70.0, "offset": Vector2(-120, -120)},
	{"action": "dodge", "label": "DODGE", "radius": 54.0, "offset": Vector2(-280, -90)},
	# Drawn by the WeaponWheel (shows the equipped weapons).
	{"action": "weapon_wheel", "label": "", "radius": 44.0, "offset": Vector2(-262, -238), "wheel": true},
]

var _move_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_knob := Vector2.ZERO
var _look_finger := -1
var _look_last := Vector2.ZERO
var _button_fingers: Array[int] = []
var _button_last: Array[Vector2] = []
## Actions whose buttons are currently hidden.
var _hidden := {}
## finger index -> [start position, start time (s), distance moved]
var _tap_track := {}
## The weapon-wheel button only exists when a wheel is connected.
var wheel_enabled := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button_fingers.resize(BUTTONS.size())
	_button_fingers.fill(-1)
	_button_last.resize(BUTTONS.size())
	visible = DisplayServer.is_touchscreen_available()


## Centre of a button by action name (for overlays like the weapon wheel).
func button_center(action: String) -> Vector2:
	for i in BUTTONS.size():
		if BUTTONS[i].action == action:
			return _button_center(i)
	return Vector2.ZERO


func button_radius(action: String) -> float:
	for b in BUTTONS:
		if b.action == action:
			return b.radius
	return 0.0


func _button_center(i: int) -> Vector2:
	var safe := _safe_margins()
	return Vector2(size.x - safe.y, size.y) + BUTTONS[i].offset


## Left/right insets for the iPhone notch / home indicator in landscape.
func _safe_margins() -> Vector2:
	return Vector2(maxf(40.0, size.x * 0.03), maxf(40.0, size.x * 0.03))


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if not visible:
			visible = true
		if event.pressed:
			_on_touch_down(event.index, event.position)
		else:
			_on_touch_up(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_on_touch_drag(event.index, event.position)
		get_viewport().set_input_as_handled()


func _on_touch_down(index: int, pos: Vector2) -> void:
	_tap_track[index] = [pos, Time.get_ticks_msec() / 1000.0, 0.0]
	for i in BUTTONS.size():
		if _hidden.has(BUTTONS[i].action):
			continue
		if _button_fingers[i] == -1 and pos.distance_to(_button_center(i)) <= BUTTONS[i].radius * 1.25 \
				and not (BUTTONS[i].get("wheel", false) and not wheel_enabled):
			_button_fingers[i] = index
			_button_last[i] = pos
			_press_button(i)
			queue_redraw()
			return
	if _move_finger == -1 and pos.x < size.x * move_zone:
		_move_finger = index
		_stick_origin = pos
		_stick_knob = pos
		_apply_stick(Vector2.ZERO)
	elif _look_finger == -1 and pos.x >= size.x * move_zone:
		_look_finger = index
		_look_last = pos
	queue_redraw()


func _on_touch_drag(index: int, pos: Vector2) -> void:
	if _tap_track.has(index):
		_tap_track[index][2] = maxf(_tap_track[index][2], pos.distance_to(_tap_track[index][0]))
	if index == _move_finger:
		var offset := pos - _stick_origin
		if offset.length() > stick_radius:
			# Drag the stick base along so the finger never "falls off" it.
			_stick_origin = pos - offset.normalized() * stick_radius
			offset = pos - _stick_origin
		_stick_knob = pos
		_apply_stick(offset / stick_radius)
		queue_redraw()
	elif index == _look_finger:
		var d := pos - _look_last
		_look_last = pos
		look_dragged.emit(d * look_sensitivity)
	else:
		for i in BUTTONS.size():
			if _button_fingers[i] == index and BUTTONS[i].get("wheel", false):
				_button_last[i] = pos
				wheel_dragged.emit(pos)
			if _button_fingers[i] == index and BUTTONS[i].get("look", false):
				var d := pos - _button_last[i]
				_button_last[i] = pos
				look_dragged.emit(d * look_sensitivity)


func _on_touch_up(index: int) -> void:
	# Quick, still touches that weren't on a button are taps.
	if _tap_track.has(index):
		var t: Array = _tap_track[index]
		_tap_track.erase(index)
		var on_button := false
		for i in BUTTONS.size():
			if _button_fingers[i] == index:
				on_button = true
		if not on_button and t[2] <= tap_max_move and Time.get_ticks_msec() / 1000.0 - t[1] <= tap_max_time:
			tapped.emit(t[0])
	if index == _move_finger:
		_move_finger = -1
		_apply_stick(Vector2.ZERO)
	elif index == _look_finger:
		_look_finger = -1
	for i in BUTTONS.size():
		if _button_fingers[i] == index:
			_button_fingers[i] = -1
			if BUTTONS[i].get("wheel", false):
				wheel_released.emit(_button_last[i])
			else:
				Input.action_release(BUTTONS[i].action)
	queue_redraw()


func set_action_enabled(action: String, enabled: bool) -> void:
	if enabled:
		_hidden.erase(action)
	else:
		_hidden[action] = true
		for i in BUTTONS.size():
			if BUTTONS[i].action == action and _button_fingers[i] != -1:
				_button_fingers[i] = -1
				if BUTTONS[i].get("wheel", false):
					wheel_released.emit(_button_last[i])
				else:
					Input.action_release(action)
	queue_redraw()


func _press_button(i: int) -> void:
	var b: Dictionary = BUTTONS[i]
	if b.get("wheel", false):
		wheel_pressed.emit(_button_last[i])
		return
	Input.action_press(b.action)


func _apply_stick(v: Vector2) -> void:
	_set_axis("move_left", "move_right", v.x)
	_set_axis("move_forward", "move_back", v.y)


func _set_axis(neg: String, pos: String, value: float) -> void:
	if value < 0.0:
		Input.action_press(neg, -value)
		Input.action_release(pos)
	elif value > 0.0:
		Input.action_press(pos, value)
		Input.action_release(neg)
	else:
		Input.action_release(neg)
		Input.action_release(pos)


func _draw() -> void:
	# Owner's cyan HUD style (HudStyle); sizes / positions / touch areas as before.
	var cyan := HudStyle.CYAN
	# Move stick (shows a hint at rest).
	if _move_finger != -1:
		draw_circle(_stick_origin, stick_radius, Color(HudStyle.FILL, 0.4))
		draw_arc(_stick_origin, stick_radius, 0, TAU, 48, Color(cyan, 0.75), 2.0, true)
		HudStyle.dashed_ring(self, _stick_origin, stick_radius + 7.0, 4, 0.18, Color(cyan, 0.8), 3.0, PI * 0.25 - 0.28)
		draw_circle(_stick_knob, 34.0, Color(cyan, 0.35))
		draw_arc(_stick_knob, 34.0, 0, TAU, 32, Color(cyan, 0.95), 2.0, true)
	else:
		var hint := Vector2(_safe_margins().x + 150.0, size.y - 160.0)
		draw_arc(hint, stick_radius, 0, TAU, 48, Color(cyan, 0.3), 2.0, true)
		HudStyle.dashed_ring(self, hint, stick_radius + 7.0, 4, 0.18, Color(cyan, 0.35), 3.0, PI * 0.25 - 0.28)
		_draw_label(hint, "MOVE", Color(HudStyle.TEXT, 0.4))
	# Buttons.
	for i in BUTTONS.size():
		var b: Dictionary = BUTTONS[i]
		if _hidden.has(b.action) or b.get("wheel", false):
			continue
		var c := _button_center(i)
		var active: bool = _button_fingers[i] != -1
		draw_button_ring(self, c, b.radius, active)
		_draw_label(c, b.label, Color(HudStyle.TEXT, 0.95))


## A round touch button in the HUD style (also used for the weapon button).
static func draw_button_ring(ci: CanvasItem, c: Vector2, r: float, active: bool) -> void:
	var cyan := HudStyle.CYAN
	ci.draw_circle(c, r, Color(cyan, 0.42) if active else Color(HudStyle.FILL, 0.5))
	ci.draw_arc(c, r, 0, TAU, 48, Color(cyan, 1.0 if active else 0.8), 2.0, true)
	ci.draw_arc(c, r - 5.0, 0, TAU, 48, Color(cyan, 0.25), 1.0, true)
	HudStyle.dashed_ring(ci, c, r + 5.0, 3, 0.2, Color(cyan, 0.9 if active else 0.6), 2.5, -PI * 0.5 - 0.2)


func _draw_label(center: Vector2, text: String, color: Color) -> void:
	var fs := 21
	var f := HudStyle.label_font()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, center + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
