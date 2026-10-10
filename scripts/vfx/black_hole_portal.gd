class_name BlackHolePortal
extends MeshInstance3D
## The owner's animated purple portal (Purple_Portal.mp4 + its matte, baked
## by tools/bake_portal.py) around a black hole: lies in the BlackHoleCore's
## disk plane (child of the core, so it moves, tilts and scales with it),
## drawn under the core's purple fire and over the gravity lens.
## Its ring is always `ring` x the core's size across, so it grows, pulses
## and collapses exactly with the black hole:
## - opening (`reveal(f, false)`, f < 1): the video's own opening frames,
##   each picked at the matching ring size (f = fraction of the full size,
##   e.g. the core growing in the gun's chamber);
## - open: the video's steady swirl, a seamless 15 fps loop (frame-blended),
##   sped up with the black hole's spin (`speed`);
## - closing (`reveal(f, true)`): the video's closing frames, matched to the
##   collapsing size frame by frame.

const SHADER := preload("res://scripts/vfx/black_hole_portal.gdshader")
const ATLAS := preload("res://assets/vfx/black_hole_portal/portal_atlas.png")
const RAMP := preload("res://assets/vfx/black_hole_portal/portal_ramp.png")
## Atlas layout (tools/bake_portal.py, portal_cells.json).
const LOOP_CELLS := 44
const LOOP_FPS := 15.0
const OPEN_FIRST := 44
const CLOSE_FIRST := 54
## Ring size of each opening / closing cell (fraction of the open ring).
const OPEN_SIZES: PackedFloat32Array = [0.098, 0.226, 0.313, 0.396, 0.488, 0.583, 0.706, 0.789, 0.889, 1.0]
const CLOSE_SIZES: PackedFloat32Array = [0.118, 0.192, 0.301, 0.393, 0.492, 0.619, 0.704, 0.817, 0.91, 1.0]
## Open ring radius / cell half-size.
const MATTE_FRACTION := 0.85
## Open-to-loop cross-fade (s).
const SETTLE_TIME := 0.3

## Ring diameter in core units (the core's purple fire is ~1 across).
var ring := 1.7
## Loop speed (follows the black hole's spin).
var speed := 1.0
## Last reveal: fraction of full size and whether it's closing.
var amount := 1.0
var closing := false
var _loop_t := 0.0
var _settle := 1.0
var _mat: ShaderMaterial


func _init() -> void:
	name = "Portal"
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y  # the core's disk plane (XZ)
	mesh = q
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.render_priority = -1
	_mat.set_shader_parameter("atlas", ATLAS)
	_mat.set_shader_parameter("ramp", RAMP)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_loop_t = randf() * LOOP_CELLS / LOOP_FPS


## Show the portal at `f` (0..1) of its full size: opening frames, or
## closing ones when `is_closing`. f >= 1 while not closing = fully open.
func reveal(f: float, is_closing := false) -> void:
	f = clampf(f, 0.0, 1.0)
	if not is_closing and amount < 1.0 and f >= 1.0:
		_settle = 0.0  # just opened: cross-fade into the loop
	amount = f
	closing = is_closing
	_update()


func _process(delta: float) -> void:
	_loop_t += delta * speed
	_settle = minf(_settle + delta / SETTLE_TIME, 1.0)
	_update()


func _update() -> void:
	visible = amount > 0.004
	var f := 1.0
	var a := 0.0
	var b := 0.0
	var m := 0.0
	var lf := fposmod(_loop_t * LOOP_FPS, float(LOOP_CELLS))
	var la := floorf(lf)
	if closing or amount < 1.0:
		var sizes := CLOSE_SIZES if closing else OPEN_SIZES
		var first := CLOSE_FIRST if closing else OPEN_FIRST
		var i := sizes.size() - 1
		while i > 0 and sizes[i - 1] >= amount:
			i -= 1
		# Between cell i-1 and cell i (or below the smallest: cell 0 shrunk).
		if i == 0 or amount <= sizes[0]:
			a = first
			b = first
			f = sizes[0]
		else:
			var t := (amount - sizes[i - 1]) / (sizes[i] - sizes[i - 1])
			a = first + i - 1
			b = first + i
			m = t
			f = lerpf(sizes[i - 1], sizes[i], t)
		if closing and amount > CLOSE_SIZES[CLOSE_SIZES.size() - 2]:
			# First moments of the collapse: from the swirl into the close.
			a = la
			b = CLOSE_FIRST + CLOSE_SIZES.size() - 1
			m = 1.0 - (amount - CLOSE_SIZES[CLOSE_SIZES.size() - 2]) / (1.0 - CLOSE_SIZES[CLOSE_SIZES.size() - 2])
			f = 1.0
	elif _settle < 1.0:
		a = OPEN_FIRST + OPEN_SIZES.size() - 1
		b = la
		m = _settle
	else:
		a = la
		b = fposmod(la + 1.0, float(LOOP_CELLS))
		m = lf - la
	# Quad sized so the drawn cell's ring is exactly `ring` across: the
	# core's own scale makes it follow the black hole's size.
	var q := ring / (MATTE_FRACTION * maxf(f, 0.05))
	scale = Vector3(q, 1.0, q)
	_mat.set_shader_parameter("cell_a", a)
	_mat.set_shader_parameter("cell_b", b)
	_mat.set_shader_parameter("mix_b", m)


## Which atlas cells it is showing (for tests).
func cells() -> Vector3:
	return Vector3(_mat.get_shader_parameter("cell_a"), _mat.get_shader_parameter("cell_b"), _mat.get_shader_parameter("mix_b"))
