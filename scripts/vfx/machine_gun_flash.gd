class_name MachineGunFlash
extends Node3D
## Rapid-fire yellow plasma muzzle flash of the machine gun, restarted by every
## round (`fire()`), so at high rates it is a fast sequence of separate
## flashes rather than one steady blob: crossed flame tongues along the
## barrel (+X), a white-hot core, a yellow glow, two tiny electric arcs, a
## few yellow/orange sparks (own small pool) and a brief pulse of the gun's
## single light. Each flash lives `flash_life` s, shorter than the gap
## between rounds at full rate. One per gun; nothing is allocated while
## firing.

const YELLOW := Color(1.0, 0.8, 0.08)
const HOT := Color(1.0, 0.97, 0.75)
const SPARK_COUNT := 18

## Flash length along the barrel (m) and how long one flash lasts (s).
@export var length := 0.3
@export var flash_life := 0.032
@export var light_energy := 2.6
@export var light_range := 3.2
## Colours and size (defaults: the player's machine gun). The robot boss's
## chaingun reuses this flash, bigger, orange and with smoke.
@export var flame_color := YELLOW
@export var hot_color := HOT
@export var spark_color := Color(1.0, 0.75, 0.2)
@export var light_color := Color(1.0, 0.82, 0.25)
## Scales the core, glow, arcs and sparks (the tongues use `length`).
@export var size := 1.0
## A little smoke drifting off the muzzle while it fires.
@export var smoke := false

## Flashes shown (one per round).
var flashes := 0
var _t := 99.0
## Just fired: shown on the next rendered frame whatever the frame rate.
var _fresh := false
var _life := 0.032
var _scale := 1.0
var _roll := 0.0
var _tongues: Array[MeshInstance3D] = []
var _core: MeshInstance3D
var _glow: MeshInstance3D
var _arcs: Array[MeshInstance3D] = []
var _arc_ends: Array[Vector3] = []
var _light: OmniLight3D
var _sparks: Array[MeshInstance3D] = []
var _spark_pos: Array[Vector3] = []
var _spark_vel: Array[Vector3] = []
var _spark_life: Array[float] = []
var _spark_next := 0
var _sparks_live := 0
var _smoke: CPUParticles3D
var _since := 99.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for k in 2:
		var q := Vfx.quad("muzzle" if k == 0 else "flame_a", flame_color, Vector2(0.55, 1.0))
		q.visible = false
		add_child(q)
		_tongues.append(q)
	_glow = Vfx.quad("glow", flame_color, Vector2.ONE)
	_glow.visible = false
	add_child(_glow)
	_core = Vfx.quad("star", hot_color, Vector2.ONE)
	_core.visible = false
	add_child(_core)
	for i in 2:
		var a := Vfx.quad("bolt", hot_color if i == 0 else flame_color, Vector2.ONE)
		a.visible = false
		a.top_level = true
		add_child(a)
		_arcs.append(a)
		_arc_ends.append(Vector3.ZERO)
	for i in SPARK_COUNT:
		var s := Vfx.quad("streak", spark_color, Vector2.ONE)
		s.visible = false
		s.top_level = true
		add_child(s)
		_sparks.append(s)
		_spark_pos.append(Vector3.ZERO)
		_spark_vel.append(Vector3.ZERO)
		_spark_life.append(0.0)
	_light = OmniLight3D.new()
	_light.light_color = light_color
	_light.omni_range = light_range
	_light.shadow_enabled = false
	_light.light_energy = 0.0
	_light.visible = false
	_light.position = Vector3(0.08, 0, 0)
	add_child(_light)
	if smoke:
		_smoke = CPUParticles3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE * 0.35 * size
		q.material = Vfx.mix_material("smoke")
		_smoke.mesh = q
		_smoke.amount = 14
		_smoke.lifetime = 1.0
		_smoke.local_coords = false
		_smoke.direction = Vector3(1, 0.3, 0)
		_smoke.spread = 25.0
		_smoke.initial_velocity_min = 0.6 * size
		_smoke.initial_velocity_max = 1.4 * size
		_smoke.gravity = Vector3(0, 0.6, 0)
		_smoke.damping_min = 1.0
		_smoke.damping_max = 2.0
		_smoke.angle_max = 180.0
		_smoke.scale_amount_curve = Vfx.curve([Vector2(0, 0.4), Vector2(1, 1.8)])
		_smoke.color_ramp = Vfx.ramp([Color(0.6, 0.55, 0.5, 0.0), Color(0.5, 0.48, 0.46, 0.35), Color(0.45, 0.45, 0.45, 0.0)], [0.0, 0.2, 1.0])
		_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_smoke.emitting = false
		add_child(_smoke)
	set_process(false)


