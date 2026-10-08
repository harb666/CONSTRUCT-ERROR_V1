class_name BossCoreFx
extends Node3D
## The boss reactor core's electrical state (one per boss, nothing
## allocated after _ready):
##  - hit(): every core hit throws red sparks, a red flash and a burst of
##    crackling red arcs; now and then sparks from nearby machinery too.
##  - instability (0..1, from lost health): more, faster, stronger arcs,
##    intermittent red pulses, smoke wisps when low - it struggles to hold
##    together.
##  - failure(): death. Violent overload, then (blow()) the core's internal
##    explosion, smoke pouring out, red arcs spreading out over the whole
##    robot (jumping between its joints/armour/weapons), dying away over
##    `aftermath_time`.
## Arcs are camera-facing jagged strips (2 segments each). `points` returns
## world positions across the body (joints) for the spreading arcs.

const RED := Color(1.0, 0.08, 0.04)
const HOT := Color(1.0, 0.55, 0.45)
const ARCS := 7
const BODY_ARCS := 10

## Seconds the dead robot keeps sparking and smoking.
@export var aftermath_time := 9.0

var instability := 0.0
## World-space joint positions for the spreading arcs (set by the boss).
var points: Callable
## The core's severed connections: [[wall-side end, core stub end, is hose]]
## (world), once snapped (BossCoreCables.broken_ends).
var cable_ends: Callable
var _end_burst := 0
## The core's world position (set by the boss each frame).
var core_pos := Vector3.ZERO
## Out of the chest opening (world); core arcs and sparks favour it.
var forward := Vector3.FORWARD
var radius := 0.2

var _t := 0.0
var _hit_t := 0.0
var _flash_t := 0.0
var _fail_t := -1.0
var _blown := false
var _arcs: Array = []      # [MeshInstance3D, MeshInstance3D] per arc
var _arc_life: Array[float] = []
var _arc_ab: Array = []    # [a, m, b] world points
var _body: Array = []
var _body_life: Array[float] = []
var _body_ab: Array = []
var _flash: MeshInstance3D
var _sparks: CPUParticles3D
var _machine_sparks: CPUParticles3D
var _smoke: CPUParticles3D
var _light: OmniLight3D

