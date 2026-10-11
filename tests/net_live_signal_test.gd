extends SceneTree
## Co-op matchmaking against the REAL free message service (ntfy.sh):
## run as `-- --role=host --code=NNNN` and `-- --role=join --code=NNNN` at
## the same time (.github/workflows/signal-live.yml; the dev sandbox can't
## reach that server). Checks the host opens the room, the joiner's JOIN
## reaches it and the host's WELCOME comes back - before and after the host
## loses and regains its link (as when an iPhone switches apps). The WebRTC
## link itself needs a browser (not checked here). Prints the network log.

var role := ""
var code := ""
var failures := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.substr(7)
		elif a.begins_with("--code="):
			code = a.substr(7)
	_run.call_deferred()


func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + "[%s] %s" % [role, msg])
	if not cond:
		failures += 1


func wait_for(cond: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _run() -> void:
	var n := Net.instance
	if role == "host":
		n.host_room(code)
		check(await wait_for(func() -> bool: return n.online, 20.0), "room %s open on the public server" % code)
		var joins := [0]
		PeerSignal.log_hook = func(s: String) -> void:
			n.net_log(s)
			if s.begins_with("< join"):
				joins[0] += 1
		check(await wait_for(func() -> bool: return joins[0] >= 1, 40.0), "a JOIN reached the host")
		# Lose the link (an iPhone switching apps), get it back.
		n._sig.close()
		n._signal_lost()
		check(await wait_for(func() -> bool: return n._sig and n._sig.is_open and n.status == "ROOM %s" % code, 20.0), "room back after losing the link (same code)")
		var before: int = joins[0]
		check(await wait_for(func() -> bool: return joins[0] > before, 40.0), "a JOIN reaches the host after it reconnected")
		await wait_for(func() -> bool: return false, 8.0)
	else:
		# First join (host just opened the room).
		n.join_room(code)
		check(await wait_for(func() -> bool: return n._rtc != null, 35.0), "the host answered (WELCOME) - status %s" % n.status)
		await wait_for(func() -> bool: return false, 6.0)
		# Again, after the host reconnected.
		n.leave(false)
		n.join_room(code)
		check(await wait_for(func() -> bool: return n._rtc != null, 35.0), "the host answered again after reconnecting - status %s" % n.status)
	print("---- %s network log ----" % role)
	for l in n.log_lines:
		print(l)
	print("LIVE FAILURES: %d" % failures)
	n.leave(false)
	quit(1 if failures else 0)
