extends SceneTree
## Online co-op, end to end over the network: run twice at once (ENet on
## localhost), one with `-- --role=host`, one with `-- --role=client`
## (tests/run_net_pair.sh does both). Each prints PASS / FAIL lines and
## "NET FAILURES: n".
##
## Host: Skyforge, deploys, opens the session; once the client is in it
## moves its player, lets robots fight, kills one, blows a barrel, clears the
## waves; the lift rises; when both players stand on it the squad rides down
## to the next part. Client: joins, gets the host's level, deploys and checks
## it sees all of that, and that its own player shows on the host.

const PORT := 24711

var role := ""
var failures := 0
var main: Node


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.substr(7)
	_run.call_deferred()


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + "[%s] %s" % [role, msg])
	if not cond:
		failures += 1


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


## Wait for `cond`: at least `limit` ticks and as long in real time (the
## two games run faster than real time, at different speeds).
func until(cond: Callable, limit := 600) -> bool:
	var end := Time.get_ticks_msec() + int(limit * 1000.0 / 60.0)
	var i := 0
	while i < limit or Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await physics_frame
		i += 1
	return cond.call()


func net() -> Net:
	return Net.instance


func _run() -> void:
	if net() == null:
		print("NET FAILURES: 1 (no NetSession autoload)")
		quit(1)
		return
	if role == "host":
		await _host()
	else:
		await _client()
	print("NET FAILURES: %d" % failures)
	net().leave(false)
	await ticks(5)
	quit(1 if failures else 0)


func _load(path: String, front_end := 0) -> void:
	main = load(path).instantiate()
	main.set(&"front_end_mode", front_end)
	root.add_child(main)
	current_scene = main


func _host() -> void:
	_load("res://scenes/skyforge_arena.tscn")
	await ticks(30)
	check(net().host_enet(PORT) == OK and net().online and Net.is_authority(), "hosting")
	var ok := await until(func() -> bool:
		for pid in net().roster:
			if net().roster[pid]["slot"] == 2 and net().roster[pid]["deployed"]:
				return true
		return false, 1800)
	check(ok, "the client joined and deployed")
	ok = await until(func() -> bool: return main.players.has(2), 120)
	var mate: PlayerController = main.players.get(2)
	check(ok and mate != null and mate.is_remote and mate.input is NetPlayerInput, "the client's player is here, driven by their device")
	ok = await until(func() -> bool: return mate != null and (mate.input as NetPlayerInput).packets > 10, 300)
	check(ok, "its moves arrive (%d packets)" % ((mate.input as NetPlayerInput).packets if mate else 0))
	var hp := mate.health if mate else 0.0
	if mate:
		mate.apply_damage(DamageInfo.make(5.0, DamageInfo.Type.ENERGY, mate.global_position, Vector3.FORWARD))
	check(mate != null and is_equal_approx(mate.health, hp), "hits on the client's player here don't change its health (its device decides)")
	# Move the host's player (the client checks it follows).
	var me: PlayerController = main.players[1]
	me.global_position = Vector3(3, 40.2, 46)
	me.reset_physics_interpolation()
	await ticks(120)
	# Kill a robot, blow a barrel.
	var g: RobotEnemy = main.get_node("Targets/GateGrunt")
	g.apply_damage(DamageInfo.make(1.0e4, DamageInfo.Type.ENERGY, g.global_position, Vector3.FORWARD))
	var b: ToxicBarrel = main.get_node("Barrels/HubBarrel")
	b.explode()
	await ticks(120)
	# Robots fire at players: events go out.
	RobotEnemy.ai_enabled = true
	ok = await until(func() -> bool: return int(net().sent.get(&"fire", 0)) > 3, 900)
	check(ok, "robot shots go to the client (%d)" % int(net().sent.get(&"fire", 0)))
	# Waves done -> the lift.
	var dir: WaveDirector = main.get_node("WaveDirector")
	dir.wave_gap = 0.2
	dir.spawn_gap = 0.05
	for c in main.get_node("Targets").get_children():
		if c is RobotEnemy and c.alive:
			c.apply_damage(DamageInfo.make(1.0e4, DamageInfo.Type.ENERGY, c.global_position, Vector3.FORWARD))
	ok = await until(func() -> bool: return dir.spawned >= 2, 900)
	check(ok, "wave robots teleport in (and are sent)")
	await ticks(60)
	dir.finish_now()
	var lift: ElevatorLift = main.get_node("ElevatorLift")
	lift.rise_time = 1.0
	ok = await until(func() -> bool: return lift.state == ElevatorLift.State.READY, 300)
	check(ok, "the lift is up")
	me.global_position = lift.global_position + Vector3(1.5, 0.3, 0)
	me.reset_physics_interpolation()
	ok = await until(func() -> bool: return lift.state == ElevatorLift.State.COUNTDOWN, 900)
	check(ok and lift.riders == 2 and lift.aboard == 2, "both players aboard -> countdown (%d / %d)" % [lift.aboard, lift.riders])
	lift.ride_time = 1.5
	ok = await until(func() -> bool: return current_scene != main and current_scene != null and current_scene.scene_file_path.ends_with("toxic_works.tscn"), 900)
	check(ok, "the squad rides down to the next part")
	main = current_scene
	ok = await until(func() -> bool: return main.players.has(1) and main.players.has(2), 600)
	check(ok, "both players are in the next part")
	# Give the client time to check, then finish.
	await until(func() -> bool: return net().roster.size() < 2, 900)


