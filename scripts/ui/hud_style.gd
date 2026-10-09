class_name HudStyle
extends RefCounted
## The game's HUD / menu look (owner's reference sheet: cyan sci-fi frames
## with cut corners, bracket accents, stripe ticks, segmented rings and bars
## on a dark teal grid; laid out like Ratchet: Gladiator's HUD). Everything
## is drawn with these helpers so it stays sharp at any screen size.

const CYAN := Color(0.27, 0.86, 0.96)
const CYAN_DIM := Color(0.27, 0.86, 0.96, 0.35)
const FILL := Color(0.09, 0.27, 0.31, 0.62)
const FILL_DARK := Color(0.03, 0.09, 0.11, 0.78)
const BG := Color(0.035, 0.085, 0.1)
const TEXT := Color(0.86, 0.98, 1.0)
const HEALTH := Color(0.3, 1.0, 0.4)
const ARMOUR := Color(0.35, 0.65, 1.0)
const WARN := Color(1.0, 0.75, 0.25)
const DANGER := Color(1.0, 0.3, 0.25)

const _TITLE_FONT := "res://assets/ui/fonts/orbitron-latin-900-normal.woff2"
const _NUM_FONT := "res://assets/ui/fonts/orbitron-latin-700-normal.woff2"
const _LABEL_FONT := "res://assets/ui/fonts/rajdhani-latin-700-normal.woff2"

static var _fonts := {}


## Orbitron Black: titles.
static func title_font() -> Font:
	return _font(_TITLE_FONT)


## Orbitron Bold: numbers, buttons.
static func num_font() -> Font:
	return _font(_NUM_FONT)


## Rajdhani Bold: labels, names.
static func label_font() -> Font:
	return _font(_LABEL_FONT)


static func _font(path: String) -> Font:
	if not _fonts.has(path):
		var f: Font = load(path) if ResourceLoader.exists(path) else null
		_fonts[path] = f if f else ThemeDB.fallback_font
	return _fonts[path]


## A rectangle with cut corners (the reference's panel shape). `cuts` =
## [top-left, top-right, bottom-right, bottom-left] cut sizes.
static func chamfer(r: Rect2, cuts: Array) -> PackedVector2Array:
	var a := r.position
	var b := r.end
	var tl: float = cuts[0]
	var tr: float = cuts[1]
	var br: float = cuts[2]
	var bl: float = cuts[3]
	return PackedVector2Array([
		Vector2(a.x + tl, a.y), Vector2(b.x - tr, a.y), Vector2(b.x, a.y + tr),
		Vector2(b.x, b.y - br), Vector2(b.x - br, b.y), Vector2(a.x + bl, b.y),
		Vector2(a.x, b.y - bl), Vector2(a.x, a.y + tl)])


## Panel: translucent fill, bright outline, a thicker tab on the top edge and
## a stripe tick group bottom-right (like the reference frames).
static func panel(ci: CanvasItem, r: Rect2, col := CYAN, fill := FILL, cut := 10.0, alpha := 1.0) -> void:
	var pts := chamfer(r, [cut, 0.0, cut, 0.0])
	ci.draw_colored_polygon(pts, Color(fill, fill.a * alpha))
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, Color(col, col.a * 0.85 * alpha), 1.5, true)
	# Tab along the top edge.
	var tab_w := minf(r.size.x * 0.32, 70.0)
	ci.draw_line(Vector2(r.position.x + cut + 6, r.position.y - 1.5), Vector2(r.position.x + cut + 6 + tab_w, r.position.y - 1.5), Color(col, alpha), 3.0)
	# Stripe ticks bottom-right.
	if r.size.x > 90.0:
		stripes(ci, Vector2(r.end.x - cut - 40, r.end.y - 5), 5, Color(col, 0.7 * alpha))


## Corner brackets just outside a rect.
static func brackets(ci: CanvasItem, r: Rect2, col := CYAN, arm := 14.0, gap := 5.0, width := 2.0) -> void:
	var g := r.grow(gap)
	for c in [[g.position, Vector2(1, 1)], [Vector2(g.end.x, g.position.y), Vector2(-1, 1)],
			[g.end, Vector2(-1, -1)], [Vector2(g.position.x, g.end.y), Vector2(1, -1)]]:
		var p: Vector2 = c[0]
		var d: Vector2 = c[1]
		ci.draw_polyline(PackedVector2Array([p + Vector2(0, d.y * arm), p, p + Vector2(d.x * arm, 0)]), col, width)


## One corner bracket at `corner` whose two arms run along unit directions
## `u` and `v` (the shape's edges there), pushed `gap` outward - for
## slanted / non-rectangular frames.
static func slant_corner(ci: CanvasItem, corner: Vector2, u: Vector2, v: Vector2, col: Color, gap := 6.0, arm := 18.0, width := 3.0) -> void:
	# Outward = away from both edges (miter direction).
	var out := -(u + v).normalized()
	# A fixed distance out (a true miter flies far off at sharp corners).
	var c := corner + out * gap * 1.3
	ci.draw_polyline(PackedVector2Array([c + u * arm, c, c + v * arm]), col, width, true)


