class_name WeaponDefinition
extends Resource
## Data describing one weapon. Spawn pads and the player's WeaponHolder only
## talk to this, so new weapons need a definition + a Weapon scene, no new
## pickup/equip code. `id` is what a network layer would replicate.

@export var id: StringName
@export var display_name := ""
## Scene whose root extends Weapon.
@export var weapon_scene: PackedScene

@export_group("Loadout")
## Picture for the weapon wheel (tools/render_weapon_icons.gd makes these).
@export var icon: Texture2D
## Main colour of the weapon's energy (wheel highlights, switch flash).
@export var accent_color := Color(0.4, 0.8, 1.0)
## Available from the start of a session (otherwise unlocked by a pickup).
@export var unlocked_at_start := false
## Arms it can be equipped to.
@export var allowed_sides: PackedStringArray = ["Left", "Right"]
## Heavy weapon (owner asked: the Black Hole Generator and the Frost Byte).
## Held on the RIGHT arm only, so two heavy weapons are never held at once;
## only light weapons dual-wield. Asked for on the left arm, it goes on the
## right one instead (`side_for`). Marked HEAVY in the wheel and the HUD.
@export var heavy := false

const HEAVY_SIDE := "Right"

## Ammo (owner asked: only the pistol cannon is unlimited; enemies drop
## ammo for the rest). 0 = unlimited. A pad gives a full load; an enemy's
## drop gives `ammo_pack` (more from bigger enemies - RecoveryDrops).
@export var max_ammo := 0
@export var ammo_pack := 0


func unlimited() -> bool:
	return max_ammo <= 0


## Can it go on `side`?
func can_go_on(side: String) -> bool:
	return side in allowed_sides and (not heavy or side == HEAVY_SIDE)


## The arm it actually goes on when asked for `side`: a heavy weapon always
## goes on the right arm.
func side_for(side: String) -> String:
	return HEAVY_SIDE if heavy else side

@export_group("Mount")
## Skeleton bone the weapon attaches to (existing bones only).
@export var mount_bone := "mixamorig_RightForeArm"
## Arm it goes on when equipped without naming a slot ("Left"/"Right"). In
## dual wield the slot decides: mount_bone's side is swapped to match and the
## roll/outward offsets are mirrored for the left arm.
@export var mount_side := "Right"

## How the weapon meets the character's WeaponSocket (see CharacterAnimator
## "Weapon sockets"; the socket is the Black Hole Generator's mount):
##  SLEEVE  - the weapon's Arm_Socket_Attachment marker sits ON the socket; the
##            weapon is a sleeve big enough to swallow the forearm (BHG).
##  ARM_END - the weapon's rear plugs into the open end of the forearm
##            (`arm_end_insert` deep) and extends forward only.
## Either way any weapon geometry left behind the arm-end boundary
## (SLEEVE: behind the socket) is trimmed off the held copy.
enum MountMode { SLEEVE, ARM_END }
@export var mount_mode := MountMode.SLEEVE
## How far the rear of an ARM_END weapon slides into the arm's open end (m).
@export var arm_end_insert := 0.04
## Small weapon-specific nudge along the forearm from the mount point (m).
@export var mount_offset := 0.0
## Roll of the weapon around the forearm axis.
@export var mount_roll_degrees := 0.0
@export var mount_scale := 1.0
## Small offsets from the forearm axis (m): up (weapon top side) and
## outward, away from the body (mirrored per arm). Normally 0 (centred).
@export var mount_lift := 0.0
@export var mount_out := 0.0

@export_group("Pickup display")
@export var display_height := 1.05
@export var display_scale := 1.0
