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
