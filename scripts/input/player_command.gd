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


func to_dict() -> Dictionary:
	return {
		"m": move,
		"y": view_yaw,
		"jp": jump_pressed,
		"dp": dodge_pressed,
		"jh": jump_held,
		"sh": sprint_held,
	}


static func from_dict(d: Dictionary) -> PlayerCommand:
	var c := PlayerCommand.new()
	c.move = d.get("m", Vector2.ZERO)
	c.view_yaw = d.get("y", 0.0)
	c.jump_pressed = d.get("jp", false)
	c.dodge_pressed = d.get("dp", false)
	c.jump_held = d.get("jh", false)
	c.sprint_held = d.get("sh", false)
	return c
