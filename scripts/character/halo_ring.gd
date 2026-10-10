class_name HaloRing
extends Node3D
## Harbinger's halo: a glowing blue electric ring following her head (her
## model's painted halo is removed by tools/build_harbinger.py; the ring sits
## exactly where it was). A bright core ring with current running round it,
## a soft glow tube around it (visible from any angle, shows over bright
## backgrounds too) and electric arcs crackling across a flat band - three
## small meshes and texture-free shaders, shared by every Harbinger (and
## her select-screen preview). No lights.
## Put it under the character's visual / model: it finds the skeleton there.

@export var bone := "mixamorig_Head"
## Ring in the model's rest pose (skeleton space), from the removed halo.
@export var centre := Vector3(0.0048, 1.6577, -0.0373)
@export var normal := Vector3(-0.001, 0.987, -0.159)
@export var radius := 0.198
@export var core_thickness := 0.007
## Soft glow tube round the core (radius of its cross-section).
@export var shell_thickness := 0.03
## Flat band the electric arcs crackle across (half its width).
@export var glow_width := 0.06
@export var color := Color(0.15, 0.55, 1.0)

static var _core_mesh: Mesh
static var _shell_mesh: Mesh
static var _glow_mesh: Mesh
static var _core_mat: ShaderMaterial
static var _shell_mat: ShaderMaterial
static var _glow_mat: ShaderMaterial

var ring: Node3D


func _ready() -> void:
	var sk := _find_skeleton(get_parent())
	var b := sk.find_bone(bone) if sk else -1
	if b < 0:
		return
	_make_shared()
	var att := BoneAttachment3D.new()
	att.name = "HaloAttachment"
	att.bone_name = bone
	sk.add_child(att)
	ring = Node3D.new()
	ring.name = "Halo"
	var up := normal.normalized()
	var x := Vector3.RIGHT - up * up.dot(Vector3.RIGHT)
	var ring_xf := Transform3D(Basis(x.normalized(), up, x.normalized().cross(up)), centre)
	ring.transform = sk.get_bone_global_rest(b).affine_inverse() * ring_xf
	att.add_child(ring)
	for pair in [[_core_mesh, _core_mat], [_shell_mesh, _shell_mat], [_glow_mesh, _glow_mat]]:
		var mi := MeshInstance3D.new()
		mi.mesh = pair[0]
		mi.material_override = pair[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.add_child(mi)
	tree_exiting.connect(att.queue_free)


func _find_skeleton(n: Node) -> Skeleton3D:
	var found := n.find_children("*", "Skeleton3D", true, false) if n else []
	return found[0] if not found.is_empty() else null


func _make_shared() -> void:
	if _core_mesh == null:
		var t := TorusMesh.new()
		t.inner_radius = radius - core_thickness
		t.outer_radius = radius + core_thickness
		t.rings = 48
		t.ring_segments = 6
		_core_mesh = t
		var sh := TorusMesh.new()
		sh.inner_radius = radius - shell_thickness
		sh.outer_radius = radius + shell_thickness
		sh.rings = 48
		sh.ring_segments = 8
		_shell_mesh = sh
		_glow_mesh = _annulus(radius - glow_width, radius + glow_width, 64)
		_core_mat = ShaderMaterial.new()
		_core_mat.shader = preload("res://scripts/vfx/halo_core.gdshader")
		_core_mat.set_shader_parameter("color", color)
		_shell_mat = ShaderMaterial.new()
		_shell_mat.shader = preload("res://scripts/vfx/halo_shell.gdshader")
		_shell_mat.set_shader_parameter("color", color)
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = preload("res://scripts/vfx/halo_glow.gdshader")
		_glow_mat.set_shader_parameter("color", color)


## Flat ring in the XZ plane; UV.x runs round it, UV.y across it.
static func _annulus(r0: float, r1: float, segments: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in segments + 1:
		var a := TAU * i / segments
		var d := Vector3(cos(a), 0, sin(a))
		v.append(d * r0)
		v.append(d * r1)
		uv.append(Vector2(float(i) / segments, 0.0))
		uv.append(Vector2(float(i) / segments, 1.0))
		if i < segments:
			var k := i * 2
			idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
