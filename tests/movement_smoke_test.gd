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
	# Robots stand still for the deterministic checks; the combat test
	# turns their AI on.
	RobotEnemy.ai_enabled = false
	# The old test arena: these checks rely on its known layout. The game
	# itself (scenes/main.tscn) runs in Toxic Arena, checked at the end.
	var main: Node = load("res://scenes/test_arena.tscn").instantiate()
	root.add_child(main)
	await _ticks(30)
	var p: PlayerController = main.players[1]
	var anim: CharacterAnimator = p.get_node("Visual/GrinchVisual")
	_check(p.is_on_floor(), "player starts grounded")
	_check(anim.current_state == "Locomotion", "anim idle in Locomotion")

	# Stick push picks the gait: light = walk, firmer = run, (nearly) all the
	# way = sprint, held for as long as it stays there.
	var gait_start := p.global_transform
	var z0 := p.global_position.z
	Input.action_press("move_forward", 0.45)  # 0.31 after the 0.2 dead zone
	await _ticks(20)
	var walk := Vector2(p.velocity.x, p.velocity.z).length()
	_check(walk > 1.5 and walk <= p.walk_speed + 0.05 and not p.is_sprinting, "light push walks (%.2f m/s)" % walk)
	_check(p.global_position.z < z0, "moved forward")
	Input.action_press("move_forward", 0.8)  # 0.75
	await _ticks(20)
	var run := Vector2(p.velocity.x, p.velocity.z).length()
	_check(run >= p.run_min_speed and run <= p.run_speed + 0.05 and not p.is_sprinting, "firmer push runs (%.2f m/s)" % run)
	_check(anim._arm_aim.weight > 0.9, "arms aim forward while running (%.2f)" % anim._arm_aim.weight)
	Input.action_press("move_forward", 1.0)
	await _ticks(15)
	var sprint := Vector2(p.velocity.x, p.velocity.z).length()
	_check(p.is_sprinting and absf(sprint - p.sprint_speed) < 0.2, "full push sprints (%.2f m/s)" % sprint)
	_check(anim.current_state == "Locomotion", "anim sprint stays Locomotion")
	Input.action_press("move_forward", 0.86)  # 0.825: inside the hysteresis band
	await _ticks(6)
	_check(p.is_sprinting, "sprint holds while the stick stays near the edge")
	Input.action_press("move_forward", 0.8)
	await _ticks(12)
	_check(not p.is_sprinting and Vector2(p.velocity.x, p.velocity.z).length() < p.run_speed + 0.1, "easing off drops back to a run")
	Input.action_release("move_forward")
	await _ticks(20)
	_check(Vector2(p.velocity.x, p.velocity.z).length() < 0.1, "stops after release")
	_check(anim._arm_aim.weight > 0.02 and anim._arm_aim.weight < 0.3, "arms ease down after stopping (%.2f)" % anim._arm_aim.weight)
	# Back to the start (the gaits covered more ground than later tests expect).
	p.global_transform = gait_start
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
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
	var slide_end := {}
	p.dodge_ended.connect(func(_d: Vector3, _f: bool) -> void: slide_end.pos = p.global_position, CONNECT_ONE_SHOT)
	await _ticks(17)
	_check(p.is_dodging, "dodge still sliding after 0.3 s (longer slide)")
	await _ticks(10)
	_check(not p.is_dodging, "dodge ends")
	_check(p.global_position.x > x0 + 4.5, "dodge moved right %.2f m" % (p.global_position.x - x0))
	var dust: Array = p.get_parent().get_children().filter(func(n: Node) -> bool: return n is DodgeDust)
	_check(dust.size() == 1, "slide end kicks up one dust puff (%d)" % dust.size())
	if dust.size() == 1:
		var dp: Vector3 = dust[0].global_position
		var feet: Vector3 = slide_end.get("pos", Vector3.INF)
		_check(dp.distance_to(feet) < 0.8, "dust at the feet where the slide ended (%s vs %s)" % [dp, feet])
		await _ticks(60)
		_check(not is_instance_valid(dust[0]), "dust puff fades and frees itself")

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
	_check(TouchControls.BUTTONS.all(func(b: Dictionary) -> bool: return b.action != "sprint"), "no SPRINT touch button (the stick sprints)")
	tap.pressed = false
	Input.parse_input_event(tap)
	down.pressed = false
	Input.parse_input_event(down)

	# Weapon spawn pad: walk straight across it without jumping.
	var pad: Node3D = main.get_node("WeaponSpawnPad")
	var spawner: WeaponSpawner = pad.get_node("WeaponSpawner")
	var holder: WeaponHolder = p.get_node("WeaponHolder")
	_check(spawner.display != null, "weapon floats above the pad")
	var gun_box := AABB()
	var gun_first := true
	for mi: MeshInstance3D in spawner.display.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh is ArrayMesh:
			var ab: AABB = mi.global_transform * mi.mesh.get_aabb()
			gun_box = ab if gun_first else gun_box.merge(ab)
			gun_first = false
	var off := gun_box.get_center() - pad.global_position
	_check(Vector2(off.x, off.z).length() < 0.05, "gun is centred over the pad (%.2f m off)" % Vector2(off.x, off.z).length())
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
	# Default dual wield: a cannon on each forearm, separate instances.
	var spawn_r := holder.weapon("Right")
	var spawn_l := holder.weapon("Left")
	_check(spawn_r is PlasmaCannon and spawn_l is PlasmaCannon and spawn_r != spawn_l, "spawns with a default cannon in each slot")
	var loadout0: WeaponLoadout = p.get_node("WeaponLoadout")
	_check(loadout0.unlocked_weapons().size() == 1 and loadout0.unlocked_weapons()[0] == holder.default_weapon, "session starts with only the Default Cannon unlocked")
	_check(spawn_r.get_parent() is BoneAttachment3D and (spawn_r.get_parent() as BoneAttachment3D).bone_name == "mixamorig_RightForeArm"
		and (spawn_l.get_parent() as BoneAttachment3D).bone_name == "mixamorig_LeftForeArm", "cannons mounted on the right and left forearms")
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
	_check(holder.current is BlackHoleGenerator and holder.weapon("Right") is BlackHoleGenerator, "Black Hole Generator equipped in the RIGHT slot")
	_check(holder.weapon("Left") == spawn_l and is_instance_valid(spawn_l), "LEFT slot keeps its default cannon")
	_check(loadout0.is_unlocked((pad as WeaponSpawnPad).weapon) and loadout0.unlocked_weapons().size() == 2, "first pickup unlocks the Black Hole Generator for the session")
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

	# Tap-to-target auto fire (gravity wells off here so the dummies stay
	# put; wells are tested separately below).
	BlackHoleProjectile.gravity_wells_enabled = false
	var rig: CameraRig = main.get_node("CameraRig")
	var tc2: TouchControls = main.get_node("UI/TouchControls")
	var lock: TargetLock = p.get_node("TargetLock")
	var selector: TargetSelector = p.get_node("Input/TargetSelector")
	var d1: RobotEnemy = main.get_node("Targets/Robot1")
	var d2: RobotEnemy = main.get_node("Targets/Robot2")
	# Hold still for the targeting checks; quick corpse/respawn.
	for r: RobotEnemy in [d1, d2]:
		r.patrol_distance = 0.0
		r.corpse_time = 1.0
		r.respawn_time = 0.5
	# The tracking target must survive several hits.
	d2.max_health = 50.0
	d2.health = 50.0
	p.global_position = Vector3(1.0, 0.05, 2.0)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	rig.yaw = 0.0
	rig.pitch = deg_to_rad(-8)
	await _ticks(30)
	# Real cooldown is 15 s; shorten it so the repeat-fire checks stay quick.
	(holder.current as BlackHoleGenerator).recharge_delay = 0.6
	(holder.current as BlackHoleGenerator).recharge_grow = 0.4
	var shots: Array = []
	holder.slot_fired.connect(func(side: String, _w) -> void:
		if side == "Right":
			shots.append(1))
	var left_shots: Array = []
	holder.slot_fired.connect(func(side: String, _w) -> void:
		if side == "Left":
			left_shots.append(1))
	var lock_l: TargetLock = p.get_node("TargetLockLeft")
	var projs: Array = []
	var stuck_on: Array = []
	var hits_at_lock := d2.hits
	(holder.current as BlackHoleGenerator).fired.connect(func(pr: BlackHoleProjectile) -> void:
		projs.append(pr)
		pr.impacted.connect(func(_at: Vector3, col: Object) -> void: stuck_on.append(col)))

	# Tap a little off the robot's mesh: must still select it (forgiving).
	# (On the side away from the other robots: a patrolling one can stand
	# just behind it on screen, and a tap nearer to that one is meant for it.)
	var d2_px := rig.camera.unproject_position(d2.get_node("Targetable").get_aim_point())
	var near_off := Vector2(35, 20)
	for o: Vector2 in [Vector2(35, 20), Vector2(-35, 20), Vector2(35, -20), Vector2(-35, -20)]:
		if selector.pick(d2_px + o) == d2.get_node("Targetable"):
			near_off = o
			break
	await _tap(tc2, d2_px + near_off)
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
	var fire_sound := false
	for i in 40:
		await process_frame
		if projs.size() > 0 and not launched:
			launched = true
			fire_sound = _sound_playing(holder.current, Sfx.BH_FIRE)
		kick_peak = maxf(kick_peak, anim2.recoil)
		cam_kicked = cam_kicked or rig2.camera.fov > rig2._base_fov + 1.0
	_check(launched and kick_peak > 0.6, "heavy recoil kick on launch (peak %.2f)" % kick_peak)
	_check(not cam_kicked, "no camera shake on launch")
	_check(fire_sound, "gun fire sound plays as the shot leaves the barrel")
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
	_check(d2.hits > hits_at_lock, "shot hits the locked enemy")

	# Independent movement while locked: strafe right (running), legs follow
	# movement.
	var shots_before := shots.size()
	Input.action_press("move_right", 0.8)
	await _ticks(90)
	_check(Vector2(p.velocity.x, p.velocity.z).length() > 5.0, "strafes at running speed while locked")
	_check(p.is_facing_yaw(-PI * 0.5, 0.3), "legs/body face the movement direction while locked")
	_check(shots.size() > shots_before, "keeps firing while strafing")
	var gun2 := holder.current
	var to_t := (lock.get_aim_point() - gun2.global_position).normalized()
	_check(gun2.get_barrel_direction().angle_to(to_t) < deg_to_rad(30), "upper body/weapon tracks the target while moving (%.0f deg)" % rad_to_deg(gun2.get_barrel_direction().angle_to(to_t)))
	Input.action_release("move_right")
	await _ticks(30)

	# Tap the same enemy again: unlock and stop firing.
	selector.forget_last_tap()
	await _tap(tc2, rig.camera.unproject_position(d2.get_node("Targetable").get_aim_point()))
	await _ticks(3)
	_check(not lock.has_target(), "tapping the same enemy unlocks")
	var shots_after_unlock := shots.size()
	await _ticks(90)
	_check(shots.size() == shots_after_unlock, "stops firing when unlocked")

	# Tap empty floor: nothing selected. (Patrolling robots are wherever
	# their patrol has got to, so use a spot with no robot near it.)
	var empty_px := Vector2(tc2.size.x * 0.5, tc2.size.y * 0.9)
	for o: Vector2 in [Vector2(0.5, 0.9), Vector2(0.3, 0.9), Vector2(0.7, 0.9), Vector2(0.5, 0.8)]:
		if selector.pick(tc2.size * o) == null:
			empty_px = tc2.size * o
			break
	await _tap(tc2, empty_px)
	await _ticks(3)
	_check(not lock.has_target(), "tapping empty space selects nothing")

	# Lock one enemy (RIGHT), then tap another: the LEFT slot takes it.
	selector.forget_last_tap()
	await _tap(tc2, rig.camera.unproject_position(d2.get_node("Targetable").get_aim_point()))
	await _ticks(3)
	await _tap(tc2, rig.camera.unproject_position(d1.get_node("Targetable").get_aim_point()))
	await _ticks(3)
	_check(lock_l.current == d1.get_node("Targetable") and lock.current == d2.get_node("Targetable"), "second enemy goes to the LEFT slot, RIGHT keeps the first")

	# Left slot's enemy dies: only that slot clears; its firing stops.
	for i in 900:
		await _ticks(1)
		if not lock_l.has_target():
			break
	_check(d1.health <= 0 and not lock_l.has_target(), "left lock clears when its enemy dies")
	_check(selector.selected_left == null and selector.selected == d2.get_node("Targetable") and lock.has_target(), "only the left selection clears; right stays locked")
	var shots_dead := left_shots.size()
	await _ticks(60)
	_check(left_shots.size() == shots_dead, "left cannon stops firing after the kill")
	selector.clear()
	await _ticks(260)
	_check(d1.alive and d1.health == d1.max_health and d1.get_node("Targetable").is_valid_target(), "robot respawns")

	# Out of range: lock clears.
	selector.forget_last_tap()
	await _tap(tc2, rig.camera.unproject_position(d2.get_node("Targetable").get_aim_point()))
	await _ticks(3)
	_check(lock.has_target(), "re-lock before range test")
	p.global_position = Vector3(2.0, 0.05, 35.0)
	p.reset_physics_interpolation()
	await _ticks(3)
	_check(not lock.has_target(), "lock clears when the enemy is out of range")

	await _gravity_well_tests(main, p, holder)
	await _cooldown_audio_tests(main)
	await _robot_tests(main)
	await _flight_gravity_tests(main)
	await _supernova_finish_tests(main)
	await _robot_combat_tests(main)
	await _dual_wield_tests(main)
	await _shotgun_tests(main)
	await _robot_death_variety_tests(main)
	await _weapon_fit_tests(main)
	await _weapon_socket_tests(main)
	await _weapon_switch_tests(main)
	await _mesh_cap_tests(main)
	var t := Node3D.new()
	t.name = "Targets"
	var fake := Node3D.new()
	fake.add_child(t)
	main.add_child(fake)
	StressTest.populate(fake, 30)
	await _ticks(5)
	_check(t.get_child_count() == 30, "stress test spawns 30 robots")
	fake.queue_free()
	await _ticks(2)
	main.queue_free()
	await _ticks(5)
	await _toxic_arena_tests()
	print("FAILURES: %d" % _failures)
	quit(1 if _failures else 0)


