class_name BlackHoleLightning
extends Node3D
## Violent electricity lashing out of a flying black hole.
## - Pooled bolts (fixed MeshInstance3D + ImmediateMesh each), rebuilt as
##   jagged, forking, camera-facing ribbons; re-jittered every few frames.
## - Frequent small arcs + occasional large bolts (capped at `max_major`).
## - Each strike casts ONE ray in a random (ground/wall-biased) direction;
##   if it hits within reach the bolt terminates on that surface, with a
##   flash + sparks (+ light for big ones). Nearer surfaces are hit more
##   often. Big bolts sometimes go for a nearby enemy (Targetable).
## Visual only. Owner sets `radius` (black hole size) every frame.

@export var minor_interval := Vector2(0.012, 0.03)
@export var major_interval := Vector2(0.1, 0.3)
@export var max_minor := 14
@export var max_major := 4
@export var minor_life := Vector2(0.07, 0.16)
@export var major_life := Vector2(0.15, 0.3)
## Pre-supernova eruption: thick, long blue-violet bolts.
@export var max_erupt := 9
@export var erupt_interval := Vector2(0.02, 0.06)
@export var erupt_life := Vector2(0.12, 0.26)
@export var erupt_reach := 7.5
const ERUPT_COLOR := Color(0.32, 0.24, 1.0)

## Black hole diameter (m). Reach and thickness scale with it.
var radius := 3.0
## Physics bodies the rays ignore (the shooter).
var exclude: Array[RID] = []
var active := true
## 0..1 gravity-well instability: more frequent, longer, bigger bolts.
var violence := 0.0
## 0..1: eruption of blue-violet lightning (set via erupt()).
var eruption := 0.0

var _bolts: Array[Dictionary] = []
var _flashes: Array[MeshInstance3D] = []
var _flash_age: Array[float] = []
var _flash_next := 0
var _sparks: Array[CPUParticles3D] = []
var _spark_next := 0
var _light: OmniLight3D
var _light_t := 0.0
var _minor_t := 0.0
var _major_t := 0.3
var _glow_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _erupt_glow_mat: StandardMaterial3D
var _erupt_core_mat: StandardMaterial3D
var _erupt_t := 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_glow_mat = Vfx.material("glow", Color(0.75, 0.25, 1.0, 1.0))
	_core_mat = Vfx.material("glow", Color(1.0, 0.92, 1.0, 1.0))
	_erupt_glow_mat = Vfx.material("glow", Color(ERUPT_COLOR, 1.0))
	_erupt_core_mat = Vfx.material("glow", Color(0.45, 0.4, 1.0, 1.0))
	for i in max_minor + max_major + max_erupt:
		var mi := MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		mi.top_level = true
		mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 16.0
		add_child(mi)
		mi.global_transform = Transform3D.IDENTITY
		var kind := 0 if i < max_minor else (1 if i < max_minor + max_major else 2)
		_bolts.append({"mi": mi, "life": 0.0, "major": kind >= 1, "erupt": kind == 2, "end": Vector3.ZERO, "dir0": Vector3.FORWARD, "rejit": 0.0, "pts": [], "branches": []})
	for i in 6:
		var f := Vfx.quad("star" if i % 2 == 0 else "crackle", Vfx.HOT, Vector2.ONE)
		f.top_level = true
		f.visible = false
		add_child(f)
		_flashes.append(f)
		_flash_age.append(99.0)
	for i in 3:
		var sp := Vfx.particles("glow", 0.07, 14, 0.4)
		sp.top_level = true
		sp.one_shot = true
		sp.emitting = false
		sp.explosiveness = 1.0
		sp.direction = Vector3.UP
		sp.spread = 180.0
		sp.initial_velocity_min = 2.0
		sp.initial_velocity_max = 6.0
		sp.damping_min = 3.0
		sp.damping_max = 5.0
		sp.gravity = Vector3(0, -7, 0)
		sp.color_ramp = Vfx.ramp([Color(1, 0.95, 1, 1), Color(0.7, 0.3, 1, 1), Color(0.5, 0.1, 0.9, 0)], [0.0, 0.45, 1.0])
		add_child(sp)
		_sparks.append(sp)
	_light = OmniLight3D.new()
	_light.top_level = true
	_light.light_color = Vfx.PURPLE
	_light.shadow_enabled = false
	_light.light_energy = 0.0
	add_child(_light)
	Vfx.tame_light(_light)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var center := global_position
	if active and radius > 0.8:
		_minor_t -= delta
		_major_t -= delta
		var rate := 1.0 - violence * 0.55
		if _minor_t <= 0.0:
			_minor_t = randf_range(minor_interval.x, minor_interval.y) * rate
			_strike(false, center)
		if _major_t <= 0.0:
			_major_t = randf_range(major_interval.x, major_interval.y) * rate
			_strike(true, center)
		if eruption > 0.0:
			_erupt_t -= delta
			var n := 0
			while _erupt_t <= 0.0 and n < 4:  # keep up at low frame rates
				_erupt_t += randf_range(erupt_interval.x, erupt_interval.y)
				_strike(true, center, true)
				n += 1
			_erupt_t = maxf(_erupt_t, 0.0)
	for b in _bolts:
		var mi: MeshInstance3D = b.mi
		if b.life <= 0.0:
			if mi.visible:
				mi.visible = false
				(mi.mesh as ImmediateMesh).clear_surfaces()
			continue
		b.life -= delta
		b.rejit -= delta
		if b.rejit <= 0.0:
			b.rejit = 0.035
			_jitter(b)
		mi.visible = randf() > 0.12  # rapid irregular flicker
		_build(b, center, cam)
	for i in _flashes.size():
		_flash_age[i] += delta
		var f := _flashes[i]
		if f.visible:
			var k := _flash_age[i] / 0.16
			if k >= 1.0:
				f.visible = false
			else:
				Vfx.set_alpha(f, 1.0 - k)
				Vfx.face_camera(f, f.get_meta("size", 0.6) * (1.0 + k * 0.6), f.get_meta("roll", 0.0))
	if _light_t > 0.0:
		_light_t -= delta
		_light.light_energy = maxf(_light_t / 0.15, 0.0) * 5.0


