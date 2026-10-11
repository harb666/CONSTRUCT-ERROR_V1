class_name ToxicSlime
extends Node3D
## A puddle of burning toxic slime from an exploded ToxicBarrel (owner
## asked: "green flaming slime"): a glossy bubbling puddle on the surface
## (toxic_slime.gdshader) that splashes out, green cartoon flames licking up
## off it and flickering, green embers drifting up and a green glow. It
## burns for `burn_time`, the flames die down, the slime darkens to a
## residue and fades. Standing in it burns: players and robots inside it
## take `player_burn` / `robot_burn` damage every `tick` seconds.

const SHADER := preload("res://scripts/vfx/toxic_slime.gdshader")
const FIRE := preload("res://scripts/vfx/toxic_fire.gdshader")
const GREEN := Color(0.35, 1.0, 0.1)
const HOT := Color(0.9, 1.0, 0.65)
const DARK := Color(0.03, 0.25, 0.04)

@export var burn_time := 12.0
@export var die_time := 2.5
@export var fade_time := 3.0
## Per tick; players' x5 `incoming_damage_scale` makes it 4 health.
@export var player_burn := 0.8
@export var robot_burn := 0.3
@export var tick := 1.0

static var active := 0
static var spawned := 0

var radius := 1.5
var source: Node
var burns := 0
var _t := 0.0
var _delay := 0.0
var _tick_t := 0.0
var _normal := Vector3.UP
var _decal: MeshInstance3D
var _mat: ShaderMaterial
var _flames: Array[MeshInstance3D] = []
var _flame_off: Array[Vector3] = []
var _flame_h: Array[float] = []
var _flame_w: Array[float] = []
var _flame_mats: Array[ShaderMaterial] = []
var _embers: CPUParticles3D
var _light: OmniLight3D


## A puddle `r` metres across-radius at `at` (on a surface facing `normal`),
## appearing after `delay` seconds (the slime's flight).
static func spawn(parent: Node, at: Vector3, normal: Vector3, r: float, delay := 0.0, from: Node = null) -> ToxicSlime:
	var s := ToxicSlime.new()
	s.radius = r
	s._delay = delay
	s._normal = normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	s.source = from
	parent.add_child(s)
	s.global_position = at
	spawned += 1
	return s


func _ready() -> void:
	top_level = true
	active += 1
	var up := _normal
	var x := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var basis := Basis(x, up, x.cross(up)).rotated(up, randf() * TAU)
	_decal = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2.ONE * radius * 2.0
	_decal.mesh = q
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("seed", randf() * 40.0)
	_mat.set_shader_parameter("grow", 0.0)
	_decal.material_override = _mat
	_decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_decal)
	_decal.transform = Transform3D(basis, up * 0.03)
	# Flames (toxic_fire.gdshader): a big one in the middle and a few round
	# it on the big puddle, one or two on the splashes.
	var n := 1 + clampi(int(radius * 1.5), 0, 3)
	var a0 := randf() * TAU
	for i in n:
		var t := MeshInstance3D.new()
		t.mesh = QuadMesh.new()
		var fm := ShaderMaterial.new()
		fm.shader = FIRE
		fm.set_shader_parameter("seed", randf() * 50.0)
		fm.set_shader_parameter("speed", randf_range(0.85, 1.2))
		t.material_override = fm
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.top_level = true
		add_child(t)
		_flames.append(t)
		_flame_mats.append(fm)
		var a := a0 + TAU * (i + randf_range(-0.25, 0.25)) / n
		var d := radius * randf_range(0.3, 0.55) if i > 0 else 0.0
		_flame_off.append(Vector3(cos(a), 0.0, sin(a)) * d)
		var h := (radius * 0.85 + 0.3) * (1.0 if i == 0 else randf_range(0.5, 0.72))
		_flame_h.append(h)
		_flame_w.append(h * randf_range(0.55, 0.68))
	_embers = Vfx.particles("glow", 0.08, clampi(int(radius * 8.0), 4, 16), 1.1)
	_embers.local_coords = false
	_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_embers.emission_sphere_radius = radius * 0.6
	_embers.direction = Vector3.UP
	_embers.spread = 25.0
	_embers.initial_velocity_min = 0.8
	_embers.initial_velocity_max = 2.2
	_embers.gravity = Vector3(0, 0.6, 0)
	_embers.color_ramp = Vfx.ramp([Color(0.9, 1.0, 0.6, 1), Color(0.4, 1.0, 0.1, 0.9), Color(0.1, 0.5, 0.05, 0.0)], [0.0, 0.4, 1.0])
	_embers.emitting = false
	add_child(_embers)
	_embers.position = up * 0.2
	_light = OmniLight3D.new()
	_light.light_color = Color(0.45, 1.0, 0.2)
	_light.omni_range = radius * 3.0 + 1.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)
	_light.position = up * 0.6
	Vfx.tame_light(_light)
	visible = false
	_update()


