class_name SonicBoom
extends Node3D
## The glide melee's sonic boom (owner asked: "faster and dramatic, almost
## sonic like"), pooled: as the player launches - and again, smaller, as
## they arrive - two shock rings race out round them across the line of
## flight (white-hot core, cyan / magenta torn edge), a vapor cone flares
## out behind, and a white flash pops. `spawn(tree, at, dir, size)`.

const SHADER := preload("res://scripts/vfx/sonic_ring.gdshader")
const POOL_SIZE := 3

@export var duration := 0.32

static var _pool: Array[SonicBoom] = []
static var spawned := 0

var active := false
var size := 1.0
var _t := 99.0
var _rings: Array[MeshInstance3D] = []
var _ring_mats: Array[ShaderMaterial] = []
var _cone: MeshInstance3D
var _cone_mat: ShaderMaterial
var _flash: MeshInstance3D
var _flash_mat: ShaderMaterial


static func spawn(tree: SceneTree, at: Vector3, dir: Vector3, boom_size := 1.0) -> SonicBoom:
	_pool = _pool.filter(func(s) -> bool: return is_instance_valid(s) and s.is_inside_tree())
	var b: SonicBoom = null
	for s in _pool:
		if not s.active:
			b = s
			break
	if b == null:
		if _pool.size() < POOL_SIZE:
			b = SonicBoom.new()
			var host: Node = tree.current_scene if tree.current_scene else tree.root
			host.add_child(b)
			_pool.append(b)
		else:
			b = _pool[0]
	b._start(at, dir, boom_size)
	spawned += 1
	return b


## Warm-up items (Vfx.warm_up): one of each piece.
static func warm_up_items() -> Array[Node3D]:
	var b := SonicBoom.new()
	b._build()
	for n in [b._rings[0], b._cone, b._flash]:
		n.visible = true
	b.set_process(false)
	return [b]


func _ready() -> void:
	if _rings.is_empty():
		_build()
		visible = false


func _build() -> void:
	for i in 2:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE * 2.0
		mi.mesh = q
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("width", 0.16 if i == 0 else 0.1)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_rings.append(mi)
		_ring_mats.append(m)
	_cone = MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = 1.0
	c.height = 1.0
	c.radial_segments = 24
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	_cone.mesh = c
	_cone_mat = ShaderMaterial.new()
	_cone_mat.shader = SHADER
	_cone_mat.set_shader_parameter("cone", 1.0)
	_cone.material_override = _cone_mat
	_cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cone)
	_flash = MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2.ONE * 2.0
	_flash.mesh = fq
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = SHADER
	_flash_mat.set_shader_parameter("width", 0.95)
	_flash.material_override = _flash_mat
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flash)


func _start(at: Vector3, dir: Vector3, boom_size: float) -> void:
	if _rings.is_empty():
		_build()
	var d := dir.normalized() if dir.length_squared() > 1e-4 else Vector3.FORWARD
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	# Local -Z along the flight: the rings face it, the cone's tip points
	# forward along it.
	global_transform = Transform3D(Basis.looking_at(d, up), at)
	size = boom_size
	active = true
	visible = true
	_t = 0.0
	_apply(0.0)


func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	if _t >= duration:
		active = false
		visible = false
		return
	_apply(_t / duration)


func _apply(k: float) -> void:
	var out := 1.0 - pow(1.0 - k, 3.0)
	var fade := 1.0 - k
	for i in _rings.size():
		var lag := 0.25 * i
		var ki := clampf((k - lag) / (1.0 - lag), 0.0, 1.0)
		var r := size * lerpf(0.5, 3.2 - 0.8 * i, 1.0 - pow(1.0 - ki, 3.0))
		_rings[i].scale = Vector3(r, r, 1.0)
		_rings[i].position = Vector3(0, 0, 0.35 * i * size)  # the second a little behind
		_ring_mats[i].set_shader_parameter("amount", (1.0 - ki) * (1.0 if i == 0 else 0.7) if ki > 0.0 else 0.0)
	# The cone: tip forward, flaring out behind (its height along local +Z).
	var len := size * lerpf(1.2, 2.6, out)
	var rad := size * lerpf(0.5, 1.6, out)
	_cone.basis = Basis(Vector3.RIGHT, -PI * 0.5)
	_cone.scale = Vector3(rad, len, rad)
	_cone.position = Vector3(0, 0, len * 0.5 - 0.2 * size)
	_cone_mat.set_shader_parameter("amount", fade * fade * 0.9)
	var f := size * lerpf(0.6, 1.4, out)
	_flash.scale = Vector3(f, f, 1.0)
	_flash_mat.set_shader_parameter("amount", maxf(1.0 - k * 3.0, 0.0))
