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
## Arm it goes on when equipped without naming a slot ("Left"/"Right"). In
## dual wield the slot decides: mount_bone's side is swapped to match and the
## roll/outward offsets are mirrored for the left arm.
@export var mount_side := "Right"
## Distance along the bone (+Y, towards the hand) to place the weapon's socket.
@export var mount_offset := 0.05
## Roll of the weapon around the forearm axis.
@export var mount_roll_degrees := 0.0
@export var mount_scale := 1.0
## Offsets of the socket from the forearm axis (m): up (weapon top side) and
## outward, away from the body (mirrored per arm).
@export var mount_lift := 0.0
@export var mount_out := 0.0

@export_group("Pickup display")
@export var display_height := 1.05
@export var display_scale := 1.0