func _exit_tree() -> void:
	active = maxi(active - 1, 0)


func _process(delta: float) -> void:
	if _delay > 0.0:
		_delay -= delta
		return
	if not visible:
		visible = true
		_embers.emitting = true
	_t += delta
	if _t >= burn_time + die_time + fade_time:
		queue_free()
		return
	_update()
	_tick_t -= delta
	if _t < burn_time + die_time * 0.5 and _tick_t <= 0.0:
		_tick_t = tick
		_burn_things()


func burn_amount() -> float:
	return 1.0 - clampf((_t - burn_time) / die_time, 0.0, 1.0)


func _update() -> void:
	var grow := 1.0 - pow(1.0 - clampf(_t / 0.18, 0.0, 1.0), 3.0)
	var burn := burn_amount()
	var fade := 1.0 - clampf((_t - burn_time - die_time) / fade_time, 0.0, 1.0)
	_mat.set_shader_parameter("grow", maxf(grow, 0.05))
	_mat.set_shader_parameter("burn", burn)
	_mat.set_shader_parameter("fade", fade)
	_embers.emitting = visible and burn > 0.3
	var flick := 0.8 + 0.2 * sin(_t * 23.0) * sin(_t * 9.0 + 1.3)
	if not Vfx.effect_lights:
		_light.light_energy = 0.0
	else:
		_light.light_energy = 2.2 * burn * grow * flick
	# Flames: roar up as it lands, flicker, then die down with the burn
	# (the shader licks and sways them; here: size, facing the camera).
	var cam := get_viewport().get_camera_3d()
	var roar := 1.0 + 0.35 * (1.0 - clampf(_t / 0.6, 0.0, 1.0))
	for i in _flames.size():
		var f := _flames[i]
		var k := grow * roar * (0.35 + 0.65 * burn) * (0.93 + 0.07 * sin(_t * (9.0 + i * 1.7) + i * 2.3))
		var h := _flame_h[i] * k
		f.visible = visible and burn > 0.02
		if not f.visible:
			continue
		_flame_mats[i].set_shader_parameter("burn", burn)
		var base := global_position + _flame_off[i] * grow
		var y := Vector3.UP
		var mid := base + y * h * 0.46
		var view := cam.global_position - mid if cam else Vector3.BACK
		view.y = 0.0
		var x := y.cross(view.normalized() if view.length_squared() > 1e-4 else Vector3.BACK).normalized()
		f.global_transform = Transform3D(Basis(x * _flame_w[i] * k, y * h, x.cross(y)), mid)


## Anyone standing in it burns.
func _burn_things() -> void:
	var at := global_position
	for p in get_tree().get_nodes_in_group(&"players"):
		var pc := p as Node3D
		if pc and _inside(pc.global_position, at) and pc.has_method("apply_damage"):
			var info := DamageInfo.make(player_burn, DamageInfo.Type.ENERGY, pc.global_position + Vector3.UP, Vector3.UP, 0.0, 0.0, self)
			info.weapon = &"toxic_slime"
			pc.apply_damage(info)
			burns += 1
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var r := e as Node3D
		if r == null or not r.get(&"alive") or not _inside(r.global_position, at):
			continue
		var info := DamageInfo.make(robot_burn, DamageInfo.Type.ENERGY, r.global_position + Vector3.UP, Vector3.UP, 0.0, 0.0, self)
		info.weapon = &"toxic_slime"
		r.call(&"apply_damage", info)
		burns += 1


func _inside(p: Vector3, at: Vector3) -> bool:
	return Vector2(p.x - at.x, p.z - at.z).length() < radius * 0.85 and absf(p.y - at.y) < 1.2
