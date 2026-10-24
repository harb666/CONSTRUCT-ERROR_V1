class_name PlasmaVent
extends Node3D
## The pistol cannon's cooldown (owner asked: unlimited shots but "a quick
## cooldown so it's not continuous fire", "clearly visible but absolutely
## epic and magnificent"). Child of the PlasmaCannon, in its space (barrel
## along +X, muzzle at x 0.41):
##  - cell lights: a row of glowing pips floating over the gun, one per shot
##    left before it vents (`cells`), going dark as it fires;
##  - on venting: the gun flares white-hot orange with energy bands crawling
##    down the barrel (plasma_vent.gdshader overlay), plasma jets roar out of
##    both sides, a spray of sparks, and three segmented rings of light lock
##    round the barrel spinning against each other - the big one at the
##    muzzle fills up round the clock as the countdown;
##  - ready: the gun flashes cyan-white, the rings snap in and the muzzle
##    ring blasts outward, the cell lights flash back on.
## Its shaders are warmed up behind the title (Vfx.warm_up).

const OVERLAY := preload("res://scripts/vfx/plasma_vent.gdshader")
const RING := preload("res://scripts/vfx/vent_ring.gdshader")
const CYAN := Color(0.2, 0.85, 1.0)
const HOT := Color(1.0, 0.5, 0.15)
## Rings round the barrel: [x, radius, segments, turn rate (rev/s)].
const RINGS := [[0.16, 0.15, 10.0, 1.4], [0.29, 0.19, 14.0, -1.0], [0.47, 0.25, 16.0, 0.0]]

var cannon: PlasmaCannon
var _overlay: ShaderMaterial
var _meshes: Array[MeshInstance3D] = []
var _rings: Array[MeshInstance3D] = []
var _ring_mats: Array[ShaderMaterial] = []
var _pips: Array[MeshInstance3D] = []
var _pip_on: StandardMaterial3D
var _pip_off: StandardMaterial3D
var _jets: Array[CPUParticles3D] = []
var _sparks: CPUParticles3D
var _venting := false
## What the gun's meshes had as their overlay before (a hologram, say).
var _before := {}
## Seconds since the gun came back ready (the flare / ring blast).
var _ready_t := 99.0
var _turn := 0.0
static var _shared := {}


static func _mat(key: String, make: Callable) -> Material:
	if not _shared.has(key):
		_shared[key] = make.call()
	return _shared[key]


## Warm-up items (Vfx.warm_up).
static func warm_up_items() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for sh: Shader in [OVERLAY, RING]:
		var mi := MeshInstance3D.new()
		mi.mesh = QuadMesh.new()
		var m := ShaderMaterial.new()
		m.shader = sh
		mi.material_override = m
		out.append(mi)
	var v := PlasmaVent.new()
	out.append(v)
	return out


func _ready() -> void:
	cannon = get_parent() as PlasmaCannon
	_overlay = ShaderMaterial.new()
	_overlay.shader = OVERLAY
	_overlay.set_shader_parameter("color", CYAN)
	_overlay.set_shader_parameter("hot", HOT)
	if cannon:
		for mi: MeshInstance3D in cannon.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh is ArrayMesh:
				_meshes.append(mi)
	for spec: Array in RINGS:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE * spec[1] * 2.0
		mi.mesh = q
		var m := ShaderMaterial.new()
		m.shader = RING
		m.set_shader_parameter("color", CYAN)
		m.set_shader_parameter("hot", HOT)
		m.set_shader_parameter("segments", spec[2])
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(spec[0], -0.01, 0.0)
		mi.rotation.y = PI * 0.5  # facing down the barrel
		mi.visible = false
		add_child(mi)
		_rings.append(mi)
		_ring_mats.append(m)
	_pip_on = _mat("pip_on", func() -> Material: return _pip_material(CYAN.lerp(Color.WHITE, 0.3))) as StandardMaterial3D
	_pip_off = _mat("pip_off", func() -> Material: return _pip_material(Color(0.08, 0.22, 0.3))) as StandardMaterial3D
	var crystal := SphereMesh.new()  # 4 sides, 1 ring: a little crystal
	crystal.radial_segments = 4
	crystal.rings = 1
	crystal.radius = 0.024
	crystal.height = 0.07
	var n := cannon.cells if cannon else 6
	for i in n:
		var mi := MeshInstance3D.new()
		mi.mesh = crystal
		mi.material_override = _pip_on
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(lerpf(-0.26, 0.12, float(i) / maxf(n - 1, 1)), 0.15, 0.0)
		add_child(mi)
		_pips.append(mi)
	for side in [-1.0, 1.0]:
		var j := _jet(side)
		add_child(j)
		_jets.append(j)
	_sparks = _make_sparks()
	add_child(_sparks)
	set_process(true)