## Pick an end point: a real surface/enemy if one is within reach, else air.
func _strike(major: bool, center: Vector3, erupt := false) -> void:
	var b := _free_bolt(major, erupt)
	if b.is_empty():
		return
	var shell := radius * 0.18  # edge of the dark core
	var reach := (radius * 0.6 + (4.5 if major else 2.0)) * (1.0 + violence * 0.6)
	if erupt:
		reach = (radius * 0.9 + erupt_reach) * randf_range(0.75, 1.15)
	var end := Vector3.ZERO
	var hit_surface := false
	# Big bolts sometimes go for an enemy in reach.
	if major and randf() < (0.5 if erupt else 0.35):
		for t: Targetable in Targetable.all():
			if t.is_valid_target() and t.get_aim_point().distance_to(center) < reach:
				end = t.get_aim_point() + Vector3(randf_range(-0.3, 0.3), randf_range(-0.6, 0.4), randf_range(-0.3, 0.3))
				hit_surface = true
				break
	if not hit_surface:
		# Lash outward: mostly diagonally down (strikes the ground well
		# outside the disc) or sideways (walls/props), sometimes up. One ray.
		var flat := Vector2.from_angle(randf() * TAU)
		var roll := randf()
		var y := randf_range(-0.75, -0.25) if roll < 0.45 else (randf_range(-0.2, 0.3) if roll < 0.85 else randf_range(0.3, 0.8))
		var dir := Vector3(flat.x, y, flat.y).normalized()
		var q := PhysicsRayQueryParameters3D.create(center + dir * shell, center + dir * reach)
		q.exclude = exclude
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		# The closer the surface, the more likely the bolt jumps the gap.
		if hit and randf() < clampf(1.25 - center.distance_to(hit.position) / reach, 0.25, 1.0):
			end = hit.position
			hit_surface = true
		else:
			end = center + dir * reach * randf_range(0.7, 1.0)
	b.life = randf_range(major_life.x, major_life.y) if major else randf_range(minor_life.x, minor_life.y)
	if erupt:
		b.life = randf_range(erupt_life.x, erupt_life.y)
	b.end = end
	b.dir0 = (end - center).normalized()
	b.rejit = 0.0
	_jitter(b)
	if hit_surface:
		_contact(end, major, erupt)


func _free_bolt(major: bool, erupt := false) -> Dictionary:
	for b in _bolts:
		if b.major == major and b.erupt == erupt and b.life <= 0.0:
			return b
	return {}


## New random jag offsets (+ forks) for a bolt, as fractions along it.
func _jitter(b: Dictionary) -> void:
	var segs := 14 if b.erupt else (12 if b.major else 7)
	var pts := []
	for i in segs + 1:
		var t := float(i) / segs
		var amp := sin(t * PI)  # pinned at both ends
		pts.append([t, Vector2(randf_range(-1, 1), randf_range(-1, 1)) * amp])
	b.pts = pts
	var branches := []
	for k in (randi_range(2, 4) if b.erupt else (randi_range(1, 3) if b.major else randi_range(0, 1))):
		branches.append([randf_range(0.25, 0.75), Vector3(randf_range(-1, 1), randf_range(-1, 0.6), randf_range(-1, 1)).normalized(), randf_range(0.25, 0.5)])
	b.branches = branches


