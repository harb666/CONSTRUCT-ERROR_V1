class_name MagmaSplat
extends MeshInstance3D
## Molten splat where a shotgun stream hits a wall or the floor (pooled):
## lies flat on the surface (magma_splat.gdshader) so the fire burst above
## it (MagmaImpact) is rooted in something - splashes out in a blink,
## white-hot, cools to a charred scorch with glowing cracks, then fades.
## Only on fixed scenery (it would float off a moving robot). Streams landing
## on the same spot in the same instant make one bigger splat.

const SHADER := preload("res://scripts/vfx/magma_splat.gdshader")
const POOL_SIZE := 16
const MERGE_DIST := 0.45
const MERGE_TIME := 0.08
const SPLASH_TIME := 0.09
## Seconds hot (white / orange), cooling, then fading.
const HOT_TIME := 0.35
const COOL_TIME := 1.1
const FADE_TIME := 0.9
## Size across (m), the merged maximum, and the lift off the surface (m).
const SIZE := 0.75
const SIZE_MAX := 1.35
const LIFT := 0.025

static var _pool: Array[MagmaSplat] = []
static var spawned := 0

var active := false
var size := SIZE
var _t := 99.0
var _mat: ShaderMaterial


static func spawn(tree: SceneTree, at: Vector3, normal: Vector3) -> MagmaSplat:
	_pool = _pool.filter(func(m: MagmaSplat) -> bool: return is_instance_valid(m) and m.is_inside_tree())
	for m in _pool:
		if m.active and m._t < MERGE_TIME and m.global_position.distance_to(at) < MERGE_DIST:
			m.size = minf(m.size + 0.18, SIZE_MAX)
			return m
	var s: MagmaSplat = null
	for m in _pool:
		if not m.active:
			s = m
			break
	if s == null:
		if _pool.size() < POOL_SIZE:
			s = MagmaSplat.new()
			var host: Node = tree.current_scene if tree.current_scene else tree.root
			host.add_child(s)
			_pool.append(s)
		else:
			s = _pool[0]
			for m in _pool:
				if m._t > s._t:
					s = m
	s._start(at, normal)
	spawned += 1
	return s


static func active_count() -> int:
	var n := 0
	for m in _pool:
		if is_instance_valid(m) and m.active:
			n += 1
	return n


func _init() -> void:
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	mesh = q
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visible = false
	set_process(false)


func _start(at: Vector3, normal: Vector3) -> void:
	var n := normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	var x := n.cross(Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(n).normalized()
	var b := Basis(x, n, z).rotated(n, randf() * TAU)
	global_transform = Transform3D(b, at + n * LIFT)
	size = SIZE * randf_range(0.85, 1.15)
	_mat.set_shader_parameter("seed", randf() * 40.0)
	_t = 0.0
	active = true
	visible = true
	set_process(true)
	_update()


func _process(delta: float) -> void:
	_t += delta
	if _t >= HOT_TIME + COOL_TIME + FADE_TIME:
		active = false
		visible = false
		set_process(false)
		return
	_update()


func _update() -> void:
	var g := 1.0 - pow(1.0 - clampf(_t / SPLASH_TIME, 0.0, 1.0), 3.0)
	var heat := 1.0 - clampf((_t - HOT_TIME) / COOL_TIME, 0.0, 1.0)
	var fade := 1.0 - clampf((_t - HOT_TIME - COOL_TIME) / FADE_TIME, 0.0, 1.0)
	scale = Vector3(size, 1.0, size)
	_mat.set_shader_parameter("grow", 0.35 + 0.65 * g)
	_mat.set_shader_parameter("heat", heat)
	_mat.set_shader_parameter("fade", fade)