## Slanted stripe ticks ("////"), `at` = left end of the group's baseline.
static func stripes(ci: CanvasItem, at: Vector2, n: int, col: Color, h := 5.0, step := 6.0) -> void:
	for i in n:
		var x := at.x + i * step
		ci.draw_line(Vector2(x, at.y), Vector2(x + h * 0.7, at.y - h), col, 2.0)


## Segmented bar inside a cut-corner frame. Lost value (`trail`, above `frac`)
## shows as a fading white chunk; `flash` brightens the fill.
static func seg_bar(ci: CanvasItem, r: Rect2, frac: float, col: Color, segments := 20, trail := 0.0, flash := 0.0, alpha := 1.0) -> void:
	var frame := chamfer(r, [0.0, r.size.y * 0.6, 0.0, r.size.y * 0.6])
	ci.draw_colored_polygon(frame, Color(0, 0, 0, 0.5 * alpha))
	var inner := r.grow(-2.0)
	var gap := 2.0
	var w := (inner.size.x - gap * (segments - 1)) / segments
	frac = clampf(frac, 0.0, 1.0)
	trail = clampf(trail, frac, 1.0)
	var fill := col.lerp(Color.WHITE, flash * 0.6)
	var low := frac <= 0.25
	for i in segments:
		var x0 := inner.position.x + i * (w + gap)
		var s0 := float(i) / segments
		var s1 := float(i + 1) / segments
		var seg := Rect2(x0, inner.position.y, w, inner.size.y)
		# Slanted segments.
		var sk := inner.size.y * 0.35
		var poly := PackedVector2Array([seg.position + Vector2(sk, 0), Vector2(seg.end.x, seg.position.y),
			seg.end - Vector2(sk, 0), Vector2(seg.position.x, seg.end.y)])
		ci.draw_colored_polygon(poly, Color(col, 0.12 * alpha))
		var k := clampf((frac - s0) / (s1 - s0), 0.0, 1.0)
		if k > 0.0:
			var c := fill
			if low:
				c = c.lerp(DANGER, 0.35)
			_part(ci, poly, k, Color(c, alpha))
		var kt := clampf((trail - s0) / (s1 - s0), 0.0, 1.0)
		if kt > k:
			var p2 := poly.duplicate()
			_part(ci, p2, kt, Color(1, 1, 1, 0.75 * alpha), k)


## Draws the left `k` (from `from`) of a slanted segment polygon.
static func _part(ci: CanvasItem, poly: PackedVector2Array, k: float, col: Color, from := 0.0) -> void:
	var tl := poly[0].lerp(poly[1], from)
	var bl := poly[3].lerp(poly[2], from)
	var tr := poly[0].lerp(poly[1], k)
	var br := poly[3].lerp(poly[2], k)
	ci.draw_colored_polygon(PackedVector2Array([tl, tr, br, bl]), col)


## Ring made of `n` arc dashes, rotated by `spin` (radians).
static func dashed_ring(ci: CanvasItem, c: Vector2, r: float, n: int, fill_frac: float, col: Color, width := 2.0, spin := 0.0) -> void:
	var step := TAU / n
	for i in n:
		var a := spin + i * step
		ci.draw_arc(c, r, a, a + step * fill_frac, 6, col, width, true)


## Emblem of concentric rings like the reference's round gauges (portraits,
## loading, the title screen). `t` animates it; `scale` sizes everything.
static func emblem(ci: CanvasItem, c: Vector2, radius: float, t: float, col := CYAN, alpha := 1.0) -> void:
	var a := alpha
	ci.draw_circle(c, radius * 0.98, Color(FILL_DARK, 0.55 * a))
	ci.draw_arc(c, radius, 0, TAU, 64, Color(col, 0.9 * a), 2.0, true)
	dashed_ring(ci, c, radius * 0.9, 3, 0.26, Color(col, 0.9 * a), radius * 0.06, t * 0.6)
	dashed_ring(ci, c, radius * 0.8, 48, 0.45, Color(col, 0.45 * a), 1.5, -t * 0.25)
	ci.draw_arc(c, radius * 0.7, t * -0.9, t * -0.9 + TAU * 0.7, 48, Color(col, 0.7 * a), 2.0, true)
	dashed_ring(ci, c, radius * 1.08, 6, 0.12, Color(col, 0.75 * a), radius * 0.035, -t * 0.35)


## Text helpers. `x_align`: 0 left, 0.5 centre, 1 right of `pos.x`.
static func text(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, col: Color, x_align := 0.0, outline := 0) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := Vector2(pos.x - w * x_align, pos.y)
	if outline > 0:
		ci.draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(0, 0, 0, col.a * 0.6))
	ci.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## Largest font size (<= `size`) at which `s` fits in `max_w`.
static func fit(font: Font, s: String, max_w: float, size: int, min_size := 9) -> int:
	while size > min_size and font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
		size -= 1
	return size


## Background grid like the reference sheet's.
static func grid(ci: CanvasItem, r: Rect2, step: float, col: Color, offset := Vector2.ZERO) -> void:
	var x := r.position.x + fposmod(offset.x, step)
	while x < r.end.x:
		ci.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), col, 1.0)
		x += step
	var y := r.position.y + fposmod(offset.y, step)
	while y < r.end.y:
		ci.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), col, 1.0)
		y += step
