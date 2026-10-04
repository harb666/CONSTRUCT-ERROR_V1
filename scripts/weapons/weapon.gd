class_name Weapon
extends Node3D
## Base for weapon scenes (used both for the floating pickup display and the
## equipped weapon). Weapons expose standard marker nodes by name:
##   Arm_Socket_Attachment  - where the forearm enters (insertion axis +X)
##   Muzzle_Exit            - projectile exit (forward +X)

const SOCKET_MARKER := "Arm_Socket_Attachment"
const MUZZLE_MARKER := "Muzzle_Exit"

var definition: WeaponDefinition
var is_equipped := false
## Keep firing while the trigger is held (as fast as can_fire() allows).
@export var auto_fire := true


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
		var a: AABB = (global_transform.affine_inverse() * mi.global_transform) * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box.get_center()


func on_displayed() -> void:
	for gi: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func can_fire() -> bool:
	return false


## Fire towards the aim ray (camera through crosshair). Returns true if fired.
func fire(_shooter: Node3D, _aim_origin: Vector3, _aim_dir: Vector3) -> bool:
	return false


## Point the aim ray hits (ignoring the shooter), for converging shots
## from an offset muzzle onto the crosshair.
func resolve_aim_point(shooter: Node3D, aim_origin: Vector3, aim_dir: Vector3, max_range := 150.0) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(aim_origin, aim_origin + aim_dir * max_range)
	if shooter is CollisionObject3D:
		q.exclude = [(shooter as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if hit else aim_origin + aim_dir * max_range


func on_equipped(_owner_player: Node) -> void:
	is_equipped = true
