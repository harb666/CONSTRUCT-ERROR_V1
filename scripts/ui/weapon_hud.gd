class_name WeaponHud
extends Control
## Arm weapons, top-right (Ratchet: Gladiator's weapon corner, owner's cyan
## frame style): one framed box per arm (LEFT ARM on the left, RIGHT ARM on
## the right) with the weapon's icon, name and a status bar - the Rocket
## Launcher's reload, the Machine Gun's heat (OVERHEAT while locked out),
## READY for the others. The arm firing right now lights up. Display only.
## Pistol cannon (owner asked: unlimited, with a clearly visible cooldown):
## its cells as the bar (one segment per shot left, "CELLS"), then VENTING -
## the bar filling in pulsing orange-white as it cools - and a READY flash
## when it's back. Other weapons show their ammo count in the corner (red
## when low, flashing when ammo is picked up; "EMPTY" when dry).

const BOX := Vector2(176, 80)
const GAP := 10.0
const SIDES := ["Left", "Right"]

var holder: WeaponHolder
var _fire_glow := {"Left": 0.0, "Right": 0.0}
## The cannon came back from venting / ammo was picked up for that arm.
var _ready_glow := {"Left": 0.0, "Right": 0.0}
var _ammo_glow := {"Left": 0.0, "Right": 0.0}
var _was_venting := {"Left": false, "Right": false}
var _t := 0.0
## What the boxes showed when last drawn: redrawn only when that changes
## (every redraw remakes graphics buffers - see HudStyle.fill).
var _shown := []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(BOX.x * 2 + GAP, BOX.y + 8)
	_place()
	get_viewport().size_changed.connect(_place)
	if holder:
		holder.slot_fired.connect(func(side: String, _w: Weapon) -> void: _fire_glow[side] = 1.0)
		var lo := loadout()
		if lo:
			lo.ammo_changed.connect(_on_ammo_changed)


func loadout() -> WeaponLoadout:
	return holder.get_parent().get_node_or_null("WeaponLoadout") as WeaponLoadout if holder and holder.get_parent() else null


var _ammo_seen := {}


func _on_ammo_changed(def: WeaponDefinition) -> void:
	var lo := loadout()
	var n := lo.ammo_of(def) if lo else 0
	if n > int(_ammo_seen.get(def.id, n)):
		for s in SIDES:
			var w := holder.weapon(s)
			if w and w.definition == def:
				_ammo_glow[s] = 1.0
	_ammo_seen[def.id] = n


## Top-right, clear of the notch (same inset as the touch controls).
func _place() -> void:
	var w := get_viewport_rect().size.x
	position = Vector2(w - maxf(40.0, w * 0.03) - size.x, 14.0)


func _process(delta: float) -> void:
	_t += delta
	for s in SIDES:
		_fire_glow[s] = maxf(_fire_glow[s] - delta * 4.0, 0.0)
		_ready_glow[s] = maxf(_ready_glow[s] - delta * 2.5, 0.0)
		_ammo_glow[s] = maxf(_ammo_glow[s] - delta * 2.0, 0.0)
	var now := []
	var lo := loadout()
	if holder:
		for s in SIDES:
			var w := holder.weapon(s)
			var pc := w as PlasmaCannon
			var venting := pc != null and pc.venting
			if _was_venting[s] and not venting and pc:
				_ready_glow[s] = 1.0
			_was_venting[s] = venting
			var st := status_of(w) if w else []
			if venting:
				st.append(snappedf(sin(_t * 18.0), 0.25))  # the VENTING pulse
			now.append_array([w, w.definition if w else null, _fire_glow[s], st, _ready_glow[s], _ammo_glow[s],
				lo.ammo_of(w.definition) if lo and w and w.definition else -1])
	if now != _shown:
		_shown = now
		queue_redraw()


const VENT_HOT := Color(1.0, 0.55, 0.2)