func _gravity_well_tests(main: Node, p: PlayerController, holder: WeaponHolder) -> void:
	BlackHoleProjectile.gravity_wells_enabled = true
	await _ticks(120)
	var crate: RigidBody3D = main.get_node("Props/Crate1")
	var heavy: RigidBody3D = main.get_node("Props/HeavyBlock")
	var gun := holder.current as BlackHoleGenerator
	# Fire straight at the floor next to the crate, with the player far away.
	p.global_position = Vector3(-14.0, 0.05, -2.0)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	await _ticks(30)
	var spot := crate.global_position + Vector3(1.5, 0.0, 0.5)
	spot.y = 0.0
	var pr: BlackHoleProjectile = gun.projectile_scene.instantiate()
	main.add_child(pr)
	pr.global_position = spot + Vector3(0, 1.4, 0)
	var core: BlackHoleCore = gun.core_scene.instantiate()
	core.scale = Vector3.ONE * 0.28
	pr.launch(core, Vector3.DOWN, p)
	pr._travelled = 2.0
	_check(pr._hum != null and pr._hum.stream == Sfx.BH_LOOP and pr._hum.playing, "energy hum plays as soon as it leaves the barrel")
	var h: DynamicSound = pr._hum
	_check(h.distance_gain(1.0) == 1.0 and h.distance_gain(15.0) < 0.6 and h.distance_gain(15.0) > 0.05 and h.distance_gain(h.far + 1.0) == 0.0,
		"sounds are loud close up, quieter further away, silent far off")
	await _ticks(2)
	var far_gain := h.gain
	_check(far_gain < 0.9, "energy hum is quieter with the player %.0f m away (%.2f)" % [p.global_position.distance_to(pr.global_position), far_gain])
	_check(pr.explode_volume_db > maxf(maxf(pr.loop_volume_db, pr.charge_volume_db), maxf(pr.burst_volume_db, gun.fire_volume_db)), "explosion is the loudest sound")
	var crate_d0 := crate.global_position.distance_to(spot)
	var heavy_d0 := heavy.global_position.distance_to(spot)
	for i in 30:
		await _ticks(1)
		if pr.state == BlackHoleProjectile.State.STUCK_GRAVITY_WELL:
			break
	_check(pr.state == BlackHoleProjectile.State.STUCK_GRAVITY_WELL, "black hole sticks to the floor as a gravity well")
	var trail: VortexTrail = pr._vfx.trail
	_check(trail != null and trail.particle_count() > 0, "purple motes, black dust and mist stream off it (%d)" % (trail.particle_count() if trail else 0))
	var orbit_ok := trail != null and trail.particle_count() > 0
	if orbit_ok:
		var s0: Array = trail.sample(0, 0)
		await _ticks(6)
		var s1: Array = trail.sample(0, 0) if trail.particle_count() > 0 else s0
		orbit_ok = (s1[0] as Vector3).distance_to(s0[0]) < 0.001 and absf(float(s1[2]) - float(s0[2])) > 0.05
	_check(orbit_ok, "wake particles orbit the flight axis (fixed spot on the axis, angle advancing)")
	_check(pr._vfx._lightning.eruption == 0.0, "no lightning eruption yet")
	var stuck_at := pr.global_position
	var sizes: Array = []
	var shrunk := false
	var captured_max := 0
	for i in 150:
		await _ticks(1)
		sizes.append(pr._size)
		var vis: Array = crate.get_meta("gw_visuals", [])
		if vis.size() > 0 and (vis[0][0] as Node3D).scale.x < 0.9:
			shrunk = true
		if pr.well:
			captured_max = maxi(captured_max, pr.well.captured_count())
	_check(pr.global_position.distance_to(stuck_at) < 0.01, "stays stuck at the impact point")
	_check(sizes.max() - sizes.min() > 0.3, "size pulses while stuck (%.2f..%.2f m)" % [sizes.min(), sizes.max()])
	_check(crate.global_position.distance_to(spot) < crate_d0 - 0.5 or captured_max > 0, "light crate is pulled in")
	_check(shrunk, "pulled object shrinks visually near the core")
	_check(captured_max > 0, "objects get captured (%d)" % captured_max)
	_check(absf(crate.scale.x - 1.0) < 0.001, "body's real scale is never changed")
	var heavy_moved := heavy_d0 - heavy.global_position.distance_to(spot)
	_check(heavy_moved < crate_d0 - crate.global_position.distance_to(spot) + 0.01 or captured_max > 0, "heavy block resists more than the light crate")
	# Player inside the field gets pulled but can still move away.
	p.global_position = spot + Vector3(0.0, 0.05, 5.0)
	p.reset_physics_interpolation()
	await _ticks(20)
	_check(p.external_velocity.length() > 1.0, "player feels the pull (%.1f m/s)" % p.external_velocity.length())
	main.get_node("CameraRig").yaw = 0.0
	Input.action_press("move_back")
	Input.action_press("sprint")
	var z0 := p.global_position.z
	var dbg := []  # what the player touched (only reported on failure)
	for i in 40:
		await _ticks(1)
		for k in p.get_slide_collision_count():
			var c := p.get_slide_collision(k).get_collider()
			if c and not dbg.has(c.name): dbg.append(c.name)
	if p.global_position.z <= z0 + 2.0:
		# Rare; say what held the player back if it ever happens.
		print("escape blocked: well at ", spot, ", player ", p.global_position, ", pull ", p.external_velocity, ", velocity ", p.velocity, ", touching ", dbg, ", sprinting ", p.is_sprinting)
	Input.action_release("move_back")
	Input.action_release("sprint")
	_check(p.global_position.z > z0 + 2.0, "player can still sprint out of the pull (%.1f m)" % (p.global_position.z - z0))
	# Wait for collapse + supernova.
	var saw_collapse := false
	var saw_supernova := false
	var burst_lead := -1.0
	var burst_cfg := pr.burst_lead_time
	var hum_until_supernova := true
	var explode_played := false
	var t_now := 0.0
	var charge_last := -1.0
	var supernova_t := -1.0
	var charge_during_stuck := false
	var charge_at_supernova := false
	for i in 400:
		await _ticks(1)
		if not is_instance_valid(pr):
			break
		t_now += 1.0 / Engine.physics_ticks_per_second
		if pr.charge_sound_remaining() > 0.0:
			charge_last = t_now
			charge_during_stuck = charge_during_stuck or pr.state == BlackHoleProjectile.State.STUCK_GRAVITY_WELL
		if supernova_t < 0.0 and pr.state == BlackHoleProjectile.State.SUPERNOVA:
			supernova_t = t_now
			charge_at_supernova = pr.charge_sound_remaining() > 0.0
		if burst_lead < 0.0 and pr._burst_played:
			_check(pr._vfx._lightning.eruption > 0.0 and pr._vfx._lightning.erupt_bolts_alive() > 0, "blue-violet lightning erupts as the burst sound starts")
			burst_lead = pr._time_to_supernova() - pr._state_t
		if pr.state != BlackHoleProjectile.State.SUPERNOVA and not pr._hum.playing:
			hum_until_supernova = false
		if pr.state == BlackHoleProjectile.State.SUPERNOVA and not explode_played:
			explode_played = _sound_playing(main, Sfx.BH_EXPLODE)
			_check(not pr._hum.playing, "energy hum stops at the explosion")
		saw_collapse = saw_collapse or pr.state == BlackHoleProjectile.State.COLLAPSING
		saw_supernova = saw_supernova or pr.state == BlackHoleProjectile.State.SUPERNOVA
	_check(saw_collapse and saw_supernova, "collapses then goes supernova")
	_check(hum_until_supernova, "energy hum keeps playing until the explosion")
	_check(absf(burst_lead - burst_cfg) < 0.1, "energy burst starts %.2f s before the explosion" % burst_lead)
	_check(explode_played, "explosion sound plays at the supernova")
	_check(charge_during_stuck, "black hole charge sound plays while it's stuck")
	_check(not charge_at_supernova and supernova_t - charge_last < 0.25,
		"charge sound ends just before the explosion (%.2f s before)" % (supernova_t - charge_last))
	await _ticks(30)
	_check(not crate.freeze and crate.collision_layer != 0, "captured objects are released with collision restored")
	var vis2: Array = crate.get_meta("gw_visuals", [])
	_check(vis2.is_empty() or absf((vis2[0][0] as Node3D).scale.x - 1.0) < 0.01, "released objects get their normal size back")
	_check(crate.linear_velocity.length() < 30.0 and heavy.linear_velocity.length() < 30.0, "launch speeds stay capped")
	_check(not is_instance_valid(pr), "projectile finishes and frees itself")


func _sound_playing(root: Node, stream: AudioStream) -> bool:
	for n: AudioStreamPlayer3D in root.find_children("*", "AudioStreamPlayer3D", true, false):
		if n.stream == stream and n.playing:
			return true
	return false


func _cooldown_audio_tests(main: Node) -> void:
	var gun: BlackHoleGenerator = load("res://scenes/weapons/black_hole_generator.tscn").instantiate()
	main.add_child(gun)
	gun.global_position = Vector3(0, 30, 0)
	await _ticks(5)
	var bs: BarrelStatic = gun.get_node("BarrelStatic")
	_check(gun.fire_at(null, gun.global_position + Vector3(10, 30, 0)), "test gun fires")
	var fired_at := -1.0
	var sound_at := -1.0
	var peak := 0.0
	var t := 0.0
	var step := 1.0 / Engine.physics_ticks_per_second
	for i in Engine.physics_ticks_per_second * 11:
		await _ticks(1)
		t += step
		if fired_at < 0.0 and gun.core == null:
			fired_at = t
		if sound_at < 0.0 and gun.is_barrel_static_active():
			sound_at = t
		if sound_at < 0.0:
			_check_once(bs.intensity < 0.01, "no barrel static straight after firing")
		peak = maxf(peak, bs.intensity)
	_check(sound_at > 0.0 and absf(sound_at - fired_at - gun.cooldown_static_delay) < 0.15,
		"barrel static starts %.2f s after firing" % (sound_at - fired_at))
	_check(peak > 0.9, "barrel static swells (peak %.2f)" % peak)
	_check(not gun.is_barrel_static_active() and bs.intensity < 0.01, "barrel static dies away")
	_check(gun.find_children("*", "AudioStreamPlayer3D", true, false).filter(func(n: Node) -> bool: return (n as AudioStreamPlayer3D).stream == Sfx.BH_CHARGE).is_empty(),
		"gun no longer plays the charge sound itself")
	gun.queue_free()


var _once_failed := {}
func _check_once(cond: bool, msg: String) -> void:
	if not cond and not _once_failed.has(msg):
		_once_failed[msg] = true
		_check(false, msg)


func _spawn_robot(main: Node, at: Vector3) -> RobotEnemy:
	var r: RobotEnemy = load("res://scenes/enemies/robot_enemy.tscn").instantiate()
	r.patrol_distance = 0.0
	r.respawn_time = -1.0
	main.add_child(r)
	r.global_position = at
	r.reset_physics_interpolation()
	return r


func _robot_tests(main: Node) -> void:
	var spot := Vector3(30, 0, 30)
	var r := _spawn_robot(main, spot)
	await _ticks(10)
	_check(r.get_skeleton() != null and r.get_breaker().sections.size() == 13, "robot model loaded with its 13 detachable sections")
	var anim: AnimationPlayer = r._anim
	for clip in [r.death_anim_electric, r.death_anim_from_front] + r.death_anims_from_behind:
		_check_once(anim.has_animation(clip), "death clip %s exists in the robot GLB" % clip)
	# Destruction level depends on the killing hit (with some randomness).
	var br := r.get_breaker()
	var low := DamageInfo.make(1, DamageInfo.Type.BULLET, spot, Vector3.FORWARD, 2.0, 0.0)
	var mid := DamageInfo.make(3, DamageInfo.Type.EXPLOSION, spot, Vector3.FORWARD, 0.0, 20.0)
	var big := DamageInfo.make(3, DamageInfo.Type.SUPERNOVA, spot, Vector3.FORWARD, 0.0, 42.0)
	var counts := {"low": [0, 0, 0, 0, 0], "mid": [0, 0, 0, 0, 0], "big": [0, 0, 0, 0, 0]}
	for i in 300:
		counts.low[br.choose_level(low)] += 1
		counts.mid[br.choose_level(mid)] += 1
		counts.big[br.choose_level(big)] += 1
	_check(counts.low[0] > 270, "ordinary hits almost always leave the robot whole (%s)" % [counts.low])
	_check(counts.mid[0] < 30 and counts.mid[1] + counts.mid[2] + counts.mid[3] > 200, "explosions mostly break it partly, varied (%s)" % [counts.mid])
	_check(counts.big[4] + counts.big[3] > 270 and counts.big[4] > 120, "point-blank supernova breaks it heavily/extremely (%s)" % [counts.big])

	# Normal death: assembled, death clip, behaviour stops, target invalid.
	var r2 := _spawn_robot(main, spot + Vector3(4, 0, 0))
	await _ticks(10)
	_check(r2.is_whole_mesh() and r2._sections.all(func(m: MeshInstance3D) -> bool: return not m.visible), "living robot draws as one merged mesh")
	var whole_surfaces: int = r2._whole.mesh.get_surface_count()
	_check(whole_surfaces == 2, "merged robot mesh = 2 draw surfaces (was %d section meshes)" % r2._sections.size())
	_check(r2._whole_far != null and r2._whole.visibility_range_end > 0.0 and is_equal_approx(r2._whole_far.visibility_range_begin, r2._whole.visibility_range_end), "swaps to a simpler mesh far away")
	_check(r2._whole.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and r2._shadow_proxy.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "shadow cast by the simple mesh")
	r2.force_death_style = "clip"
	r2.apply_damage(DamageInfo.make(10, DamageInfo.Type.BULLET, r2.global_position + Vector3(0, 1, 2), Vector3(0, 0, -1), 1.0))
	_check(not r2.alive and r2.last_destruction == BreakApart.Level.NONE, "low-force kill: dies whole")
	_check(not r2.is_whole_mesh() and r2._sections.all(func(m: MeshInstance3D) -> bool: return m.visible), "on death it switches to its separate sections")
	_check(r2._whole_far == null and r2._shadow_proxy == null, "far mesh and shadow stand-in removed on death")
	_check(r2._anim.current_animation == String(r2.last_death_anim) and r2.last_death_anim != &"Walking", "plays one of its own death clips (%s)" % r2.last_death_anim)
	_check(not r2.get_node("Targetable").is_valid_target(), "dead robot can't be targeted")
	await _ticks(90)
	_check(r2.get_breaker().detached_count() == 0, "stays assembled")
	_check(Vector2(r2.linear_velocity.x, r2.linear_velocity.z).length() < 0.2, "stops walking when dead")
	_check(JointSparks.active_count() > 0, "subtle electrical failure sparks on the corpse")

	# Extreme breakup: pieces keep their exact pose and fly.
	var r3 := _spawn_robot(main, spot + Vector3(-4, 0, 0))
	await _ticks(10)
	var sk := r3.get_skeleton()
	var head_b := sk.find_bone("mixamorig_Head")
	var cuts: Array[BreakSection] = []
	cuts.assign(r3.get_breaker().sections)
	var head_before := (sk.global_transform * sk.get_bone_global_pose(head_b))
	r3._use_section_meshes()  # as die() does
	await _ticks(1)
	r3.alive = false
	var pieces := r3.get_breaker().detach(cuts, big, Vector3.ZERO)
	_check(pieces.size() == 13, "extreme: every prepared section becomes its own piece (%d)" % pieces.size())
	var head_piece: DebrisPiece = null
	for pc in pieces:
		if pc.section == &"Head":
			head_piece = pc
	var head_after := head_piece.pose.global_transform * head_piece.pose.get_bone_global_pose(head_b) if head_piece else Transform3D()
	_check(head_piece != null and head_after.origin.distance_to(head_before.origin) < 0.01, "detached piece keeps its exact world pose (%.3f m)" % head_after.origin.distance_to(head_before.origin))
	_check(head_piece != null and head_piece.find_children("*", "MeshInstance3D", true, false).size() == 1 and sk.find_children("*", "MeshInstance3D", true, false).is_empty(), "meshes moved off the body onto the pieces (not cut)")
	_check(JointSparks.active_count() >= 6, "sparks at the broken joints (%d)" % JointSparks.active_count())
	var max_v := 0.0
	var min_y := 99.0
	for i in 240:
		await _ticks(1)
		for pc in pieces:
			if is_instance_valid(pc):
				max_v = maxf(max_v, pc.linear_velocity.length())
				min_y = minf(min_y, pc.global_position.y)
	_check(max_v <= 16.01, "debris speed stays clamped (max %.1f m/s)" % max_v)
	_check(min_y > -0.1, "no debris falls through the floor (min y %.2f)" % min_y)
	var resting := 0
	for pc in pieces:
		if is_instance_valid(pc) and (pc.freeze or pc.sleeping or pc.linear_velocity.length() < 0.3):
			resting += 1
	_check(resting == pieces.size(), "debris settles calmly (%d/%d at rest)" % [resting, pieces.size()])
	await _ticks(Engine.physics_ticks_per_second * 3)
	var frozen := pieces.filter(func(pc: DebrisPiece) -> bool: return is_instance_valid(pc) and pc.freeze and not pc.is_physics_processing()).size()
	_check(frozen == pieces.size(), "settled debris is frozen and stops processing (%d/%d)" % [frozen, pieces.size()])
	_check(JointSparks.active_count() == 0, "joint sparks die away")

	# Heavy explosive kill through the real path (cascade of breaks).
	var r4 := _spawn_robot(main, spot + Vector3(0, 0, -5))
	await _ticks(10)
	var blast := DamageInfo.make(5, DamageInfo.Type.EXPLOSION, r4.global_position + Vector3(0, 0.5, 1.5), Vector3(0, 0.2, -1), 0.0, 30.0)
	var tries := 0
	r4.apply_damage(blast)
	await _ticks(45)
	_check(r4.last_destruction >= BreakApart.Level.LIGHT and (r4.last_destruction == BreakApart.Level.LIGHT or r4.get_breaker().detached_count() > 0),
		"explosive kill breaks it apart (%s, %d sections off)" % [BreakApart.Level.keys()[r4.last_destruction], r4.get_breaker().detached_count()])

	# Mobile cap on simultaneous debris.
	var old_max := DebrisPiece.max_active
	DebrisPiece.max_active = 10
	var r5 := _spawn_robot(main, spot + Vector3(4, 0, -5))
	await _ticks(5)
	var all5: Array[BreakSection] = []
	all5.assign(r5.get_breaker().sections)
	r5.alive = false
	r5.get_breaker().detach(all5, big, Vector3.ZERO)
	await _ticks(2)
	_check(DebrisPiece.active_count() <= 10, "active debris capped (%d)" % DebrisPiece.active_count())
	DebrisPiece.max_active = old_max

	# Corpse stops costing anything once its clip ends and it has settled.
	await _ticks(Engine.physics_ticks_per_second * 5)
	_check(not r2.is_physics_processing() and r2.freeze, "settled corpse stops processing")
	# Reaching the black hole's core kills it at once (no lock stays on it);
	# its death/breakup plays out when the supernova throws it out.
	var r6 := _spawn_robot(main, spot + Vector3(-6, 0, 6))
	await _ticks(5)
	var gun: BlackHoleGenerator = load("res://scenes/weapons/black_hole_generator.tscn").instantiate()
	var bh: BlackHoleProjectile = gun.projectile_scene.instantiate()
	main.add_child(bh)
	bh.global_position = r6.global_position + Vector3(2.5, 1.6, 0)
	var bh_core: BlackHoleCore = gun.core_scene.instantiate()
	bh_core.scale = Vector3.ONE * 0.28
	bh.launch(bh_core, Vector3.DOWN, null)
	bh._travelled = 2.0
	var torn_near := -1.0
	var pieces_swallowed := false
	var pieces_shrunk := false
	for i in Engine.physics_ticks_per_second * 8:
		await _ticks(1)
		if torn_near < 0.0 and not r6.alive and is_instance_valid(bh):
			torn_near = (r6.global_position + Vector3.UP * 0.9).distance_to(bh.global_position)
		if is_instance_valid(bh) and bh.well:
			for e in bh.well._captured:
				if e.body is DebrisPiece:
					pieces_swallowed = true
					if (e.body as DebrisPiece).pose.scale.x < 0.5:
						pieces_shrunk = true
	_check(torn_near > 0.0 and torn_near < 2.6 and not r6.get_node("Targetable").is_valid_target(), "enemy near the core dies there, untargetable (%.1f m from it)" % torn_near)
	_check(r6.last_destruction == BreakApart.Level.EXTREME and r6.get_breaker().detached_count() > 0, "and visibly tears apart on the spot")
	_check(pieces_swallowed and pieces_shrunk, "its pieces are pulled in, swallowed and shrunk by the black hole")
	gun.free()

	for n in [r, r2, r3, r4, r5, r6]:
		if is_instance_valid(n):
			n.queue_free()


