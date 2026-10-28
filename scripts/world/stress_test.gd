class_name StressTest
extends Node
## Performance test mode. Open the game with ?stress=30 (web) or run with
## `-- --stress=30`: the arena's robots are replaced by N patrolling robots in
## front of the player, and the HUD shows frame timing and render counts.
## ?perf=1 shows the numbers without changing the arena.

const ROBOT := preload("res://scenes/enemies/robot_enemy.tscn")


static func _param(name: String) -> String:
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('%s') || ''" % name)
		return str(v) if v != null else ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.split("=", true, 1)[1]
	return ""


static func robot_count() -> int:
	return clampi(_param("stress").to_int(), 0, 120)


## ?bossfight=1 (test only): after DEPLOY the player stands on the battle
## arena's raised walkway next to the robot boss with two shotguns, locked
## onto it (re-locked every second), so a boss fight can be soaked in a
## browser. Without the parameter nothing changes.
static func boss_fight() -> bool:
	return _param("bossfight") != ""


static func start_boss_fight(main: Node, player: PlayerController) -> void:
	var bosses := main.find_children("*", "RobotBoss", true, false)
	if bosses.is_empty():
		return
	var boss := bosses[0] as RobotBoss
	player.global_position = Vector3(-20, 3.1, -16)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	var reg := load("res://resources/weapons/weapon_registry.tres") as WeaponRegistry
	var h := player.get_node("WeaponHolder") as WeaponHolder
	var lo := player.get_node("WeaponLoadout") as WeaponLoadout
	var sg := reg.find(&"shotgun")
	lo.unlock(sg)
	h.equip(sg, "Right")
	h.equip(sg, "Left")
	var sel := player.get_node("Input/TargetSelector") as TargetSelector
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	main.add_child(t)
	t.timeout.connect(func() -> void:
		if is_instance_valid(boss) and boss.alive and sel.get_selected("Right") == null:
			sel.forget_last_tap()
			sel.tap_target(boss.get_node("Targetable")))


## `?meleesoak=1` (test only): the rocket launcher on the right arm and a
## grunt put in front of the player and punched every ~1.2 s (melee swaps
## the arm to the pistol cannon and back each time) - the pattern before the
## iPhone crash report of 3m26s.
static func melee_soak() -> bool:
	return _param("meleesoak") != ""


static func start_melee_soak(main: Node, player: PlayerController) -> void:
	var reg := load("res://resources/weapons/weapon_registry.tres") as WeaponRegistry
	var h := player.get_node("WeaponHolder") as WeaponHolder
	var lo := player.get_node("WeaponLoadout") as WeaponLoadout
	var rl := reg.find(&"rocket_launcher")
	lo.unlock(rl)
	h.equip(rl, "Right")
	var t := Timer.new()
	t.wait_time = 1.2
	t.autostart = true
	main.add_child(t)
	t.timeout.connect(func() -> void:
		if not is_instance_valid(player) or player.melee.active:
			return
		var e: RobotEnemy = load("res://scenes/enemies/robot_enemy.tscn").instantiate()
		e.respawn_time = -1.0
		e.patrol_distance = 0.0
		main.add_child(e)
		var fwd := -player.global_basis.z
		fwd.y = 0.0
		e.global_position = player.global_position + fwd.normalized() * 2.6
		e.reset_physics_interpolation()
		player.get_tree().create_timer(0.15).timeout.connect(func() -> void:
			if is_instance_valid(player):
				player.melee.try_start()
			# Its remains go after a while (arena robots respawn instead).
			player.get_tree().create_timer(6.0).timeout.connect(func() -> void:
				if is_instance_valid(e):
					e.queue_free())))


## `?frostsoak=1` (test only): the Frost Byte on the right arm, the machine
## gun on the left. Every 12 s a crowd of 6 grunts and 2 skirmishers is put
## 9 m in front of the player, the Frost Byte is locked on it (one blizzard
## freezes the crowd) and the machine gun then shatters them one by one -
## the pattern before the iPhone freeze / crash with the Frost Byte.
static func frost_soak() -> bool:
	return _param("frostsoak") != ""


