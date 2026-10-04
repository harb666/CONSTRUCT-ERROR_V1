class_name WeaponDefinition
extends Resource
## Data describing one weapon. Spawn pads and the player's WeaponHolder only
## talk to this, so new weapons need a definition + a Weapon scene, no new
## pickup/equip code. `id` is what a network layer would replicate.

@export var id: StringName
@export var display_name := ""
## Scene whose root extends Weapon.
@export var weapon_scene: PackedScene

@export_group("Mount")
## Skeleton bone the weapon attaches to (existing bones only).
@export var mount_bone := "mixamorig_RightForeArm"
## Which arm is raised to hold it ("Left"/"Right"), used by the aim layer.
@export var mount_side := "Right"
## Distance along the bone (+Y, towards the hand) to place the weapon's socket.
@export var mount_offset := 0.05
## Roll of the weapon around the forearm axis.
@export var mount_roll_degrees := 0.0
@export var mount_scale := 1.0

@export_group("Pickup display")
@export var display_height := 1.05
@export var display_scale := 1.0
