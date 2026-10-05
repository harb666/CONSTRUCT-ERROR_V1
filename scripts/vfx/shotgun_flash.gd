class_name ShotgunFlash
extends Node3D
## Flaming muzzle flash for the five-barrel shotgun, owned by the gun (child
## of its root; +X = firing direction) and restarted on every shot:
##  - a long flame tongue out of every barrel (three layered flame sprites,
##    crossed so they read from any angle),
##  - a rolling fireball and a white-hot flare across the barrel cluster,
##    with a wide orange glow,
##  - flame licks that keep burning and curl away for a moment afterwards,
##  - a spray of sparks, a little smoke and a bright orange light.
## Strong and short (the core flash ~0.11 s, licks ~0.4 s). Built once; no
## allocations while firing.

const ORANGE := Color(1.0, 0.42, 0.05)
const YELLOW := Color(1.0, 0.72, 0.2)
const WHITE_HOT := Color(1.0, 0.95, 0.8)

## Barrel muzzle positions (local to the gun).
var barrels: Array[Vector3] = []
@export var duration := 0.11
@export var flame_length := 0.95
@export var light_energy := 9.0
@export var light_range := 7.0

var intensity := 1.0
var _t := 99.0
var _centre := Vector3.ZERO
## Per barrel: [outer A, outer B (crossed), hot core]
var _flames: Array = []
var _fireball: MeshInstance3D
var _flare: MeshInstance3D
var _glow: MeshInstance3D
var _licks: CPUParticles3D
var _sparks: CPUParticles3D
var _smoke: CPUParticles3D
var _light: OmniLight3D
var _roll := 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for b in barrels:
		_centre += b
	_centre /= maxf(barrels.size(), 1)
	for i in barrels.size():
		var layers: Array = []
		layers.append(Vfx.quad("flame_a" if i % 2 == 0 else "flame_b", ORANGE, Vector2.ONE))
		layers.append(Vfx.quad("flame_b" if i % 2 == 0 else "flame_a", ORANGE, Vector2.ONE))
		layers.append(Vfx.quad("flame_c", YELLOW, Vector2.ONE))
		for q: MeshInstance3D in layers:
			q.visible = false
			add_child(q)
		_flames.append(layers)
	_glow = Vfx.quad("glow", ORANGE, Vector2.ONE)
	_glow.top_level = true
	_glow.visible = false
	add_child(_glow)
	_fireball = Vfx.quad("fireball", YELLOW, Vector2.ONE)
	_fireball.top_level = true
	_fireball.visible = false
	add_child(_fireball)
	_flare = Vfx.quad("flare", WHITE_HOT, Vector2.ONE)
	_flare.top_level = true
	_flare.visible = false
	add_child(_flare)

	# Flame licks: burning wisps thrown forward that curl up and die out.
	_licks = CPUParticles3D.new()
	var lq := QuadMesh.new()
	lq.size = Vector2.ONE * 0.5
	lq.material = Vfx.material("lick_a", Color.WHITE, BaseMaterial3D.BILLBOARD_PARTICLES, true)
	_licks.mesh = lq
	_licks.amount = 14
	_licks.lifetime = 0.42
	_licks.one_shot = true
	_licks.explosiveness = 0.85
	_licks.emitting = false
	_licks.local_coords = false
	_licks.direction = Vector3.RIGHT
	_licks.spread = 22.0
	_licks.initial_velocity_min = 2.5
	_licks.initial_velocity_max = 6.5
	_licks.damping_min = 5.0
	_licks.damping_max = 9.0
	_licks.gravity = Vector3(0, 2.2, 0)
	_licks.angle_min = -180.0
	_licks.angle_max = 180.0
	_licks.angular_velocity_min = -220.0
	_licks.angular_velocity_max = 220.0
	_licks.scale_amount_min = 0.6
	_licks.scale_amount_max = 1.3
	_licks.scale_amount_curve = Vfx.curve([Vector2(0, 0.5), Vector2(0.35, 1.2), Vector2(1, 1.6)])
	_licks.color_ramp = Vfx.ramp([Color(1, 0.95, 0.7, 1), Color(1, 0.6, 0.12, 0.95), Color(0.9, 0.22, 0.02, 0.6), Color(0.4, 0.05, 0.0, 0)], [0.0, 0.25, 0.6, 1.0])
	_licks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_licks.position = _centre + Vector3(0.12, 0, 0)
	add_child(_licks)

	_sparks = Vfx.particles("glow", 0.05, 44, 0.4)
	_sparks.one_shot = true
	_sparks.explosiveness = 0.95
	_sparks.emitting = false
	_sparks.local_coords = false
	_sparks.direction = Vector3.RIGHT
	_sparks.spread = 30.0
	_sparks.initial_velocity_min = 7.0
	_sparks.initial_velocity_max = 20.0
	_sparks.damping_min = 6.0
	_sparks.damping_max = 10.0
	_sparks.gravity = Vector3(0, -7.0, 0)
	_sparks.scale_amount_min = 0.6
	_sparks.scale_amount_max = 1.6
	_sparks.color_ramp = Vfx.ramp([Color(1, 0.95, 0.7, 1), Color(1, 0.55, 0.1, 1), Color(0.8, 0.15, 0.0, 0)], [0.0, 0.4, 1.0])
	_sparks.position = _centre
	add_child(_sparks)

	_smoke = CPUParticles3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2.ONE * 0.4
	sq.material = Vfx.mix_material("smoke")
	_smoke.mesh = sq
	_smoke.amount = 6
	_smoke.lifetime = 0.8
	_smoke.one_shot = true
	_smoke.explosiveness = 0.8
	_smoke.emitting = false
	_smoke.local_coords = false
	_smoke.direction = Vector3.RIGHT
	_smoke.spread = 25.0
	_smoke.initial_velocity_min = 0.8
	_smoke.initial_velocity_max = 2.2
	_smoke.damping_min = 2.0
	_smoke.damping_max = 3.0
	_smoke.gravity = Vector3(0, 0.7, 0)
	_smoke.scale_amount_min = 0.8
	_smoke.scale_amount_max = 1.6
	_smoke.scale_amount_curve = Vfx.curve([Vector2(0, 0.6), Vector2(1, 2.0)])
	_smoke.color_ramp = Vfx.ramp([Color(0.35, 0.3, 0.27, 0.0), Color(0.3, 0.27, 0.25, 0.35), Color(0.25, 0.24, 0.23, 0.0)], [0.0, 0.2, 1.0])
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke.position = _centre + Vector3(0.2, 0, 0)
	add_child(_smoke)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.omni_range = light_range
	_light.shadow_enabled = false
	_light.light_energy = 0.0
	_light.visible = false
	_light.position = _centre + Vector3(0.3, 0, 0)
	add_child(_light)
	set_process(false)


