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