func _flight_gravity_tests(main: Node) -> void:
	# A black hole flying across open floor past a crate and into a robot.
	var base := Vector3(-30, 0, 30)
	var gun: BlackHoleGenerator = load("res://scenes/weapons/black_hole_generator.tscn").instantiate()
	main.add_child(gun)
	gun.global_position = base + Vector3(0, 1.4, 0)
	gun.global_basis = Basis(Vector3.UP, PI * 0.5)  # barrel (+X) along -Z
	var crate: RigidBody3D = load("res://scenes/props/physics_prop.tscn").instantiate()
	main.add_child(crate)
	crate.global_position = base + Vector3(2.6, 0.3, -20)
	var robot := _spawn_robot(main, base + Vector3(0.6, 0, -9))
	var robot_z := base.z - 9.0
	await _ticks(10)
	var p0 := crate.global_position
	var shots: Array = []
	gun.fired.connect(func(pr: BlackHoleProjectile) -> void: shots.append(pr))
	gun.fire_at(null, base + Vector3(0, 1.4, -30))
	for i in 15:
		await _ticks(1)
		if not shots.is_empty():
			break
	var pr: BlackHoleProjectile = shots[0] if not shots.is_empty() else null
	_check(pr != null and pr.well != null and pr.well.moving, "flying black hole carries its gravity field")
	var sparks: Array = (main.get_children() + main.get_tree().root.get_children()).filter(func(n: Node) -> bool: return n is GravitySparks)
	_check(not sparks.is_empty(), "muzzle flash throws out glowing blue particles")
	var angle0 := -99.0
	var swirled := 0.0
	var passed_robot := false
	var robot_dead := false
	var player: PlayerController = main.players[1]
	var player_v_max := 0.0
	for i in 90:
		await _ticks(1)
		if is_instance_valid(crate):
			var rel := crate.global_position - (base + Vector3(0, 1.4, 0))
			var a := atan2(rel.y, rel.x)
			if angle0 > -90.0:
				swirled += absf(wrapf(a - angle0, -PI, PI))
			angle0 = a
		if is_instance_valid(pr) and pr.state == BlackHoleProjectile.State.TRAVELLING and pr.global_position.z < robot_z - 0.5:
			passed_robot = true
		robot_dead = robot_dead or not robot.alive
		player_v_max = maxf(player_v_max, player.external_velocity.length())
	_check(crate.global_position.distance_to(p0) > 1.0, "props near its path are dragged in (%.1f m)" % crate.global_position.distance_to(p0))
	_check(swirled > 0.6, "and swirl around its flight axis (%.1f rad)" % swirled)
	_check(robot_dead and passed_robot, "an enemy in its path is torn apart and it flies on through")
	var gs: GravitySparks = sparks[0] if not sparks.is_empty() and is_instance_valid(sparks[0]) else null
	for i in 120:
		if gs == null or not is_instance_valid(gs) or gs.consumed > 10:
			break
		await _ticks(1)
	_check(gs != null and is_instance_valid(gs) and gs.consumed > 10, "blue muzzle particles swirl after it and get swallowed (%d)" % (gs.consumed if gs and is_instance_valid(gs) else -1))
	for n in [gun, crate, robot]:
		if is_instance_valid(n):
			n.queue_free()
	if is_instance_valid(pr):
		pr.queue_free()
	await _ticks(5)


func _supernova_finish_tests(main: Node) -> void:
	var f := SupernovaFinish.spawn(main, Vector3(-30, 1, -30), 12.0)
	await _ticks(2)
	var reach := float(f._burst.get_meta("extent")) * f._burst.scale.x * 0.5
	_check(absf(reach - 12.0) < 0.05, "supernova burst reaches just past the damage radius (%.1f m)" % reach)
	_check(f._mats[0].transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and f._mats[0].albedo_color.a < 0.5 and f._mats[0].depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED, "burst is translucent")
	var t := 0.0
	while is_instance_valid(f) and t < 2.0:
		await _ticks(1)
		t += 1.0 / Engine.physics_ticks_per_second
	_check(not is_instance_valid(f) and t <= 0.85, "whole burst plays in 0.8 s (%.2f s)" % t)
	var bp: BlackHoleProjectile = load("res://scenes/weapons/black_hole_projectile.tscn").instantiate()
	_check(bp.supernova_radius + bp.supernova_finish_margin > bp.supernova_radius, "burst set just beyond the supernova's damage radius")
	bp.free()


func _robot_combat_tests(main: Node) -> void:
	RobotEnemy.ai_enabled = true
	var p: PlayerController = main.players[1]
	var base := Vector3(-14, 0, 33)
	p.global_position = base
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	var r := _spawn_robot(main, base + Vector3(0, 0, -12))
	var hits_before := p.damage_taken
	var flashes := 0
	var impacts := 0
	var bolts_max := 0
	var start := r.global_position
	var moved := 0.0
	var facing_err := 0.0
	var legs_err := 0.0
	var samples := 0
	for i in Engine.physics_ticks_per_second * 6:
		await _ticks(1)
		bolts_max = maxi(bolts_max, PlasmaBolt.active_count())
		moved = maxf(moved, r.global_position.distance_to(start))
		if r.target and i > 60:
			facing_err = maxf(facing_err, r.upper_body_facing_error())
			samples += 1
			var hv := Vector2(r.linear_velocity.x, r.linear_velocity.z)
			if hv.length() > 1.0:
				var legs := Vector2(r._visual.global_basis.z.x, r._visual.global_basis.z.z)
				var ang := rad_to_deg(absf(legs.angle_to(hv)))
				legs_err = maxf(legs_err, minf(ang, absf(180.0 - ang)))
	_check(r.target == p, "robot detects and engages the player")
	_check(moved > 1.5, "it moves/strafes while fighting (%.1f m)" % moved)
	_check(samples > 0 and facing_err < 35.0, "upper body keeps facing the player (worst %.0f deg)" % facing_err)
	_check(legs_err < 60.0, "legs face along its movement (forwards or backpedalling), no sideways floating (worst %.0f deg)" % legs_err)
	_check(r.shots_fired >= 6, "fires bursts from its cannons (%d shots in 6 s)" % r.shots_fired)
	_check(r.shots_fired < 40, "bursts, not constant spam (%d shots in 6 s)" % r.shots_fired)
	_check(bolts_max > 0, "green plasma bolts fly (%d at once)" % bolts_max)
	_check(p.damage_taken > hits_before, "plasma hits the player (%.0f hits)" % (p.damage_taken - hits_before))
	var m0 := r._aim.muzzle_position(0)
	var m1 := r._aim.muzzle_position(1)
	_check(m0.distance_to(m1) > 0.1 and m0.y > 0.8 and m0.y < 1.6 and m1.y > 0.8 and m1.y < 1.6,
		"bolts leave from both (aimed) cannon muzzles (heights %.2f / %.2f m)" % [m0.y, m1.y])
	# Hands off when it dies.
	r.apply_damage(DamageInfo.make(99, DamageInfo.Type.BULLET, r.global_position, Vector3.FORWARD, 1.0))
	var shots_dead := r.shots_fired
	await _ticks(60)
	_check(r.shots_fired == shots_dead and r.target == null, "dead robots stop fighting")
	RobotEnemy.ai_enabled = false
	r.queue_free()


func add_child_to_root(n: Node) -> void:
	get_root().add_child(n)


