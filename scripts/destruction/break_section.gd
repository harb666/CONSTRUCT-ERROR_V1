class_name BreakSection
extends Resource
## One prepared, separately-modelled body section of a breakable character
## (the meshes already exist in the model; nothing is cut at runtime).
## Sections form a tree (child -> `parent`); detaching a section takes every
## still-attached child with it as one piece.

@export var section_name: StringName
## MeshInstance3D node names under the character's Skeleton3D.
@export var mesh_names: PackedStringArray
## Section this one is connected to ("" = root of the body).
@export var parent: StringName
## Bone that drives this section (sets the detached piece's frame).
@export var bone: StringName
## Bone at the connection to the parent (where sparks fly when it breaks).
@export var joint_bone: StringName
## 0 = small (foot, forearm), 1 = medium (head, shin, upper arm),
## 2 = major (thigh, torso). Lower destruction levels only break small ones.
@export_range(0, 2) var tier := 0
