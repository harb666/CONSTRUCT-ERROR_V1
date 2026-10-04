class_name WeaponHolder
extends Node
## Lives on a player. Equips weapons onto existing skeleton bones via a
## BoneAttachment3D (no rig changes). Reads only WeaponDefinition data, so it
## works for any weapon and for local or (later) remote players.

signal weapon_equipped(definition: WeaponDefinition)

@export var visual_path: NodePath = ^"../Visual/GrinchVisual"

var current: Weapon
var current_definition: WeaponDefinition
var _attachment: BoneAttachment3D
var _socket := Transform3D.IDENTITY


func _skeleton() -> Skeleton3D:
	var visual := get_node_or_null(visual_path)
	if visual == null:
		return null
	var found := visual.find_children("*", "Skeleton3D", true, false)
	return found[0] if found.size() > 0 else null


func can_equip(_definition: WeaponDefinition) -> bool:
	return true


func equip(definition: WeaponDefinition) -> Weapon:
	unequip()
	var sk := _skeleton()
	if sk == null or definition.weapon_scene == null:
		return null
	_attachment = BoneAttachment3D.new()
	_attachment.name = "WeaponMount"
	_attachment.bone_name = definition.mount_bone
	sk.add_child(_attachment)

	var weapon: Weapon = definition.weapon_scene.instantiate()
	weapon.definition = definition
	_attachment.add_child(weapon)
	_socket = weapon.get_socket_transform()
	if not sk.skeleton_updated.is_connected(_align_weapon):
		sk.skeleton_updated.connect(_align_weapon)
	current = weapon
	current_definition = definition
	_align_weapon()
	weapon.on_equipped(get_parent())
	var animator := get_node_or_null(visual_path) as CharacterAnimator
	if animator:
		animator.set_armed_side(definition.mount_side)
	weapon_equipped.emit(definition)
	return weapon


## Runs after every skeleton pose update: the weapon's socket axis (+X) follows
## the forearm, its position rides the bone, and it is rolled around the
## forearm so the weapon's top stays facing up (forearm twist from the
## animations would otherwise tilt it).
func _align_weapon() -> void:
	if current == null or _attachment == null or not is_instance_valid(current):
		return
	var def := current_definition
	# Read the final (post-modifier) pose straight from the skeleton.
	var sk := _attachment.get_parent() as Skeleton3D
	var bone := sk.global_transform * sk.get_bone_global_pose(_attachment.bone_idx)
	var axis := bone.basis.y.normalized()
	var up := Vector3.UP - axis * axis.dot(Vector3.UP)
	if up.length_squared() < 1e-4:
		up = bone.basis.z - axis * axis.dot(bone.basis.z)
	up = up.normalized().rotated(axis, deg_to_rad(def.mount_roll_degrees))
	var basis := Basis(axis, up, axis.cross(up)).scaled(Vector3.ONE * def.mount_scale)
	var socket_world := bone.origin + axis * def.mount_offset
	current.global_transform = Transform3D(basis, socket_world) * _socket.affine_inverse()


func unequip() -> void:
	if _attachment:
		_attachment.queue_free()
	_attachment = null
	current = null
	current_definition = null
	var animator := get_node_or_null(visual_path) as CharacterAnimator
	if animator:
		animator.set_armed_side("")