## Counters (tests).
var hits := 0
var body_arcs_shown := 0


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for i in ARCS:
		_arcs.append(_arc_pair())
		_arc_life.append(0.0)
		_arc_ab.append([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	for i in BODY_ARCS:
		_body.append(_arc_pair())
		_body_life.append(0.0)
		_body_ab.append([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	_flash = Vfx.quad("star", HOT, Vector2.ONE)
	# Flashes glow over the pocket's rim.
	(_flash.material_override as StandardMaterial3D).no_depth_test = true
	(_flash.material_override as StandardMaterial3D).render_priority = 2
	_flash.top_level = true
	_flash.visible = false
	add_child(_flash)
	_sparks = Vfx.particles("glow", 0.14, 28, 0.55)
	_sparks.one_shot = true
	_sparks.explosiveness = 0.9
	_sparks.local_coords = false
	_sparks.direction = Vector3(0, 0, 1)
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 3.5
	_sparks.initial_velocity_max = 9.0
	_sparks.gravity = Vector3(0, -12, 0)
	_sparks.color_ramp = Vfx.ramp([Color(1, 0.75, 0.6, 1), Color(1, 0.15, 0.05, 1), Color(0.5, 0.02, 0.0, 0)], [0.0, 0.35, 1.0])
	_sparks.emitting = false
	add_child(_sparks)
	_machine_sparks = Vfx.particles("glow", 0.12, 16, 0.6)
	_machine_sparks.one_shot = true
	_machine_sparks.explosiveness = 0.95
	_machine_sparks.local_coords = false
	_machine_sparks.top_level = true
	_machine_sparks.direction = Vector3.UP
	_machine_sparks.spread = 80.0
	_machine_sparks.initial_velocity_min = 1.5
	_machine_sparks.initial_velocity_max = 5.0
	_machine_sparks.gravity = Vector3(0, -12, 0)
	_machine_sparks.color_ramp = Vfx.ramp([Color(1, 0.9, 0.6, 1), Color(1, 0.4, 0.1, 1), Color(0.6, 0.1, 0.0, 0)], [0.0, 0.4, 1.0])
	_machine_sparks.emitting = false
	add_child(_machine_sparks)
	_smoke = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 1.4
	q.material = Vfx.mix_material("smoke")
	_smoke.mesh = q
	_smoke.amount = 18
	_smoke.lifetime = 2.4
	_smoke.local_coords = false
	_smoke.direction = Vector3(0, 1, 0.4)
	_smoke.spread = 25.0
	_smoke.initial_velocity_min = 0.6
	_smoke.initial_velocity_max = 1.6
	_smoke.gravity = Vector3(0, 1.0, 0)
	_smoke.damping_min = 0.5
	_smoke.damping_max = 1.0
	_smoke.angle_max = 180.0
	_smoke.scale_amount_curve = Vfx.curve([Vector2(0, 0.3), Vector2(1, 2.0)])
	_smoke.color_ramp = Vfx.ramp([Color(0.4, 0.36, 0.34, 0.0), Color(0.36, 0.34, 0.33, 0.8), Color(0.45, 0.45, 0.45, 0.0)], [0.0, 0.15, 1.0])
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke.emitting = false
	add_child(_smoke)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.1, 0.05)
	_light.omni_range = 6.0
	_light.shadow_enabled = false
	_light.light_energy = 0.0
	_light.visible = false
	add_child(_light)
	Vfx.tame_light(_light)


## One arc: two jagged segments, each a hot core streak plus a wide red glow.
func _arc_pair() -> Array:
	var pair := []
	for k in 4:
		var core_q := k < 2
		var q := Vfx.quad("bolt" if core_q else "glow", Color(1.0, 0.55, 0.45) if core_q else Color(1.0, 0.06, 0.03), Vector2.ONE)
		q.top_level = true
		q.visible = false
		add_child(q)
		pair.append(q)
	return pair


## A shot hit the core: `strength` 0..1.
func hit(strength: float, from_dir: Vector3) -> void:
	hits += 1
	_hit_t = 0.12 + 0.1 * strength
	_flash_t = 0.07
	_sparks.global_position = core_pos
	_sparks.direction = ((-from_dir if from_dir.length_squared() > 0.01 else forward) + forward).normalized()
	_sparks.amount = clampi(12 + int(16 * strength), 12, 28)
	_sparks.restart()
	_sparks.emitting = true
	# A burst of arcs off the core.
	for i in mini(ARCS, 2 + int(3 * strength + 3 * instability)):
		_spawn_core_arc(i, 1.0)
	# Now and then the machinery around it shorts out too.
	if randf() < 0.25 + 0.4 * instability:
		_machine_burst()


## Death: the core overloads (call once).
func failure() -> void:
	_fail_t = 0.0
	_blown = false


## The core blows (internal explosion): smoke pours, arcs spread.
func blow() -> void:
	_blown = true
	_end_burst = 0
	_fail_t = maxf(_fail_t, 0.0)
	_smoke.global_position = core_pos
	_smoke.restart()
	_smoke.emitting = true
	_sparks.global_position = core_pos
	_sparks.amount = 24
	_sparks.initial_velocity_max = 10.0
	_sparks.restart()
	_sparks.emitting = true


func reset() -> void:
	_fail_t = -1.0
	_blown = false
	instability = 0.0
	_smoke.emitting = false
	_sparks.initial_velocity_max = 9.0
	for i in ARCS:
		_hide(_arcs[i])
		_arc_life[i] = 0.0
	for i in BODY_ARCS:
		_hide(_body[i])
		_body_life[i] = 0.0


func is_failing() -> bool:
	return _fail_t >= 0.0


func _machine_burst() -> void:
	if not points.is_valid():
		return
	var pts: Array = points.call()
	if pts.is_empty():
		return
	_machine_sparks.global_position = pts[randi() % pts.size()]
	_machine_sparks.restart()
	_machine_sparks.emitting = true


func _spawn_core_arc(i: int, reach: float) -> void:
	var dir := (Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() + forward * 1.1).normalized()
	var a := core_pos + dir * radius * 0.4
	var b := core_pos + (dir + Vector3(randf_range(-0.7, 0.7), randf_range(-0.7, 0.7), randf_range(-0.7, 0.7))).normalized() * radius * randf_range(1.0, 2.2) * reach
	_arc_ab[i] = [a, (a + b) * 0.5 + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * radius * 0.5, b]
	_arc_life[i] = randf_range(0.04, 0.09)
	_show(_arcs[i], randf_range(0.6, 1.0))


func _spawn_body_arc(i: int, spread: float) -> void:
	if not points.is_valid():
		return
	var pts: Array = points.call()
	if pts.size() < 2:
		return
	# A joint within the spreading front, jumping to a nearby one.
	var cand: Array = []
	for p in pts:
		if (p as Vector3).distance_to(core_pos) <= spread:
			cand.append(p)
	if cand.is_empty():
		return
	var a: Vector3 = cand[randi() % cand.size()]
	var b: Vector3 = pts[randi() % pts.size()]
	for k in 4:
		var c: Vector3 = pts[randi() % pts.size()]
		if c != a and (b == a or c.distance_to(a) < b.distance_to(a)):
			b = c
	if a.distance_to(b) < 0.05:
		return
	var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * a.distance_to(b) * 0.3
	_body_ab[i] = [a, (a + b) * 0.5 + off, b]
	_body_life[i] = randf_range(0.05, 0.12)
	body_arcs_shown += 1
	_show(_body[i], randf_range(0.6, 1.0))


func _show(pair: Array, alpha: float) -> void:
	for i in pair.size():
		var q: MeshInstance3D = pair[i]
		q.visible = true
		Vfx.set_alpha(q, alpha * (1.0 if i < 2 else 0.55))


func _hide(pair: Array) -> void:
	for q: MeshInstance3D in pair:
		q.visible = false


func _process(delta: float) -> void:
	_t += delta
	var cam := get_viewport().get_camera_3d()
	var failing := _fail_t >= 0.0
	if failing:
		_fail_t += delta
	var after := clampf((_fail_t - 0.6) / aftermath_time, 0.0, 1.0) if _blown else 0.0
	var chaos := 1.0 if failing and not _blown else (1.0 - after if _blown else 0.0)
	# Core arcs: from hits, plus continuous crackle that grows with damage.
	var crackle := maxf(instability * instability, chaos) if not _blown else 0.0
	_hit_t = maxf(_hit_t - delta, 0.0)
	for i in ARCS:
		_arc_life[i] -= delta
		if _arc_life[i] <= 0.0:
			_hide(_arcs[i])
			var want := (1.0 if _hit_t > 0.0 else 0.0) + crackle * (2.5 if chaos > 0.5 else 1.4)
			if randf() < want * delta * 18.0:
				_spawn_core_arc(i, 1.0 + chaos)
		elif cam:
			_draw(_arcs[i], _arc_ab[i], radius * 0.22, cam)
	# Spreading failure: arcs jump across the whole body, dying away.
	if _blown:
		var spread := 0.5 + 9.0 * clampf(_fail_t / 1.0, 0.0, 1.0)
		var rate := lerpf(16.0, 0.0, pow(after, 0.6)) * (1.0 if randf() > 0.15 else 0.0)
		for i in BODY_ARCS:
			_body_life[i] -= delta
			if _body_life[i] <= 0.0:
				_hide(_body[i])
				if randf() < rate * delta * (1.0 if i < 4 else 0.5):
					_spawn_body_arc(i, spread)
			elif cam:
				_draw(_body[i], _body_ab[i], 0.22 + 0.14 * (1.0 - after), cam)
		if randf() < (1.0 - after) * delta * 2.5:
			_machine_burst()
		_smoke.emitting = after < 0.85
		_smoke.global_position = core_pos
		_severed(delta, after)
	elif instability > 0.6 or failing:
		# Smoke wisps from a badly damaged core.
		_smoke.global_position = core_pos
		_smoke.emitting = true
	else:
		_smoke.emitting = false
	# Red flashes: on hits, intermittent when unstable, wild when failing.
	_flash_t -= delta
	var pulse := randf() < (instability * instability * 1.5 + chaos * 8.0) * delta and not _blown
	if pulse:
		_flash_t = randf_range(0.04, 0.09)
	_flash.visible = _flash_t > 0.0
	if _flash.visible:
		_flash.global_position = core_pos + forward * radius * 0.6
		Vfx.face_camera(_flash, radius * randf_range(2.0, 3.2) * (1.0 + chaos * 0.6), randf() * TAU)
		Vfx.set_alpha(_flash, randf_range(0.6, 1.0))
	var glow := 0.0
	if _flash_t > 0.0:
		glow = 2.5
	elif chaos > 0.0 and not _blown:
		glow = randf_range(0.5, 3.0)
	elif _blown:
		glow = 1.5 * (1.0 - after) if randf() < 0.1 else 0.0
	_light.global_position = core_pos
	_light.light_energy = glow
	_light.visible = glow > 0.05


## The snapped cables: a burst of sparks out of every severed end (one
## after another), red arcs jumping between broken ends, smoke out of the
## torn hoses (the core's smoke follows one of them).
func _severed(delta: float, after: float) -> void:
	if not cable_ends.is_valid():
		return
	var ends: Array = cable_ends.call()
	if ends.is_empty():
		return
	if _end_burst < ends.size() * 2 and randf() < delta * 30.0:
		var e: Array = ends[_end_burst % ends.size()]
		_machine_sparks.global_position = e[0] if _end_burst < ends.size() else e[1]
		_machine_sparks.restart()
		_machine_sparks.emitting = true
		_end_burst += 1
	elif randf() < (1.0 - after) * delta * 3.0:
		var e: Array = ends[randi() % ends.size()]
		_machine_sparks.global_position = e[0]
		_machine_sparks.restart()
		_machine_sparks.emitting = true
	# Arcs between a loose end and its stub (or two loose ends).
	var cam := get_viewport().get_camera_3d()
	for i in ARCS:
		if _arc_life[i] > 0.0:
			continue
		if randf() < (1.0 - after) * delta * 6.0:
			var e: Array = ends[randi() % ends.size()]
			var b: Vector3 = e[1] if randf() < 0.7 else (ends[randi() % ends.size()] as Array)[0]
			var a: Vector3 = e[0]
			if a.distance_to(b) < 0.05:
				continue
			var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * a.distance_to(b) * 0.3
			_arc_ab[i] = [a, (a + b) * 0.5 + off, b]
			_arc_life[i] = randf_range(0.04, 0.1)
			_show(_arcs[i], randf_range(0.7, 1.0))
	# Smoke out of a torn hose.
	for e: Array in ends:
		if e[2]:
			_smoke.global_position = e[0]
			break


## A jagged two-segment arc a -> m -> b, `width` wide (its glow wider),
## facing the camera.
func _draw(pair: Array, abm: Array, width: float, cam: Camera3D) -> void:
	for k in 2:
		var a: Vector3 = abm[k]
		var b: Vector3 = abm[k + 1]
		var axis := b - a
		var len := axis.length()
		if len < 1e-4:
			continue
		var y := axis / len
		var x := y.cross((cam.global_position - (a + b) * 0.5).normalized())
		if x.length_squared() < 1e-6:
			continue
		x = x.normalized()
		var w := width * (1.0 if k == 0 else 0.8)
		(pair[k] as MeshInstance3D).global_transform = Transform3D(Basis(x * w * 1.6, y * len, x.cross(y)), (a + b) * 0.5)
		(pair[k + 2] as MeshInstance3D).global_transform = Transform3D(Basis(x * w * 4.0, y * len * 1.15, x.cross(y)), (a + b) * 0.5)
