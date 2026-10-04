class_name TargetDummy
extends StaticBody3D
## Simple shooting target: flashes and wobbles when a projectile hits it.

signal hit(count: int)

var hits := 0
var _flash := 0.0
var _wobble := 0.0
@onready var _mesh: MeshInstance3D = $Mesh
var _mat: StandardMaterial3D


func _ready() -> void:
	_mat = (_mesh.mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
	_mesh.material_override = _mat


func on_projectile_hit(_projectile: Node) -> void:
	hits += 1
	_flash = 1.0
	_wobble = 1.0
	hit.emit(hits)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 2.5, 0.0)
		_mat.emission_enabled = _flash > 0.0
		_mat.emission = Color(0.8, 0.2, 1.0) * _flash * 3.0
	if _wobble > 0.0:
		_wobble = maxf(_wobble - delta * 1.5, 0.0)
		_mesh.rotation.z = sin(_wobble * 25.0) * 0.25 * _wobble
