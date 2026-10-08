class_name MuzzleFlash
extends Node3D
## One-shot purple muzzle flash: two crossed flame quads along the barrel
## (+X of the parent marker), a bright star pop and a brief light.

@export var duration := 0.14
@export var length := 0.9

var _t := 0.0
var _flames: Array[MeshInstance3D] = []
var _star: MeshInstance3D
var _light: OmniLight3D


static func spawn(at: Node3D) -> MuzzleFlash:
	var f := MuzzleFlash.new()
	at.add_child(f)
	return f


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for k in 2:
		var q := Vfx.quad("muzzle", Vfx.PINK, Vector2(length * 0.55, length))
		# Flame points up the texture (+Y); lay it along the barrel (+X).
		q.rotation = Vector3(k * PI * 0.5, 0, -PI * 0.5)
		q.position.x = length * 0.45
		add_child(q)
		_flames.append(q)
	_star = Vfx.quad("star", Vfx.HOT, Vector2.ONE * 0.8)
	add_child(_star)
	_light = OmniLight3D.new()
	_light.light_color = Vfx.PURPLE
	_light.omni_range = 4.0
	_light.light_energy = 3.0
	_light.shadow_enabled = false
	add_child(_light)
	Vfx.tame_light(_light)
	_update()


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	_update()


func _update() -> void:
	var k := _t / duration
	var fade := 1.0 - k
	for q in _flames:
		q.scale = Vector3(0.7 + k * 0.6, 0.7 + k * 0.6, 1.0)
		Vfx.set_alpha(q, fade)
	Vfx.face_camera(_star, 0.6 + k * 0.8, k * 2.0)
	Vfx.set_alpha(_star, fade)
	_light.light_energy = 3.0 * fade