func _pip_material(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.disable_receive_shadows = true
	return m


func _jet(side: float) -> CPUParticles3D:
	var c := CPUParticles3D.new()
	c.name = "VentJet"
	c.amount = 22
	c.lifetime = 0.42
	c.local_coords = false
	c.emitting = false
	c.position = Vector3(-0.04, 0.02, 0.08 * side)
	c.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	c.emission_box_extents = Vector3(0.12, 0.02, 0.01)
	c.direction = Vector3(0.0, 0.55, side).normalized()
	c.spread = 16.0
	c.initial_velocity_min = 2.2
	c.initial_velocity_max = 4.0
	c.gravity = Vector3(0, 1.5, 0)
	c.damping_min = 3.0
	c.damping_max = 5.0
	c.scale_amount_min = 0.7
	c.scale_amount_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.35))
	sc.add_point(Vector2(1, 1.6))
	c.scale_amount_curve = sc
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.13
	q.material = _mat("jet", func() -> Material:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_texture = _puff_texture()
		m.disable_receive_shadows = true
		return m)
	c.mesh = q
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.65, 1.0])
	g.colors = PackedColorArray([Color(1, 0.95, 0.85), HOT.lerp(Color.WHITE, 0.2), CYAN, Color(0.6, 0.2, 1.0, 0.0)])
	c.color_ramp = g
	return c


static func _puff_texture() -> Texture2D:
	var t := GradientTexture2D.new()
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	t.gradient = g
	return t


func _make_sparks() -> CPUParticles3D:
	var c := CPUParticles3D.new()
	c.name = "VentSparks"
	c.amount = 18
	c.lifetime = 0.4
	c.one_shot = true
	c.explosiveness = 0.9
	c.local_coords = false
	c.emitting = false
	c.position = Vector3(0.1, 0.03, 0.0)
	c.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	c.emission_sphere_radius = 0.08
	c.direction = Vector3.UP
	c.spread = 75.0
	c.initial_velocity_min = 3.0
	c.initial_velocity_max = 6.5
	c.gravity = Vector3(0, -9.0, 0)
	c.particle_flag_align_y = true
	var b := BoxMesh.new()
	b.size = Vector3(0.012, 0.12, 0.012)
	b.material = _mat("spark", func() -> Material:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.vertex_color_use_as_albedo = true
		m.disable_receive_shadows = true
		return m)
	c.mesh = b
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 0.9), HOT, Color(CYAN, 0.0)])
	c.color_ramp = g
	return c


## The cannon overheated: everything on.
func start() -> void:
	_venting = true
	_ready_t = 99.0
	for mi in _meshes:
		if mi.material_overlay != _overlay:
			_before[mi] = mi.material_overlay
		mi.material_overlay = _overlay
	for r in _rings:
		r.visible = true
		r.scale = Vector3.ONE * 1.6
	for j in _jets:
		j.emitting = true
	_sparks.restart()
	_sparks.emitting = true


## Cooled down: the ready flare.
func finish() -> void:
	_venting = false
	_ready_t = 0.0
	for j in _jets:
		j.emitting = false


func _process(delta: float) -> void:
	if cannon == null:
		return
	_turn += delta
	# Cell lights: one per shot left (all off while venting, then on again).
	var left := 0 if cannon.venting else int(floor(cannon.charge + 0.001))
	for i in _pips.size():
		var on := i < left
		_pips[i].material_override = _pip_on if on else _pip_off
		var pop := 1.0 + 0.8 * maxf(1.0 - _ready_t / 0.25, 0.0)
		_pips[i].scale = Vector3.ONE * (pop if on else 0.75)
		_pips[i].rotation.y = _turn * 2.5 + i * 0.6  # turning
	if _venting:
		var p := cannon.vent_progress()
		var heat := 1.0 - p
		_overlay.set_shader_parameter("heat", heat)
		_overlay.set_shader_parameter("flash", 0.0)
		for i in _rings.size():
			var spec: Array = RINGS[i]
			# Lock on round the barrel (snapping in from wide), then hold.
			_rings[i].scale = _rings[i].scale.lerp(Vector3.ONE, 1.0 - exp(-14.0 * delta))
			var m := _ring_mats[i]
			m.set_shader_parameter("heat", heat * 0.8)
			m.set_shader_parameter("amount", 1.0 + 0.3 * sin(_turn * 22.0 + i))
			if i == _rings.size() - 1:
				m.set_shader_parameter("progress", p)
				m.set_shader_parameter("spin", 0.0)
			else:
				m.set_shader_parameter("progress", 1.0)
				m.set_shader_parameter("spin", _turn * float(spec[3]))
		for j in _jets:
			j.emitting = p < 0.7
		return
	if _ready_t < 1.0:
		_ready_t += delta
		var k := clampf(_ready_t / 0.3, 0.0, 1.0)
		_overlay.set_shader_parameter("heat", 0.0)
		_overlay.set_shader_parameter("flash", 1.0 - k)
		for i in _rings.size():
			var m := _ring_mats[i]
			m.set_shader_parameter("heat", 0.0)
			m.set_shader_parameter("progress", 1.0)
			if i == _rings.size() - 1:
				_rings[i].scale = Vector3.ONE * lerpf(1.0, 2.6, 1.0 - pow(1.0 - k, 2.0))  # blasts out
			else:
				_rings[i].scale = Vector3.ONE * lerpf(1.0, 0.2, k)  # snaps in
			m.set_shader_parameter("amount", (1.0 - k) * 1.6)
			_rings[i].visible = k < 1.0
		if k >= 1.0:
			for mi in _meshes:
				if mi.material_overlay == _overlay:
					mi.material_overlay = _before.get(mi)
			_before.clear()
			_ready_t = 99.0
