class_name PlasmaFx
extends Node3D
## Plasma effects (pooled, mobile-light), green by default (robots' hand
## cannons); any colour can be passed (the player's cyan cannons):
##  - muzzle_flash(): punchy green flash at a cannon muzzle + a brief green
##    light (lights shared from a small pool: few lights on mobile).
##  - impact(): bright flash + expanding ring + green sparks; on level
##    geometry also a glowing green scorch mark that crackles with tiny
##    electrical sparks and quickly fades away.

const GREEN := Color(0.15, 1.0, 0.1)
const HOT := Color(0.65, 1.0, 0.5)
const MAX_LIGHTS := 4
const MAX_FLASHES := 16
const MAX_IMPACTS := 24

enum Kind { FLASH, IMPACT }

static var _flashes: Array[PlasmaFx] = []
static var _impacts: Array[PlasmaFx] = []
static var _lights: Array[OmniLight3D] = []
static var _light_t: Array[float] = []
static var _light_next := 0

var kind := Kind.FLASH
var _t := 99.0
var _life := 0.1
var _size := 1.0
var _normal := Vector3.UP
var _scorch_on := false
var _crackle := true
var _flash: MeshInstance3D
var _ring: MeshInstance3D
var _scorch: MeshInstance3D
var _arcs: Array[MeshInstance3D] = []
var _arc_ends: Array[Vector3] = []
var _arc_t := 0.0
var _sparks: CPUParticles3D
var _roll := 0.0
var _color := GREEN
var _hot := HOT
static var _ramps := {}


# --- Public API ---

## Green flash at a cannon muzzle, pointing along `dir`.
static func muzzle_flash(tree: SceneTree, at: Vector3, dir: Vector3, col := GREEN, hot := HOT) -> void:
	var f := _take(tree, Kind.FLASH)
	if f:
		f._recolor(col, hot)
		f._start_flash(at, dir)
	_flash_light(tree, at + dir * 0.1, col)


## Plasma hits something at `at` with surface `normal`. `mark_life`: how
## long the scorch mark glows; `crackle`: tiny electrical arcs on it.
static func impact(tree: SceneTree, at: Vector3, normal: Vector3, leave_mark: bool, col := GREEN, hot := HOT,
		mark_life := 1.3, crackle := true, fx_scale := 1.0) -> void:
	var f := _take(tree, Kind.IMPACT)
	if f:
		f._recolor(col, hot)
		f._crackle = crackle
		f._start_impact(at, normal, leave_mark, mark_life)
		f._size *= fx_scale
		if leave_mark:
			f._scorch.global_basis = f._scorch.global_basis.scaled(Vector3.ONE * fx_scale)


## A very brief light pop at `at` (shared light pool; no new lights).
static func flash_light(tree: SceneTree, at: Vector3, col: Color, energy := 3.0) -> void:
	_flash_light(tree, at, col, energy)


static func busy_count() -> int:
	var n := 0
	for f in _flashes + _impacts:
		if is_instance_valid(f) and f.is_processing():
			n += 1
	return n


# --- Pools ---

static func _host(tree: SceneTree) -> Node:
	return tree.current_scene if tree.current_scene else tree.root


static func _take(tree: SceneTree, k: Kind) -> PlasmaFx:
	var pool: Array[PlasmaFx] = _flashes if k == Kind.FLASH else _impacts
	var valid := pool.filter(func(p: PlasmaFx) -> bool: return is_instance_valid(p) and p.is_inside_tree())
	pool.assign(valid)
	for p in pool:
		if not p.is_processing():
			return p
	var cap := MAX_FLASHES if k == Kind.FLASH else MAX_IMPACTS
	if pool.size() < cap:
		var f := PlasmaFx.new()
		f.kind = k
		_host(tree).add_child(f)
		pool.append(f)
		return f
	# Reuse the oldest (they are short-lived anyway).
	var oldest := pool[0]
	for p in pool:
		if p._t > oldest._t:
			oldest = p
	return oldest