func _build(b: Dictionary, center: Vector3, cam: Camera3D) -> void:
	if cam == null:
		return
	var dir0: Vector3 = b.dir0
	var start: Vector3 = center + dir0 * radius * 0.18
	var end: Vector3 = b.end
	var axis: Vector3 = end - start
	var length: float = axis.length()
	if length < 0.05:
		return
	var fwd: Vector3 = axis / length
	var side_a: Vector3 = fwd.cross(Vector3.UP if absf(fwd.y) < 0.9 else Vector3.RIGHT).normalized()
	var side_b: Vector3 = fwd.cross(side_a)
	var jag: float = length * (0.11 if b.major else 0.14)
	var line := PackedVector3Array()
	for p in b.pts:
		var off: Vector2 = p[1] * jag
		line.append(start + axis * p[0] + side_a * off.x + side_b * off.y)
	var width: float = (0.6 if b.erupt else (0.26 if b.major else 0.12)) * clampf(radius / 3.0, 0.4, 1.4)
	var mi: MeshInstance3D = b.mi
	var im := mi.mesh as ImmediateMesh
	im.clear_surfaces()
	for pass_i in 2:
		var w := width * ((3.0 if b.erupt else 2.4) if pass_i == 0 else (0.45 if b.erupt else 0.7))
		if b.erupt:
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _erupt_glow_mat if pass_i == 0 else _erupt_core_mat)
		else:
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _glow_mat if pass_i == 0 else _core_mat)
		_ribbon(im, line, w, cam)
		for br in b.branches:
			var i0 := int(br[0] * (line.size() - 1))
			var from: Vector3 = line[i0]
			var dirb: Vector3 = (fwd + br[1]).normalized()
			var blen: float = length * br[2]
			var bl := PackedVector3Array([from])
			for k in range(1, 5):
				var t := k / 4.0
				bl.append(from + dirb * blen * t + (side_a * randf_range(-1, 1) + side_b * randf_range(-1, 1)) * jag * 0.5 * sin(t * PI))
			_ribbon(im, bl, w * 0.6, cam)
		im.surface_end()


## Camera-facing triangle ribbon along a polyline (u across the width).
func _ribbon(im: ImmediateMesh, line: PackedVector3Array, width: float, cam: Camera3D) -> void:
	var cp := cam.global_position
	for i in line.size() - 1:
		var a := line[i]
		var c := line[i + 1]
		var seg := c - a
		var side := seg.cross(cp - (a + c) * 0.5).normalized() * width * 0.5
		# Sample the streak texture's bright centre line across the width only.
		var a0 := a - side
		var a1 := a + side
		var c0 := c - side
		var c1 := c + side
		im.surface_set_uv(Vector2(0, 0.5)); im.surface_add_vertex(a0)
		im.surface_set_uv(Vector2(1, 0.5)); im.surface_add_vertex(a1)
		im.surface_set_uv(Vector2(1, 0.5)); im.surface_add_vertex(c1)
		im.surface_set_uv(Vector2(0, 0.5)); im.surface_add_vertex(a0)
		im.surface_set_uv(Vector2(1, 0.5)); im.surface_add_vertex(c1)
		im.surface_set_uv(Vector2(0, 0.5)); im.surface_add_vertex(c0)


## Bright flash + sparks where a bolt lands (+ purple light for big ones).
func _contact(at: Vector3, major: bool, erupt := false) -> void:
	var f := _flashes[_flash_next]
	_flash_next = (_flash_next + 1) % _flashes.size()
	_flash_age[_flashes.find(f)] = 0.0
	f.visible = true
	f.global_position = at
	f.set_meta("size", (1.6 if erupt else (1.1 if major else 0.55)) * clampf(radius / 3.0, 0.5, 1.3))
	f.set_meta("roll", randf() * TAU)
	(f.material_override as StandardMaterial3D).albedo_color = Color(ERUPT_COLOR if erupt else Vfx.HOT, 1.0)
	Vfx.face_camera(f, f.get_meta("size"), f.get_meta("roll"))
	if major or randf() < 0.5:
		var sp := _sparks[_spark_next]
		_spark_next = (_spark_next + 1) % _sparks.size()
		sp.global_position = at
		sp.restart()
		sp.emitting = true
	if major:
		_light.global_position = at + Vector3.UP * 0.3
		_light.light_color = ERUPT_COLOR if erupt else Vfx.PURPLE
		_light.omni_range = 7.0 if erupt else 5.0
		_light_t = 0.15
		_light.light_energy = 5.0


## Violent eruption of blue-violet lightning (before the supernova): an
## immediate salvo, then rapid thick bolts until stopped.
func erupt() -> void:
	if eruption > 0.0 or not active:
		return
	eruption = 1.0
	for i in 5:
		_strike(true, global_position, true)
	_contact(global_position, true, true)


func erupt_bolts_alive() -> int:
	var n := 0
	for b in _bolts:
		if b.erupt and b.life > 0.0:
			n += 1
	return n


func stop() -> void:
	active = false
