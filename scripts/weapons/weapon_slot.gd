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
## Weapon switching (switch_to): started / new weapon fully in place.
signal switch_started(slot: WeaponSlot, from_def: WeaponDefinition, to_def: WeaponDefinition)
signal switch_finished(slot: WeaponSlot, definition: WeaponDefinition)

## Switch timing (s): the old weapon retracts into the arm, then the new one
## snaps out of the same mount (~0.3 s in all). It can fire as soon as it is
## half out.
const RETRACT_TIME := 0.11
const EXTEND_TIME := 0.18

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
## Character-side weapon socket for this arm (follows the forearm; see
## CharacterAnimator "Weapon sockets"). Every weapon mounts relative to it.
var socket_node: Marker3D
var _socket_bone := -1

const DEFAULT_SOCKET_OFFSET := 0.05
const DEFAULT_ARM_END := 0.34
## Trimmed copies of weapon meshes, shared: key -> ArrayMesh.
static var _trim_cache := {}

## Switching state: 0 = idle, 1 = retracting the old weapon, 2 = the new one
## materialising. `switch_scale` shrinks/grows the weapon about its mount.
var switch_phase := 0
var switch_scale := 1.0
var _switch_t := 0.0
var _pending: WeaponDefinition
var _owner_player: Node
var _fx: WeaponSwitchFx


## +1 for the right arm, -1 for the left (mirrors per-weapon mount offsets).
func mirror() -> float:
	return 1.0 if side == "Right" else -1.0


func has_target() -> bool:
	return lock != null and lock.has_target()


## Auto-fire at this slot's locked target when the barrel points at it.
## Returns true if a shot left the muzzle.
func update(shooter: Node3D) -> bool:
	if current == null or not is_instance_valid(current) or not has_target():
		_set_aim_offset(Vector3.ZERO)
		return false
	# Mid-switch: the old weapon has stopped; the new one fires once half out.
	if switch_phase == 1 or (switch_phase == 2 and switch_scale < 0.5):
		return false
	var point := lock.get_aim_point()
	if current.has_method("update_aim"):
		current.update_aim(point)
	# Weapons that fire exactly along their barrel steer the arm's aim so the
	# barrel (not just the arm) lands on the target.
	_set_aim_offset(current.aim_correction(point) if current.has_method("aim_correction") else Vector3.ZERO)
	if not current.can_fire():
		return false
	var aim_dir := (point - current.global_position).normalized()
	if current.get_barrel_direction().angle_to(aim_dir) > deg_to_rad(fire_cone_degrees):
		return false
	if current.fire_at(shooter, point):
		fired.emit(self, current)
		return true
	return false


func _set_aim_offset(offset: Vector3) -> void:
	if animator:
		animator.aim_offset[side] = offset


## The definition's bone, moved to this slot's arm (e.g. RightForeArm ->
## LeftForeArm), so one definition mounts on either side.
func mount_bone_for(def: WeaponDefinition) -> String:
	var other := "Left" if side == "Right" else "Right"
	return def.mount_bone.replace(other, side)


## Create this arm's WeaponSocket (call once the skeleton is known).
func ensure_socket() -> void:
	if socket_node or skeleton == null:
		return
	_socket_bone = skeleton.find_bone("mixamorig_%sForeArm" % side)
	socket_node = Marker3D.new()
	socket_node.name = "%sWeaponSocket" % side
	socket_node.top_level = true
	socket_node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	skeleton.add_child(socket_node)
	_fx = WeaponSwitchFx.new()
	_fx.name = "SwitchFx"
	socket_node.add_child(_fx)
	_fx.position = Vector3(arm_end_offset(), 0, 0)
	skeleton.skeleton_updated.connect(align)
	set_process(false)
	align()


func socket_offset() -> float:
	return animator.weapon_socket_offset if animator else DEFAULT_SOCKET_OFFSET


func arm_end_offset() -> float:
	return animator.arm_end_offset if animator else DEFAULT_ARM_END


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
	_trim_rear()
	align()
	weapon.on_equipped(player)
	weapon.recoiled.connect(_on_weapon_recoil)
	if animator:
		animator.set_armed(side, true)
		animator.set_weapon_fit(side, fit_box())
	equipped.emit(self, def)
	return weapon