static func _flash_light(tree: SceneTree, at: Vector3, col := GREEN, energy := 3.0) -> void:
	_lights = _lights.filter(func(l: OmniLight3D) -> bool: return is_instance_valid(l) and l.is_inside_tree())
	if _lights.size() < MAX_LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = GREEN
		l.omni_range = 3.5
		l.shadow_enabled = false
		l.light_energy = 0.0
		l.visible = false
		_host(tree).add_child(l)
		_lights.append(l)
		_light_t.append(0.0)
	_light_next = (_light_next + 1) % _lights.size()
	var light := _lights[_light_next]
	light.light_color = col
	light.global_position = at
	light.light_energy = energy
	light.visible = true
	_light_t[_light_next] = 0.08
	# Fades via the pool's driver (see _process of any active effect).
	if not light.has_meta("fading"):
		light.set_meta("fading", true)
		var tw := light.create_tween()
		tw.tween_property(light, "light_energy", 0.0, 0.08)
		tw.tween_callback(func() -> void:
			light.visible = false
			light.remove_meta("fading"))


# --- Instance ---

## Switch this pooled effect's colours (only touches materials on a change).
func _recolor(col: Color, hot: Color) -> void:
	if col == _color and hot == _hot:
		return
	_color = col
	_hot = hot
	var mains: Array = [_flash] if kind == Kind.FLASH else [_scorch, _ring]
	var hots: Array = [_ring] if kind == Kind.FLASH else [_flash]
	for i in _arcs.size():
		(mains if i > 0 else hots).append(_arcs[i])
	for q in mains:
		((q as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = col
	for q in hots:
		((q as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = hot
	if _sparks:
		_sparks.color_ramp = _spark_ramp(col, hot)


static func _spark_ramp(col: Color, hot: Color) -> Gradient:
	var key := str(col) + str(hot)
	if not _ramps.has(key):
		var mid := col.lerp(Color.WHITE, 0.25)
		var end := Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, 0.0)
		_ramps[key] = Vfx.ramp([Color(hot.r, hot.g, hot.b, 1), Color(mid.r, mid.g, mid.b, 1), end], [0.0, 0.4, 1.0])
	return _ramps[key]

func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if kind == Kind.FLASH:
		_flash = Vfx.quad("muzzle", GREEN, Vector2.ONE)
		_ring = Vfx.quad("star", HOT, Vector2.ONE)  # hot core
		add_child(_flash)
		add_child(_ring)
	else:
		_scorch = Vfx.quad("scorch", GREEN, Vector2.ONE)
		add_child(_scorch)
		_ring = Vfx.quad("ring", GREEN, Vector2.ONE)
		add_child(_ring)
		_flash = Vfx.quad("star", HOT, Vector2.ONE)
		add_child(_flash)
		for i in 3:
			var a := Vfx.quad("bolt", GREEN if i > 0 else HOT, Vector2.ONE)
			a.visible = false
			add_child(a)
			_arcs.append(a)
			_arc_ends.append(Vector3.ZERO)
		_sparks = Vfx.particles("glow", 0.045, 12, 0.4)
		_sparks.one_shot = true
		_sparks.explosiveness = 0.9
		_sparks.emitting = false
		_sparks.spread = 70.0
		_sparks.initial_velocity_min = 1.5
		_sparks.initial_velocity_max = 4.5
		_sparks.gravity = Vector3(0, -9.0, 0)
		_sparks.color_ramp = Vfx.ramp([Color(0.9, 1, 0.85, 1), Color(0.35, 1, 0.3, 1), Color(0.1, 0.6, 0.1, 0)], [0.0, 0.4, 1.0])
		add_child(_sparks)
	visible = false
	set_process(false)


func _start_flash(at: Vector3, dir: Vector3) -> void:
	global_position = at + dir * 0.06
	_t = 0.0
	_life = 0.09
	_roll = randf() * TAU
	visible = true
	set_process(true)
	_process(0.0)


func _start_impact(at: Vector3, normal: Vector3, leave_mark: bool, mark_life := 1.3) -> void:
	_normal = normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	global_position = at + _normal * 0.02
	_t = 0.0
	_scorch_on = leave_mark
	_life = maxf(mark_life, 0.2) if leave_mark else 0.25
	_roll = randf() * TAU
	_size = randf_range(0.85, 1.15)
	visible = true
	_scorch.visible = leave_mark
	if leave_mark:
		# Lie flat on the surface.
		var z := _normal
		var x := z.cross(Vector3.UP if absf(z.y) < 0.9 else Vector3.RIGHT).normalized()
		var y := z.cross(x)
		var c := cos(_roll)
		var s := sin(_roll)
		_scorch.global_basis = Basis(x * c + y * s, -x * s + y * c, z).scaled(Vector3.ONE * 0.55 * _size)
		_scorch.global_position = global_position
	_sparks.global_position = global_position
	_sparks.direction = _normal
	_sparks.amount = 12
	_sparks.restart()
	_sparks.emitting = true
	_arc_t = 0.0
	set_process(true)
	_process(0.0)


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		visible = false
		for a in _arcs:
			a.visible = false
		set_process(false)
		return
	if kind == Kind.FLASH:
		var k := _t / _life
		Vfx.face_camera(_flash, lerpf(0.7, 1.2, k), _roll)
		Vfx.set_alpha(_flash, 1.0 - k * k)
		Vfx.face_camera(_ring, lerpf(0.5, 0.2, k), -_roll)
		Vfx.set_alpha(_ring, 1.0 - k)
		return
	# Impact: flash + ring in the first instant.
	var fk := clampf(_t / 0.14, 0.0, 1.0)
	_flash.visible = fk < 1.0
	_ring.visible = fk < 1.0
	if fk < 1.0:
		Vfx.face_camera(_flash, (0.5 + 0.4 * fk) * _size, _roll)
		Vfx.set_alpha(_flash, 1.0 - fk)
		Vfx.face_camera(_ring, (0.25 + 0.9 * fk) * _size, 0.0)
		Vfx.set_alpha(_ring, (1.0 - fk) * 0.8)
	if not _scorch_on:
		return
	# Glowing scorch mark: bright, then quickly fades away.
	var sk := clampf((_t - 0.05) / (_life - 0.05), 0.0, 1.0)
	Vfx.set_alpha(_scorch, (1.0 - sk) * (1.0 - sk) * 0.9)
	if not _crackle:
		return
	# Tiny electrical crackle from the mark, dying down.
	_arc_t -= delta
	if _arc_t <= 0.0:
		_arc_t = randf_range(0.03, 0.07)
		var chance := 0.9 * (1.0 - sk)
		for i in _arcs.size():
			var on := randf() < chance * (1.0 if i == 0 else 0.6)
			_arcs[i].visible = on
			if on:
				var tangent := _normal.cross(Vector3.UP if absf(_normal.y) < 0.9 else Vector3.RIGHT).normalized().rotated(_normal, randf() * TAU)
				_arc_ends[i] = (tangent * randf_range(0.08, 0.22) + _normal * randf_range(0.02, 0.1)) * _size
				Vfx.set_alpha(_arcs[i], randf_range(0.6, 1.0) * (1.0 - sk))
		if randf() < 0.08 * (1.0 - sk):
			_sparks.amount = 3
			_sparks.restart()
			_sparks.emitting = true
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var a := global_position
	for i in _arcs.size():
		if not _arcs[i].visible:
			continue
		var b := a + _arc_ends[i]
		var axis := b - a
		var len := axis.length()
		if len < 1e-4:
			continue
		var y := axis / len
		var x := y.cross((cam.global_position - (a + b) * 0.5).normalized()).normalized()
		var z := x.cross(y)
		_arcs[i].global_transform = Transform3D(Basis(x * 0.06, y * len, z), (a + b) * 0.5)
