class_name WeaponHolder
extends Node
## Lives on a player. Equips weapons onto existing skeleton bones via a
## BoneAttachment3D (no rig changes). Reads only WeaponDefinition data, so it
## works for any weapon and for local or (later) remote players.

signal weapon_equipped(definition: WeaponDefinition)
signal weapon_fired(weapon: Weapon)
## The instant a shot leaves the muzzle (local player hooks the camera kick).
signal weapon_recoil(strength: float)

## Extra slide of the weapon back along its barrel and muzzle climb at peak
## recoil (on top of the arm's own recoil).
@export var recoil_slide := 0.12
@export var recoil_pitch_deg := 7.0

## Fire only when the barrel is within this angle of the target (degrees),
## so shots always leave the gun the way it points.
@export var fire_cone_degrees := 25.0

@export var visual_path: NodePath = ^"../Visual/GrinchVisual"
@export var target_lock_path: NodePath = ^"../TargetLock"

var current: Weapon
var current_definition: WeaponDefinition
var _attachment: BoneAttachment3D
var _socket := Transform3D.IDENTITY


func _ready() -> void:
	var player := get_parent() as PlayerController
	if player:
		player.command_processed.connect(_on_command)


## Auto-fire: each tick, if a target is locked and the (upper-body-aimed)
## weapon points at it, fire as fast as the weapon allows. Movement is never
## touched here, except turning a standing player towards a target that is
## outside the upper body's reach.
func _on_command(cmd: PlayerCommand, _delta: float) -> void:
	var lock := get_node_or_null(target_lock_path) as TargetLock
	if current == null or lock == null or not lock.has_target():
		return
	var player := get_parent() as PlayerController
	var point := lock.get_aim_point()
	if current.has_method("update_aim"):
		current.update_aim(point)
	var to := point - current.global_position
	to.y = 0.0
	if cmd.move.length() < 0.1 and to.length() > 0.01:
		player.face_yaw_when_idle(atan2(-to.x, -to.z))
	if not current.can_fire():
		return
	var aim_dir := (point - current.global_position).normalized()
	if current.get_barrel_direction().angle_to(aim_dir) > deg_to_rad(fire_cone_degrees):
		return
	if current.fire_at(player, point):
		weapon_fired.emit(current)


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
	# Posed every rendered frame from the skeleton, so not physics-interpolated.
	_attachment.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	sk.add_child(_attachment)

	var weapon: Weapon = definition.weapon_scene.instantiate()
	weapon.definition = definition
	_attachment.add_child(weapon)
	# Placed in world space every rendered frame from the skeleton's
	# interpolated pose (like the camera), so it never lags the character.
	weapon.top_level = true
	weapon.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_socket = weapon.get_socket_transform()
	if not sk.skeleton_updated.is_connected(_align_weapon):
		sk.skeleton_updated.connect(_align_weapon)
	current = weapon
	current_definition = definition
	_align_weapon()
	weapon.on_equipped(get_parent())
	weapon.recoiled.connect(_on_weapon_recoil)
	var animator := get_node_or_null(visual_path) as CharacterAnimator
	if animator:
		animator.set_armed_side(definition.mount_side)
	weapon_equipped.emit(definition)
	return weapon


## Runs after every skeleton pose update: the weapon's socket axis (+X) follows
## the forearm, its position rides the bone, and it is rolled around the
## forearm so the weapon's top stays facing up (forearm twist from the
## animations would otherwise tilt it).
func _on_weapon_recoil(strength: float) -> void:
	var animator := get_node_or_null(visual_path) as CharacterAnimator
	if animator:
		animator.add_recoil(strength)
	weapon_recoil.emit(strength)


func _recoil_value() -> float:
	var animator := get_node_or_null(visual_path) as CharacterAnimator
	return animator.recoil if animator else 0.0


func _align_weapon() -> void:
	if current == null or _attachment == null or not is_instance_valid(current):
		return
	var def := current_definition
	# Read the final (post-modifier) pose straight from the skeleton.
	var sk := _attachment.get_parent() as Skeleton3D
	var bone := sk.get_global_transform_interpolated() * sk.get_bone_global_pose(_attachment.bone_idx)
	var axis := bone.basis.y.normalized()
	var up := Vector3.UP - axis * axis.dot(Vector3.UP)
	if up.length_squared() < 1e-4:
		up = bone.basis.z - axis * axis.dot(bone.basis.z)
	up = up.normalized().rotated(axis, deg_to_rad(def.mount_roll_degrees))
	var basis := Basis(axis, up, axis.cross(up))
	var r := _recoil_value()
	if r != 0.0:
		# Muzzle climbs around the weapon's side axis; whole cannon slides back.
		basis = Basis(basis.z, deg_to_rad(recoil_pitch_deg) * r) * basis
	basis = basis.scaled(Vector3.ONE * def.mount_scale)
	var socket_world := bone.origin + axis * (def.mount_offset - recoil_slide * maxf(r, -0.3))
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