## Fire the flash (`strength` scales size and brightness; 1 = default).
func play(strength := 1.0) -> void:
	intensity = maxf(strength, 0.0)
	_t = 0.0
	_roll = randf() * TAU
	for layers: Array in _flames:
		for q: MeshInstance3D in layers:
			q.visible = true
	_glow.visible = true
	_fireball.visible = true
	_flare.visible = true
	_light.visible = true
	_light.omni_range = light_range * clampf(intensity, 0.5, 2.0)
	_sparks.amount = maxi(int(44 * clampf(intensity, 0.3, 2.0)), 4)
	for p: CPUParticles3D in [_sparks, _licks, _smoke]:
		p.restart()
		p.emitting = true
	set_process(true)
	_process(0.0)


func is_flashing() -> bool:
	return _t < duration


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		for layers: Array in _flames:
			for q: MeshInstance3D in layers:
				q.visible = false
		_glow.visible = false
		_fireball.visible = false
		_flare.visible = false
		_light.visible = false
		_light.light_energy = 0.0
		set_process(false)
		return
	var k := _t / duration
	var fade := 1.0 - k
	var punch := 1.0 - (1.0 - minf(k * 4.0, 1.0)) ** 2  # shoots out fast
	for i in barrels.size():
		var layers: Array = _flames[i]
		var flicker := randf_range(0.85, 1.15)
		var len := flame_length * intensity * (0.55 + 0.6 * punch) * flicker
		for j in 3:
			var q: MeshInstance3D = layers[j]
			# Flame sprites point up their texture (+Y): lay them along the
			# barrel (+X); two crossed outer planes and a hot inner core.
			var l := len * (1.0 if j < 2 else 0.6)
			var w := len * (0.5 if j < 2 else 0.32)
			var roll := (PI * 0.5 if j == 1 else 0.0) + i * 0.63 + _roll
			var b := Basis(Vector3(1, 0, 0), roll) * Basis(Vector3(0, 0, 1), -PI * 0.5)
			q.transform = Transform3D(b.scaled(Vector3(w, l, 1.0)), barrels[i] + Vector3(l * 0.46, 0, 0))
			Vfx.set_alpha(q, fade * (0.95 if j < 2 else 1.0))
	var c := to_global(_centre + Vector3(0.18 * intensity, 0, 0))
	_fireball.global_position = c
	Vfx.face_camera(_fireball, 0.9 * intensity * (0.7 + 0.6 * k), _roll + _t * 6.0)
	Vfx.set_alpha(_fireball, fade)
	_flare.global_position = c
	Vfx.face_camera(_flare, 1.5 * intensity * (1.0 - 0.6 * k), _roll * 0.5)
	Vfx.set_alpha(_flare, fade * fade)
	_glow.global_position = c
	Vfx.face_camera(_glow, 2.3 * intensity * (0.8 + 0.4 * k))
	Vfx.set_alpha(_glow, 0.85 * fade)
	_light.light_energy = light_energy * intensity * fade
