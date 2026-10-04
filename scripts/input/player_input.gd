class_name PlayerInput
extends Node
## Base input source for a player. Produces one PlayerCommand per physics tick.
## Subclass for local devices (LocalPlayerInput), and later for network/AI sources.


func get_command() -> PlayerCommand:
	return PlayerCommand.new()
