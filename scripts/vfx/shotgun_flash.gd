class_name ShotgunFlash
extends Node3D
## Flaming muzzle flash for the five-barrel shotgun, owned by the gun (child
## of its root; +X = firing direction) and restarted on every shot: a flame
## tongue out of each barrel, a white-hot fireball across the cluster, an
## orange glow, a spray of sparks, a little smoke and a brief orange light.
## Strong but very short. Built once; no allocations while firing.

const ORANGE := Color(1.0, 0.45, 0.06)
const YELLOW := Color(1.0, 0.78, 0.25)
const WHITE_HOT := Color(1.0, 0.95, 0.8)

## Barrel muzzle positions (local to the gun).
var barrels: Array[Vector3] = []
@export var duration := 0.085
@export var flame_length := 0.55
@export var light_energy := 5.0

var intensity := 1.0
var _t := 99.0
var _centre := Vector3.ZERO
var _flames: Array[MeshInstance3D] = []
var _fireball: MeshInstance3D
var _glow: MeshInstance3D
var _sparks: CPUParticles3D
var _smoke: CPUParticles3D
var _light: OmniLight3D


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for b in barrels:
		_centre += b
	_centre /= maxf(barrels.size(), 1)
	for b in barrels:
		for k in 2:
			var q := Vfx.quad("muzzle", ORANGE if k == 0 else YELLOW, Vector2.ONE)
			q.visible = false
			add_child(q)
			_flames.append(q)
	_glow = Vfx.quad("glow", ORANGE, Vector2.ONE)
	_glow.top_level = true
	_glow.visible = false
	add_child(_glow)
	_fireball = Vfx.quad("star", WHITE_HOT, Vector2.ONE)
	_fireball.top_level = true
	_fireball.visible = false
	add_child(_fireball)

	_sparks = Vfx.particles("glow", 0.05, 28, 0.35)
	_sparks.one_shot = true
	_sparks.explosiveness = 0.95
	_sparks.emitting = false
	_sparks.local_coords = false
	_sparks.direction = Vector3.RIGHT
	_sparks.spread = 28.0
	_sparks.initial_velocity_min = 5.0
	_sparks.initial_velocity_max = 15.0
	_sparks.damping_min = 6.0
	_sparks.damping_max = 10.0
	_sparks.gravity = Vector3(0, -6.0, 0)
	_sparks.scale_amount_min = 0.6
	_sparks.scale_amount_max = 1.4
	_sparks.color_ramp = Vfx.ramp([Color(1, 0.95, 0.7, 1), Color(1, 0.55, 0.1, 1), Color(0.8, 0.15, 0.0, 0)], [0.0, 0.4, 1.0])
	_sparks.position = _centre
	add_child(_sparks)

	_smoke = CPUParticles3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2.ONE * 0.35
	sq.material = Vfx.mix_material("smoke")
	_smoke.mesh = sq
	_smoke.amount = 5
	_smoke.lifetime = 0.7
	_smoke.one_shot = true
	_smoke.explosiveness = 0.9
	_smoke.emitting = false
	_smoke.local_coords = false
	_smoke.direction = Vector3.RIGHT
	_smoke.spread = 25.0
	_smoke.initial_velocity_min = 0.8
	_smoke.initial_velocity_max = 2.0
	_smoke.damping_min = 2.0
	_smoke.damping_max = 3.0
	_smoke.gravity = Vector3(0, 0.6, 0)
	_smoke.scale_amount_min = 0.8
	_smoke.scale_amount_max = 1.6
	_smoke.scale_amount_curve = Vfx.curve([Vector2(0, 0.6), Vector2(1, 1.8)])
	_smoke.color_ramp = Vfx.ramp([Color(0.35, 0.3, 0.27, 0.0), Color(0.3, 0.27, 0.25, 0.32), Color(0.25, 0.24, 0.23, 0.0)], [0.0, 0.2, 1.0])
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke.position = _centre + Vector3(0.15, 0, 0)
	add_child(_smoke)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.omni_range = 5.0
	_light.shadow_enabled = false
	_light.light_energy = 0.0
	_light.visible = false
	_light.position = _centre + Vector3(0.2, 0, 0)
	add_child(_light)
	set_process(false)


## Fire the flash (`strength` scales size and brightness; 1 = default).
func play(strength := 1.0) -> void:
	intensity = maxf(strength, 0.0)
	_t = 0.0
	for q in _flames:
		q.visible = true
	_glow.visible = true
	_fireball.visible = true
	_light.visible = true
	_sparks.amount = maxi(int(28 * clampf(intensity, 0.3, 2.0)), 4)
	_sparks.restart()
	_sparks.emitting = true
	_smoke.restart()
	_smoke.emitting = true
	set_process(true)
	_process(0.0)


func is_flashing() -> bool:
	return _t < duration


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		for q in _flames:
			q.visible = false
		_glow.visible = false
		_fireball.visible = false
		_light.visible = false
		_light.light_energy = 0.0
		set_process(false)
		return
	var k := _t / duration
	var fade := 1.0 - k
	var flicker := randf_range(0.85, 1.15)
	var len := flame_length * intensity * (0.75 + 0.5 * k) * flicker
	for i in barrels.size():
		for j in 2:
			var q := _flames[i * 2 + j]
			# Flame points up its texture (+Y): lay it along the barrel (+X),
			# two crossed planes per barrel, rolled a little for variety.
			var w := len * (0.42 if j == 0 else 0.3)
			var l := len * (1.0 if j == 0 else 0.7)
			var b := Basis(Vector3(1, 0, 0), j * PI * 0.5 + i * 0.6) * Basis(Vector3(0, 0, 1), -PI * 0.5)
			q.transform = Transform3D(b.scaled(Vector3(w, l, 1.0)), barrels[i] + Vector3(l * 0.45, 0, 0))
			Vfx.set_alpha(q, fade * (1.0 if j == 0 else 0.9))
	var c := to_global(_centre + Vector3(0.12 * intensity, 0, 0))
	_fireball.global_position = c
	Vfx.face_camera(_fireball, 0.75 * intensity * (1.0 - 0.3 * k), _t * 9.0)
	Vfx.set_alpha(_fireball, fade)
	_glow.global_position = c
	Vfx.face_camera(_glow, 1.5 * intensity * (0.8 + 0.4 * k))
	Vfx.set_alpha(_glow, 0.8 * fade)
	_light.light_energy = light_energy * intensity * fade