## Switch this arm to `def` with the retract / materialise sequence. The
## other arm is never touched; this arm's target lock stays, so the new weapon
## takes over the current target at once.
func switch_to(def: WeaponDefinition, player: Node) -> void:
	if def == null:
		return
	var showing := _pending if _pending else definition
	if showing == def and (switch_phase == 0 or _pending == null):
		return
	_owner_player = player
	var from := definition
	_pending = def
	switch_started.emit(self, from, def)
	if current == null or switch_phase == 2:
		# Nothing to put away (or the last one is still coming out: swap it
		# straight for the newest choice).
		_begin_extend()
	elif switch_phase == 0:
		switch_phase = 1
		_switch_t = 0.0
		if _fx and from:
			_fx.play(from.accent_color, 0.85, RETRACT_TIME + 0.08)
	set_process(true)


## Whatever this arm will hold once a switch in progress is done.
func target_definition() -> WeaponDefinition:
	return _pending if _pending else definition


func _begin_extend() -> void:
	var def := _pending
	_pending = null
	equip(def, _owner_player if _owner_player else get_parent().get_parent())
	switch_phase = 2
	_switch_t = 0.0
	switch_scale = 0.05
	if _fx:
		_fx.play(def.accent_color, 1.0)


func _process(delta: float) -> void:
	_switch_t += delta
	match switch_phase:
		1:
			var k := clampf(_switch_t / RETRACT_TIME, 0.0, 1.0)
			switch_scale = 1.0 - k * k
			if k >= 1.0:
				_begin_extend()
		2:
			var k := clampf(_switch_t / EXTEND_TIME, 0.0, 1.0)
			# Snap out with a little overshoot.
			var c := 1.9
			switch_scale = 1.0 + (c + 1.0) * pow(k - 1.0, 3) + c * pow(k - 1.0, 2)
			if k >= 1.0:
				switch_scale = 1.0
				switch_phase = 0
				set_process(false)
				switch_finished.emit(self, definition)
		_:
			set_process(false)


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
## How much deeper than its rest position an ARM_END weapon may recoil into
## the arm's open end (m).
const ARM_END_RECOIL_ROOM := 0.03


## Where the weapon's rear boundary is in the socket frame: the arm's open end
## (less the insert) for ARM_END weapons, the socket itself for sleeves.
## Weapon geometry behind it is trimmed off.
func trim_x() -> float:
	if definition and definition.mount_mode == WeaponDefinition.MountMode.ARM_END:
		return arm_end_offset() - definition.arm_end_insert
	return 0.0


## The weapon's marker placement in the socket frame (origin = WeaponSocket,
## +X along the forearm, +Y up, +Z = X x Y) at rest: [basis (scaled), position
## of the weapon's Arm_Socket_Attachment marker].
func _rest_parts() -> Array:
	var def := definition
	var b := Basis(Vector3.RIGHT, deg_to_rad(def.mount_roll_degrees) * mirror())
	var x := def.mount_offset
	if def.mount_mode == WeaponDefinition.MountMode.ARM_END:
		# Rear of the (untrimmed) weapon, measured from its own socket marker.
		var rear := (_socket.affine_inverse() * _untrimmed_aabb()).position.x
		x += trim_x() - rear * def.mount_scale
	var pos := Vector3(x, 0, 0) + b * Vector3(0, def.mount_lift, def.mount_out * mirror())
	return [b.scaled(Vector3.ONE * def.mount_scale), pos]


func _rest_mount() -> Transform3D:
	var parts := _rest_parts()
	return Transform3D(parts[0], parts[1]) * _socket.affine_inverse()


func _untrimmed_aabb() -> AABB:
	if not current.has_meta("untrimmed_aabb"):
		current.set_meta("untrimmed_aabb", current.get_local_aabb())
	return current.get_meta("untrimmed_aabb")


## The weapon's mount in the forearm frame (origin = elbow, +X along the
## forearm, +Y up, +Z = X x Y), recoil `r` included.
func mount_transform(r := 0.0) -> Transform3D:
	var parts := _rest_parts()
	var b: Basis = parts[0]
	var pos: Vector3 = parts[1]
	if r != 0.0:
		# Muzzle climbs around the weapon's side axis (pivoting on its socket
		# marker); the weapon slides back along the forearm, but never past
		# its rear boundary (tilting a tall weapon swings its back corner
		# rearwards too).
		var kick := Basis(b.z.normalized(), deg_to_rad(recoil_pitch_deg) * r)
		var box := Transform3D(b, pos) * _socket.affine_inverse() * current.get_local_aabb()
		var rear := INF
		for i in 8:
			rear = minf(rear, (pos + kick * (box.get_endpoint(i) - pos)).x)
		var min_rear := trim_x() - ARM_END_RECOIL_ROOM if definition.mount_mode == WeaponDefinition.MountMode.ARM_END \
			else MIN_REAR_GAP - socket_offset()
		b = kick * b
		pos.x -= minf(recoil_slide * maxf(r, -0.3), rear - min_rear)
	if switch_phase != 0:
		# Retracting into / snapping out of the arm, about the mount point.
		b = b.scaled(Vector3.ONE * maxf(switch_scale, 0.02))
	return Transform3D(Basis.IDENTITY, Vector3(socket_offset(), 0, 0)) * Transform3D(b, pos) * _socket.affine_inverse()