func _client() -> void:
	# Like on a phone: the title, TAP TO START, then JOIN on character select.
	_load("res://scenes/skyforge_arena.tscn", 1)
	await ticks(20)
	main.front_end.press_start()
	await ticks(5)
	var ok := false
	for attempt in 40:
		net().join_enet("127.0.0.1", PORT)
		ok = await until(func() -> bool: return net().online or net().failed, 120)
		if net().online:
			break
		await ticks(30)
	check(net().online and not Net.is_authority(), "joined the host")
	# Already in the host's level: no reload, the world is put in step.
	ok = await until(func() -> bool: return int(net().received.get(&"world", 0)) > 0, 300)
	check(ok and current_scene == main and main.front_end != null and main.front_end.screen == FrontEnd.Screen.SELECT,
		"same level as the host: no reload, still at the character select, world in step")
	await ticks(30)
	main.front_end.press_character(&"harbinger")
	main.front_end.press_deploy()
	ok = await until(func() -> bool: return main.players.has(net().my_slot), 300)
	var me: PlayerController = main.players.get(net().my_slot)
	check(ok and net().my_slot == 2 and me != null and not me.is_remote, "deployed as player 2")
	ok = await until(func() -> bool: return main.players.has(1), 300)
	var host: PlayerController = main.players.get(1)
	check(ok and host.is_remote, "the host's player is here")
	var g: RobotEnemy = main.get_node("Targets/GateGrunt")
	check(g.net_puppet, "robots here are the host's (puppets)")
	ok = await until(func() -> bool: return host.global_position.distance_to(Vector3(3, 40.2, 46)) < 1.5, 600)
	check(ok, "the host's player moves here as it does there (%s)" % host.global_position)
	ok = await until(func() -> bool: return not g.alive, 600)
	check(ok, "a robot the host killed dies here")
	ok = await until(func() -> bool: return not is_instance_valid(main.get_node_or_null("Barrels/HubBarrel")) or main.get_node("Barrels/HubBarrel").exploded, 300)
	check(ok, "a barrel the host blew up goes off here")
	ok = await until(func() -> bool: return int(net().received.get(&"fire", 0)) >= 2, 1200)
	check(ok, "robots fire here when the host's do (%d)" % int(net().received.get(&"fire", 0)))
	ok = await until(func() -> bool: return int(net().received.get(&"spawn", 0)) >= 2, 900)
	check(ok, "wave robots teleport in here too")
	var lift: ElevatorLift = main.get_node("ElevatorLift")
	ok = await until(func() -> bool: return lift.state == ElevatorLift.State.READY or lift.state == ElevatorLift.State.RISING, 1200)
	check(ok, "the lift rises here")
	await until(func() -> bool: return lift.state == ElevatorLift.State.READY, 300)
	me.global_position = lift.global_position + Vector3(-1.5, 0.3, 0)
	me.reset_physics_interpolation()
	ok = await until(func() -> bool: return current_scene != main and current_scene != null and current_scene.scene_file_path.ends_with("toxic_works.tscn"), 1800)
	check(ok, "rode down with the squad to the next part")
	main = current_scene
	ok = await until(func() -> bool: return main.players.has(1) and main.players.has(2) and (main.players[2] as PlayerController).character.id == &"harbinger", 600)
	check(ok, "both players in the next part, same character")
