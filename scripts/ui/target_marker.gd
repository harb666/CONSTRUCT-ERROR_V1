extends Control
## Draws lock-on reticles around the local player's locked targets in the
## HUD's sci-fi style (owner's reference sheet: segmented rings, tick rings,
## crosshair notches, corner brackets, dotted rings, data bars). One per
## weapon slot (RIGHT magenta, LEFT cyan). A target both slots share gets
## both (the left one just outside the right one, its rings only).
## States, colours kept per arm:
## - locking on: the reticle drops in large and snaps tight onto the target
##   (brackets closing in, a ping ring flying out, "LOCK" blinking) -
##   `ACQUIRE_TIME`;
## - firing solution: three bright segmented arcs spinning, a fine tick
##   ring turning the other way, four crosshair notches, corner brackets
##   and a centre diamond, plus a readout on its own side (arm tag,
##   distance, the target's health as a segmented bar) on a leader line;
## - behind cover (TargetLock.clear false): a dim dotted ring, slower, an
##   arc that drains as the cover memory runs out and "COVER" in the readout;
## - lost (out of range / hidden too long / died): the ring and brackets
##   collapse and fade out where the target was with "LOST" (0.35 s).

const RIGHT_COLOR := Color(1.0, 0.35, 0.95, 0.95)
const LEFT_COLOR := Color(0.25, 0.9, 1.0, 0.95)
const GHOST_TIME := 0.35
const ACQUIRE_TIME := 0.32

var lock: TargetLock
var lock_left: TargetLock
var camera: Camera3D
var _spin := 0.0
var _clock := 0.0
## Fading "lost" rings: [world point, colour, age].
var _ghosts: Array = []
var _hooked := []
## Per lock: [target it is drawing, clock time it locked on].
var _acquired := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_spin += delta * 1.5
	_clock += delta
	for g in _ghosts:
		g[2] += delta
	_ghosts = _ghosts.filter(func(g: Array) -> bool: return g[2] < GHOST_TIME)
	for pair in [[lock, RIGHT_COLOR], [lock_left, LEFT_COLOR]]:
		var l: TargetLock = pair[0]
		if l and not _hooked.has(l):
			_hooked.append(l)
			var col: Color = pair[1]
			l.target_lost.connect(func(reason: String) -> void:
				if reason != "released":
					_ghosts.append([l.last_lost_point, col, 0.0]))
		if l:
			var was: Array = _acquired.get(l, [null, 0.0])
			if l.current != was[0]:
				_acquired[l] = [l.current, _clock]
	queue_redraw()


## 0 just locked -> 1 settled on the target.
func acquire_amount(l: TargetLock) -> float:
	var a: Array = _acquired.get(l, [null, -99.0])
	return clampf((_clock - float(a[1])) / ACQUIRE_TIME, 0.0, 1.0)


func _draw() -> void:
	if camera == null:
		return
	var shared := lock != null and lock_left != null and lock.has_target() and lock.current == lock_left.current
	_reticle(lock, RIGHT_COLOR, 1.0, 1.0, true, shared)
	_reticle(lock_left, LEFT_COLOR, 1.28 if shared else 1.0, -1.0, not shared, shared)
	for g in _ghosts:
		var p: Vector3 = g[0]
		if camera.is_position_behind(p):
			continue
		var k: float = g[2] / GHOST_TIME
		var col: Color = g[1]
		col.a *= 1.0 - k
		var c := camera.unproject_position(p)
		var r := lerpf(34.0, 10.0, k)
		draw_arc(c, r, 0.0, TAU, 20, col, 2.0, true)
		HudStyle.brackets(self, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), col, 8.0, r * 0.25, 2.0)
		HudStyle.text(self, HudStyle.label_font(), c + Vector2(0, -r - 10.0), "LOST", 13, col, 0.5, 2)