## The weapon's visible bounds in the forearm frame, at rest (no recoil).
## The arm-aim layer uses it to keep weapons clear of each other, of the
## other arm and of the body.
func fit_box() -> AABB:
	if current == null or not is_instance_valid(current):
		return AABB()
	if _fit_cache.size() == 0:
		_fit_cache.append(mount_transform(0.0) * current.get_local_aabb())
	return _fit_cache[0]


## Hide the held copy's geometry behind the rear boundary (the arm), so no
## part of a weapon ever shows through the forearm. Shared trimmed meshes;
## the pickup display keeps the whole weapon.
func _trim_rear() -> void:
	var to_socket := _rest_mount()
	var limit := trim_x() - 0.002
	var trimmed := false
	for mi: MeshInstance3D in current.find_children("*", "MeshInstance3D", true, false):
		if not (mi.mesh is ArrayMesh):
			continue
		var xf := to_socket * current._local_xf(mi)
		var key := "%d|%s|%.4f" % [mi.mesh.get_rid().get_id(), xf, limit]
		if not _trim_cache.has(key):
			_trim_cache[key] = _trimmed_mesh(mi.mesh as ArrayMesh, xf, limit)
		var m: ArrayMesh = _trim_cache[key]
		if m != mi.mesh:
			mi.mesh = m
			trimmed = true
	if trimmed:
		current.remove_meta("local_aabb")
		_fit_cache.clear()


## `mesh` without the triangles that reach behind x = `limit` (in the frame
## `xf` maps mesh space to), or `mesh` itself if nothing reaches back there.
static func _trimmed_mesh(mesh: ArrayMesh, xf: Transform3D, limit: float) -> ArrayMesh:
	var out := ArrayMesh.new()
	var any := false
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var behind := PackedByteArray()
		behind.resize(verts.size())
		var n_behind := 0
		for i in verts.size():
			if (xf * verts[i]).x < limit:
				behind[i] = 1
				n_behind += 1
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		var keep := PackedInt32Array()
		if n_behind > 0:
			any = true
			for t in range(0, idx.size(), 3):
				if behind[idx[t]] == 0 and behind[idx[t + 1]] == 0 and behind[idx[t + 2]] == 0:
					keep.append(idx[t])
					keep.append(idx[t + 1])
					keep.append(idx[t + 2])
		else:
			keep = idx
		arrays[Mesh.ARRAY_INDEX] = keep
		if keep.is_empty():
			continue
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(si))
	return out if any else mesh


## Forearm frame from a bone transform (+Y along the bone), any space whose
## up is +Y (world or skeleton).
static func forearm_frame(bone: Transform3D) -> Transform3D:
	var axis := bone.basis.y.normalized()
	var up := Vector3.UP - axis * axis.dot(Vector3.UP)
	if up.length_squared() < 1e-4:
		up = bone.basis.z - axis * axis.dot(bone.basis.z)
	up = up.normalized()
	return Transform3D(Basis(axis, up, axis.cross(up)), bone.origin)


## Runs after every skeleton pose update: the WeaponSocket follows the
## forearm (on its axis, upright: forearm twist from the animations would
## otherwise tilt weapons) and the weapon is placed on it. Left-arm mounts
## are mirrored.
func align() -> void:
	var sk := skeleton
	if sk == null or _socket_bone < 0:
		return
	# Read the final (post-modifier) pose straight from the skeleton.
	var frame := forearm_frame(sk.get_global_transform_interpolated() * sk.get_bone_global_pose(_socket_bone))
	if socket_node:
		socket_node.global_transform = frame * Transform3D(Basis.IDENTITY, Vector3(socket_offset(), 0, 0))
	if current == null or _attachment == null or not is_instance_valid(current):
		return
	current.global_transform = frame * mount_transform(_recoil_value())