## One round leaves the muzzle. `energy` (0..1): the gun's spin/heat, makes
## flashes bigger and hotter; `intensity`: overall size/brightness.
func fire(energy: float, intensity := 1.0) -> void:
	_t = 0.0
	_since = 0.0
	if _smoke and not _smoke.emitting:
		_smoke.emitting = true
	flashes += 1
	_fresh = true
	_life = flash_life
	_scale = intensity * (0.8 + 0.45 * energy) * randf_range(0.8, 1.15)
	_roll = randf() * TAU
	var len := length * _scale
	for k in _tongues.size():
		var q := _tongues[k]
		# Flame points up its texture (+Y); laid along the barrel (+X), the
		# two quads crossed and rolled a little each round.
		q.transform = Transform3D(Basis(Vector3.RIGHT, _roll + k * PI * 0.5) * Basis(Vector3.BACK, -PI * 0.5)
			* Basis.from_scale(Vector3(len * randf_range(0.45, 0.6), len * randf_range(0.8, 1.2), 1.0)), Vector3(len * 0.42, 0, 0))
		q.visible = true
	_core.visible = true
	_glow.visible = true
	# Tiny arcs licking out of the muzzle rim.
	for i in _arcs.size():
		var on := randf() < 0.35 + 0.6 * energy
		_arcs[i].visible = on
		if on:
			_arc_ends[i] = Vector3(randf_range(0.03, 0.1), randf_range(-0.06, 0.06), randf_range(-0.06, 0.06)) * (1.0 + energy) * size
	# Sparks: a few per round, more as it spins up.
	var n := 1 + int(round(randf() * (1.0 + 2.0 * energy)))
	var dir := global_basis.x.normalized()
	for i in n:
		var j := _spark_next
		_spark_next = (_spark_next + 1) % SPARK_COUNT
		_spark_pos[j] = global_position + dir * 0.03 * size
		var side := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized().rotated(dir, randf() * TAU)
		_spark_vel[j] = (dir * randf_range(3.0, 7.0) + side * randf_range(0.8, 3.0)) * (0.8 + 0.4 * energy) * sqrt(size)
		_spark_life[j] = randf_range(0.1, 0.22)
		_sparks[j].visible = true
	_light.light_energy = light_energy * intensity * (0.8 + 0.5 * energy)
	_light.visible = true
	set_process(true)


func _process(delta: float) -> void:
	if _fresh:
		_fresh = false
	else:
		_t += delta
	_since += delta
	if _smoke and _smoke.emitting and _since > 0.25:
		_smoke.emitting = false
	var gs := global_basis.get_scale().x * size
	var k := clampf(_t / _life, 0.0, 1.0)
	var on := _t < _life
	for q in _tongues:
		q.visible = on
		if on:
			Vfx.set_alpha(q, 1.0 - k * k)
	_core.visible = on
	_glow.visible = on
	if on:
		Vfx.face_camera(_core, 0.13 * _scale * gs * (1.0 - 0.4 * k), _roll)
		Vfx.set_alpha(_core, 1.0 - k)
		Vfx.face_camera(_glow, 0.32 * _scale * gs, -_roll)
		Vfx.set_alpha(_glow, 0.55 * (1.0 - k))
	# The light pulses with each round and is dark between them.
	_light.light_energy *= exp(-delta * 70.0)
	_light.visible = _light.light_energy > 0.05
	var cam := get_viewport().get_camera_3d()
	var arcs_on := on and _t < _life * 1.2
	for i in _arcs.size():
		if not arcs_on:
			_arcs[i].visible = false
		elif _arcs[i].visible and cam:
			_stretch(_arcs[i], global_position, global_transform * _arc_ends[i], 0.035 * gs, cam)
	_sparks_live = 0
	for j in SPARK_COUNT:
		if _spark_life[j] <= 0.0:
			continue
		_spark_life[j] -= delta
		if _spark_life[j] <= 0.0:
			_sparks[j].visible = false
			continue
		_sparks_live += 1
		_spark_vel[j] += Vector3(0, -9.0, 0) * delta
		_spark_pos[j] += _spark_vel[j] * delta
		if cam:
			var tail := _spark_pos[j] - _spark_vel[j] * 0.02
			_stretch(_sparks[j], tail, _spark_pos[j], 0.022 * sqrt(size), cam)
			Vfx.set_alpha(_sparks[j], clampf(_spark_life[j] / 0.12, 0.0, 1.0))
	if not on and _sparks_live == 0 and not _light.visible and (_smoke == null or not _smoke.emitting):
		set_process(false)


## Camera-facing strip from `a` to `b`, `width` wide.
static func _stretch(q: MeshInstance3D, a: Vector3, b: Vector3, width: float, cam: Camera3D) -> void:
	var axis := b - a
	var len := axis.length()
	if len < 1e-4:
		return
	var y := axis / len
	var x := y.cross((cam.global_position - (a + b) * 0.5).normalized())
	if x.length_squared() < 1e-6:
		return
	x = x.normalized()
	q.global_transform = Transform3D(Basis(x * width, y * len, x.cross(y)), (a + b) * 0.5)
