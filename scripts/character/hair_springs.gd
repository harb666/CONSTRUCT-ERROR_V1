class_name HairSprings
extends Node
## Lager's long hair swings on its own (owner asked: it moved as one block
## with her head and back). tools/build_lager.py gives the hanging hair a
## chain of bones from the head down her back (Hair_Root -> Hair_1 -> Hair_2
## -> Hair_End); this springs that chain (Godot's SpringBoneSimulator3D):
## it lags behind as she runs, turns and jumps and settles back, kept out of
## her back by a capsule round the spine. Visual only (each device its own).
## Works on the player (CharacterAnimator) and the character-select preview.

@export var root_bone := &"Hair_Root"
@export var end_bone := &"Hair_End"
## Pull back to the animated pose (higher = stiffer hair).
@export var stiffness := 5.0
## Air resistance (higher = settles sooner, less swing).
@export var drag := 0.3
@export var gravity := 0.4
## Joint radius (m) for the collisions.
@export var radius := 0.035
## Capsule round the spine (Spine1's frame) keeping the hair off her back.
@export var back_radius := 0.165
@export var back_height := 0.55
@export var back_offset := Vector3(0, 0.02, 0)

var sim: SpringBoneSimulator3D


func _ready() -> void:
	# After the CharacterAnimator has added its pose layers (it is the
	# parent; children are ready first), so the hair reacts to the final pose.
	_attach.call_deferred()


func _attach() -> void:
	var host := get_parent()
	if host == null:
		return
	var found := host.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return
	var sk := found[0] as Skeleton3D
	if sk.find_bone(root_bone) < 0 or sk.find_bone(end_bone) < 0:
		return
	sim = SpringBoneSimulator3D.new()
	sim.name = "HairSprings"
	sim.setting_count = 1
	# On the skeleton first: bone names set before it is there never resolve
	# (the simulator then silently does nothing).
	sk.add_child(sim)
	sim.set_root_bone_name(0, root_bone)
	sim.set_end_bone_name(0, end_bone)
	sim.set_stiffness(0, stiffness)
	sim.set_drag(0, drag)
	sim.set_gravity(0, gravity)
	sim.set_radius(0, radius)
	var back := SpringBoneCollisionCapsule3D.new()
	back.name = "Back"
	sim.add_child(back)  # (likewise: in place before naming its bone)
	back.bone_name = "mixamorig_Spine1"
	back.radius = back_radius
	back.height = back_height
	back.position_offset = back_offset
	sim.set_enable_all_child_collisions(0, true)
	sim.reset()
