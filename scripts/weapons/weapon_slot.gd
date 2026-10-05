class_name WeaponSlot
extends Node
## One arm's weapon slot ("Left" or "Right"). Owns everything per arm: the
## equipped weapon, its target lock, aiming, auto-fire, cooldown (via the
## weapon), recoil and swapping. Two slots never share state, so changing one
## never touches the other. Weapon-specific behaviour (projectile, damage,
## rate, muzzle, effects) lives in the Weapon itself; this only mounts it,
## points it and pulls the trigger.

signal equipped(slot: WeaponSlot, definition: WeaponDefinition)
signal fired(slot: WeaponSlot, weapon: Weapon)
signal recoiled(slot: WeaponSlot, strength: float)

var side := "Right"
var lock: TargetLock
var animator: CharacterAnimator
var skeleton: Skeleton3D
var current: Weapon
var definition: WeaponDefinition

## Weapon slides back along its barrel / muzzle climbs at peak recoil (on top
## of the arm's own recoil).
var recoil_slide := 0.12
var recoil_pitch_deg := 7.0
## Fire only when the barrel is within this angle of the target (degrees).
var fire_cone_degrees := 25.0

var _attachment: BoneAttachment3D
var _socket := Transform3D.IDENTITY
var _fit_cache: Array[AABB] = []


## +1 for the right arm, -1 for the left (mirrors per-weapon mount offsets).
func mirror() -> float:
	return 1.0 if side == "Right" else -1.0


func has_target() -> bool:
	return lock != null and lock.has_target()


## Auto-fire at this slot's locked target when the barrel points at it.
## Returns true if a shot left the muzzle.
func update(shooter: Node3D) -> bool:
	if current == null or not is_instance_valid(current) or not has_target():
		return false
	var point := lock.get_aim_point()
	if current.has_method("update_aim"):
		current.update_aim(point)
	if not current.can_fire():
		return false
	var aim_dir := (point - current.global_position).normalized()
	if current.get_barrel_direction().angle_to(aim_dir) > deg_to_rad(fire_cone_degrees):
		return false
	if current.fire_at(shooter, point):
		fired.emit(self, current)
		return true
	return false


## The definition's bone, moved to this slot's arm (e.g. RightForeArm ->
## LeftForeArm), so one definition mounts on either side.
func mount_bone_for(def: WeaponDefinition) -> String:
	var other := "Left" if side == "Right" else "Right"
	return def.mount_bone.replace(other, side)


func equip(def: WeaponDefinition, player: Node) -> Weapon:
	unequip()
	if skeleton == null or def == null or def.weapon_scene == null:
		return null
	_attachment = BoneAttachment3D.new()
	_attachment.name = "%sWeaponMount" % side
	_attachment.bone_name = mount_bone_for(def)
	# Posed every rendered frame from the skeleton, so not physics-interpolated.
	_attachment.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	skeleton.add_child(_attachment)

	var weapon: Weapon = def.weapon_scene.instantiate()
	weapon.definition = def
	weapon.name = "%sWeapon" % side
	_attachment.add_child(weapon)
	# Placed in world space every rendered frame from the skeleton's
	# interpolated pose (like the camera), so it never lags the character.
	weapon.top_level = true
	weapon.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_socket = weapon.get_socket_transform()
	_fit_cache.clear()
	if not skeleton.skeleton_updated.is_connected(align):
		skeleton.skeleton_updated.connect(align)
	current = weapon
	definition = def
	align()
	weapon.on_equipped(player)
	weapon.recoiled.connect(_on_weapon_recoil)
	if animator:
		animator.set_armed(side, true)
		animator.set_weapon_fit(side, fit_box())
	equipped.emit(self, def)
	return weapon


func unequip() -> void:
	if _attachment:
		_attachment.queue_free()
	_attachment = null
	current = null
	definition = null
	_fit_cache.clear()
	if animator:
		animator.set_armed(side, false)
		animator.set_weapon_fit(side, AABB())


func _on_weapon_recoil(strength: float) -> void:
	if animator:
		animator.add_recoil(strength, side)
	recoiled.emit(self, strength)


func _recoil_value() -> float:
	return animator.recoil_side[side] if animator else 0.0


## Closest the weapon's rear may come to the elbow (m), recoil included:
## weapons never stick out behind the elbow.
const MIN_REAR_GAP := 0.01


## The weapon's mount in the forearm frame (origin = elbow, +X along the
## forearm, +Y up, +Z = X x Y), recoil `r` included.
func mount_transform(r := 0.0) -> Transform3D:
	var def := definition
	var b := Basis(Vector3.RIGHT, deg_to_rad(def.mount_roll_degrees) * mirror())
	var pos := b * Vector3(def.mount_offset, def.mount_lift, def.mount_out * mirror())
	if r != 0.0:
		# Muzzle climbs around the weapon's side axis; the weapon slides back
		# along the forearm, but never past the elbow.
		var kick := Basis(b.z, deg_to_rad(recoil_pitch_deg) * r)
		b = kick * b
		# Rear-most point of the tilted weapon (tilting a tall weapon swings
		# its back corner rearwards too).
		var box := fit_box()
		var rear := INF
		for i in 8:
			rear = minf(rear, (pos + kick * (box.get_endpoint(i) - pos)).x)
		pos.x -= minf(recoil_slide * maxf(r, -0.3), rear - MIN_REAR_GAP)
	return Transform3D(b.scaled(Vector3.ONE * def.mount_scale), pos) * _socket.affine_inverse()


## The weapon's visible bounds in the forearm frame, at rest (no recoil).
## The arm-aim layer uses it to keep weapons clear of each other, of the
## other arm and of the body.
func fit_box() -> AABB:
	if current == null or not is_instance_valid(current):
		return AABB()
	if _fit_cache.size() == 0:
		var def := definition
		var b := Basis(Vector3.RIGHT, deg_to_rad(def.mount_roll_degrees) * mirror())
		var pos := b * Vector3(def.mount_offset, def.mount_lift, def.mount_out * mirror())
		var xf := Transform3D(b.scaled(Vector3.ONE * def.mount_scale), pos) * _socket.affine_inverse()
		_fit_cache.append(xf * current.get_local_aabb())
	return _fit_cache[0]


## Forearm frame from a bone transform (+Y along the bone), any space whose
## up is +Y (world or skeleton).
static func forearm_frame(bone: Transform3D) -> Transform3D:
	var axis := bone.basis.y.normalized()
	var up := Vector3.UP - axis * axis.dot(Vector3.UP)
	if up.length_squared() < 1e-4:
		up = bone.basis.z - axis * axis.dot(bone.basis.z)
	up = up.normalized()
	return Transform3D(Basis(axis, up, axis.cross(up)), bone.origin)


## Runs after every skeleton pose update: the weapon's socket axis (+X) follows
## the forearm, its position rides the bone, and it stays upright (forearm
## twist from the animations would otherwise tilt it). Left-arm mounts are
## mirrored.
func align() -> void:
	if current == null or _attachment == null or not is_instance_valid(current):
		return
	# Read the final (post-modifier) pose straight from the skeleton.
	var sk := _attachment.get_parent() as Skeleton3D
	var bone := sk.get_global_transform_interpolated() * sk.get_bone_global_pose(_attachment.bone_idx)
	current.global_transform = forearm_frame(bone) * mount_transform(_recoil_value())
