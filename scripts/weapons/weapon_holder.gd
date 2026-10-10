class_name WeaponHolder
extends Node
## Lives on a player. Dual wield: a RIGHT and a LEFT WeaponSlot, each with its
## own weapon, target lock, aiming, firing, cooldown, recoil and swapping.
## Weapons go onto existing skeleton bones via BoneAttachment3D (no rig
## changes). Holds no weapon-specific logic: it reads only WeaponDefinition
## data and the Weapon interface, so it works for any weapon and for local
## or (later) remote players.
##
## Both slots start with `default_weapon` (the permanent default cannons).
## Pickups go to the RIGHT slot; the LEFT keeps its default.

signal weapon_equipped(definition: WeaponDefinition)
signal weapon_fired(weapon: Weapon)
## The instant a shot leaves a muzzle (local player hooks the camera kick).
signal weapon_recoil(strength: float)
## Per-slot versions of the above.
signal slot_equipped(side: String, definition: WeaponDefinition)
signal slot_fired(side: String, weapon: Weapon)

const SIDES := ["Right", "Left"]

## Equipped into both arms at spawn and restored when a slot is emptied.
@export var default_weapon: WeaponDefinition

## Extra slide of the weapon back along its barrel and muzzle climb at peak
## recoil (on top of the arm's own recoil).
@export var recoil_slide := 0.12
@export var recoil_pitch_deg := 7.0

## Fire only when the barrel is within this angle of the target (degrees),
## so shots always leave the gun the way it points.
@export var fire_cone_degrees := 25.0

@export var visual_path: NodePath = ^"../Visual/GrinchVisual"
## Target lock per slot.
@export var target_lock_path: NodePath = ^"../TargetLock"
@export var left_target_lock_path: NodePath = ^"../TargetLockLeft"

var slots := {}

## The RIGHT slot's weapon (single-weapon callers, pickups, HUD).
var current: Weapon:
	get:
		return slots.Right.current if slots.has("Right") else null
var current_definition: WeaponDefinition:
	get:
		return slots.Right.definition if slots.has("Right") else null


func _ready() -> void:
	var player := get_parent() as PlayerController
	var animator := get_node_or_null(visual_path) as CharacterAnimator
	var sk := _skeleton()
	for side in SIDES:
		var slot := WeaponSlot.new()
		slot.name = side + "Slot"
		slot.side = side
		slot.animator = animator
		slot.skeleton = sk
		slot.lock = get_node_or_null(target_lock_path if side == "Right" else left_target_lock_path) as TargetLock
		slot.recoil_slide = recoil_slide
		slot.recoil_pitch_deg = recoil_pitch_deg
		slot.fire_cone_degrees = fire_cone_degrees
		add_child(slot)
		slot.ensure_socket()
		slot.fired.connect(func(s: WeaponSlot, w: Weapon) -> void:
			slot_fired.emit(s.side, w)
			weapon_fired.emit(w))
		slot.recoiled.connect(func(_s: WeaponSlot, strength: float) -> void: weapon_recoil.emit(strength))
		slot.equipped.connect(func(s: WeaponSlot, d: WeaponDefinition) -> void:
			slot_equipped.emit(s.side, d)
			weapon_equipped.emit(d))
		slots[side] = slot
	if player:
		player.command_processed.connect(_on_command)
	if default_weapon:
		for side in SIDES:
			equip(default_weapon, side)


func slot(side: String) -> WeaponSlot:
	return slots.get(side)


func weapon(side: String) -> Weapon:
	return slots[side].current if slots.has(side) else null


## Auto-fire: each tick every slot fires at its own locked target as fast as
## its weapon allows, once that arm's (upper-body-aimed) barrel points at it.
## Movement is never touched here, except turning a standing player towards
## its targets when they are outside the upper body's reach.
func _on_command(cmd: PlayerCommand, _delta: float) -> void:
	var player := get_parent() as PlayerController
	var sum := Vector3.ZERO
	var n := 0
	for side in SIDES:
		var s: WeaponSlot = slots[side]
		if s.current == null or not s.has_target():
			continue
		var to := s.lock.get_aim_point() - player.global_position
		to.y = 0.0
		if to.length() > 0.01:
			sum += to.normalized()
			n += 1
	if n > 0 and cmd.move.length() < 0.1 and sum.length() > 0.01:
		player.face_yaw_when_idle(atan2(-sum.x, -sum.z))
	for side in SIDES:
		# The right arm's cannon is busy punching (PlayerMelee fires it).
		if side == "Right" and player.melee and player.melee.active:
			continue
		(slots[side] as WeaponSlot).update(player)


func _skeleton() -> Skeleton3D:
	var visual := get_node_or_null(visual_path)
	if visual == null:
		return null
	var found := visual.find_children("*", "Skeleton3D", true, false)
	return found[0] if found.size() > 0 else null


func can_equip(_definition: WeaponDefinition) -> bool:
	return true


## Equip into a slot (pickups: the RIGHT slot). The other slot is untouched.
func equip(definition: WeaponDefinition, side := "Right") -> Weapon:
	if not slots.has(side):
		return null
	return (slots[side] as WeaponSlot).equip(definition, get_parent())


## Switch a slot to another weapon with the retract / materialise sequence
## (~0.3 s). The other slot is untouched and keeps firing.
func switch_weapon(definition: WeaponDefinition, side: String) -> void:
	if slots.has(side):
		(slots[side] as WeaponSlot).switch_to(definition, get_parent())


## Empty a slot (its arm lowers). `restore_default` puts the default back.
func unequip(side := "Right", restore_default := false) -> void:
	if not slots.has(side):
		return
	(slots[side] as WeaponSlot).unequip()
	if restore_default and default_weapon:
		equip(default_weapon, side)
