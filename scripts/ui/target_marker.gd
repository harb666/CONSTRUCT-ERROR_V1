extends Control
## Draws lock-on rings around the local player's locked targets: one per
## weapon slot (RIGHT magenta, LEFT cyan). A target both slots share gets
## both rings (the left one just outside the right one).
## States, colours kept per arm:
## - firing solution: four bright spinning arcs + centre dot;
## - behind cover (TargetLock.clear false): eight thin dim dashes, slower,
##   plus an arc that drains as the cover memory runs out;
## - lost (out of range / hidden too long / died): the ring shrinks and
##   fades out where the target was (0.35 s).

const RIGHT_COLOR := Color(1.0, 0.35, 0.95, 0.95)
const LEFT_COLOR := Color(0.25, 0.9, 1.0, 0.95)

var lock: TargetLock
var lock_left: TargetLock
var camera: Camera3D
var _spin := 0.0
## Fading "lost" rings: [world point, colour, age].
var _ghosts: Array = []
var _hooked := []
const GHOST_TIME := 0.35


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_spin += delta * 1.5
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
	queue_redraw()


func _draw() -> void:
	if camera == null:
		return
	var shared := lock != null and lock_left != null and lock.has_target() and lock.current == lock_left.current
	_ring(lock, RIGHT_COLOR, 1.0, 1.0)
	_ring(lock_left, LEFT_COLOR, 1.28 if shared else 1.0, -1.0)
	for g in _ghosts:
		var p: Vector3 = g[0]
		if camera.is_position_behind(p):
			continue
		var k: float = g[2] / GHOST_TIME
		var col: Color = g[1]
		col.a *= 1.0 - k
		draw_arc(camera.unproject_position(p), lerpf(34.0, 10.0, k), 0.0, TAU, 20, col, 2.0, true)


func _ring(l: TargetLock, col: Color, scale: float, dir: float) -> void:
	if l == null or not l.has_target():
		return
	var p := l.get_aim_point()
	if camera.is_position_behind(p):
		return
	var c := camera.unproject_position(p)
	var edge := camera.unproject_position(p + camera.global_basis.x * l.current.select_radius)
	var r := clampf(c.distance_to(edge), 28.0, 140.0) * scale
	if not l.clear:
		# Behind cover: held, not firing.
		var dim := Color(col, col.a * 0.45)
		for k in 8:
			var a := _spin * 0.4 * dir + k * TAU / 8.0
			draw_arc(c, r, a, a + 0.28, 4, dim, 2.0, true)
		var left := 1.0 - clampf(l.obstructed_for / maxf(l.cover_memory, 0.01), 0.0, 1.0)
		draw_arc(c, r * 0.72, -PI * 0.5, -PI * 0.5 + TAU * left, 24, dim, 2.0, true)
		return
	for k in 4:
		var a := _spin * dir + k * TAU / 4.0
		draw_arc(c, r, a, a + 0.9, 12, col, 3.0, true)
	draw_circle(c, 3.0, col)