func _reticle(l: TargetLock, col: Color, scale: float, dir: float, full: bool, shared := false) -> void:
	if l == null or not l.has_target():
		return
	var p := l.get_aim_point()
	if camera.is_position_behind(p):
		return
	var c := camera.unproject_position(p)
	var edge := camera.unproject_position(p + camera.global_basis.x * l.current.select_radius)
	var r := clampf(c.distance_to(edge), 34.0, 140.0) * scale
	# Readout on the outer side (away from the screen centre), so two
	# reticles' readouts never meet; a shared target: RIGHT right, LEFT left.
	var side := dir if shared else (1.0 if c.x >= size.x * 0.5 else -1.0)
	var k := acquire_amount(l)
	var e := 1.0 - pow(1.0 - k, 3.0)
	var s := r * lerpf(2.1, 1.0, e)
	# Blinks while it locks on, then holds steady.
	var a := 1.0 if k >= 1.0 else (0.55 + 0.45 * float(int(k * 9.0) % 2 == 0))
	var c_col := Color(col, col.a * a)
	var dim := Color(col, col.a * 0.4 * a)
	if k < 1.0:
		# Ping ring flying out as it locks.
		draw_arc(c, r * (1.0 + 1.4 * e), 0.0, TAU, 40, Color(col, col.a * 0.6 * (1.0 - k)), 2.0, true)
	if not l.clear:
		# Behind cover: held, not firing.
		var cdim := Color(col, col.a * 0.45 * a)
		for i in 16:
			var ang := _spin * 0.4 * dir + i * TAU / 16.0
			draw_circle(c + Vector2(cos(ang), sin(ang)) * s, 2.0, cdim)
		var left := 1.0 - clampf(l.obstructed_for / maxf(l.cover_memory, 0.01), 0.0, 1.0)
		draw_arc(c, s * 0.72, -PI * 0.5, -PI * 0.5 + TAU * left, 24, cdim, 2.0, true)
		if full:
			_readout(l, c, s, side, cdim, true)
		return
	# Firing solution: segmented arcs + a thin inner circle.
	HudStyle.dashed_ring(self, c, s, 3, 0.26, c_col, 3.5, _spin * dir)
	draw_arc(c, s * 0.84, 0.0, TAU, 40, dim, 1.0, true)
	_diamond(c, 4.0, c_col)
	if not full:
		return
	# Fine tick ring turning the other way (every 9th tick long).
	var ticks := PackedVector2Array()
	var tr := s * 1.12
	for i in 36:
		var ang := -_spin * 0.3 * dir + i * TAU / 36.0
		var d := Vector2(cos(ang), sin(ang))
		var tl := 7.0 if i % 9 == 0 else 3.5
		ticks.append(c + d * tr)
		ticks.append(c + d * (tr + tl))
	draw_multiline(ticks, dim, 1.5)
	# Crosshair notches pointing in at N / E / S / W.
	var notch := PackedVector2Array()
	for d: Vector2 in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		notch.append(c + d * s * 1.42)
		notch.append(c + d * s * 1.2)
	draw_multiline(notch, c_col, 2.0)
	# Corner brackets closing in as it locks.
	var h := s * 1.3
	HudStyle.brackets(self, Rect2(c - Vector2(h, h), Vector2(h, h) * 2.0), c_col, clampf(s * 0.3, 8.0, 18.0), 0.0, 2.0)
	_readout(l, c, s, side, c_col, false)


func _diamond(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)


## Data readout beside the reticle (`side` +1 right / -1 left) on a leader line from the bracket corner: arm tag ("LOCK" blinking
## while it locks on, "COVER" behind cover), distance, health bar.
func _readout(l: TargetLock, c: Vector2, s: float, side: float, col: Color, covered: bool) -> void:
	var corner := c + Vector2(side * s * 1.3, -s * 1.3)
	var elbow := corner + Vector2(side * 10.0, -10.0)
	var end := elbow + Vector2(side * 66.0, 0.0)
	draw_polyline(PackedVector2Array([corner, elbow, end]), col, 1.5, true)
	var xa := 0.0 if side > 0.0 else 1.0
	var x := elbow.x + side * 2.0
	var tag := ("R" if l.side == "Right" else "L") + (" COVER" if covered else (" LOCK" if acquire_amount(l) < 1.0 else " TGT"))
	HudStyle.text(self, HudStyle.label_font(), Vector2(x, elbow.y - 4.0), tag, 15, col, xa, 2)
	var dist := 0.0
	if l._player:
		dist = l._player.global_position.distance_to(l.get_aim_point())
	HudStyle.text(self, HudStyle.num_font(), Vector2(x, elbow.y + 16.0), "%.1fM" % dist, 13, col, xa, 2)
	var who := l.current.get_parent() if l.current else null
	if who and who.get("max_health") != null and float(who.get("max_health")) > 0.0:
		var frac := clampf(float(who.get("health")) / float(who.get("max_health")), 0.0, 1.0)
		var bw := 64.0
		var bx := x if side > 0.0 else x - bw
		HudStyle.seg_bar(self, Rect2(bx, elbow.y + 22.0, bw, 8.0), frac, Color(col, 1.0), 8, 0.0, 0.0, col.a)
