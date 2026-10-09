class_name RocketMuzzleFlash
extends Node3D
## The Rocket Launcher's muzzle flash: two crossed flame jets along the
## barrel and a fireball at the mouth, drawn as solid fire (FLASH_SHADER,
## alpha-blended) so they show clearly against the bright arena too, plus a
## white-hot star and a brief light. Placed at the muzzle each shot, +Z out
## of the barrel; shown for at least two frames. The smoke is LauncherBlast.

const FLASH_SHADER := preload("res://scripts/vfx/flash_mix.gdshader")

@export var duration := 0.12
## Flame jet length (m).
@export var length := 1.3

var _t := 99.0
var _frames := 0
var _jets: Array[MeshInstance3D] = []
var _ball: MeshInstance3D
var _star: MeshInstance3D
var _light: OmniLight3D
var shown := 0


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for k in 2:
		var j := _solid("flame_a", Color(1.0, 0.5, 0.1), Vector2(length * 0.7, length))
		# The flame points up its texture (+Y): lay it along +Z, crossed.
		var x := Vector3.RIGHT if k == 0 else Vector3.UP
		j.transform = Transform3D(Basis(x, Vector3.BACK, x.cross(Vector3.BACK)), Vector3(0, 0, length * 0.45))
		add_child(j)
		_jets.append(j)
	_ball = _solid("fireball", Color(1.0, 0.62, 0.18), Vector2.ONE)
	add_child(_ball)
	_star = Vfx.quad("star", Color(1.0, 0.95, 0.75), Vector2.ONE)
	add_child(_star)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.65, 0.3)
	_light.omni_range = 6.0
	_light.shadow_enabled = false
	add_child(_light)
	Vfx.tame_light(_light)
	visible = false
	set_process(false)


func _solid(tex: String, col: Color, size: Vector2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	var m := ShaderMaterial.new()
	m.shader = FLASH_SHADER
	m.set_shader_parameter("tex", Vfx.TEX[tex])
	m.set_shader_parameter("color", col)
	q.material = m
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func fire(mouth: Transform3D) -> void:
	global_transform = Transform3D(mouth.basis.orthonormalized(), mouth.origin)
	_t = 0.0
	_frames = 0
	shown += 1
	visible = true
	set_process(true)
	_update()


func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	if _t >= duration and _frames >= 2:
		visible = false
		set_process(false)
		return
	_update()


func _update() -> void:
	# Full strength for the first two frames however long they take (slow
	# phones), then it fades out.
	var k := clampf(_t / duration, 0.0, 1.0) if _frames >= 2 else 0.0
	var a := 1.0 - k * k
	var roll := randf() * TAU
	for j in _jets:
		j.scale = Vector3(randf_range(0.85, 1.15), (0.8 + 0.4 * k) * randf_range(0.9, 1.1), 1.0)
		(j.mesh.surface_get_material(0) as ShaderMaterial).set_shader_parameter("fade", a)
	Vfx.face_camera(_ball, 0.95 + 0.6 * k, roll)
	_ball.position = Vector3(0, 0, 0.15 + 0.2 * k)
	(_ball.mesh.surface_get_material(0) as ShaderMaterial).set_shader_parameter("fade", a)
	Vfx.face_camera(_star, 0.9 * (1.0 - k * 0.5), roll)
	_light.light_energy = 6.0 * a