static func start_frost_soak(main: Node, player: PlayerController) -> void:
	var reg := load("res://resources/weapons/weapon_registry.tres") as WeaponRegistry
	var h := player.get_node("WeaponHolder") as WeaponHolder
	var lo := player.get_node("WeaponLoadout") as WeaponLoadout
	for id: StringName in [&"frost_byte", &"machine_gun"]:
		lo.unlock(reg.find(id))
	h.equip(reg.find(&"frost_byte"), "Right")
	h.equip(reg.find(&"machine_gun"), "Left")
	var sel := player.get_node("Input/TargetSelector") as TargetSelector
	var crowd: Array[RobotEnemy] = []
	var cycle := func() -> void:
		if not is_instance_valid(player):
			return
		for e in crowd:
			if is_instance_valid(e):
				e.queue_free()
		crowd.clear()
		var fwd := -player.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var side := fwd.cross(Vector3.UP)
		for i in 8:
			var scene: PackedScene = load("res://scenes/enemies/robot_skirmisher.tscn" if i >= 6 else "res://scenes/enemies/robot_enemy.tscn")
			var e: RobotEnemy = scene.instantiate()
			e.respawn_time = -1.0
			e.patrol_distance = 0.0
			main.add_child(e)
			e.global_position = player.global_position + fwd * (8.0 + (i / 4) * 1.6) + side * ((i % 4) - 1.5) * 1.3
			e.reset_physics_interpolation()
			crowd.append(e)
		player.get_tree().create_timer(0.4).timeout.connect(func() -> void:
			if crowd.size() > 1 and is_instance_valid(crowd[1]):
				sel._set_side("Right", crowd[1].get_node("Targetable")))
		for k in 8:
			player.get_tree().create_timer(2.5 + k * 0.7).timeout.connect(func() -> void:
				if k < crowd.size() and is_instance_valid(crowd[k]) and crowd[k].alive:
					sel._set_side("Left", crowd[k].get_node("Targetable")))
	var t := Timer.new()
	t.wait_time = 12.0
	t.autostart = true
	main.add_child(t)
	t.timeout.connect(cycle)
	cycle.call()


## `?fxsoak=1` (test only): every kind of effect set off in turn, 4 s apart,
## each step printed as "FXSOAK <step>" (and a crash-report note) - a
## browser test counts the shaders made and the long frames per step (the
## iPhone freezes: anything first drawn mid-play stalls a phone).
static var fx_done := false


static func fx_soak() -> bool:
	return _param("fxsoak") != ""


