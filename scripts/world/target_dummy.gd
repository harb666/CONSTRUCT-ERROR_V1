class_name TargetDummy
extends StaticBody3D
## Test enemy: flashes and wobbles when hit, is destroyed after `max_health`
## hits (which clears any lock on it) and respawns after `respawn_time`.

signal hit(count: int)

@export var max_health := 5
@export var respawn_time := 4.0

var hits := 0
var health := 0
var _flash := 0.0
var _wobble := 0.0
@onready var _mesh: MeshInstance3D = $Mesh
@onready var _targetable: Targetable = $Targetable
var _mat: StandardMaterial3D


func _ready() -> void:
	_mat = (_mesh.mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
	_mesh.material_override = _mat
	health = max_health


func on_projectile_hit(_projectile: Node) -> void:
	if health <= 0:
		return
	hits += 1
	health -= 1
	_flash = 1.0
	_wobble = 1.0
	hit.emit(hits)
	if health <= 0:
		_die()


func _die() -> void:
	_targetable.kill()
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	collision_layer = 0
	get_tree().create_timer(respawn_time).timeout.connect(_respawn)


func _respawn() -> void:
	health = max_health
	_flash = 0.0
	_wobble = 0.0
	_mat.emission_enabled = false
	_mesh.rotation = Vector3.ZERO
	collision_layer = 1
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	_targetable.revive()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 2.5, 0.0)
		_mat.emission_enabled = _flash > 0.0
		_mat.emission = Color(0.8, 0.2, 1.0) * _flash * 3.0
	if _wobble > 0.0:
		_wobble = maxf(_wobble - delta * 1.5, 0.0)
		_mesh.rotation.z = sin(_wobble * 25.0) * 0.25 * _wobble