static func _seg_dist(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var best := INF
	for i in 21:
		var a := p1.lerp(q1, i / 20.0)
		best = minf(best, a.distance_to(Geometry3D.get_closest_point_to_segment(a, p2, q2)))
	return best


## Closest approach (m) between the two cannons' axes, and between each cannon
## and the other arm's upper arm/forearm. Sampled inside the skeleton update
## (bone poses read later don't include the procedural aim layer).
func _cannon_clearance(p: PlayerController) -> Vector2:
	var h: WeaponHolder = p.get_node("WeaponHolder")
	var sk: Skeleton3D = p.find_children("*", "Skeleton3D", true, false)[0]
	await sk.skeleton_updated
	var seg := {}
	for side in ["Right", "Left"]:
		var w := h.weapon(side)
		seg[side] = [w.find_marker(Weapon.SOCKET_MARKER).global_position, w.find_marker(Weapon.MUZZLE_MARKER).global_position]
	var cc := _seg_dist(seg.Right[0], seg.Right[1], seg.Left[0], seg.Left[1])
	var arm := INF
	# Weapons are placed from the interpolated (drawn) pose.
	var g := sk.get_global_transform_interpolated()
	for side in ["Right", "Left"]:
		var other := "Left" if side == "Right" else "Right"
		var a0 := g * sk.get_bone_global_pose(sk.find_bone("mixamorig_%sArm" % other)).origin
		var a1 := g * sk.get_bone_global_pose(sk.find_bone("mixamorig_%sForeArm" % other)).origin
		var a2 := g * sk.get_bone_global_pose(sk.find_bone("mixamorig_%sHand" % other)).origin
		arm = minf(arm, minf(_seg_dist(seg[side][0], seg[side][1], a0, a1), _seg_dist(seg[side][0], seg[side][1], a1, a2)))
	return Vector2(cc, arm)


## Dual wield: two default cannons, per-slot tap targeting, independent aim,
## firing and recoil, no clipping, movement unaffected.
func _dual_wield_tests(main: Node) -> void:
	var p: PlayerController = main.players[1]
	var h: WeaponHolder = p.get_node("WeaponHolder")
	var sel: TargetSelector = p.get_node("Input/TargetSelector")
	var lock_r: TargetLock = p.get_node("TargetLock")
	var lock_l: TargetLock = p.get_node("TargetLockLeft")
	var anim: CharacterAnimator = p.get_node("Visual/GrinchVisual")
	sel.clear()
	sel.forget_last_tap()
	# Swap back: the RIGHT slot returns to the default cannon.
	h.equip(h.default_weapon, "Right")
	var wr := h.weapon("Right") as PlasmaCannon
	var wl := h.weapon("Left") as PlasmaCannon
	_check(wr != null and wl != null and wr != wl, "both slots hold a default cannon (right swapped back)")
	var c := PlayerCommand.new()
	c.target_id = 3
	c.target_id_left = 7
	var c2 := PlayerCommand.from_dict(c.to_dict())
	_check(c2.target_id == 3 and c2.target_id_left == 7, "both slots' targets survive command serialisation")

	var base := Vector3(-14, 0, 33)
	p.global_position = base
	p.velocity = Vector3.ZERO
	p.rotation.y = 0.0
	p.reset_physics_interpolation()
	var ra := _spawn_robot(main, base + Vector3(3.5, 0, -10))   # on the player's right
	var rb := _spawn_robot(main, base + Vector3(-3.5, 0, -10))  # on the player's left
	var rc := _spawn_robot(main, base + Vector3(0, 0, -14))
	for r: RobotEnemy in [ra, rb, rc]:
		r.max_health = 500.0
		r.health = 500.0
	var ta: Targetable = ra.get_node("Targetable")
	var tb: Targetable = rb.get_node("Targetable")
	var tc: Targetable = rc.get_node("Targetable")
	await _ticks(20)

	# First enemy -> RIGHT cannon locks and fires; LEFT idle.
	var r0 := wr.shots_fired
	var l0 := wl.shots_fired
	var ha := ra.hits
	sel.tap_target(ta)
	await _ticks(45)
	_check(lock_r.current == ta and not lock_l.has_target(), "first tap: RIGHT slot locks the enemy")
	_check(wr.shots_fired > r0 and wl.shots_fired == l0, "only the right cannon fires (%d / %d)" % [wr.shots_fired - r0, wl.shots_fired - l0])
	_check(ra.hits > ha, "right cannon's plasma hits its target")
	# Second enemy -> LEFT cannon.
	sel.forget_last_tap()
	sel.tap_target(tb)
	await _ticks(30)
	_check(lock_l.current == tb and lock_r.current == ta, "second enemy: LEFT slot locks it, RIGHT keeps the first")
	r0 = wr.shots_fired
	l0 = wl.shots_fired
	ha = ra.hits
	var hb := rb.hits
	var both_kick := 0.0
	for i in 60:
		await _ticks(1)
		both_kick = maxf(both_kick, minf(anim.recoil_side.Right, anim.recoil_side.Left))
	_check(wr.shots_fired > r0 + 1 and wl.shots_fired > l0 + 1, "both cannons fire at the same time (%d / %d in 1 s)" % [wr.shots_fired - r0, wl.shots_fired - l0])
	_check(ra.hits > ha and rb.hits > hb, "both enemies are hit simultaneously")
	_check(both_kick > 0.05, "both arms recoil together (%.2f)" % both_kick)
	var aim_r := rad_to_deg(wr.get_barrel_direction().angle_to(ta.get_aim_point() - wr.global_position))
	var aim_l := rad_to_deg(wl.get_barrel_direction().angle_to(tb.get_aim_point() - wl.global_position))
	var apart := rad_to_deg(wr.get_barrel_direction().angle_to(wl.get_barrel_direction()))
	_check(aim_r < 12.0 and aim_l < 12.0 and apart > 20.0, "arms aim independently (right %.0f deg, left %.0f deg off; %.0f deg apart)" % [aim_r, aim_l, apart])
	var body_yaw := p.rotation.y
	_check(absf(wrapf(body_yaw, -PI, PI)) < 0.35, "whole character doesn't turn to either target (%.0f deg)" % rad_to_deg(body_yaw))
	var cl: Vector2 = await _cannon_clearance(p)
	_check(cl.x > 0.15 and cl.y > 0.12, "no cannon clipping, split aim (%.2f / %.2f m)" % [cl.x, cl.y])

	# Tapping one slot's enemy (different targets) unlocks only that slot.
	sel.forget_last_tap()
	sel.tap_target(tb)
	await _ticks(40)
	_check(lock_r.current == ta and not lock_l.has_target(), "tapping the left slot's enemy unlocks only the left")
	# Independent recoil: right keeps kicking, left is still.
	var peak_r := 0.0
	var peak_l := 0.0
	for i in 40:
		await process_frame
		peak_r = maxf(peak_r, anim.recoil_side.Right)
		peak_l = maxf(peak_l, absf(anim.recoil_side.Left))
	_check(peak_r > 0.15 and peak_l < 0.02, "independent recoil (right %.2f, left %.2f)" % [peak_r, peak_l])

	# Double tap -> both lock the same enemy.
	sel.clear()
	sel.forget_last_tap()
	await _ticks(5)
	sel.tap_target(ta)
	sel.tap_target(ta)
	await _ticks(40)
	_check(lock_r.current == ta and lock_l.current == ta, "double tap: both cannons lock the same enemy")
	r0 = wr.shots_fired
	l0 = wl.shots_fired
	await _ticks(40)
	_check(wr.shots_fired > r0 and wl.shots_fired > l0, "both cannons fire at the shared target")
	cl = await _cannon_clearance(p)
	_check(cl.x > 0.15 and cl.y > 0.12, "no cannon clipping, shared target (%.2f / %.2f m)" % [cl.x, cl.y])
	# Tap it again: LEFT unlocks first, then RIGHT.
	sel.forget_last_tap()
	sel.tap_target(ta)
	await _ticks(3)
	_check(lock_r.current == ta and not lock_l.has_target(), "tap shared enemy: LEFT unlocks first")
	sel.forget_last_tap()
	sel.tap_target(ta)
	await _ticks(3)
	_check(not lock_r.has_target() and not lock_l.has_target(), "tap again: RIGHT unlocks")

	# Both busy: a third enemy replaces the older assignment.
	sel.forget_last_tap()
	sel.tap_target(ta)
	sel.forget_last_tap()
	sel.tap_target(tb)
	sel.forget_last_tap()
	sel.tap_target(tc)
	await _ticks(3)
	_check(lock_r.current == tc and lock_l.current == tb, "third enemy replaces the slot locked longest ago")

	# Crossed targets (right slot on the left enemy and vice versa): arms
	# cross over/under without the cannons touching, both still fire.
	sel.clear()
	sel.forget_last_tap()
	sel.tap_target(tb)
	sel.forget_last_tap()
	sel.tap_target(ta)
	var worst := Vector2(INF, INF)
	r0 = wr.shots_fired
	l0 = wl.shots_fired
	for i in 70:
		await _ticks(1)
		if i > 35:
			var k: Vector2 = await _cannon_clearance(p)
			worst = Vector2(minf(worst.x, k.x), minf(worst.y, k.y))
	_check(lock_r.current == tb and lock_l.current == ta, "crossed targets locked")
	_check(worst.x > 0.15 and worst.y > 0.12, "no cannon clipping with crossed arms (%.2f / %.2f m)" % [worst.x, worst.y])
	_check(wr.shots_fired > r0 and wl.shots_fired > l0, "both fire at crossed targets")

	# Movement and animations keep working while both are locked.
	sel.clear()
	sel.forget_last_tap()
	sel.tap_target(ta)
	sel.forget_last_tap()
	sel.tap_target(tb)
	await _ticks(10)
	r0 = wr.shots_fired
	l0 = wl.shots_fired
	worst = Vector2(INF, INF)
	Input.action_press("move_right")
	for i in 70:
		await _ticks(1)
		if i > 30:
			var k: Vector2 = await _cannon_clearance(p)
			worst = Vector2(minf(worst.x, k.x), minf(worst.y, k.y))
	_check(Vector2(p.velocity.x, p.velocity.z).length() > 5.0 and p.is_facing_yaw(-PI * 0.5, 0.35), "runs normally (legs follow movement) while dual locked")
	_check(anim.current_state == "Locomotion", "locomotion animation keeps playing (%s)" % anim.current_state)
	Input.action_press("jump")
	await _ticks(2)
	Input.action_release("jump")
	await _ticks(10)
	_check(not p.is_on_floor() and anim.current_state in ["Jump", "AirJump", "Fall"], "jumps while dual locked (%s)" % anim.current_state)
	for i in 30:
		await _ticks(1)
		var k: Vector2 = await _cannon_clearance(p)
		worst = Vector2(minf(worst.x, k.x), minf(worst.y, k.y))
	Input.action_release("move_right")
	_check(wr.shots_fired > r0 and wl.shots_fired > l0, "both keep firing while moving")
	_check(worst.x > 0.15 and worst.y > 0.12, "no cannon clipping while running/jumping (%.2f / %.2f m)" % [worst.x, worst.y])
	await _ticks(40)

	# A slot's target dies: only that slot clears.
	p.velocity = Vector3.ZERO
	rb.apply_damage(DamageInfo.make(999, DamageInfo.Type.BULLET, rb.global_position, Vector3.FORWARD, 1.0))
	await _ticks(5)
	_check(not lock_l.has_target() and sel.selected_left == null and lock_r.current == ta, "target death clears only its slot")
	sel.clear()
	await _ticks(3)
	for r in [ra, rb, rc]:
		r.queue_free()


## Five-barrel shotgun: pad (orange, separate from the BHG pad), pickup into
## the RIGHT slot, five streams from five barrels, close-range kill, spread
## and damage falling off with distance, subtle secondary hits, VFX, dual use.
func _shotgun_tests(main: Node) -> void:
	var p: PlayerController = main.players[1]
	var h: WeaponHolder = p.get_node("WeaponHolder")
	var sel: TargetSelector = p.get_node("Input/TargetSelector")
	sel.clear()
	sel.forget_last_tap()
	var pad: WeaponSpawnPad = main.get_node("ShotgunSpawnPad")
	var bh_pad: WeaponSpawnPad = main.get_node("WeaponSpawnPad")
	var spawner: WeaponSpawner = pad.get_node("WeaponSpawner")
	# Earlier tests can carry the player across this pad (gravity wells pull
	# it around): start from a fresh display and default weapons.
	var lo: WeaponLoadout = p.get_node("WeaponLoadout")
	h.equip(h.default_weapon, "Right")
	h.equip(h.default_weapon, "Left")
	lo.relock(pad.weapon)
	if spawner.display == null:
		spawner.spawn_display()
	await _ticks(2)
	_check(spawner.display is Shotgun, "shotgun floats above its own pad")
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in spawner.display.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh is ArrayMesh:
			var ab: AABB = mi.global_transform * mi.mesh.get_aabb()
			box = ab if first else box.merge(ab)
			first = false
	var off := box.get_center() - pad.global_position
	_check(Vector2(off.x, off.z).length() < 0.05 and off.y > 0.6, "shotgun is centred above the pad (%.2f m off)" % Vector2(off.x, off.z).length())
	var rot_a := spawner._pivot.rotation.y
	await _ticks(20)
	_check(absf(spawner._pivot.rotation.y - rot_a) > 0.05, "shotgun display rotates")
	var ring: MeshInstance3D = pad.get_node("GlowRing")
	var ring_col: Color = (ring.get_active_material(0) as StandardMaterial3D).albedo_color
	_check(ring_col.r > 0.9 and ring_col.g > 0.3 and ring_col.g < 0.6 and ring_col.b < 0.2, "shotgun pad glows orange (%s)" % ring_col)
	var model_mi: MeshInstance3D = pad.get_node("Model").find_children("*", "MeshInstance3D", true, false)[0]
	_check(model_mi.get_active_material(0) is ShaderMaterial, "shotgun pad model recoloured")
	var bh_ring: Color = (bh_pad.get_node("GlowRing").get_active_material(0) as StandardMaterial3D).albedo_color
	var bh_model: MeshInstance3D = bh_pad.get_node("Model").find_children("*", "MeshInstance3D", true, false)[0]
	_check(bh_ring.b > 0.9 and bh_model.get_active_material(0) is StandardMaterial3D, "Black Hole Generator pad keeps its purple glow")
	_check(bh_pad.weapon.id == &"black_hole_generator" and pad.weapon.id == &"shotgun", "each pad offers its own weapon")

	# Walk onto the pad: the shotgun goes into the RIGHT slot.
	var left_before := h.weapon("Left")
	p.global_position = pad.global_position + Vector3(0, 0.05, 3.0)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	await _ticks(10)
	Input.action_press("move_forward")
	for i in 60:
		await _ticks(1)
		if h.weapon("Right") is Shotgun:
			break
	Input.action_release("move_forward")
	await _ticks(10)
	_check(h.weapon("Right") is Shotgun and spawner.display == null, "walking onto the pad equips the shotgun (RIGHT slot)")
	_check(h.weapon("Left") == left_before and h.weapon("Left") is PlasmaCannon, "LEFT slot keeps its weapon")
	var sg := h.weapon("Right") as Shotgun
	_check(sg.barrel_positions().size() == 5, "five barrel muzzles")
	var bp := sg.barrel_positions()
	var min_gap := INF
	for i in 5:
		for j in range(i + 1, 5):
			min_gap = minf(min_gap, bp[i].distance_to(bp[j]))
	_check(min_gap > 0.02, "each barrel has its own muzzle point (closest %.3f m)" % min_gap)

	# Close range: one blast, all five streams, kills a normal robot.
	var base := Vector3(-14, 0, 33)
	p.global_position = base
	p.velocity = Vector3.ZERO
	p.rotation.y = 0.0
	p.reset_physics_interpolation()
	await _ticks(5)
	var near := _spawn_robot(main, base + Vector3(0, 0, -3.0))
	await _ticks(10)
	var tn: Targetable = near.get_node("Targetable")
	sg._cool = 0.0
	_check(sg.fire_at(p, tn.get_aim_point()), "shotgun fires")
	_check(sg.last_shot.size() == 5, "every shot fires all five barrels (%d streams)" % sg.last_shot.size())
	var from_ok := true
	var bp2 := sg.barrel_positions()
	for i in sg.last_shot.size():
		from_ok = from_ok and (sg.last_shot[i].from as Vector3).distance_to(bp2[i]) < 0.001
	_check(from_ok, "each stream starts exactly at its own barrel")
	_check(ShotgunStream.active_count() >= 5, "five visible streams (%d)" % ShotgunStream.active_count())
	_check(sg._flash.is_flashing() and sg._flash._light.light_energy > 1.0, "flaming muzzle flash with orange light")
	var hits_close := 0
	for st in sg.last_shot:
		if st.target == tn:
			hits_close += 1
	_check(hits_close == 5, "close range: all five streams on the target (%d)" % hits_close)
	_check(near.alive, "damage lands when the streams arrive, not instantly")
	await _ticks(3)
	_check(not near.alive, "a clean close-range blast kills a normal enemy")
	await _ticks(12)
	_check(ShotgunStream.active_count() >= 5 and not sg._flash.is_flashing(), "rail trails linger after the hit, the flash is brief")
	var st0: ShotgunStream = null
	for c in get_root().find_children("*", "ShotgunStream", true, false):
		if (c as ShotgunStream).active:
			st0 = c
			break
	_check(st0 != null and st0._helix.get_surface_count() == 1 and st0._helix.surface_get_array_len(0) > 20, "each trail has its own spiral")
	await _ticks(45)
	_check(ShotgunStream.active_count() == 0, "trails fade out within a second")

	# Further away: wider spread, fewer hits, less damage per stream.
	_check(sg.spread_at(3.0) < sg.spread_at(10.0) and sg.spread_at(10.0) < sg.spread_at(18.0), "spread grows with distance")
	_check(sg.damage_at(3.0) > sg.damage_at(12.0) and sg.damage_at(12.0) > sg.damage_at(22.0), "damage per stream falls with distance")
	var far := _spawn_robot(main, base + Vector3(0, 0, -17.0))
	far.max_health = 999.0
	far.health = 999.0
	await _ticks(10)
	var tf: Targetable = far.get_node("Targetable")
	var hits_far := 0
	var dmg_far := 0.0
	for k in 10:
		sg._cool = 0.0
		var h0 := far.health
		sg.fire_at(p, tf.get_aim_point())
		for st in sg.last_shot:
			if st.target == tf:
				hits_far += 1
		await _ticks(8)
		dmg_far += h0 - far.health
	_check(hits_far / 10.0 < 3.0 and hits_far > 0, "at 17 m fewer streams hit (%.1f per shot)" % (hits_far / 10.0))
	_check(dmg_far / 10.0 < 1.5, "so a far shot does much less damage (%.2f per shot)" % (dmg_far / 10.0))
	far.queue_free()

	# Medium range with enemies next to the target: outer streams may bend
	# onto them for slight damage; the target still takes the most.
	var a := _spawn_robot(main, base + Vector3(0, 0, -12.0))
	var b := _spawn_robot(main, base + Vector3(2.3, 0, -12.5))
	var c2 := _spawn_robot(main, base + Vector3(-2.3, 0, -11.6))
	for r: RobotEnemy in [a, b, c2]:
		r.max_health = 999.0
		r.health = 999.0
	await _ticks(10)
	var ta: Targetable = a.get_node("Targetable")
	var dmg_a := 0.0
	var dmg_o := 0.0
	var assisted := 0
	var max_bend := 0.0
	for k in 10:
		sg._cool = 0.0
		var ha := a.health
		var ho := b.health + c2.health
		sg.fire_at(p, ta.get_aim_point())
		for st in sg.last_shot:
			if st.assisted:
				assisted += 1
		await _ticks(8)
		dmg_a += ha - a.health
		dmg_o += ho - (b.health + c2.health)
	_check(assisted > 0 and dmg_o > 0.0, "outer streams semi-lock onto nearby enemies (%d streams, %.2f dmg)" % [assisted, dmg_o])
	_check(dmg_o < dmg_a * 0.4, "secondary hits do only slight damage (%.2f vs %.2f on the target)" % [dmg_o, dmg_a])
	_check(assisted <= 20, "at most one bent stream per nearby enemy per shot (%d in 10 shots)" % assisted)

	# Auto-fire through the normal slot/lock path, and dual-wield ready: the
	# same shotgun definition works in the LEFT slot too.
	h.equip(pad.weapon, "Left")
	var sl := h.weapon("Left") as Shotgun
	_check(sl != null and sl != sg and (sl.get_parent() as BoneAttachment3D).bone_name == "mixamorig_LeftForeArm", "shotgun also mounts on the LEFT arm")
	sel.forget_last_tap()
	sel.tap_target(ta)
	sel.tap_target(ta)  # double tap: both slots
	var r0 := sg.shots_fired
	var l0 := sl.shots_fired
	for i in 120:
		await _ticks(1)
		if sg.shots_fired > r0 and sl.shots_fired > l0:
			break
	_check(sg.shots_fired > r0 and sl.shots_fired > l0, "shotgun + shotgun: both auto-fire at the locked enemy")
	sel.clear()
	await _ticks(3)
	for r: RobotEnemy in [a, b, c2]:
		r.queue_free()
	if is_instance_valid(near):
		near.queue_free()
	h.equip(h.default_weapon, "Left")
	h.equip(h.default_weapon, "Right")
	await _ticks(3)


## Seven robot deaths: the model's four clips plus three procedural ones;
## kills by the same weapon vary and never repeat back to back.
func _robot_death_variety_tests(main: Node) -> void:
	var base := Vector3(5, 0, 26)
	for style in ["blown_back", "spin", "stagger"]:
		var r := _spawn_robot(main, base)
		await _ticks(10)
		r.force_death_style = style
		var fwd: Vector3 = r._visual.global_basis.z
		var push := -fwd if style != "spin" else fwd.cross(Vector3.UP)
		var start := r.global_position
		r.apply_damage(DamageInfo.make(99, DamageInfo.Type.BULLET, r.global_position + Vector3.UP, push, 8.0))
		var yaw0: float = r._yaw
		var max_turn := 0.0
		var moved := 0.0
		var lifted := 0.0
		for i in 120:
			await _ticks(1)
			if not is_instance_valid(r):
				break
			max_turn = maxf(max_turn, absf(wrapf(r._visual.rotation.y - yaw0, -PI, PI)))
			moved = maxf(moved, Vector2(r.global_position.x - start.x, r.global_position.z - start.z).length())
			lifted = maxf(lifted, r.global_position.y - start.y)
		match style:
			"blown_back":
				_check(r.last_death_style == "blown_back" and moved > 1.0 and lifted > 0.15, "death: blown back off its feet (%.1f m back, %.2f m up)" % [moved, lifted])
			"spin":
				_check(r.last_death_style == "spin" and max_turn > deg_to_rad(120), "death: spun round by a side hit (%.0f deg)" % rad_to_deg(max_turn))
			"stagger":
				_check(r.last_death_style == "stagger" and moved > 0.3 and r._anim.current_animation != "Walking", "death: staggers back then topples (%.2f m, now %s)" % [moved, r._anim.current_animation])
		var head := r.get_skeleton().find_bone("mixamorig_Head")
		await _ticks(90)
		var hy: float = (r.get_skeleton().global_transform * r.get_skeleton().get_bone_global_pose(head)).origin.y
		_check(hy < 0.7, "%s ends on the floor (head %.2f m)" % [style, hy])
		r.queue_free()
		await _ticks(2)
	# Natural picks from energy kills: varied, never the same twice running.
	var seen := {}
	var prev := ""
	var repeats := 0
	for k in 12:
		var r := _spawn_robot(main, base + Vector3(3 * (k % 4), 0, 3 * (k / 4)))
		r._breaker.reference_force = 1000.0  # keep it whole: no debris pile-up
		await _ticks(3)
		var fwd: Vector3 = r._visual.global_basis.z
		var dirs := [-fwd, fwd, fwd.cross(Vector3.UP)]
		# The picks are random: seed right before each kill so this check
		# doesn't depend on whatever else used random numbers in between.
		seed(20261006 + k)
		r.apply_damage(DamageInfo.make(5, DamageInfo.Type.ENERGY, r.global_position + Vector3.UP, dirs[k % 3], [2.0, 9.0][k % 2]))
		var key := r.last_death_style + ":" + String(r.last_death_anim)
		seen[key] = true
		if key == prev:
			repeats += 1
		prev = key
	_check(seen.size() >= 5, "kills pick from many deaths (%d different in 12)" % seen.size())
	_check(repeats == 0, "never the same death twice in a row")
	await _ticks(5)
	for r in main.get_children():
		if r is RobotEnemy and not (r as RobotEnemy).alive:
			r.queue_free()
	await _ticks(2)


## Held weapons never touch each other, the other arm or the body, and
## never stick out behind the elbow, for every weapon combination.
func _weapon_fit_tests(main: Node) -> void:
	var p: PlayerController = main.players[1]
	var h: WeaponHolder = p.get_node("WeaponHolder")
	var sk: Skeleton3D = p.find_children("*", "Skeleton3D", true, false)[0]
	var sel: TargetSelector = p.get_node("Input/TargetSelector")
	sel.clear()
	var base := Vector3(-14, 0, 33)
	var defs := {"cannon": h.default_weapon, "shotgun": load("res://resources/weapons/shotgun.tres"), "bhg": load("res://resources/weapons/black_hole_generator.tres")}
	var combos := [["cannon", "cannon"], ["shotgun", "cannon"], ["shotgun", "shotgun"], ["bhg", "cannon"], ["bhg", "shotgun"]]
	var ta := _spawn_robot(main, base + Vector3(0, 0, -10))
	var tb := _spawn_robot(main, base + Vector3(-7, 0, -7))
	var tc := _spawn_robot(main, base + Vector3(7, 0, -7))
	for r: RobotEnemy in [ta, tb, tc]:
		r.max_health = 9999.0
		r.health = 9999.0
	var a: Targetable = ta.get_node("Targetable")
	var b: Targetable = tb.get_node("Targetable")
	var c: Targetable = tc.get_node("Targetable")
	for combo in combos:
		h.equip(defs[combo[0]], "Right")
		h.equip(defs[combo[1]], "Left")
		var worst := {"weapons": INF, "arm": INF, "torso": INF, "rear": -INF}
		# [right target, left target, move]: shared, split, crossed, running.
		for sc in [[a, a, ""], [c, b, ""], [b, c, ""], [b, c, "move_right"]]:
			p.global_position = base
			p.velocity = Vector3.ZERO
			p.rotation.y = 0.0
			p.reset_physics_interpolation()
			sel.clear()
			sel.forget_last_tap()
			sel.tap_target(sc[0])
			if sc[1] == sc[0]:
				sel.tap_target(sc[0])
			else:
				sel.forget_last_tap()
				sel.tap_target(sc[1])
			if sc[2] != "":
				Input.action_press(sc[2])
			for i in 50:
				await _ticks(1)
				if i < 25:
					continue
				await sk.skeleton_updated
				var g := sk.get_global_transform_interpolated()
				var bp := {}
				for n in ["LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand", "Hips", "Neck"]:
					bp[n] = g * sk.get_bone_global_pose(sk.find_bone("mixamorig_" + n)).origin
				var R := WeaponBounds.obb(h.weapon("Right"))
				var L := WeaponBounds.obb(h.weapon("Left"))
				worst.weapons = minf(worst.weapons, WeaponBounds.gap(R, L))
				worst.arm = minf(worst.arm, minf(minf(WeaponBounds.capsule_gap(R, bp.LeftArm, bp.LeftForeArm, 0.06), WeaponBounds.capsule_gap(R, bp.LeftForeArm, bp.LeftHand, 0.06)),
					minf(WeaponBounds.capsule_gap(L, bp.RightArm, bp.RightForeArm, 0.06), WeaponBounds.capsule_gap(L, bp.RightForeArm, bp.RightHand, 0.06))))
				var ta0: Vector3 = bp.Hips + Vector3(0, 0.12, 0)
				worst.torso = minf(worst.torso, minf(WeaponBounds.capsule_gap(R, ta0, bp.Neck, 0.13), WeaponBounds.capsule_gap(L, ta0, bp.Neck, 0.13)))
				worst.rear = maxf(worst.rear, maxf(WeaponBounds.rear_overhang(R, bp.RightForeArm, bp.RightHand - bp.RightForeArm), WeaponBounds.rear_overhang(L, bp.LeftForeArm, bp.LeftHand - bp.LeftForeArm)))
			if sc[2] != "":
				Input.action_release(sc[2])
		var name := "%s + %s" % combo
		_check(worst.weapons > 0.0, "%s: weapons never touch (closest %.3f m)" % [name, worst.weapons])
		_check(worst.arm > 0.0, "%s: no weapon touches the other arm (closest %.3f m)" % [name, worst.arm])
		_check(worst.torso > 0.0, "%s: no weapon cuts into the body (closest %.3f m)" % [name, worst.torso])
		_check(worst.rear < 0.01, "%s: nothing sticks out behind the elbows (%.3f m)" % [name, worst.rear])
	sel.clear()
	h.equip(h.default_weapon, "Right")
	h.equip(h.default_weapon, "Left")
	for r: RobotEnemy in [ta, tb, tc]:
		r.queue_free()
	await _ticks(3)


## Weapon arm attachment standard: one character-side WeaponSocket per arm,
## exactly at the Black Hole Generator's (reference) mount; the BHG mount is
## unchanged; ARM_END weapons plug into the arm's open end, centred, and
## never extend back along the forearm; geometry that would is trimmed.
func _weapon_socket_tests(main: Node) -> void:
	var p: PlayerController = main.players[1]
	var h: WeaponHolder = p.get_node("WeaponHolder")
	var sk: Skeleton3D = p.find_children("*", "Skeleton3D", true, false)[0]
	var anim: CharacterAnimator = p.get_node("Visual/GrinchVisual")
	var bhg: WeaponDefinition = load("res://resources/weapons/black_hole_generator.tres")
	var sg: WeaponDefinition = load("res://resources/weapons/shotgun.tres")
	p.global_position = Vector3(-14, 0, 33)
	p.velocity = Vector3.ZERO
	await _ticks(10)
	var socket_err := 0.0
	var bhg_err := 0.0
	var rear_min := INF
	var centre_max := 0.0
	for combo in [[bhg, bhg], [h.default_weapon, sg], [sg, h.default_weapon]]:
		h.equip(combo[0], "Right")
		h.equip(combo[1], "Left")
		for i in 12:
			await _ticks(1)
			await sk.skeleton_updated
			for side in ["Right", "Left"]:
				var slot := h.slot(side)
				var bone := sk.get_global_transform_interpolated() * sk.get_bone_global_pose(sk.find_bone("mixamorig_%sForeArm" % side))
				var axis := bone.basis.y.normalized()
				var up := (Vector3.UP - axis * axis.dot(Vector3.UP)).normalized()
				var ref := Transform3D(Basis(axis, up, axis.cross(up)), bone.origin + axis * 0.05)
				socket_err = maxf(socket_err, slot.socket_node.global_transform.origin.distance_to(ref.origin))
				var w := h.weapon(side)
				if slot.definition == bhg:
					# The original Black Hole Generator mount (pre-socket formula).
					var expect := ref * slot._socket.affine_inverse()
					var d := w.global_transform.origin.distance_to(expect.origin)
					for k in 3:
						d = maxf(d, (w.global_transform.basis[k] - expect.basis[k]).length())
					bhg_err = maxf(bhg_err, d)
				else:
					var box := WeaponBounds.obb(w)
					var c: Vector3 = box[0]
					var back := (c - ref.origin).dot(axis)
					for v: Vector3 in box[1]:
						back -= absf(v.dot(axis))
					rear_min = minf(rear_min, back)
					var lateral := (c - ref.origin) - axis * (c - ref.origin).dot(axis)
					centre_max = maxf(centre_max, lateral.length())
	_check(socket_err < 0.001, "left/right WeaponSockets sit at the reference (BHG) mount for every weapon (%.4f m)" % socket_err)
	_check(bhg_err < 0.001, "Black Hole Generator mount unchanged (%.6f m)" % bhg_err)
	var arm_end := anim.arm_end_offset - sg.arm_end_insert
	_check(rear_min > arm_end - 0.035, "cannon/shotgun start at the arm's open end, never back along the forearm (rear %.3f m past the socket, arm end %.3f)" % [rear_min, anim.arm_end_offset])
	_check(centre_max < 0.05, "cannon/shotgun centred on the forearm axis (%.3f m off)" % centre_max)
	# Rear trimming: a weapon mounted too far back loses only the geometry
	# behind the arm boundary; its visible front and the pad copy are whole.
	var deep := sg.duplicate() as WeaponDefinition
	deep.mount_offset = -0.25
	var full := h.equip(sg, "Right")
	var full_n := 0
	for mi: MeshInstance3D in full.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh is ArrayMesh:
			for si in mi.mesh.get_surface_count():
				full_n += mi.mesh.surface_get_array_index_len(si)
	var w2 := h.equip(deep, "Right")
	await _ticks(2)
	await sk.skeleton_updated
	var slot2 := h.slot("Right")
	var limit := slot2.trim_x() - 0.002
	var to_socket := slot2._rest_mount()
	var kept := 0
	var behind := 0
	for mi: MeshInstance3D in w2.find_children("*", "MeshInstance3D", true, false):
		if not (mi.mesh is ArrayMesh):
			continue
		var xf := to_socket * w2._local_xf(mi)
		for si in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			kept += ix.size()
			for i in ix:
				if (xf * vs[i]).x < limit:
					behind += 1
	_check(behind == 0 and kept > 0 and kept < full_n, "rear trimming hides only the part behind the arm (%d of %d indices kept)" % [kept, full_n])
	# A fresh pickup display (pads never trim) still has the whole mesh.
	var disp: Weapon = sg.weapon_scene.instantiate()
	add_child_to_root(disp)
	var disp_n := 0
	for mi: MeshInstance3D in disp.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh is ArrayMesh:
			for si in mi.mesh.get_surface_count():
				disp_n += mi.mesh.surface_get_array_index_len(si)
	_check(disp_n == full_n, "weapon on a pad keeps its whole mesh (%d indices)" % disp_n)
	disp.queue_free()
	h.equip(h.default_weapon, "Right")
	h.equip(h.default_weapon, "Left")
	await _ticks(3)


## Drag the wheel from its button towards `def` on `side` and release.
func _wheel_pick(wheel: WeaponWheel, side: String, def: WeaponDefinition, start: Vector2) -> void:
	wheel.open_at(start)
	await process_frame
	var dir := (wheel.item_position(side, def) - wheel.wheel_centre()).normalized()
	for k in 4:
		wheel.drag_to(start + dir * (30.0 + 30.0 * k))
		await process_frame
	wheel.release_at(start + dir * 120.0)


## Weapon wheel + dual-wield loadout: unlocks, hold-drag-release equipping,
## one arm switching without touching the other, the switch sequence,
## targets kept, registry-driven.
func _weapon_switch_tests(main: Node) -> void:
	var p: PlayerController = main.players[1]
	var h: WeaponHolder = p.get_node("WeaponHolder")
	var lo: WeaponLoadout = p.get_node("WeaponLoadout")
	var sel: TargetSelector = p.get_node("Input/TargetSelector")
	var wheel: WeaponWheel = main.get_node("UI/WeaponWheel")
	var tc: TouchControls = main.get_node("UI/TouchControls")
	var cannon := h.default_weapon
	var sg: WeaponDefinition = load("res://resources/weapons/shotgun.tres")
	var bhg: WeaponDefinition = load("res://resources/weapons/black_hole_generator.tres")
	sel.clear()
	h.equip(cannon, "Right")
	h.equip(cannon, "Left")
	lo.unlock(sg)
	lo.unlock(bhg)
	var base := Vector3(-14, 0, 33)
	p.global_position = base
	p.velocity = Vector3.ZERO
	p.rotation.y = 0.0
	p.reset_physics_interpolation()
	await _ticks(10)
	_check(wheel.loadout == lo and tc.wheel_enabled and tc.button_radius("weapon_wheel") >= 40.0, "weapon-switch button on the touch HUD")
	_check(not wheel.is_open and Engine.time_scale == 1.0, "wheel hidden until the button is held")
	var start := tc.button_center("weapon_wheel")

	# Open while moving: movement keeps going, game slows a little.
	Input.action_press("move_forward")
	await _ticks(20)
	wheel.open_at(start)
	for i in 12:
		await process_frame
	var spd := Vector2(p.velocity.x, p.velocity.z).length()
	_check(wheel.is_open and spd > 3.0, "wheel opens while moving; movement continues (%.1f m/s)" % spd)
	_check(Engine.time_scale < 0.8 and Engine.time_scale >= 0.4, "game slows slightly while the wheel is open (x%.2f)" % Engine.time_scale)
	_check(wheel._items.Left.size() == 3 and wheel._items.Right.size() == 3, "both arms list all 3 unlocked weapons")
	# Release in the dead zone: nothing changes.
	wheel.drag_to(start + Vector2(20, -15))
	await process_frame
	_check(wheel.hover_def == null, "small drags select nothing (dead zone)")
	wheel.release_at(start + Vector2(20, -15))
	await create_timer(0.2, true, false, true).timeout  # wheel easing runs in real time
	Input.action_release("move_forward")
	_check(not wheel.is_open and Engine.time_scale == 1.0 and h.slot("Right").definition == cannon and h.slot("Left").definition == cannon, "releasing in the dead zone changes nothing; speed back to normal")

	# Shotgun to RIGHT (left untouched), timed.
	p.global_position = base
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	await _ticks(5)
	var left_w := h.weapon("Left")
	var left_phase_max := 0
	var times := {"start": -1.0, "end": -1.0, "now": 0.0}
	h.slot("Right").switch_started.connect(func(_s, _a, _b) -> void: times.start = times.now, CONNECT_ONE_SHOT)
	h.slot("Right").switch_finished.connect(func(_s, _d) -> void: times.end = times.now, CONNECT_ONE_SHOT)
	await _wheel_pick(wheel, "Right", sg, start)
	var shrank := false
	for i in 40:
		await _ticks(1)
		times.now += 1.0 / Engine.physics_ticks_per_second
		left_phase_max = maxi(left_phase_max, h.slot("Left").switch_phase)
		shrank = shrank or (h.slot("Right").switch_phase == 1 and h.slot("Right").switch_scale < 0.6)
	_check(h.weapon("Right") is Shotgun and h.slot("Right").switch_scale == 1.0, "equip Shotgun to the RIGHT arm through the wheel")
	_check(h.weapon("Left") == left_w and left_phase_max == 0, "LEFT arm untouched while RIGHT switches")
	_check(shrank, "old weapon retracts into the arm before the new one appears")
	var dur: float = times.end - times.start
	_check(times.start >= 0.0 and dur >= 0.25 and dur <= 0.4, "switch takes %.2f s (0.25-0.4)" % dur)
	# BHG to LEFT.
	var right_w := h.weapon("Right")
	await _wheel_pick(wheel, "Left", bhg, start)
	await _ticks(30)
	_check(h.weapon("Left") is BlackHoleGenerator and h.weapon("Right") == right_w, "equip Black Hole Generator to the LEFT arm; RIGHT keeps its Shotgun")
	# Swap only RIGHT, then only LEFT.
	left_w = h.weapon("Left")
	await _wheel_pick(wheel, "Right", cannon, start)
	await _ticks(30)
	_check(h.weapon("Right") is PlasmaCannon and h.weapon("Left") == left_w, "swap only RIGHT (Shotgun -> Cannon); LEFT unaffected")
	right_w = h.weapon("Right")
	await _wheel_pick(wheel, "Left", sg, start)
	await _ticks(30)
	_check(h.weapon("Left") is Shotgun and h.weapon("Right") == right_w, "swap only LEFT (BHG -> Shotgun); RIGHT unaffected")
	# Shotgun + Shotgun.
	await _wheel_pick(wheel, "Right", sg, start)
	await _ticks(30)
	_check(h.weapon("Left") is Shotgun and h.weapon("Right") is Shotgun and h.weapon("Left") != h.weapon("Right"), "Shotgun + Shotgun")
	_check(lo.unlocked_weapons().size() == 3, "every unlocked weapon stays available")

	# Switch one arm while the other is firing; targets kept.
	var ra := _spawn_robot(main, base + Vector3(2.5, 0, -6))
	var rb := _spawn_robot(main, base + Vector3(-2.5, 0, -6))
	for r: RobotEnemy in [ra, rb]:
		r.max_health = 9999.0
		r.health = 9999.0
	await _ticks(10)
	h.equip(cannon, "Right")
	sel.clear()
	sel.forget_last_tap()
	sel.tap_target(ra.get_node("Targetable"))
	sel.forget_last_tap()
	sel.tap_target(rb.get_node("Targetable"))
	await _ticks(40)
	var lock_r: TargetLock = p.get_node("TargetLock")
	var lock_l: TargetLock = p.get_node("TargetLockLeft")
	var lsg := h.weapon("Left") as Shotgun
	var l0 := lsg.shots_fired
	var hits_b := rb.hits
	var fired := {"right": false}
	h.slot("Right").fired.connect(func(_s, _w) -> void: fired.right = true)
	lo.equip("Right", bhg)
	for i in 24:
		await _ticks(1)
	_check(h.weapon("Right") is BlackHoleGenerator and h.slot("Right").switch_phase == 0, "RIGHT switched to the Black Hole Generator")
	_check(lock_r.current == ra.get_node("Targetable") and lock_l.current == rb.get_node("Targetable"), "both arms keep their own targets through the switch")
	for i in 54:
		await _ticks(1)
	_check(lsg == h.weapon("Left") and lsg.shots_fired > l0 and rb.hits > hits_b, "LEFT shotgun keeps tracking/firing while RIGHT switches (%d shots)" % (lsg.shots_fired - l0))
	# The new weapon takes over that arm's target at once.
	for i in 120:
		if fired.right:
			break
		await _ticks(1)
	_check(fired.right, "the new weapon fires at that arm's existing target")
	# A pad for an unlocked weapon stays put (no need to return to it).
	var pad: WeaponSpawnPad = main.get_node("ShotgunSpawnPad")
	var spawner: WeaponSpawner = pad.get_node("WeaponSpawner")
	if spawner.display == null:
		spawner.spawn_display()
	await _ticks(2)
	spawner._on_body_entered(p)
	_check(spawner.display != null and lo.is_unlocked(sg), "walking onto a pad for an unlocked weapon leaves it there")
	# Allowed arms + registry-driven: a new right-only weapon shows only there.
	var extra := cannon.duplicate() as WeaponDefinition
	extra.id = &"test_right_only"
	extra.allowed_sides = PackedStringArray(["Right"])
	lo.unlock(extra)
	wheel.open_at(start)
	await process_frame
	_check(wheel._items.Right.size() == 4 and wheel._items.Left.size() == 3, "new weapons appear in the wheel from data alone (allowed arms respected)")
	wheel.close()
	_check(not lo.equip("Left", extra), "a weapon can't go on an arm it doesn't allow")
	lo.relock(extra)
	sel.clear()
	for r in [ra, rb]:
		r.queue_free()
	h.equip(cannon, "Right")
	h.equip(cannon, "Left")
	for i in 10:
		await process_frame
	_check(Engine.time_scale == 1.0, "game speed back to normal")


## Open holes sealed with minimal caps: the player's hand-less gauntlets and
## the robot's cut sections (its own interior caps made opaque + caps for the
## cuts it lacked), with no extra draw calls and LODs kept.
func _mesh_cap_tests(main: Node) -> void:
	var p: PlayerController = main.players[1]
	var g_src: ArrayMesh = (load("res://assets/characters/grinch/grinch.glb") as PackedScene).instantiate().find_children("*", "MeshInstance3D", true, false)[0].mesh
	var g_caps: MeshCaps = load("res://assets/characters/grinch/grinch_caps.res")
	var body: MeshInstance3D = null
	for mi: MeshInstance3D in p.get_node("Visual").find_children("*", "MeshInstance3D", true, false):
		if mi.skin and mi.mesh and mi.mesh.get_surface_count() == g_src.get_surface_count() and mi.mesh.surface_get_array_len(0) > 50000:
			body = mi
	var cap_v: int = (g_caps.caps.values()[0].vertices as PackedVector3Array).size()
	_check(body != null and body.mesh.surface_get_array_len(0) == g_src.surface_get_array_len(0) + cap_v, "player: gauntlet ends sealed (+%d vertices, same surface)" % cap_v)
	_check(g_caps.caps.values()[0].holes == 2, "player: both hand-less gauntlet openings capped")
	var lods_src: int = RenderingServer.mesh_get_surface(g_src.get_rid(), 0).get("lods", []).size()
	var lods_now: int = RenderingServer.mesh_get_surface(body.mesh.get_rid(), 0).get("lods", []).size() if body else -1
	_check(lods_now == lods_src, "player: LODs kept (%d)" % lods_now)
	# Robot.
	var r := _spawn_robot(main, Vector3(10, 0, 26))
	await _ticks(5)
	var all_opaque := true
	var surfaces_ok := true
	var src_scene: Node = (load("res://assets/characters/robot/robot_enemy.glb") as PackedScene).instantiate()
	var src_counts := {}
	for mi: MeshInstance3D in src_scene.find_children("*", "MeshInstance3D", true, false):
		src_counts[mi.name] = mi.mesh.get_surface_count()
	src_scene.free()
	for mi in r._sections:
		var m: Mesh = mi.mesh
		if src_counts.has(mi.name) and m.get_surface_count() != src_counts[mi.name]:
			surfaces_ok = false
		for si in m.get_surface_count():
			var mat := m.surface_get_material(si) as BaseMaterial3D
			if mat and mat.resource_name.contains("Interior") and (mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or mat.albedo_color.a < 1.0):
				all_opaque = false
	_check(all_opaque, "robot: interior caps of every section are solid (opaque)")
	_check(surfaces_ok and r._whole.mesh.get_surface_count() == 2, "robot: no extra surfaces / draw calls (whole body still 2)")
	var rc: MeshCaps = load("res://assets/characters/robot/robot_caps.res")
	var holes := 0
	for k in rc.caps:
		holes += int(rc.caps[k].holes)
	_check(holes == 5 and rc.caps.has("Torso") and rc.caps.has("Left_Upper_Arm") and rc.caps.has("Pelvis") and rc.caps.has("Left_Thigh"), "robot: the 5 uncapped cuts (left shoulder, left hip, pelvis) get caps")
	# Pieces keep the sealed meshes.
	r._use_section_meshes()
	var cuts: Array[BreakSection] = []
	cuts.assign(r.get_breaker().sections)
	var pieces := r.get_breaker().detach(cuts, DamageInfo.make(99, DamageInfo.Type.EXPLOSION, r.global_position + Vector3.UP, Vector3.FORWARD, 30.0, 30.0), Vector3.ZERO)
	r.alive = false
	var sealed := true
	for pc in pieces:
		for mi: MeshInstance3D in pc.find_children("*", "MeshInstance3D", true, false):
			for si in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(si) as BaseMaterial3D
				if mat and mat.resource_name.contains("Interior") and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					sealed = false
	_check(pieces.size() == 13 and sealed, "robot: every broken piece keeps its sealed cut faces")
	await _ticks(2)
	for pc in pieces:
		if is_instance_valid(pc):
			pc.queue_free()
	r.queue_free()
	await _ticks(2)


## The game's level: Toxic Arena (image-to-level's level.glb) in main.tscn.
func _toxic_arena_tests() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _ticks(30)
	var arena: ToxicArena = main.get_node_or_null("ToxicArena")
	_check(arena != null and main.get_node_or_null("TestArena") == null, "toxic: Toxic Arena is the active level (old test arena gone)")
	var fluid := arena.level.find_child("HazardFluid", true, false) as MeshInstance3D
	_check(fluid != null and arena.level.find_children("*", "MeshInstance3D", true, false).size() > 130, "toxic: level.glb loaded with its named objects and HazardFluid")
	var p: PlayerController = main.players[1]
	var rig: CameraRig = main.get_node("CameraRig")
	var spawn := p.spawn_transform.origin
	_check(p.is_on_floor() and absf(p.global_position.y - 6.0) < 0.05 and Vector2(spawn.x, spawn.z).length() < 11.0, "toxic: player spawns standing on the central platform (y %.2f)" % p.global_position.y)
	_check(p.get_node("Visual/GrinchVisual").current_state == "Locomotion", "toxic: player animations run")

	# Materials: the level's own, emissive where authored.
	var fm := fluid.get_active_material(0) as StandardMaterial3D
	_check(fm != null and fm.resource_name == "toxic" and fm.emission_enabled and fm.emission.g > 0.8, "toxic: HazardFluid keeps its bright emissive green (%s)" % (fm.emission if fm else Color()))
	var red := arena.level.find_child("Central_Tower_Banner_01", true, false) as MeshInstance3D
	var rm := red.get_active_material(0) as StandardMaterial3D
	_check(rm.resource_name == "red_panel" and rm.emission_enabled and rm.emission.r > 0.6, "toxic: red panels stay emissive")
	var glow := arena.level.find_child("Central_Tower_Glow_01_L", true, false) as MeshInstance3D
	var gm := glow.get_active_material(0) as StandardMaterial3D
	_check(gm.resource_name == "glow_strip" and gm.emission_enabled, "toxic: green glow strips stay emissive")
	var floor_mi := arena.level.find_child("Central_Platform_Floor", true, false) as MeshInstance3D
	_check((floor_mi.get_active_material(0) as StandardMaterial3D).albedo_texture != null, "toxic: floors keep their textures")
	var ab := fluid.global_transform * fluid.mesh.get_aabb()
	_check(absf(arena.level.scale.x - 1.0) < 0.001 and ab.size.x > 70.0, "toxic: level at its authored 1:1 scale (metres)")

	# Collision: simple shapes only, nothing on decoration or the fluid.
	var boxes := 0
	var hulls := 0
	var other := 0
	for c: CollisionShape3D in arena.collision.get_children():
		if c.shape is BoxShape3D:
			boxes += 1
		elif c.shape is ConvexPolygonShape3D:
			hulls += 1
		else:
			other += 1
	_check(other == 0 and boxes > 40 and hulls == 10 and arena.collision.get_node_or_null("HazardFluid") == null, "toxic: collision is %d boxes + %d convex hulls, no mesh collision" % [boxes, hulls])

	# Run across the central platform and the south bridge onto the south platform.
	var minys := {"y": INF}
	var watch := func() -> void: minys.y = minf(minys.y, p.global_position.y)
	rig.yaw = 0.0
	p.global_position = Vector3(0, 6.05, 8.5)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	await _ticks(10)
	Input.action_press("move_back", 0.8)
	for i in 110:
		await _ticks(1)
		watch.call()
	Input.action_release("move_back")
	await _ticks(20)
	_check(p.global_position.z > 21.0 and p.is_on_floor() and minys.y > 5.9, "toxic: walks across the bridge onto the south platform (z %.1f, lowest y %.2f)" % [p.global_position.z, minys.y])

	# Jump on the platform.
	Input.action_press("jump")
	await _ticks(2)
	Input.action_release("jump")
	await _ticks(10)
	var up := p.global_position.y
	await _ticks(60)
	_check(up > 6.8 and p.is_on_floor() and absf(p.global_position.y - 6.0) < 0.05, "toxic: jumps and lands back on the platform")

	# Down a ramp from the central platform onto a corner platform.
	p.global_position = Vector3(7.5, 6.05, 7.5)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	await _ticks(10)
	minys.y = INF
	Input.action_press("move_back", 0.6)
	Input.action_press("move_right", 0.6)
	for i in 120:
		await _ticks(1)
		watch.call()
		if p.global_position.x > 15.0:
			break
	Input.action_release("move_back")
	Input.action_release("move_right")
	await _ticks(20)
	_check(p.is_on_floor() and absf(p.global_position.y - 4.0) < 0.1 and p.global_position.x > 12.0 and minys.y > 3.9, "toxic: walks down a ramp onto a corner platform (%s)" % p.global_position)

	# Up a staircase from a corner platform (y 4) to its top (y 6).
	p.global_position = Vector3(17.0, 4.05, -16.0)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	await _ticks(10)
	Input.action_press("move_forward", 0.7)
	var top := {"y": -INF}
	for i in 140:
		await _ticks(1)
		if p.global_position.z < -27.0:
			top.y = maxf(top.y, p.global_position.y)
		if p.global_position.z < -29.0:
			break
	Input.action_release("move_forward")
	_check(top.y > 5.6, "toxic: climbs the stairs from a corner platform (top y %.2f)" % top.y)

	# Major structures block: the central tower and the outer wall.
	p.global_position = Vector3(0, 6.05, 7.0)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	await _ticks(5)
	Input.action_press("move_forward")
	await _ticks(90)
	Input.action_release("move_forward")
	_check(p.global_position.z > 3.5 and p.global_position.z < 4.6, "toxic: can't walk through the central tower (z %.2f)" % p.global_position.z)
	p.global_position = Vector3(-20, 6.05, 33.5)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	await _ticks(5)
	Input.action_press("move_back")
	await _ticks(60)
	Input.action_release("move_back")
	_check(p.global_position.z < 36.0 and p.is_on_floor(), "toxic: can't walk through the outer wall (z %.2f)" % p.global_position.z)

	# Camera behind the player with the tower in the way: stays out of it.
	p.global_position = Vector3(0, 6.05, -5.0)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	rig.yaw = 0.0
	await _ticks(30)
	var cz := rig.camera.global_position.z
	_check(cz < -3.4, "toxic: camera never goes inside the tower (z %.2f)" % cz)

	# HazardFluid: not walkable, falling in sends the player back to spawn.
	p.global_position = Vector3(8.0, 5.0, 16.0)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	var low := {"y": INF}
	for i in 90:
		await _ticks(1)
		low.y = minf(low.y, p.global_position.y)
		if p.global_position.distance_to(spawn) < 0.5:
			break
	_check(p.global_position.distance_to(spawn) < 0.5 and low.y > 0.5, "toxic: falling into HazardFluid respawns the player (lowest y %.2f)" % low.y)
	# Robots die in it.
	var r: RobotEnemy = main.get_node("Targets/Robot4")
	r.global_position = Vector3(-8.0, 3.0, 16.0)
	for i in 90:
		await _ticks(1)
		if not r.alive:
			break
	_check(not r.alive, "toxic: a robot that falls into HazardFluid dies")
	# Out of bounds (below the level).
	p.global_position = Vector3(60.0, -4.0, 60.0)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	for i in 60:
		await _ticks(1)
		if p.global_position.distance_to(spawn) < 0.5:
			break
	_check(p.global_position.distance_to(spawn) < 0.5, "toxic: falling out of the level respawns the player")

	# Combat: lock a robot across the south bridge; the cannons hit it.
	await _ticks(30)
	var target: RobotEnemy = main.get_node("Targets/LoneRobot2")
	target.global_position = Vector3(1.0, 6.0, 24.0)
	await _ticks(10)
	var hits0 := target.hits
	var sel: TargetSelector = p.get_node("Input/TargetSelector")
	sel.clear()
	sel.tap_target(target.get_node("Targetable"))
	for i in 240:
		await _ticks(1)
		if target.hits > hits0:
			break
	_check(target.hits > hits0, "toxic: weapons fire at and hit a locked robot")
	sel.clear()

	await _robot_boss_tests(main)

	# Stress test robots stand on platforms.
	StressTest.populate(main, 30)
	await _ticks(60)
	var standing := 0
	for sr: RobotEnemy in main.get_node("Targets").get_children():
		if sr.name.begins_with("StressRobot") and sr.alive and sr.global_position.y > 3.9:
			standing += 1
	_check(standing == 30, "toxic: stress test robots all stand on the arena's platforms (%d/30)" % standing)
	main.queue_free()
	await _ticks(2)


## World positions of (a sample of) a skinned mesh's vertices, optionally
## only those mostly bound to one of `bones`.
func _skinned_points(mi: MeshInstance3D, stride: int, bones: Array = []) -> PackedVector3Array:
	var sk := mi.get_node(mi.skeleton) as Skeleton3D
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bi: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var bw: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bi.size() / verts.size()
	var bone_of := {}
	for i in mi.skin.get_bind_count():
		bone_of[i] = sk.find_bone(mi.skin.get_bind_name(i))
	var out := PackedVector3Array()
	for v in range(0, verts.size(), stride):
		var p := Vector3.ZERO
		var keep := bones.is_empty()
		for k in per:
			var w := bw[v * per + k]
			if w <= 0.0:
				continue
			var b: int = bone_of[bi[v * per + k]]
			if w > 0.5 and b in bones:
				keep = true
			p += (sk.get_bone_global_pose(b) * mi.skin.get_bind_pose(bi[v * per + k]) * verts[v]) * w
		if keep:
			out.append(sk.global_transform * p)
	return out


## Robot boss: asset, chaingun, missile + marker, chest core loop, death.
func _robot_boss_tests(main: Node) -> void:
	var boss: RobotBoss = main.get_node_or_null("Targets/RobotBoss")
	_check(boss != null and boss.alive, "boss: the robot boss stands in Toxic Arena")
	if boss == null:
		return
	var p: PlayerController = main.players[1]
	var sk: Skeleton3D = boss.model.find_child("Skeleton3D", true, false)
	var body: MeshInstance3D = null
	for mi: MeshInstance3D in boss.model.find_children("*", "MeshInstance3D", true, false):
		if mi.skin:
			body = mi
	# Asset.
	var clips := [&"Idle", &"Walking", &"Running", &"Walk_Fight_Back", &"Heavy_Death"]
	_check(sk.get_bone_count() == 28 and clips.all(func(c: StringName) -> bool: return boss.anim.has_animation(c))
		and [&"Chest_Open", &"Chest_Close", &"Chest_Open_Hold", &"Chest_Closed"].all(func(c: StringName) -> bool: return boss.chest_player.has_animation(c))
		and boss.gun_player.has_animation(RobotBoss.GUN_CLIP), "boss: 28-bone rig, body clips, chest and chaingun clips on their own layers")
	_check(boss.core != null and boss.core.mesh.get_faces().size() / 3 <= 200 and (boss.core.get_active_material(0) as StandardMaterial3D).emission_enabled
		and boss.core.get_active_material(0) != body.get_active_material(0), "boss: Reactor_Core is its own light node with its own emissive material")
	_check(boss.missile_socket != null and boss.model.find_child("Chest_Plate_Carriage", true, false).get_class() == "Node3D"
		and boss.model.find_children("*issile*", "MeshInstance3D", true, false).is_empty(), "boss: Missile_Spawn socket, no missile mesh, slide rails gone")
	var bm := body.get_active_material(0) as StandardMaterial3D
	_check(bm.albedo_texture != null and bm.normal_texture != null and bm.metallic_texture != null, "boss: body keeps its own colour / normal / metal-roughness textures")
	var draws := 0
	var tris := 0
	for mi: MeshInstance3D in boss.model.find_children("*", "MeshInstance3D", true, false):
		draws += mi.mesh.get_surface_count()
		tris += mi.mesh.get_faces().size() / 3
	_check(draws <= 7 and tris < 120000, "boss: %d draw calls (6 + the core's glow), %d triangles" % [draws, tris])

	# Rig: a body clip moves the skeleton (no rest-pose lock).
	var leg := sk.find_bone("mixamorig_LeftUpLeg")
	boss.anim.play(&"Walking")
	var swing := 0.0
	var q1 := Quaternion()
	for k in 12:
		boss.anim.seek(boss.anim.current_animation_length * k / 12.0, true)
		boss.anim.advance(0.0)
		if k == 0:
			q1 = sk.get_bone_pose_rotation(leg)
		swing = maxf(swing, q1.angle_to(sk.get_bone_pose_rotation(leg)))
	_check(swing > 0.15, "boss: body animations drive the rig (thigh swings %.0f deg)" % rad_to_deg(swing))
	boss.anim.play(&"Idle")
	await _ticks(3)  # bone attachments follow a frame later

	# Chaingun: spins about its own fixed axis on demand, stops on demand,
	# stays on the arm.
	var fore := sk.find_bone("mixamorig_LeftForeArm")
	var rel0 := (sk.global_transform * sk.get_bone_global_pose(fore)).affine_inverse() * boss.rotor.global_transform
	boss.set_spin(1.0)
	await _ticks(2)
	var r0 := boss.rotor.quaternion
	await _ticks(6)
	var r1 := boss.rotor.quaternion
	var axis := (r0.inverse() * r1).get_axis()
	_check(r0.angle_to(r1) > 0.3 and absf(absf(axis.dot(RobotBoss.ROTOR_AXIS.normalized())) - 1.0) < 0.02, "boss: chaingun barrel spins about its own axis (%.0f deg in 0.1 s)" % rad_to_deg(r0.angle_to(r1)))
	var rel1 := (sk.global_transform * sk.get_bone_global_pose(fore)).affine_inverse() * boss.rotor.global_transform
	_check(rel0.origin.distance_to(rel1.origin) < 0.001, "boss: barrel stays mounted on the forearm while spinning")
	boss.set_spin(0.0)
	await _ticks(2)
	var s0 := boss.rotor.quaternion
	await _ticks(6)
	_check(s0.angle_to(boss.rotor.quaternion) < 0.001, "boss: chaingun stops spinning on demand")

	# Missile: from the launcher socket, at the spot where the player stood.
	p.global_position = boss.global_position + Vector3(1.0, 0.05, 11.0)
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	await _ticks(10)
	var stood := p.global_position
	var events := {"exposed": -1.0, "protected": -1.0, "boom": Vector3.INF}
	var t_ms := func() -> float: return Time.get_ticks_msec() / 1000.0
	boss.core_exposed.connect(func() -> void: events.exposed = Engine.get_physics_frames() / 60.0, CONNECT_ONE_SHOT)
	boss.core_protected.connect(func() -> void: events.protected = Engine.get_physics_frames() / 60.0, CONNECT_ONE_SHOT)
	var launch_frame := Engine.get_physics_frames()
	var m := boss.fire_missile(p.global_position)
	m.exploded.connect(func(at: Vector3) -> void: events.boom = at, CONNECT_ONE_SHOT)
	_check(m.global_position.distance_to(boss.missile_socket.global_position) < 0.05, "boss: missile appears at the launcher's Missile_Spawn")
	_check(boss.last_missile_target.distance_to(stood) < 0.15, "boss: missile targets where the player stood at launch")
	var marker := boss.last_marker
	_check(is_instance_valid(marker) and marker.global_position.distance_to(boss.last_missile_target) < 0.1, "boss: warning marker on the ground at the impact point")
	# The player runs away: the missile and marker don't follow.
	p.global_position = stood + Vector3(0.0, 0.0, 6.0)
	p.reset_physics_interpolation()
	var marker_moved := 0.0
	var marker_at := marker.global_position
	for i in 240:
		await _ticks(1)
		if is_instance_valid(marker):
			marker_moved = maxf(marker_moved, marker.global_position.distance_to(marker_at))
		if events.boom != Vector3.INF:
			break
	_check(events.boom != Vector3.INF and (events.boom as Vector3).distance_to(boss.last_missile_target) < 0.5, "boss: missile lands on the recorded point (%.2f m off)" % (events.boom as Vector3).distance_to(boss.last_missile_target))
	_check((events.boom as Vector3).distance_to(p.global_position) > 3.0, "boss: missile doesn't chase the player who moved away")
	_check(marker_moved < 0.01, "boss: marker stays fixed while the player moves")
	await _ticks(12)
	_check(not is_instance_valid(marker), "boss: marker removed once the missile lands")

	# Chest: opened by the launch, flap hinged downward, head untouched.
	_check(events.exposed > 0.0 and events.exposed - launch_frame / 60.0 < 0.5, "boss: launching opens the chest and exposes the core (%.2f s)" % (events.exposed - launch_frame / 60.0))
	var flap_up := boss.flap.global_basis.y.normalized()
	_check(flap_up.y < -0.3 and flap_up.dot(boss.model.global_basis.z.normalized()) > 0.3, "boss: flap swung open downward (%s)" % flap_up.snapped(Vector3.ONE * 0.01))
	var chest_only := true
	for c in boss.chest_player.get_animation_list():
		var ca := boss.chest_player.get_animation(c)
		for t in ca.get_track_count():
			chest_only = chest_only and String(ca.track_get_path(t)).ends_with("Chest_Frown_Plate_Hinge")
	_check(chest_only, "boss: chest clips move only the flap (head and face untouched)")
	# Core visible from the front while open, hidden behind the flap when closed.
	var front := boss.core.global_position + boss.model.global_basis.z * 2.0 + Vector3.UP * 0.2
	_check(not _segment_hits_flap(boss, front, boss.core.global_position), "boss: core clearly visible with the flap open")
	# Core-only damage while open.
	var h0 := boss.health
	var aim := boss.core.global_position
	boss.apply_damage(DamageInfo.make(1.0, DamageInfo.Type.ENERGY, aim + boss.model.global_basis.z * 0.6, -boss.model.global_basis.z, 2.0))
	var core_dmg := h0 - boss.health
	h0 = boss.health
	var leg_at := sk.global_transform * sk.get_bone_global_pose(leg).origin
	boss.apply_damage(DamageInfo.make(1.0, DamageInfo.Type.ENERGY, leg_at + boss.model.global_basis.z * 0.3, -boss.model.global_basis.z, 2.0))
	var leg_dmg := h0 - boss.health
	_check(absf(core_dmg - 1.0) < 0.01 and absf(leg_dmg - boss.armour_damage_scale) < 0.01 and boss.core_hits == 1, "boss: open core takes full damage (%.2f), armour only %.2f" % [core_dmg, leg_dmg])
	# Stays open ~3 s, then closes.
	for i in 300:
		await _ticks(1)
		if events.protected > 0.0:
			break
	var window: float = events.protected - events.exposed
	_check(absf(window - boss.core_exposed_time) < 0.1, "boss: core vulnerable for %.2f s (~3 s)" % window)
	await _ticks(40)
	_check(boss.flap.quaternion.is_equal_approx(Quaternion()) and boss.flap.position.length() < 0.001, "boss: chest closes back exactly")
	_check(_segment_hits_flap(boss, front, boss.core.global_position), "boss: closed flap hides and protects the core")
	h0 = boss.health
	boss.apply_damage(DamageInfo.make(1.0, DamageInfo.Type.ENERGY, aim + boss.model.global_basis.z * 0.6, -boss.model.global_basis.z, 2.0))
	_check(absf(h0 - boss.health - boss.armour_damage_scale) < 0.01, "boss: closed core takes only armour damage")

	# The open flap never cuts into the arms, weapons or body while it moves.
	boss.chest_player.play(&"Chest_Open_Hold")
	var worst := 0
	for clip in [&"Idle", &"Walking", &"Walk_Fight_Back", &"Running"]:
		boss.anim.play(clip)
		for k in 6:
			boss.anim.seek(boss.anim.current_animation_length * k / 6.0, true)
			boss.chest_player.advance(0.0)
			worst = maxi(worst, _points_in_flap(boss, _skinned_points(body, 7)))
	_check(worst == 0, "boss: open flap clear of arms, weapons and torso in every move (%d points inside)" % worst)
	boss.chest_player.play(&"Chest_Closed")
	boss.anim.play(&"Idle")

	await _robot_boss_v2_tests(main, boss, body)

	# Death: collapses and lies flat, feet not planted, weapons attached.
	var foot := sk.find_bone("mixamorig_LeftFoot")
	var foot0 := sk.global_transform * sk.get_bone_global_pose(foot).origin
	boss.die()
	var foot_move := 0.0
	for i in 70:
		await _ticks(1)
		foot_move = maxf(foot_move, (sk.global_transform * sk.get_bone_global_pose(foot).origin).distance_to(foot0))
	await _ticks(60)
	_check(boss.anim.assigned_animation == RobotBoss.DEATH_CLIP and not boss.alive, "boss: dies with its heavy death animation")
	var pts := _skinned_points(body, 9)
	var lo := INF
	for q in pts:
		lo = minf(lo, q.y)
	var ground := boss.global_position.y
	var sc := boss.model_scale
	_check(lo > ground - 0.03 * sc and lo < ground + 0.06 * sc, "boss: corpse rests on the floor, nothing through it (lowest %.3f m)" % (lo - ground))
	var hips_at := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_Hips")).origin
	var head_at := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_Head")).origin
	var torso := head_at - hips_at
	_check(hips_at.y - ground < 0.5 * sc and head_at.y - ground < 0.8 * sc and Vector2(torso.x, torso.z).length() > absf(torso.y) * 2.0,
		"boss: lies flat on its chest, not kneeling or upright (hips %.2f m, head %.2f m up)" % [hips_at.y - ground, head_at.y - ground])
	_check(foot_move > 0.2 * sc, "boss: feet don't stay planted while it falls (%.2f m)" % foot_move)
	var rel2 := (sk.global_transform * sk.get_bone_global_pose(fore)).affine_inverse() * boss.rotor.global_transform
	_check(rel0.origin.distance_to(rel2.origin) < 0.001, "boss: weapons stay attached through the death")
	_check(not boss.get_node("Targetable").is_valid_target(), "boss: dead boss can't be targeted")


## Does the segment a..b pass through the chest flap's box?
func _segment_hits_flap(boss: RobotBoss, a: Vector3, b: Vector3) -> bool:
	var box: AABB = boss.flap.mesh.get_aabb() if boss.flap is MeshInstance3D else AABB()
	var inv := boss.flap.global_transform.affine_inverse()
	var la := inv * a
	var lb := inv * b
	for i in 41:
		if box.has_point(la.lerp(lb, i / 40.0)):
			return true
	return false


## How many points lie inside the flap's box (shrunk 1 cm)?
func _points_in_flap(boss: RobotBoss, pts: PackedVector3Array) -> int:
	var box: AABB = (boss.flap as MeshInstance3D).mesh.get_aabb().grow(-0.01)
	var inv := boss.flap.global_transform.affine_inverse()
	var n := 0
	for q in pts:
		if box.has_point(inv * q):
			n += 1
	return n


## Robot boss, round 2: 4x size, heavy walk, aimed chaingun with a synced
## fire rate, quick orange impacts, the integrated rocket arm.
func _robot_boss_v2_tests(main: Node, boss: RobotBoss, body: MeshInstance3D) -> void:
	var p: PlayerController = main.players[1]
	var sk: Skeleton3D = boss.model.find_child("Skeleton3D", true, false)
	var sc := boss.model_scale
	var ground := boss.global_position.y
	# Size: scaled at the root, collider and aim point with it, feet on the floor.
	var cap := boss.get_node("Collision").shape as CapsuleShape3D
	_check(absf(sc - 4.0) < 0.01 and boss.model.global_basis.get_scale().is_equal_approx(Vector3.ONE * sc)
		and absf(cap.radius - 0.55 * sc) < 0.01 and absf(cap.height - 1.75 * sc) < 0.01, "boss: 4x size; collider scaled with it (r %.2f, h %.2f m)" % [cap.radius, cap.height])
	boss.anim.play(&"Idle")
	await _ticks(3)
	var lo := INF
	var hi := -INF
	for q in _skinned_points(body, 9):
		lo = minf(lo, q.y)
		hi = maxf(hi, q.y)
	_check(absf(lo - ground) < 0.05 * sc and hi - ground > 1.5 * sc, "boss: standing on the floor (lowest %.2f m), %.1f m tall" % [lo - ground, hi - ground])
	_check(boss.get_node("Targetable").position.y > 1.0 * sc - 0.01 and absf(boss.get_node("Targetable").select_radius - 1.2 * sc) < 0.01, "boss: aim point and tap area follow the size")
	_check(boss.chaingun_muzzle.global_position.distance_to(boss.rotor.global_position) > 0.25 * sc, "boss: chaingun muzzle at the barrel tips")
	# Rocket arm: housing on the forearm, launch line out through its port.
	var housing := boss.model.find_child("Rocket_Launcher_Housing", true, false) as MeshInstance3D
	var ms := boss.missile_socket.global_transform
	_check(housing != null and housing.get_parent() is BoneAttachment3D and housing.get_parent().bone_name == "mixamorig_RightForeArm", "boss: rocket launcher housing built onto the right forearm")
	# The launch line runs from inside the housing straight out of its port.
	var crossings := -1
	var inside := false
	if housing:
		var faces := housing.mesh.get_faces()
		var xf := housing.global_transform
		var a := ms.origin
		var b := ms.origin + ms.basis.z.normalized() * 1.5 * sc
		crossings = 0
		for i in range(0, faces.size(), 3):
			if Geometry3D.segment_intersects_triangle(a, b, xf * faces[i], xf * faces[i + 1], xf * faces[i + 2]) != null:
				crossings += 1
		var box := housing.mesh.get_aabb()
		inside = box.has_point(xf.affine_inverse() * a)
	_check(inside and crossings == 0, "boss: Missile_Spawn sits in the launcher's bore and its path out is clear (%d faces crossed)" % crossings)

	# Walk: walks at the speed its feet show, feet planted don't slide.
	boss.always_active = true
	boss._missile_t = 999.0  # no missile attacks during these checks
	var home := boss.home_radius
	boss.home_radius = 40.0
	var fwd := Vector3(sin(boss._yaw), 0, cos(boss._yaw))
	p.global_position = boss.global_position + fwd * (boss.preferred_range.y + 8.0) + Vector3(0, 0.05, 0)
	p.reset_physics_interpolation()
	var feet := [sk.find_bone("mixamorig_LeftFoot"), sk.find_bone("mixamorig_RightFoot")]
	var walked := {"frames": 0, "speed_err": 0.0}
	var tracks := [[], []]
	for i in 150:
		await _ticks(1)
		if i < 60 or boss.anim.current_animation != RobotBoss.WALK_CLIP:
			continue
		walked.frames += 1
		var v := Vector2(boss.linear_velocity.x, boss.linear_velocity.z).length()
		walked.speed_err = maxf(walked.speed_err, absf(v - boss.walk_anim_ground_speed()))
		for k in 2:
			tracks[k].append(sk.global_transform * sk.get_bone_global_pose(feet[k]).origin)
	_check(walked.frames > 60, "boss: walks with its heavy walk (%d frames)" % walked.frames)
	_check(walked.speed_err < 0.05, "boss: walk animation speed matches the ground speed (worst %.3f m/s off)" % walked.speed_err)
	# Planted foot: lowest stretch of each foot's track.
	var worst_slide := 0.0
	for k in 2:
		var tr: Array = tracks[k]
		if tr.is_empty():
			continue
		var floor_y := INF
		for q: Vector3 in tr:
			floor_y = minf(floor_y, q.y)
		var start := Vector3.INF
		for q: Vector3 in tr:
			if q.y < floor_y + 0.01 * sc:
				if start == Vector3.INF:
					start = q
				worst_slide = maxf(worst_slide, Vector2(q.x - start.x, q.z - start.z).length())
			else:
				start = Vector3.INF
	_check(worst_slide < 0.06 * sc, "boss: planted feet don't slide while walking (%.3f m)" % worst_slide)
	# Stop: the player comes closer, it halts and settles into idle.
	p.global_position = boss.global_position + fwd * (boss.preferred_range.x + 2.0) + Vector3(0, 0.05, 0)
	p.reset_physics_interpolation()
	for i in 120:
		await _ticks(1)
	_check(boss.anim.current_animation == &"Idle" and absf(boss._speed) < 0.01, "boss: stops walking and settles into idle (%s)" % boss.anim.current_animation)

	# Chaingun: aimed where it fires, rate synced with the barrels.
	p.global_position = boss.global_position + fwd.rotated(Vector3.UP, 0.35) * 16.0 + Vector3(0, 0.05, 0)
	p.reset_physics_interpolation()
	boss._gun_phase = 0
	boss._gun_t = 0.0
	var shots0 := boss.bullets_fired
	var err := {"max": 0.0, "dir": 0.0}
	var t_fire := {"first": -1, "count": 0}
	for i in 150:
		await _ticks(1)
		if boss.bullets_fired > shots0:
			var m := boss.chaingun_muzzle.global_transform
			err.max = maxf(err.max, rad_to_deg(boss.last_shot_dir.angle_to(m.basis.z.normalized())))
			err.dir = maxf(err.dir, rad_to_deg(boss.last_shot_dir.angle_to((p.global_position + Vector3.UP - m.origin).normalized())))
			if t_fire.first < 0:
				t_fire.first = i
			shots0 = boss.bullets_fired
			t_fire.count += 1
	_check(boss.gun_aim.aim_error_deg < 4.0, "boss: chaingun arm aims at the player (%.1f deg off)" % boss.gun_aim.aim_error_deg)
	_check(t_fire.count > 0 and err.max <= boss.chaingun_spread_deg * 1.5 + 0.1, "boss: rounds fly the way the barrels point (%.1f deg)" % err.max)
	_check(err.dir < boss.chaingun_fire_cone_deg + 2.0, "boss: and towards the player (%.1f deg)" % err.dir)
	# Rate: rounds per second = chaingun_fire_rate, barrels spin to match.
	boss.set_spin(1.0)
	_check(absf(boss.gun_player.speed_scale - boss.chaingun_fire_rate / RobotBoss.FULL_CLIP_RATE) < 0.001, "boss: barrel spin set by the fire rate")
	var rate := await _boss_fire_rate(boss)
	_check(absf(rate - boss.chaingun_fire_rate) <= 1.5, "boss: fires %.1f rounds/s (fire rate %.0f)" % [rate, boss.chaingun_fire_rate])
	var old_rate := boss.chaingun_fire_rate
	boss.chaingun_fire_rate = 15.0
	rate = await _boss_fire_rate(boss)
	_check(absf(rate - 15.0) <= 2.0 and absf(boss.gun_player.speed_scale - 1.5) < 0.05, "boss: retuned to 15/s, fires %.1f/s with the barrels spinning faster" % rate)
	boss.chaingun_fire_rate = old_rate

	# Orange impact: brief, no crackle, then gone (with the gun quiet).
	boss.always_active = false
	boss._gun_phase = 0
	boss.set_spin(0.0)
	await _ticks(120)
	var fx_t0 := PlasmaFx.busy_count()
	PlasmaFx.impact(self, boss.global_position + Vector3(0, 0.02, 3), Vector3.UP, true, RobotBoss.BULLET_COLOR, RobotBoss.BULLET_HOT, boss.chaingun_impact_lifetime, false)
	await _ticks(int(boss.chaingun_impact_lifetime * 30.0))
	var mid := PlasmaFx.busy_count()
	await _ticks(int(boss.chaingun_impact_lifetime * 60.0) + 6)
	_check(mid > fx_t0 and PlasmaFx.busy_count() <= fx_t0, "boss: orange impact mark glows briefly and is gone after %.2f s" % boss.chaingun_impact_lifetime)

	boss.always_active = false
	boss.home_radius = home
	boss.set_spin(0.0)
	boss._gun_phase = 0
	p.global_position = Vector3(0, 6.05, 8.5)
	p.reset_physics_interpolation()
	boss.anim.play(&"Idle")
	await _ticks(10)


## Rounds per second while the chaingun fires at full spin (1 s sample).
func _boss_fire_rate(boss: RobotBoss) -> float:
	boss._gun_phase = 2
	boss._gun_t = 99.0
	boss.set_spin(1.0)
	await _ticks(20)
	var n0 := boss.bullets_fired
	await _ticks(60)
	var n := boss.bullets_fired - n0
	boss._gun_t = 0.0
	return n
