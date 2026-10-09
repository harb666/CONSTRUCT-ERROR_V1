class_name WeaponHud
extends Control
## Arm weapons, top-right (Ratchet: Gladiator's weapon corner, owner's cyan
## frame style): one framed box per arm (LEFT ARM on the left, RIGHT ARM on
## the right) with the weapon's icon, name and a status bar - the Rocket
## Launcher's reload, the Machine Gun's heat (OVERHEAT while locked out),
## READY for the others. The arm firing right now lights up. Display only.

const BOX := Vector2(176, 80)
const GAP := 10.0
const SIDES := ["Left", "Right"]

var holder: WeaponHolder
var _fire_glow := {"Left": 0.0, "Right": 0.0}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(BOX.x * 2 + GAP, BOX.y + 8)
	_place()
	get_viewport().size_changed.connect(_place)
	if holder:
		holder.slot_fired.connect(func(side: String, _w: Weapon) -> void: _fire_glow[side] = 1.0)


## Top-right, clear of the notch (same inset as the touch controls).
func _place() -> void:
	var w := get_viewport_rect().size.x
	position = Vector2(w - maxf(40.0, w * 0.03) - size.x, 14.0)


func _process(delta: float) -> void:
	for s in SIDES:
		_fire_glow[s] = maxf(_fire_glow[s] - delta * 4.0, 0.0)
	queue_redraw()


## [fraction 0..1, label, colour] for a weapon's status bar.
static func status_of(w: Weapon) -> Array:
	if w is RocketLauncher:
		var rl := w as RocketLauncher
		var left := rl.reload_left()
		if left > 0.0:
			return [1.0 - left / maxf(rl.fire_interval, 0.01), "RELOADING", HudStyle.WARN]
		return [1.0, "READY", HudStyle.CYAN]
	if w is MachineGun:
		var mg := w as MachineGun
		if mg.overheated:
			return [mg.heat_ratio(), "OVERHEAT", HudStyle.DANGER]
		return [mg.heat_ratio(), "HEAT", HudStyle.WARN.lerp(HudStyle.DANGER, mg.heat_ratio())]
	return [1.0, "READY", HudStyle.CYAN]


func _draw() -> void:
	if holder == null:
		return
	var lf := HudStyle.label_font()
	var nf := HudStyle.num_font()
	for i in 2:
		var side: String = SIDES[i]
		var r := Rect2(Vector2(i * (BOX.x + GAP), 4), BOX)
		var w := holder.weapon(side)
		var def := w.definition if w else null
		var acc := def.accent_color if def else HudStyle.CYAN
		var glow: float = _fire_glow[side]
		HudStyle.panel(self, r, HudStyle.CYAN, HudStyle.FILL.lerp(Color(acc, 0.55), glow * 0.35), 10.0)
		# Accent strip down the outer edge.
		var sx := r.position.x + 3.0 if i == 0 else r.end.x - 6.0
		draw_rect(Rect2(sx, r.position.y + 12, 3, r.size.y - 24), Color(acc, 0.9))
		HudStyle.text(self, nf, r.position + Vector2(14, 16), "L" if i == 0 else "R", 12, HudStyle.CYAN)
		HudStyle.text(self, lf, r.position + Vector2(28, 16), "LEFT ARM" if i == 0 else "RIGHT ARM", 13, Color(HudStyle.TEXT, 0.6))
		if def == null:
			HudStyle.text(self, lf, r.get_center() + Vector2(0, 8), "EMPTY", 18, Color(HudStyle.TEXT, 0.45), 0.5)
			continue
		if def.icon:
			var s := 54.0
			draw_texture_rect(def.icon, Rect2(r.position + Vector2(10, 20), Vector2(s, s)), false)
		var tx := r.position.x + 70
		var nm := def.display_name.to_upper()
		HudStyle.text(self, lf, Vector2(tx, r.position.y + 40), nm, HudStyle.fit(lf, nm, BOX.x - 80, 16), HudStyle.TEXT)
		var st := status_of(w)
		var bar := Rect2(tx, r.position.y + 50, BOX.x - 82, 9)
		HudStyle.seg_bar(self, bar, st[0], st[2], 10)
		HudStyle.text(self, lf, Vector2(tx, r.position.y + 74), st[1], 13, st[2])