static func start_fx_soak(main: Node, player: PlayerController) -> void:
	var tree := main.get_tree()
	var reg := load("res://resources/weapons/weapon_registry.tres") as WeaponRegistry
	var h := player.get_node("WeaponHolder") as WeaponHolder
	var lo := player.get_node("WeaponLoadout") as WeaponLoadout
	var sel := player.get_node("Input/TargetSelector") as TargetSelector
	var step := func(name: String) -> void:
		print("FXSOAK ", name)
		DebugHud.note("fx " + name)
	var put := func(path: String, dist: float, side_off := 0.0) -> RobotEnemy:
		var e: RobotEnemy = load(path).instantiate()
		e.respawn_time = -1.0
		e.patrol_distance = 0.0
		main.add_child(e)
		var fwd := -player.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		e.global_position = player.global_position + fwd * dist + fwd.cross(Vector3.UP) * side_off + Vector3.UP * 0.2
		e.reset_physics_interpolation()
		return e
	var lock := func(e: Node3D, side: String) -> void:
		if is_instance_valid(e):
			sel._set_side(side, e.get_node("Targetable"))
	var wait := func(t: float) -> void:
		await tree.create_timer(t).timeout
	const GRUNT := "res://scenes/enemies/robot_enemy.tscn"
	const SKIRM := "res://scenes/enemies/robot_skirmisher.tscn"
	const SENT := "res://scenes/enemies/robot_sentinel.tscn"
	await wait.call(float(_param("fxdelay")) if _param("fxdelay") != "" else 3.0)
	step.call("start")
	await wait.call(3.0)
	# Glide melee onto a grunt 12 m off.
	var g: RobotEnemy = put.call(GRUNT, 12.0)
	await wait.call(0.6)
	lock.call(g, "Right")
	step.call("glide")
	player.melee.try_start()
	await wait.call(4.0)
	# The combo's five moves.
	step.call("combo")
	for k in 5:
		g = put.call(GRUNT, 2.4)
		await wait.call(0.25)
		player.melee.try_start()
		await wait.call(0.75)
	await wait.call(3.0)
	# Pistol cannons on a skirmisher (cells run out: the vent).
	var sk: RobotEnemy = put.call(SKIRM, 9.0)
	await wait.call(0.5)
	step.call("pistol")
	lock.call(sk, "Right")
	lock.call(sk, "Left")
	await wait.call(6.0)
	# Each weapon on a grunt.
	for id: StringName in [&"shotgun", &"machine_gun", &"rocket_launcher", &"frost_byte", &"black_hole_generator"]:
		var d := reg.find(id)
		lo.unlock(d)
		h.equip(d, "Right")
		if not d.heavy:
			h.equip(d, "Left")
		g = put.call(GRUNT, 10.0)
		await wait.call(0.8)
		step.call(String(id))
		lock.call(g, "Right")
		lock.call(g, "Left")
		await wait.call(6.0)
		if id == &"frost_byte":
			step.call("shatter")
			h.equip(reg.find(&"machine_gun"), "Left")
			lock.call(g, "Left")
			await wait.call(4.0)
	# A sentinel, shot down.
	h.equip(reg.find(&"machine_gun"), "Right")
	h.equip(reg.find(&"machine_gun"), "Left")
	var sn: RobotEnemy = put.call(SENT, 9.0)
	await wait.call(1.0)
	step.call("sentinel")
	lock.call(sn, "Right")
	lock.call(sn, "Left")
	await wait.call(8.0)
	# Shot by a grunt (hit flash, flinch).
	step.call("hurt")
	g = put.call(GRUNT, 7.0, 3.0)
	await wait.call(5.0)
	if is_instance_valid(g):
		g.queue_free()
	# A toxic barrel (Skyforge) blown up.
	for b: ToxicBarrel in main.find_children("*", "ToxicBarrel", true, false):
		step.call("barrel")
		b.global_position = player.global_position - player.global_basis.z * 6.0
		b.explode(player)
		await wait.call(5.0)
		break
	# The robot boss (test arena): rockets on it, close enough to be stomped.
	for boss: RobotBoss in main.find_children("*", "RobotBoss", true, false):
		step.call("boss")
		var rl := reg.find(&"rocket_launcher")
		lo.unlock(rl)
		h.equip(rl, "Right")
		h.equip(rl, "Left")
		player.global_position = boss.global_position + Vector3(4.0, 0.5, 0.0)
		player.reset_physics_interpolation()
		lock.call(boss, "Right")
		lock.call(boss, "Left")
		await wait.call(14.0)
		break
	# A fall (splash, sink, death wipe).
	step.call("fall")
	SlimeSplash.spawn(tree, player.global_position, SlimeSplash.SLIME)
	player.fell(player.global_position.y)
	await wait.call(4.0)
	# The glide again: its shaders shouldn't be made a second time.
	h.equip(h.default_weapon, "Right")
	h.equip(h.default_weapon, "Left")
	g = put.call(GRUNT, 12.0)
	await wait.call(0.6)
	lock.call(g, "Right")
	step.call("glide_again")
	player.melee.try_start()
	await wait.call(4.0)
	step.call("done")
	fx_done = true


static func perf_enabled() -> bool:
	return robot_count() > 0 or _param("perf") != ""


## Replace the arena's robots with `n` patrolling robots in a grid ahead of
## the spawn (clear of the ramp and pillars).
static func populate(main: Node, n: int) -> void:
	var targets := main.get_node_or_null("Targets")
	if targets == null:
		return
	for c in targets.get_children():
		c.queue_free()
	# A level can say where robots can stand (Toxic Arena: its platforms).
	var level := main.get_node_or_null("ToxicArena")
	var spots: Array[Vector3] = []
	if level and level.has_method("stress_spawn_points"):
		spots = level.stress_spawn_points(n)
	var cols := [-15.0, -9.0, -3.6, 3.6, 9.0, 15.0]
	var i := 0
	var row := 0
	while i < n:
		for x in cols:
			if i >= n:
				break
			var r: RobotEnemy = ROBOT.instantiate()
			r.name = "StressRobot%d" % i
			r.max_health = 2.0
			r.patrol_distance = 3.0
			r.patrol_axis = Vector3.RIGHT if (i % 2 == 0) else Vector3.BACK
			targets.add_child(r)
			r.global_position = spots[i] if i < spots.size() else Vector3(x + (row % 2) * 1.5, 0, -12.0 - row * 5.0)
			i += 1
		row += 1
