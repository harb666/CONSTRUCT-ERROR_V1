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


## Simulated finger tap at a UI position (converted to window pixels).
func _tap(tc: TouchControls, ui_pos: Vector2) -> void:
	var xf := root.get_final_transform()
	var ev := InputEventScreenTouch.new()
	ev.index = 3
	ev.pressed = true
	ev.position = xf * ui_pos
	Input.parse_input_event(ev)
	await _ticks(3)
	ev = ev.duplicate()
	ev.pressed = false
	Input.parse_input_event(ev)
	await _ticks(1)


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
	var spawner: WeaponSpawner = pad.get_node("WeaponSpawner")
	var holder: WeaponHolder = p.get_node("WeaponHolder")
	_check(spawner.display != null, "weapon floats above the pad")
	var y_a := spawner.display.global_position.y
	var rot_a := spawner._pivot.rotation.y
	await _ticks(20)
	_check(absf(spawner._pivot.rotation.y - rot_a) > 0.05, "display spins")
	_check(absf(spawner.display.global_position.y - y_a) > 0.001, "display bobs")
	var shown_core: BlackHoleCore = (spawner.display as BlackHoleGenerator).core
	_check(shown_core != null and shown_core.global_position.distance_to(spawner.display.find_marker("Black_Hole_Projectile_Spawn").global_position) < 0.001, "black hole sits in the display gun's chamber")
	var tumble_a := shown_core.global_basis
	await _ticks(10)
	_check(not shown_core.global_basis.is_equal_approx(tumble_a), "black hole tumbles in the chamber")
	_check(shown_core.global_position.distance_to(spawner.display.find_marker("Black_Hole_Projectile_Spawn").global_position) < 0.001, "black hole stays centred while tumbling")
	var core_anim: AnimationPlayer = shown_core.find_child("AnimationPlayer", true, false)
	_check(core_anim.is_playing() and core_anim.current_animation == "Accretion_Disk_Rotation", "black hole animation plays")
	_check(holder.current == null, "player starts unarmed")
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
	_check(top_y > 0.12, "walks up onto the pad (%.2f m)" % top_y)
	_check(air_ticks < 6, "stays grounded crossing the pad (%d airborne ticks)" % air_ticks)
	_check(p.global_position.z < pad.global_position.z - 1.5, "walks across and off the far side")
	_check(spawner.display == null, "pickup removes the floating display")
	_check(holder.current is BlackHoleGenerator, "Black Hole Generator equipped")
	var gun := holder.current as BlackHoleGenerator
	await _ticks(5)
	var chamber := gun.find_marker("Black_Hole_Projectile_Spawn")
	_check(gun.core != null and chamber.is_ancestor_of(gun.core) and gun.core.global_position.distance_to(chamber.global_position) < 0.001, "black hole stays in the equipped gun's chamber")
	var fore := gun.global_basis.x.normalized()
	_check(fore.dot(-p.global_basis.z) > 0.7, "equipped gun points forward (%.2f)" % fore.dot(-p.global_basis.z))
	_check(gun.global_basis.y.normalized().dot(Vector3.UP) > 0.7, "equipped gun is upright")
	# Same at sprint speed, coming from the other side.
	p.global_position = pad.global_position + Vector3(0, 0.05, -5.0)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	await _ticks(10)
	top_y = 0.0
	air_ticks = 0
	Input.action_press("move_back")
	Input.action_press("sprint")
	for i in 50:
		await _ticks(1)
		top_y = maxf(top_y, p.global_position.y - pad.global_position.y)
		if not p.is_on_floor():
			air_ticks += 1
	Input.action_release("move_back")
	Input.action_release("sprint")
	_check(top_y > 0.12, "sprints up onto the pad (%.2f m)" % top_y)
	_check(air_ticks < 6, "stays grounded sprinting across (%d airborne ticks)" % air_ticks)
	_check(p.global_position.z > pad.global_position.z + 1.5, "sprints off the far side")

	# Tap-to-target auto fire.
	var rig: CameraRig = main.get_node("CameraRig")
	var tc2: TouchControls = main.get_node("UI/TouchControls")
	var lock: TargetLock = p.get_node("TargetLock")
	var selector: TargetSelector = p.get_node("Input/TargetSelector")
	var d1: TargetDummy = main.get_node("Targets/Dummy1")
	var d2: TargetDummy = main.get_node("Targets/Dummy2")
	p.global_position = Vector3(1.0, 0.05, 2.0)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	rig.yaw = 0.0
	rig.pitch = deg_to_rad(-8)
	await _ticks(30)
	var shots: Array = []
	holder.weapon_fired.connect(func(_w) -> void: shots.append(1))
	var projs: Array = []
	(holder.current as BlackHoleGenerator).fired.connect(func(pr: BlackHoleProjectile) -> void: projs.append(pr))

	# Tap a little off the dummy's mesh: must still select it (forgiving).
	await _tap(tc2, rig.camera.unproject_position(d2.get_node("Targetable").get_aim_point()) + Vector2(35, 20))
	await _ticks(2)
	_check(lock.current == d2.get_node("Targetable"), "tap near enemy locks it")
	for i in 90:
		await _ticks(1)
		if shots.size() > 0:
			break
	_check(shots.size() > 0, "auto-fires at the locked enemy")
	# Recoil: sharp kick right at launch, then recovery; movement unaffected.
	var anim2: CharacterAnimator = p.get_node("Visual/GrinchVisual")
	var rig2: CameraRig = main.get_node("CameraRig")
	var kick_peak := 0.0
	var cam_kicked := false
	var launched := false
	for i in 40:
		await process_frame
		if projs.size() > 0:
			launched = true
		kick_peak = maxf(kick_peak, anim2.recoil)
		cam_kicked = cam_kicked or rig2.camera.fov > rig2._base_fov + 1.0
	_check(launched and kick_peak > 0.6, "heavy recoil kick on launch (peak %.2f)" % kick_peak)
	_check(not cam_kicked, "no camera shake on launch")
	await _ticks(60)
	_check(absf(anim2.recoil) < 0.1 and absf(rig2.camera.fov - rig2._base_fov) < 0.01, "recoil and camera recover")
	var n_before := projs.size()
	for i in 240:
		await _ticks(1)
		if projs.size() > n_before:
			break
	if projs.size() > n_before:
		var pr: BlackHoleProjectile = projs[n_before]
		_check(pr._size < 0.4, "fired black hole is still chamber-sized leaving the gun (%.2f m)" % pr._size)
		await _ticks(12)
		_check(is_instance_valid(pr) and pr._size > 2.5, "then expands to ~3 m (%.2f m)" % (pr._size if is_instance_valid(pr) else -1.0))
		if is_instance_valid(pr):
			_check(pr.collision_radius > 0.5, "collision radius scales with it (%.2f m)" % pr.collision_radius)
			var bolts := 0
			for i in 20:
				await _ticks(1)
				if not is_instance_valid(pr):
					break
				for n in pr.find_children("*", "MeshInstance3D", true, false):
					if n.mesh is ImmediateMesh and n.visible:
						bolts += 1
			_check(bolts > 0, "electric bolts lash out while in flight")
	var h0 := d2.hits
	for i in 60:
		await _ticks(1)
		if d2.hits > h0:
			break
	_check(d2.hits > h0, "shot hits the locked enemy")

	# Independent movement while locked: strafe right, legs follow movement.
	var shots_before := shots.size()
	Input.action_press("move_right")
	await _ticks(90)
	_check(Vector2(p.velocity.x, p.velocity.z).length() > 5.0, "strafes at full speed while locked")
	_check(p.is_facing_yaw(-PI * 0.5, 0.3), "legs/body face the movement direction while locked")
	_check(shots.size() > shots_before, "keeps firing while strafing")
	var gun2 := holder.current
	var to_t := (lock.get_aim_point() - gun2.global_position).normalized()
	_check(gun2.get_barrel_direction().angle_to(to_t) < deg_to_rad(30), "upper body/weapon tracks the target while moving (%.0f deg)" % rad_to_deg(gun2.get_barrel_direction().angle_to(to_t)))
	Input.action_release("move_right")
	await _ticks(30)

	# Tap the same enemy again: unlock and stop firing.
	await _tap(tc2, rig.camera.unproject_position(d2.get_node("Targetable").get_aim_point()))
	await _ticks(3)
	_check(not lock.has_target(), "tapping the same enemy unlocks")
	var shots_after_unlock := shots.size()
	await _ticks(90)
	_check(shots.size() == shots_after_unlock, "stops firing when unlocked")

	# Tap empty floor: nothing selected.
	await _tap(tc2, Vector2(tc2.size.x * 0.5, tc2.size.y * 0.9))
	await _ticks(3)
	_check(not lock.has_target(), "tapping empty space selects nothing")

	# Lock one enemy, then tap another: switches immediately.
	await _tap(tc2, rig.camera.unproject_position(d2.get_node("Targetable").get_aim_point()))
	await _ticks(3)
	await _tap(tc2, rig.camera.unproject_position(d1.get_node("Targetable").get_aim_point()))
	await _ticks(3)
	_check(lock.current == d1.get_node("Targetable"), "tapping a different enemy switches lock")

	# Enemy dies: lock clears and firing stops.
	for i in 900:
		await _ticks(1)
		if not lock.has_target():
			break
	_check(d1.health <= 0 and not lock.has_target(), "lock clears when the enemy dies")
	_check(selector.selected == null, "selection clears when the enemy dies")
	var shots_dead := shots.size()
	await _ticks(60)
	_check(shots.size() == shots_dead, "stops firing after the kill")
	await _ticks(260)
	_check(d1.health == d1.max_health and d1.visible, "dummy respawns")

	# Out of range: lock clears.
	await _tap(tc2, rig.camera.unproject_position(d2.get_node("Targetable").get_aim_point()))
	await _ticks(3)
	_check(lock.has_target(), "re-lock before range test")
	p.global_position = Vector3(2.0, 0.05, 35.0)
	p.reset_physics_interpolation()
	await _ticks(3)
	_check(not lock.has_target(), "lock clears when the enemy is out of range")

	print("FAILURES: %d" % _failures)
	quit(1 if _failures else 0)
