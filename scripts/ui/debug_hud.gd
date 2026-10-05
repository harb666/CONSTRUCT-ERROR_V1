extends Label
## Minimal on-screen readout to help tune movement on device.

var player: PlayerController
var _build := ""
## Extra performance readout (stress test / ?perf=1).
var show_perf := false
var _frames: Array[float] = []
var _perf_text := ""
var _perf_t := 0.0


func _ready() -> void:
	# Written by CI so you can confirm on the phone which build is running.
	if FileAccess.file_exists("res://build_info.txt"):
		_build = FileAccess.get_file_as_string("res://build_info.txt").strip_edges()


func _process(delta: float) -> void:
	var t := "FPS %d" % Engine.get_frames_per_second()
	if show_perf:
		_frames.append(delta)
		_perf_t += delta
		if _perf_t >= 1.0:
			var avg := 0.0
			var worst := 0.0
			for f in _frames:
				avg += f
				worst = maxf(worst, f)
			avg /= maxf(_frames.size(), 1)
			var alive := 0
			for r in get_tree().get_nodes_in_group(&"enemies"):
				if r.alive:
					alive += 1
			_perf_text = "\nframe %.1f ms avg / %.1f worst   draws %d   tris %dk   robots %d" % [
				avg * 1000.0, worst * 1000.0,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
				alive]
			var mem := int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
			if mem > 0:  # not reported by web builds
				_perf_text += "   mem %d MB" % mem
			_frames.clear()
			_perf_t = 0.0
		t += _perf_text
	if player:
		var hv := Vector2(player.velocity.x, player.velocity.z).length()
		var state := "DODGE" if player.is_dodging else ("GROUND" if player.is_on_floor() else "AIR")
		t += "   speed %.1f   %s%s" % [hv, state, "  SPRINT" if player.is_sprinting else ""]
		var anim := player.get_node_or_null("Visual/GrinchVisual") as CharacterAnimator
		if anim:
			t += "   anim " + anim.current_state
		var holder := player.get_node_or_null("WeaponHolder") as WeaponHolder
		if holder and holder.current_definition:
			t += "   weapon " + holder.current_definition.display_name
	if _build:
		t += "\nbuild " + _build
	text = t
