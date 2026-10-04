extends SceneTree
## Headless smoke test: godot --headless --path . -s tests/movement_smoke_test.gd
## Drives the local player with input actions and checks basic movement works.

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		_failures += 1


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _ticks(30)
	var p: PlayerController = main.players[1]
	var anim: CharacterAnimator = p.get_node("Visual/GrinchVisual")
	_check(p.is_on_floor(), "player starts grounded")
	_check(anim.current_state == "Locomotion", "anim idle in Locomotion")

	# Walk forward (camera-relative: camera starts behind, so forward = -Z).
	var z0 := p.global_position.z
	Input.action_press("move_forward")
	await _ticks(30)
	var walk := Vector2(p.velocity.x, p.velocity.z).length()
	_check(absf(walk - p.walk_speed) < 0.2, "reaches walk speed in 0.5s (%.2f)" % walk)
	_check(p.global_position.z < z0 - 1.0, "moved forward")

	Input.action_press("sprint")
	await _ticks(20)
	var sprint := Vector2(p.velocity.x, p.velocity.z).length()
	_check(absf(sprint - p.sprint_speed) < 0.2, "reaches sprint speed (%.2f)" % sprint)
	_check(anim.current_state == "Locomotion", "anim sprint stays Locomotion")
	_check(anim._arm_aim.weight > 0.9, "arms aim forward while sprinting (%.2f)" % anim._arm_aim.weight)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _ticks(20)
	_check(Vector2(p.velocity.x, p.velocity.z).length() < 0.1, "stops after release")
	_check(anim._arm_aim.weight > 0.02 and anim._arm_aim.weight < 0.3, "arms ease down after stopping (%.2f)" % anim._arm_aim.weight)
	Input.action_press("move_forward", 0.4)
	await _ticks(30)
	_check(anim._arm_aim.weight < 0.05, "arms not aiming while walking (%.2f)" % anim._arm_aim.weight)
	Input.action_release("move_forward")
	await _ticks(30)

	# Jump + double jump.
	var y0 := p.global_position.y
	Input.action_press("jump")
	await _ticks(2)
	_check(not p.is_on_floor() and p.velocity.y > 0.0, "jump leaves ground")
	await process_frame
	_check(anim.current_state == "Jump", "anim Jump on jump (%s)" % anim.current_state)
	var peak := y0
	for i in 20:
		await _ticks(1)
		peak = maxf(peak, p.global_position.y)
	Input.action_release("jump")
	await _ticks(1)
	Input.action_press("jump")
	await _ticks(1)
	Input.action_release("jump")
	await _ticks(1)
	_check(p.velocity.y > 5.0, "double jump fires in air (vy %.2f)" % p.velocity.y)
	await process_frame
	_check(anim.current_state == "AirJump", "anim AirJump on double jump (%s)" % anim.current_state)
	var peak2 := peak
	for i in 18:
		await _ticks(1)
		peak2 = maxf(peak2, p.global_position.y)
	_check(peak - y0 > 1.5, "first jump height %.2f" % (peak - y0))
	_check(peak2 > peak + 0.8, "double jump goes higher (%.2f)" % (peak2 - y0))
	# Triple jump must not happen.
	Input.action_press("jump")
	await _ticks(1)
	Input.action_release("jump")
	_check(p.velocity.y <= 0.0 or p.is_on_floor(), "no third jump")
	var saw_fall := false
	var saw_land := false
	for i in 90:
		await _ticks(1)
		saw_fall = saw_fall or anim.current_state == "Fall"
		saw_land = saw_land or anim.current_state == "Land"
	_check(p.is_on_floor(), "lands again")
	_check(saw_fall, "anim Fall while descending")
	_check(saw_land, "anim Land on hard landing")
	_check(anim.current_state == "Locomotion", "anim back to Locomotion (%s)" % anim.current_state)

	# Dodge to the right.
	var x0 := p.global_position.x
	Input.action_press("move_right")
	Input.action_press("dodge")
	await _ticks(2)
	_check(p.is_dodging, "dodge starts")
	await process_frame
	_check(anim.current_state == "Dodge", "anim Dodge (%s)" % anim.current_state)
	Input.action_release("dodge")
	Input.action_release("move_right")
	await _ticks(20)
	_check(not p.is_dodging, "dodge ends")
	_check(p.global_position.x > x0 + 3.0, "dodge moved right %.2f m" % (p.global_position.x - x0))

	# Touch controls: simulate a finger on the left stick and a tap on JUMP.
	await _ticks(40)
	var tc: TouchControls = main.get_node("UI/TouchControls")
	# Injected events are in window pixels; the UI works in stretched logical units.
	var xf := root.get_final_transform()
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = xf * Vector2(200, 500)
	Input.parse_input_event(down)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = xf * Vector2(200, 400)
	Input.parse_input_event(drag)
	var tap := InputEventScreenTouch.new()
	tap.index = 1
	tap.pressed = true
	tap.position = xf * tc._button_center(0)
	Input.parse_input_event(tap)
	await _ticks(10)
	_check(Vector2(p.velocity.x, p.velocity.z).length() > 3.0, "touch stick moves player")
	_check(not p.is_on_floor(), "touch JUMP (second finger) jumps")
	tap.pressed = false
	Input.parse_input_event(tap)
	down.pressed = false
	Input.parse_input_event(down)

	# Weapon spawn pad: walk straight across it without jumping.
	var pad: Node3D = main.get_node("WeaponSpawnPad")
	p.global_position = pad.global_position + Vector3(0, 0.05, 4.0)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	await _ticks(10)
	var top_y := 0.0
	var air_ticks := 0
	Input.action_press("move_forward")
	for i in 60:
		await _ticks(1)
		top_y = maxf(top_y, p.global_position.y - pad.global_position.y)
		if not p.is_on_floor():
			air_ticks += 1
	Input.action_release("move_forward")
	_check(top_y > 0.25, "walks up onto the pad (%.2f m)" % top_y)
	_check(air_ticks < 6, "stays grounded crossing the pad (%d airborne ticks)" % air_ticks)
	_check(p.global_position.z < pad.global_position.z - 1.5, "walks across and off the far side")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures else 0)