## [fraction 0..1, label, colour, segments] for a weapon's status bar.
static func status_of(w: Weapon) -> Array:
	if w is PlasmaCannon:
		var pc := w as PlasmaCannon
		if pc.venting:
			return [pc.vent_progress(), "VENTING", VENT_HOT.lerp(HudStyle.CYAN, pc.vent_progress()), 10]
		return [floorf(pc.charge + 0.001) / maxf(pc.cells, 1), "CELLS", HudStyle.CYAN, pc.cells]
	if w is RocketLauncher:
		var rl := w as RocketLauncher
		var left := rl.reload_left()
		if left > 0.0:
			return [1.0 - left / maxf(rl.fire_interval, 0.01), "RELOADING", HudStyle.WARN]
		return [1.0, "READY", HudStyle.CYAN]
	if w is FrostByte:
		var fb := w as FrostByte
		var fl := fb.reload_left()
		if fl > 0.0:
			return [1.0 - fl / maxf(fb.fire_interval, 0.01), "CHARGING", HudStyle.WARN]
		return [1.0, "READY", HudStyle.CYAN]
	if w is MachineGun:
		var mg := w as MachineGun
		if mg.overheated:
			return [mg.heat_ratio(), "OVERHEAT", HudStyle.DANGER]
		return [mg.heat_ratio(), "HEAT", HudStyle.WARN.lerp(HudStyle.DANGER, mg.heat_ratio())]
	return [1.0, "READY", HudStyle.CYAN]


const HEAVY_GOLD := Color(1.0, 0.78, 0.25)


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
		if def.heavy:
			# Heavy weapon (right arm only): a gold HEAVY plate in the corner.
			var tag := Rect2(r.end.x - 62.0, r.position.y + 7.0, 52.0, 17.0)
			draw_rect(tag, Color(0.12, 0.08, 0.0, 0.85))
			draw_rect(tag, HEAVY_GOLD, false, 1.5)
			HudStyle.text(self, lf, tag.get_center() + Vector2(0, 5), "HEAVY", 12, HEAVY_GOLD, 0.5)
		if def.icon:
			var s := 54.0
			draw_texture_rect(def.icon, Rect2(r.position + Vector2(10, 20), Vector2(s, s)), false)
		var tx := r.position.x + 70
		var nm := def.display_name.to_upper()
		HudStyle.text(self, lf, Vector2(tx, r.position.y + 40), nm, HudStyle.fit(lf, nm, BOX.x - 80, 16), HudStyle.TEXT)
		var st := status_of(w)
		var bar := Rect2(tx, r.position.y + 50, BOX.x - 82, 9)
		var col: Color = st[2]
		var segs: int = st[3] if st.size() > 3 else 10
		var label: String = st[1]
		var rg: float = _ready_glow[side]
		if w is PlasmaCannon and (w as PlasmaCannon).venting:
			# Pulsing white-hot while it cools.
			col = col.lerp(Color.WHITE, 0.35 + 0.35 * sin(_t * 18.0))
			bar = bar.grow_individual(0, 2, 0, 2)
		elif rg > 0.0:
			label = "READY"
			col = HudStyle.CYAN.lerp(Color.WHITE, rg)
		HudStyle.seg_bar(self, bar, st[0], col, segs, 0.0, rg)
		HudStyle.text(self, lf, Vector2(tx, r.position.y + 74), label, 13 + roundi(rg * 3.0), col)
		# Ammo left (weapons that use it).
		var lo := loadout()
		var ammo := lo.ammo_of(def) if lo and lo.is_unlocked(def) else -1
		if ammo >= 0:
			var ag: float = _ammo_glow[side]
			var low := ammo <= ceili(def.max_ammo * 0.25)
			var ac := (HudStyle.DANGER if low else HudStyle.TEXT).lerp(Color(1.0, 0.85, 0.3), ag)
			HudStyle.text(self, nf, Vector2(r.end.x - 46, r.position.y + 75), "EMPTY" if ammo == 0 else "%d" % ammo, 16 + roundi(ag * 4.0), ac, 1.0, 3)
