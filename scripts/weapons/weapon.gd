class_name Weapon
extends Node3D
## Base for weapon scenes (used both for the floating pickup display and the
## equipped weapon). Weapons expose standard marker nodes by name:
##   Arm_Socket_Attachment  - where the forearm enters (insertion axis +X)
##   Muzzle_Exit            - projectile exit (forward +X)

const SOCKET_MARKER := "Arm_Socket_Attachment"
const MUZZLE_MARKER := "Muzzle_Exit"

## Emitted the instant a shot leaves the muzzle (drives recoil/camera kick).
signal recoiled(strength: float)

var definition: WeaponDefinition
var is_equipped := false
## Keep firing while the trigger is held (as fast as can_fire() allows).
@export var auto_fire := true
## Recoil kick strength (1 = heavy weapon).
@export var recoil_strength := 1.0


func find_marker(marker_name: String) -> Node3D:
	return find_child(marker_name, true, false) as Node3D


## Socket transform relative to this weapon's root.
func get_socket_transform() -> Transform3D:
	var m := find_marker(SOCKET_MARKER)
	return global_transform.affine_inverse() * m.global_transform if m and is_inside_tree() else Transform3D.IDENTITY


## Centre of the visible model relative to the root (for centring displays).
func get_visual_center() -> Vector3:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		# Only the imported model; runtime effect quads/ribbons would skew it.
		if not (mi.mesh is ArrayMesh):
			continue
		var a: AABB = (global_transform.affine_inverse() * mi.global_transform) * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box.get_center()


## Bounds of the visible model in this weapon's own space (root), cached.
## Used to keep held weapons clear of each other and of the arms.
func get_local_aabb() -> AABB:
	if has_meta("local_aabb"):
		return get_meta("local_aabb")
	var box := AABB()
	var first := true
	var inv := global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if not (mi.mesh is ArrayMesh):
			continue
		var xf := inv * mi.global_transform if is_inside_tree() else _local_xf(mi)
		var a: AABB = xf * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	set_meta("local_aabb", box)
	return box


func _local_xf(n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != self:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func on_displayed() -> void:
	for gi: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func can_fire() -> bool:
	return false


## Fire at a world-space point (the locked target's aim point). Each weapon
## decides its own rate (via can_fire), projectile and behaviour.
## Returns true if a shot was fired.
func fire_at(_shooter: Node3D, _target_point: Vector3) -> bool:
	return false


## Direction the weapon's barrel points (weapons fire along +X by convention).
func get_barrel_direction() -> Vector3:
	return global_basis.x.normalized()


func on_equipped(_owner_player: Node) -> void:
	is_equipped = true
