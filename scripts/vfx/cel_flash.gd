class_name CelFlash
extends Node3D
## Extra cartoon muzzle flash layered OVER a weapon's own flash (which is
## left as it is) for a brighter, more dramatic shot - cel_flash.gdshader
## (VFEZ-style: posterized white-hot / hot / colour / ink bands, a hand-drawn
## boil, and it shatters into burning blobs as it dies). Per shot: a spiky
## star burst facing the camera, crossed flame cones shooting down the
## barrel, thin spark streaks fanning out, and a bright soft glow. Child of
## the weapon, so it follows the gun; one per weapon, re-fired every shot
## (fresh random shape each time). Built once; no allocations while firing.

const SHADER := preload("res://scripts/vfx/cel_flash.gdshader")

## Size of the star (m); the cones are `cone_length` x size long.
@export var size := 0.9
@export var cone_length := 1.9
@export var cones := 3
@export var sparks := 6
@export var duration := 0.12
## Soft additive glow behind it (x size; 0 = none) and its strength.
@export var glow_size := 2.2
@export var glow_strength := 0.9

var flashes := 0
var _t := 99.0
var _strength := 1.0
var _star: MeshInstance3D
var _cones: Array[MeshInstance3D] = []
var _sparks: Array[MeshInstance3D] = []
var _spark_dir: Array[Vector3] = []
var _glow: MeshInstance3D
var _mats: Array[ShaderMaterial] = []


## `base` = the weapon's colour; the palette is built from it (white-hot
## centre, hot, base, dark ink rim).
func setup(base: Color, hot: Color) -> CelFlash:
	var cols := [Color(1, 1, 0.95), hot.lerp(Color.WHITE, 0.25), base, base.darkened(0.62)]
	_star = _part(0, cols, 10.0)
	for i in cones:
		_cones.append(_part(1, cols, 0.0))
	for i in sparks:
		_sparks.append(_part(1, cols, 0.0))
		_spark_dir.append(Vector3.RIGHT)
	if glow_size > 0.0:
		_glow = Vfx.quad("glow", hot.lerp(Color.WHITE, 0.4), Vector2.ONE)
		_glow.top_level = true
		add_child(_glow)
	_hide()
	set_process(false)
	return self


func _part(shape: int, cols: Array, spikes: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = QuadMesh.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("shape", shape)
	if spikes > 0.0:
		m.set_shader_parameter("spikes", spikes)
	m.set_shader_parameter("hot", cols[0])
	m.set_shader_parameter("mid", cols[1])
	m.set_shader_parameter("outer", cols[2])
	m.set_shader_parameter("ink", cols[3])
	m.set_shader_parameter("burn", cols[1])
	mi.material_override = m
	mi.top_level = true
	add_child(mi)
	_mats.append(m)
	return mi


## Fire at world point `at`, shooting along world direction `dir`.
func fire(at: Vector3, dir: Vector3, strength := 1.0) -> void:
	if _star == null:
		return
	global_position = at
	_dir = dir.normalized() if dir.length_squared() > 1e-6 else Vector3.FORWARD
	_strength = strength
	_t = 0.0
	_roll = randf() * TAU
	for m in _mats:
		m.set_shader_parameter("seed", randf() * 100.0)
	# Sparks fan out in a cone round the barrel, random each shot.
	var side := _dir.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = _dir.cross(Vector3.RIGHT)
	side = side.normalized()
	for i in _spark_dir.size():
		var a := deg_to_rad(randf_range(18.0, 55.0))
		var spin := TAU * (i + randf_range(-0.3, 0.3)) / _spark_dir.size()
		_spark_dir[i] = _dir.rotated(side, a).rotated(_dir, spin).normalized()
	flashes += 1
	set_process(true)
	_update()


var _dir := Vector3.FORWARD
var _roll := 0.0


func is_flashing() -> bool:
	return _t < duration


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		_hide()
		set_process(false)
		return
	_update()


func _hide() -> void:
	for n in [_star, _glow] + _cones + _sparks:
		if n:
			n.visible = false


func _update() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var k := clampf(_t / duration, 0.0, 1.0)
	var pop := 1.0 - pow(1.0 - clampf(k * 3.0, 0.0, 1.0), 3.0)
	var s := size * _strength * (0.55 + 0.55 * pop)
	var at := global_position
	for m in _mats:
		m.set_shader_parameter("progress", k)
	# Star: camera-facing, at the muzzle.
	_star.visible = true
	_star.global_position = at + _dir * s * 0.15
	Vfx.face_camera(_star, s * 1.3, _roll)
	# Cones: crossed planes along the barrel, each turned to the camera's
	# side so their width shows.
	var view := (cam.global_position - at).normalized()
	for i in _cones.size():
		var c := _cones[i]
		var ang := _roll + PI * i / maxf(_cones.size(), 1)
		var x := _dir.cross(view).normalized().rotated(_dir, ang * 0.35)
		var l := s * cone_length * (1.0 if i == 0 else 0.8)
		c.visible = true
		c.global_transform = Transform3D(Basis(x * l * 0.36, _dir * l, x.cross(_dir).normalized()), at + _dir * l * 0.5)
	for i in _sparks.size():
		var sp := _sparks[i]
		var d := _spark_dir[i]
		var l := s * 0.95
		var x := d.cross(view).normalized()
		sp.visible = true
		sp.global_transform = Transform3D(Basis(x * l * 0.12, d * l, x.cross(d).normalized()), at + d * (s * 0.4 + l * 0.5))
	if _glow:
		_glow.visible = true
		_glow.global_position = at + _dir * s * 0.3
		Vfx.face_camera(_glow, s * glow_size * (0.8 + 0.4 * pop))
		Vfx.set_alpha(_glow, glow_strength * (1.0 - k) * (1.0 - k))
