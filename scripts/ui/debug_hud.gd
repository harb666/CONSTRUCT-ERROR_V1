extends Label
## Minimal on-screen readout to help tune movement on device.

var player: PlayerController
var _build := ""
## Extra performance readout (stress test / ?perf=1).
var show_perf := false
var _frames: Array[float] = []
var _perf_text := ""
var _perf_t := 0.0
## Web only: what the game was doing, saved every few seconds, so a session
## the browser killed (iOS "this page was reloaded because a problem
## occurred") can be reported on the next start.
var _rec_t := 0.0
var _session_t := 0.0
var _last_session := ""
var _last_session_t := 0.0
## Web only, first minute: when the game was ready and when its sounds could
## first play (seconds since the page opened), to check start-up audio.
var _ready_at := -1.0
var _audio_text := ""


func _ready() -> void:
	# Small, top-centre between the player panel and the weapon panel.
	if label_settings:
		label_settings = label_settings.duplicate()
		label_settings.font_size = 13
		label_settings.font_color = Color(0.86, 0.98, 1.0, 0.8)
		label_settings.outline_size = 3
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place()
	get_viewport().size_changed.connect(_place)
	# Written by CI so you can confirm on the phone which build is running.
	if FileAccess.file_exists("res://build_info.txt"):
		_build = FileAccess.get_file_as_string("res://build_info.txt").strip_edges()
	if OS.has_feature("web"):
		var prev = JavaScriptBridge.eval("localStorage.getItem('ce_session') || ''")
		var d = JSON.parse_string(str(prev)) if prev != null and str(prev) != "" else null
		if d is Dictionary and int(d.get("ended", 1)) == 0 and float(d.get("t", 0)) > 5.0:
			_last_session = "LAST SESSION STOPPED UNEXPECTEDLY after %dm%02ds: fps %d, robots %d, debris %d, nodes %d, character %s, weapon %s, build %s" % [
				int(d.t) / 60, int(d.t) % 60, int(d.get("fps", 0)), int(d.get("robots", 0)), int(d.get("debris", 0)),
				int(d.get("nodes", 0)), str(d.get("char", "?")), str(d.get("weapon", "?")), str(d.get("build", "?"))]
		_ready_at = float(JavaScriptBridge.eval("performance.now() / 1000"))
		# A normal close / refresh marks the session as ended cleanly.
		JavaScriptBridge.eval("window.addEventListener('pagehide', function(){ try { var s = JSON.parse(localStorage.getItem('ce_session') || '{}'); s.ended = 1; localStorage.setItem('ce_session', JSON.stringify(s)); } catch (e) {} });")


func _place() -> void:
	var w := get_viewport_rect().size.x
	var width := clampf(w - 2.0 * (maxf(40.0, w * 0.03) + 372.0), 300.0, 760.0)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2((w - width) * 0.5, 6.0)
	size = Vector2(width, 40.0)


func _process(delta: float) -> void:
	var t := "FPS %d" % Engine.get_frames_per_second()
	if OS.has_feature("web"):
		_record(delta)
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
		var vis := player.get_node_or_null("Visual")
		var anim := vis.get_child(0) as CharacterAnimator if vis and vis.get_child_count() > 0 else null
		if anim:
			t += "   anim " + anim.current_state
		var holder := player.get_node_or_null("WeaponHolder") as WeaponHolder
		if holder and holder.current_definition:
			t += "   weapon " + holder.current_definition.display_name
	if _build:
		t += "\nbuild " + _build
	if _audio_text != "" and _session_t < 60.0:
		t += "\n" + _audio_text
	if _last_session != "" and _last_session_t < 90.0:
		_last_session_t += delta
		t += "\n" + _last_session
	text = t


func _record(delta: float) -> void:
	_session_t += delta
	_rec_t += delta
	if _rec_t < 2.0:
		return
	_rec_t = 0.0
	var alive := 0
	for r in get_tree().get_nodes_in_group(&"enemies"):
		if r.alive:
			alive += 1
	var weapon := "?"
	if player:
		var holder := player.get_node_or_null("WeaponHolder") as WeaponHolder
		if holder and holder.current_definition:
			weapon = holder.current_definition.display_name
	if _session_t < 60.0:
		var a = JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify(window.__ceAudio || {})")))
		if a is Dictionary and a.has("running"):
			_audio_text = "audio: game start %s, audio on %s, first sound %s, helper %s" % [
				_secs(_ready_at), _secs(a.running), _secs(a.firstSound), _secs(a.posReady)]
	var d := {"t": snappedf(_session_t, 0.1), "fps": Engine.get_frames_per_second(), "robots": alive,
		"debris": DebrisPiece.active_count(), "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"weapon": weapon, "char": player.character.display_name if player and player.character else "?", "build": _build, "ended": 0}
	JavaScriptBridge.eval("try { localStorage.setItem('ce_session', %s); } catch (e) {}" % JSON.stringify(JSON.stringify(d)))


static func _secs(v) -> String:
	return "-" if float(v) < 0.0 else "%.1fs" % float(v)
