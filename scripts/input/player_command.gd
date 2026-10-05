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
## Selected targets per weapon slot (Targetable.target_id, 0 = none): RIGHT
## and LEFT. Each slot's weapon auto-fires at its own.
var target_id := 0
var target_id_left := 0


func to_dict() -> Dictionary:
	return {
		"m": move,
		"y": view_yaw,
		"jp": jump_pressed,
		"dp": dodge_pressed,
		"jh": jump_held,
		"sh": sprint_held,
		"t": target_id,
		"tl": target_id_left,
	}


static func from_dict(d: Dictionary) -> PlayerCommand:
	var c := PlayerCommand.new()
	c.move = d.get("m", Vector2.ZERO)
	c.view_yaw = d.get("y", 0.0)
	c.jump_pressed = d.get("jp", false)
	c.dodge_pressed = d.get("dp", false)
	c.jump_held = d.get("jh", false)
	c.sprint_held = d.get("sh", false)
	c.target_id = d.get("t", 0)
	c.target_id_left = d.get("tl", 0)
	return c
