class_name LocalPlayerInput
extends PlayerInput
## Reads this device's keyboard / gamepad / touch controls.
## Also drives look for the local camera rig (look is client-side only).

## Gamepad look speed in radians/second at full stick deflection.
@export var gamepad_look_speed := Vector2(3.5, 2.5)
## Mouse look (desktop testing) in radians/pixel.
@export var mouse_sensitivity := 0.004

var camera_rig: CameraRig

# Edges are detected per physics tick from held state, so a press is never
# lost or doubled regardless of how render frames and physics ticks line up.
var _prev_jump := false
var _prev_dodge := false


func get_command() -> PlayerCommand:
	var c := PlayerCommand.new()
	c.move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	c.view_yaw = camera_rig.yaw if camera_rig else 0.0
	c.jump_held = Input.is_action_pressed("jump")
	var dodge_held := Input.is_action_pressed("dodge")
	c.jump_pressed = c.jump_held and not _prev_jump
	c.dodge_pressed = dodge_held and not _prev_dodge
	_prev_jump = c.jump_held
	_prev_dodge = dodge_held
	c.sprint_held = Input.is_action_pressed("sprint")
	return c


func _process(delta: float) -> void:
	if camera_rig == null:
		return
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick != Vector2.ZERO:
		camera_rig.add_look(Vector2(stick.x * gamepad_look_speed.x, stick.y * gamepad_look_speed.y) * delta)


## Called by the touch UI with a drag delta already converted to radians.
func add_touch_look(radians: Vector2) -> void:
	if camera_rig:
		camera_rig.add_look(radians)


func _unhandled_input(event: InputEvent) -> void:
	# Desktop testing: hold left/right mouse button and drag to look.
	if event is InputEventMouseMotion and event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT):
		if camera_rig:
			camera_rig.add_look(event.relative * mouse_sensitivity)
