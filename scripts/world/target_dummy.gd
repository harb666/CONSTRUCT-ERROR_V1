class_name TargetDummy
extends RigidBody3D
## Test enemy: a heavy, upright physics body (so gravity wells can pull and
## throw it). Flashes/wobbles when hit, destroyed after `max_health` damage
## (clears any lock on it), respawns at its start position.

signal hit(count: int)

@export var max_health := 5.0
@export var respawn_time := 4.0

var hits := 0
var health := 0.0
var _flash := 0.0
var _wobble := 0.0
var _spawn_xf: Transform3D
var _layers := 1
var _mask := 1
@onready var _mesh: MeshInstance3D = $Mesh
@onready var _targetable: Targetable = $Targetable
var _mat: StandardMaterial3D


func _ready() -> void:
	_mat = (_mesh.mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
	_mesh.material_override = _mat
	health = max_health
	_spawn_xf = global_transform
	collision_layer |= GravityWell.MOVABLE_LAYER
	_layers = collision_layer
	_mask = collision_mask
	# Gravity wells pull towards the body's middle, not its feet.
	set_meta("gravity_center_y", 0.95)


func on_projectile_hit(_projectile: Node) -> void:
	hits += 1
	hit.emit(hits)
	take_damage(1.0)


func take_damage(amount: float, _from := Vector3.ZERO) -> void:
	if health <= 0.0:
		return
	health -= amount
	_flash = 1.0
	_wobble = 1.0
	if health <= 0.0:
		_die()


func _die() -> void:
	_targetable.kill()
	visible = false
	collision_layer = 0
	collision_mask = 0
	freeze = true
	process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().create_timer(respawn_time).timeout.connect(_respawn)


func _respawn() -> void:
	health = max_health
	_flash = 0.0
	_wobble = 0.0
	_mat.emission_enabled = false
	_mesh.rotation = Vector3.ZERO
	process_mode = Node.PROCESS_MODE_INHERIT
	freeze = false
	global_transform = _spawn_xf
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	GravityWell.restore_visual(self)
	collision_layer = _layers
	collision_mask = _mask
	visible = true
	reset_physics_interpolation()
	_targetable.revive()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 2.5, 0.0)
		_mat.emission_enabled = _flash > 0.0
		_mat.emission = Color(0.8, 0.2, 1.0) * _flash * 3.0
	if _wobble > 0.0:
		_wobble = maxf(_wobble - delta * 1.5, 0.0)
		_mesh.rotation.z = sin(_wobble * 25.0) * 0.25 * _wobble
