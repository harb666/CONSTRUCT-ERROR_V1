class_name PlayerCommand
extends RefCounted
## One tick of player intent. This is the only thing the movement code reads,
## so later it can come from local input, a network peer, or a replay.

## Stick/keys in local input space: x = right, y = back (Godot's Input.get_vector convention).
var move := Vector2.ZERO
## Camera yaw (radians) the move vector is relative to.
var view_yaw := 0.0
## Edge-triggered: true for exactly one tick per press.
var jump_pressed := false
var dodge_pressed := false
## Held states.
var jump_held := false
var sprint_held := false
## Weapon trigger.
var fire_pressed := false
var fire_held := false
## Aim ray (world space): from the player's camera through the crosshair.
var aim_origin := Vector3.ZERO
var aim_dir := Vector3.FORWARD


func to_dict() -> Dictionary:
	return {
		"m": move,
		"y": view_yaw,
		"jp": jump_pressed,
		"dp": dodge_pressed,
		"jh": jump_held,
		"sh": sprint_held,
		"fp": fire_pressed,
		"fh": fire_held,
		"ao": aim_origin,
		"ad": aim_dir,
	}


static func from_dict(d: Dictionary) -> PlayerCommand:
	var c := PlayerCommand.new()
	c.move = d.get("m", Vector2.ZERO)
	c.view_yaw = d.get("y", 0.0)
	c.jump_pressed = d.get("jp", false)
	c.dodge_pressed = d.get("dp", false)
	c.jump_held = d.get("jh", false)
	c.sprint_held = d.get("sh", false)
	c.fire_pressed = d.get("fp", false)
	c.fire_held = d.get("fh", false)
	c.aim_origin = d.get("ao", Vector3.ZERO)
	c.aim_dir = d.get("ad", Vector3.FORWARD)
	return c
