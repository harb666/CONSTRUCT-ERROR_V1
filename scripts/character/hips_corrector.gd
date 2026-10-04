class_name HipsCorrector
extends SkeletonModifier3D
## Runtime-only pose adjustment of the existing Hips bone, applied after the
## AnimationTree has posed the skeleton. Used to keep clips "in place" (strip
## baked root travel / root turning) so gameplay stays in control of position
## and facing. The rig, rest pose and source animations are never modified.

var bone := -1
## Returns {"xz": Vector2, "y": float, "yaw": float} for the current frame.
var provider: Callable


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or bone < 0 or not provider.is_valid():
		return
	var c: Dictionary = provider.call()
	var xz: Vector2 = c.xz
	var y: float = c.y
	var yaw: float = c.yaw
	if xz == Vector2.ZERO and y == 0.0 and yaw == 0.0:
		return
	var pose := sk.get_bone_pose(bone)
	pose.origin += Vector3(xz.x, y, xz.y)
	if yaw != 0.0:
		pose.basis = Basis(Vector3.UP, yaw) * pose.basis
	sk.set_bone_pose(bone, pose)
