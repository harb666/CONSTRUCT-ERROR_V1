class_name Net
extends Node
## Online co-op (owner asked: "someone can join from a phone and test the
## current map", free). The autoload "NetSession" is this node
## (Net.instance); the game asks through the static helpers, which work
## offline (the normal single-player game) without it.
##
## How it connects (free, nothing to run or sign up for): in the browser,
## phones talk directly over WebRTC. To find each other they use the free
## public PeerJS signalling server (PeerSignal): the host opens a room with
## a 4-digit code, the joiner types it (or opens a ?join=<code> link). On
## a desktop build / in tests ENet over the network is used instead.
##
## Who decides what: the host's device runs the world - robots (their AI,
## health, deaths, firing), barrels, waves, the lift and moving on to the
## next part - and tells the others (events + a few snapshots a second).
## Everyone runs their own character and decides the damage they take; the
## others see it driven by what they're doing (NetPlayerInput). On a joined
## device robots are puppets (RobotEnemy.net_puppet): they walk and aim
## locally but follow the host's positions, target and fire / dodge / die
## when the host says.

signal status_changed
signal roster_changed

const VERSION := 1
const ROOM_PREFIX := "construct-error-v1-room-"
## Free public message service the phones find each other through (PeerSignal).
const SIGNAL_URL := "https://ntfy.sh"
## Free public STUN (finds each phone's public address). Phones on mobile
## data behind strict carrier NAT may need a relay (TURN), not set up yet.
const ICE_SERVERS := [{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]}]
const MAX_PLAYERS := 4
const PLAYER_RATE := 15.0
const ROBOT_RATE := 10.0
const FLOW_RATE := 4.0
const CONNECT_TIMEOUT := 30.0
## A joining phone asks the room again this often until the host answers.
const JOIN_RETRY := 3.0
const ENET_PORT := 24680

static var instance: Net

## Connected to a co-op session (hosting or joined).
var online := false
var hosting := false
var joining := false
## The room's 4-digit code (WebRTC).
var room := ""
## What to tell the player ("ROOM 4821", "CONNECTING...", ...).
var status := ""
var failed := false
## This device's player number (1 = host).
var my_slot := 1
## peer id -> {"slot": int, "character": String, "deployed": bool}
var roster := {}
## The character picked on this device (sent when joining / deploying).
var my_character := &""
## A joined device loads the host's level: set while that reload happens
## (main.gd opens the character select straight away).
var rejoin_select := false
## Counters (tests / debug).
var sent := {}
var received := {}

var _sig: PeerSignal
var _rtc: WebRTCMultiplayerPeer
var _conns := {}  # peer id -> WebRTCPeerConnection
var _src_of := {}  # peer id -> PeerJS id (host side)
var _id_of := {}  # PeerJS id -> peer id (host side)
var _host_src := ""
var _ice_out := {}  # PeerSignal id -> candidates waiting to go out
var _ice_wait := {}  # peer id -> Array of [media, index, name] before the remote description
var _have_remote := {}
var _connect_t := 0.0
var _player_t := 0.0
var _robot_t := 0.0
var _flow_t := 0.0
var _last_cmd: PlayerCommand
var _presses := {"jp": false, "dp": false, "mp": false}
var _hooked_player: PlayerController
## What's happening with joiners, for the host ("PLAYER JOINING...").
var host_note := ""
var _sig_id := ""
var _sig_token := ""
var _sig_retry := -1.0
var _join_t := 0.0
## Host: a message to itself through the server every so often; if it
## doesn't come back the link is dead (a phone can think it's still
## connected after Safari froze the page) -> reconnect.
var _ping_t := 10.0
var _ping_wait := -1.0
var _hidden_ms := -1
## Host: peers whose level has loaded (they asked for the world). Only they
## get the streams (snapshots, world events): a phone busy loading a level
## would otherwise have its receive buffer flooded and drop data.
var _ready_peers := {}


## The last lines of the network log (?netlog=1 shows them on the
## character select / in game; also printed to the console).
var log_lines: Array[String] = []


func _enter_tree() -> void:
	instance = self
	PeerSignal.log_hook = net_log


func net_log(s: String) -> void:
	var line := "%5.1f %s" % [Time.get_ticks_msec() / 1000.0, s]
	print("net: " + s)
	log_lines.append(line)
	if log_lines.size() > 14:
		log_lines.pop_front()


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- Static helpers (work offline / without the autoload) ---

## Does this peer run the world (robots, barrels, waves, the lift)? The
## host does; offline, always.
static func is_authority() -> bool:
	return instance == null or not instance.online or instance.multiplayer.is_server()


static func is_online() -> bool:
	return instance != null and instance.online


## A joined device (robots there are the host's puppets).
static func is_client() -> bool:
	return is_online() and not instance.multiplayer.is_server()


## This device's player (null before DEPLOY).
static func local_player(tree: SceneTree) -> PlayerController:
	return tree.get_first_node_in_group(&"local_player") as PlayerController


## Move the squad on to the next part of the level (online: the host takes
## everyone).
static func go_to_level(tree: SceneTree, scene_path: String) -> void:
	if is_online() and instance.multiplayer.is_server():
		instance._ready_peers.clear()  # everyone's loading
		instance.rpc(&"_go_level", scene_path)
	LevelTransfer.go(tree, scene_path, local_player(tree))


## A world event from the device that runs the world, for the others
## (robots firing / dodging / dying, barrels, the lift, wave banners).
static func world_event(node: Node, kind: StringName, args: Array = []) -> void:
	if not is_online() or not instance.multiplayer.is_server() or node == null or not node.is_inside_tree():
		return
	var scene := node.get_tree().current_scene
	if scene == null:
		return
	instance._count(instance.sent, kind)
	instance._to_ready(&"_world_event", [String(scene.get_path_to(node)), kind, args])


## Host: call `method` on every peer whose level has loaded.
func _to_ready(method: StringName, args: Array, except := 0) -> void:
	for pid in _ready_peers:
		if pid != except and pid in multiplayer.get_peers():
			rpc_id.callv([pid, method] + args)


# --- Hosting / joining ---

## Open a room (WebRTC + public signalling). Its code appears in `room`.
func host_room(code := "") -> void:
	leave(false)
	hosting = true
	failed = false
	room = code if code != "" else "%04d" % (randi() % 10000)
	_set_status("OPENING ROOM...")
	_rtc = WebRTCMultiplayerPeer.new()
	_rtc.create_server()
	_sig_token = ""
	_start_signal(ROOM_PREFIX + room)


## The host's link to the signalling server dropped (e.g. the phone switched
## to Messages and Safari froze the page): reconnect with the same room
## code, so the room is findable again.
func _signal_lost() -> void:
	if hosting and online:
		_sig_retry = 2.0
		_set_status("ROOM %s - RECONNECTING..." % room)
		print("net: room %s lost the signalling server, reconnecting" % room)
	elif joining and not online and _connect_t > 0.0:
		_sig_retry = 2.0


## Join a room by its code.
func join_room(code: String) -> void:
	leave(false)
	joining = true
	failed = false
	room = code
	_host_src = ROOM_PREFIX + code
	_connect_t = CONNECT_TIMEOUT
	_set_status("CONNECTING TO %s..." % code)
	_sig_token = ""
	_join_t = 0.0
	_start_signal("%s%s-%06d" % [ROOM_PREFIX, code, randi() % 1000000])


## ENet (desktop builds / tests): host on `port`.
func host_enet(port := ENET_PORT) -> Error:
	leave(false)
	var p := ENetMultiplayerPeer.new()
	var e := p.create_server(port, MAX_PLAYERS - 1)
	if e != OK:
		_fail("COULDN'T HOST (%d)" % e)
		return e
	hosting = true
	room = "LAN"
	multiplayer.multiplayer_peer = p
	_go_online_host()
	_set_status("HOSTING ON PORT %d" % port)
	return OK


func join_enet(address: String, port := ENET_PORT) -> Error:
	leave(false)
	var p := ENetMultiplayerPeer.new()
	var e := p.create_client(address, port)
	if e != OK:
		_fail("COULDN'T CONNECT (%d)" % e)
		return e
	joining = true
	room = "LAN"
	_connect_t = CONNECT_TIMEOUT
	multiplayer.multiplayer_peer = p
	_set_status("CONNECTING...")
	return OK


## Back to playing alone. `reload`: a joined device goes back to its own
## (fresh) level.
func leave(reload := true) -> void:
	var was_client := online and not multiplayer.is_server()
	if _sig:
		_sig.close()
		_sig = null
	for id in _conns:
		(_conns[id] as WebRTCPeerConnection).close()
	_conns.clear()
	_src_of.clear()
	_id_of.clear()
	_ice_wait.clear()
	_ice_out.clear()
	_have_remote.clear()
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_rtc = null
	_sig_retry = -1.0
	host_note = ""
	online = false
	hosting = false
	joining = false
	room = ""
	my_slot = 1
	roster.clear()
	_set_puppets(false)
	roster_changed.emit()
	if reload and was_client and is_inside_tree():
		LevelTransfer.swap.call_deferred(get_tree(), ProjectSettings.get_setting("application/run/main_scene"))


func _go_online_host() -> void:
	online = true
	my_slot = 1
	roster = {1: {"slot": 1, "character": String(my_character), "deployed": local_player(get_tree()) != null}}
	roster_changed.emit()
	print("net: hosting room %s" % room)


func _start_signal(peer_id: String) -> void:
	_sig_id = peer_id
	_sig = PeerSignal.new()
	_sig.token = _sig_token
	_sig.host = self
	var url := SIGNAL_URL
	var custom := StressTest._param("signal")
	if custom != "":
		url = custom
	var sig := _sig
	_sig.failed.connect(func(reason: String) -> void:
		if sig != _sig:
			return
		if reason == "id taken" and hosting and not online:
			host_room()  # that code is in use: another one
		elif hosting and online:
			_signal_lost()
		elif joining and not online and reason != "id taken":
			_signal_lost()
		elif not online:
			_fail("CAN'T REACH THE SERVER" if reason != "id taken" else "TRY AGAIN"))
	_sig.opened.connect(func() -> void:
		if sig != _sig:
			return
		if hosting:
			if not online:
				multiplayer.multiplayer_peer = _rtc
				_go_online_host()
			_set_status("ROOM %s" % room)
			_ping_t = 10.0
			_ping_wait = -1.0
		elif joining:
			_join_t = 0.0  # ask now
			_set_status("LOOKING FOR ROOM %s..." % room))
	_sig.expired.connect(func(_dst: String) -> void:
		if sig == _sig and joining and not online:
			_set_status("LOOKING FOR ROOM %s - IS THE HOST'S GAME OPEN?" % room))
	_sig.message.connect(_host_signal if hosting else _client_signal)
	_sig.start(url, peer_id)
	_sig_token = _sig.token


func _fail(msg: String) -> void:
	print("net: " + msg)
	leave(false)
	failed = true
	_set_status(msg)


func _set_status(s: String) -> void:
	if s != status:
		log_lines.append("%5.1f [%s]" % [Time.get_ticks_msec() / 1000.0, s])
		if log_lines.size() > 14:
			log_lines.pop_front()
	status = s
	status_changed.emit()


func _count(d: Dictionary, k: StringName) -> void:
	d[k] = int(d.get(k, 0)) + 1


# --- WebRTC signalling ---

func _new_connection(peer_id: int, send_to: String) -> WebRTCPeerConnection:
	var c := WebRTCPeerConnection.new()
	c.initialize({"iceServers": ICE_SERVERS})
	c.session_description_created.connect(func(type: String, sdp: String) -> void:
		c.set_local_description(type, sdp)
		if _sig:
			_sig.send(send_to, {"k": "sdp", "type": type, "sdp": sdp}, "ANSWER" if type == "answer" else "OFFER"))
	# Network candidates go out in batches (each message is a web request).
	c.ice_candidate_created.connect(func(media: String, index: int, name: String) -> void:
		if not _ice_out.has(send_to):
			_ice_out[send_to] = []
			get_tree().create_timer(0.6, true, false, true).timeout.connect(func() -> void:
				var l: Array = _ice_out.get(send_to, [])
				_ice_out.erase(send_to)
				if _sig and not l.is_empty():
					_sig.send(send_to, {"k": "ices", "l": l}, "CANDIDATE"))
		(_ice_out[send_to] as Array).append([media, index, name]))
	_conns[peer_id] = c
	return c


func _remote_sdp(peer_id: int, p: Dictionary) -> void:
	var c: WebRTCPeerConnection = _conns.get(peer_id)
	if c == null:
		return
	c.set_remote_description(String(p.get("type", "")), String(p.get("sdp", "")))
	_have_remote[peer_id] = true
	for ice in _ice_wait.get(peer_id, []):
		c.add_ice_candidate(ice[0], ice[1], ice[2])
	_ice_wait.erase(peer_id)


func _remote_ice(peer_id: int, p: Dictionary) -> void:
	var c: WebRTCPeerConnection = _conns.get(peer_id)
	var ice := [String(p.get("m", "")), int(p.get("i", 0)), String(p.get("n", ""))]
	if c == null or not _have_remote.get(peer_id, false):
		if not _ice_wait.has(peer_id):
			_ice_wait[peer_id] = []
		(_ice_wait[peer_id] as Array).append(ice)
		return
	c.add_ice_candidate(ice[0], ice[1], ice[2])


func _host_signal(src: String, p: Dictionary) -> void:
	match String(p.get("k", "")):
		"ping":
			if src == _sig_id:
				_ping_wait = -1.0
		"join":
			if int(p.get("v", 0)) != VERSION:
				_sig.send(src, {"k": "refused", "why": "VERSION"})
				return
			if _id_of.has(src):
				var old := int(_id_of[src])
				if old in multiplayer.get_peers():
					return
				# Asked again (their first try got lost): start over.
				_drop_link(old)
			var id := _free_peer_id()
			if id == 0:
				_sig.send(src, {"k": "refused", "why": "FULL"})
				return
			_id_of[src] = id
			_src_of[id] = src
			var c := _new_connection(id, src)
			_rtc.add_peer(c, id)
			_sig.send(src, {"k": "welcome", "id": id}, "ANSWER")
			c.create_offer()
			host_note = "A PLAYER IS JOINING..."
			print("net: player joining (peer %d)" % id)
		"sdp":
			_remote_sdp(int(_id_of.get(src, 0)), p)
		"ice":
			_remote_ice(int(_id_of.get(src, 0)), p)
		"ices":
			for ice in p.get("l", []):
				_remote_ice(int(_id_of.get(src, 0)), {"m": ice[0], "i": ice[1], "n": ice[2]})


func _client_signal(src: String, p: Dictionary) -> void:
	if src != _host_src:
		return
	match String(p.get("k", "")):
		"welcome":
			var id := int(p.get("id", 0))
			if id < 2 or online:
				return
			for c in _conns.values():
				(c as WebRTCPeerConnection).close()
			_conns.clear()
			_have_remote.clear()
			_ice_wait.clear()
			_set_status("CONNECTING TO ROOM %s..." % room)
			_rtc = WebRTCMultiplayerPeer.new()
			_rtc.create_client(id)
			var c := _new_connection(1, _host_src)
			_rtc.add_peer(c, 1)
			multiplayer.multiplayer_peer = _rtc
		"refused":
			_fail("ROOM FULL" if p.get("why") == "FULL" else "DIFFERENT GAME VERSION - RELOAD")
		"sdp":
			_remote_sdp(1, p)
		"ice":
			_remote_ice(1, p)
		"ices":
			for ice in p.get("l", []):
				_remote_ice(1, {"m": ice[0], "i": ice[1], "n": ice[2]})


## Host: forget a joiner's half-made link.
func _drop_link(id: int) -> void:
	if _rtc and _rtc.has_peer(id):
		_rtc.remove_peer(id)
	if _conns.has(id):
		(_conns[id] as WebRTCPeerConnection).close()
		_conns.erase(id)
	_have_remote.erase(id)
	_ice_wait.erase(id)
	if _src_of.has(id):
		_id_of.erase(_src_of[id])
		_src_of.erase(id)


func _free_peer_id() -> int:
	for id in range(2, MAX_PLAYERS + 1):
		if not _src_of.has(id) and not roster.has(id):
			return id
	return 0


# --- Connection events ---

func _on_peer_connected(id: int) -> void:
	print("net: peer %d connected" % id)


func _on_peer_disconnected(id: int) -> void:
	print("net: peer %d left" % id)
	if _conns.has(id):
		(_conns[id] as WebRTCPeerConnection).close()
		_conns.erase(id)
	if _src_of.has(id):
		_id_of.erase(_src_of[id])
		_src_of.erase(id)
	var slot := int((roster.get(id, {}) as Dictionary).get("slot", 0))
	roster.erase(id)
	_ready_peers.erase(id)
	roster_changed.emit()
	_remove_player(slot)
	if multiplayer.is_server():
		rpc(&"_roster", roster)


func _on_connected_to_server() -> void:
	online = true
	joining = false
	_connect_t = 0.0
	_set_status("CONNECTED - ROOM %s" % room)
	print("net: connected to room %s as peer %d" % [room, multiplayer.get_unique_id()])
	_set_puppets(true)
	rpc_id(1, &"_hello", {"v": VERSION, "character": String(my_character)})
	if _sig and _rtc:
		# Only the host keeps the signalling open (for more players).
		_sig.close()
		_sig = null


func _on_connection_failed() -> void:
	_fail("COULDN'T CONNECT")


func _on_server_disconnected() -> void:
	print("net: host left")
	leave(true)
	failed = true
	_set_status("THE HOST LEFT")


# --- Per frame ---

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_hidden_ms = Time.get_ticks_msec()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		# Back in the game after another app (e.g. Messages to send the code):
		# make sure the room can be found again.
		var away := Time.get_ticks_msec() - _hidden_ms if _hidden_ms >= 0 else 0
		_hidden_ms = -1
		if hosting and online and _sig and (not _sig.is_open or away > 8000):
			_sig_retry = 0.0


func _process(delta: float) -> void:
	if _sig:
		_sig.poll(delta)
	if _sig_retry >= 0.0:
		_sig_retry -= delta
		if _sig_retry < 0.0 and (hosting or joining):
			if _sig:
				_sig.close()
			_start_signal(_sig_id)
	if joining and not online and _sig and _sig.is_open and _rtc == null:
		# Ask the room until the host answers (a first ask can get lost).
		_join_t -= delta
		if _join_t <= 0.0:
			_join_t = JOIN_RETRY
			_sig.send(_host_src, {"k": "join", "v": VERSION})
	if hosting and online:
		_check_joiners()
	if _connect_t > 0.0 and not online:
		_connect_t -= delta
		if _connect_t <= 0.0:
			if _rtc == null:
				_fail("ROOM %s NOT FOUND - CHECK THE CODE, HOST'S GAME OPEN ON SCREEN" % room)
			else:
				_fail("FOUND THE ROOM BUT COULDN'T CONNECT - TRY THE SAME WI-FI")
	if not online:
		return
	_hook_local_player()
	_player_t -= delta
	if _player_t <= 0.0:
		_player_t = 1.0 / PLAYER_RATE
		_send_player()
	if multiplayer.is_server():
		_robot_t -= delta
		if _robot_t <= 0.0:
			_robot_t = 1.0 / ROBOT_RATE
			_send_robots()
		_flow_t -= delta
		if _flow_t <= 0.0:
			_flow_t = 1.0 / FLOW_RATE
			_send_flow()


func _check_ping(delta: float) -> void:
	if _sig == null or not _sig.is_open or _sig_retry >= 0.0:
		return
	if _ping_wait >= 0.0:
		_ping_wait -= delta
		if _ping_wait < 0.0:
			print("net: room %s didn't hear itself back, reconnecting" % room)
			_signal_lost()
		return
	_ping_t -= delta
	if _ping_t <= 0.0:
		_ping_t = 10.0
		_ping_wait = 6.0
		_sig.send(_sig_id, {"k": "ping"})


## Host: notice joiners whose link failed (so the host knows why nobody
## came in).
func _check_joiners() -> void:
	for id in _conns.keys():
		var c := _conns[id] as WebRTCPeerConnection
		var st := c.get_connection_state()
		if st == WebRTCPeerConnection.STATE_CONNECTED and host_note == "A PLAYER IS JOINING...":
			host_note = ""
		elif st == WebRTCPeerConnection.STATE_FAILED:
			print("net: peer %d couldn't connect" % id)
			host_note = "A PLAYER COULDN'T CONNECT - TRY THE SAME WI-FI"
			_drop_link(int(id))


# --- The squad ---

@rpc("any_peer", "call_remote", "reliable")
func _hello(info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var slot := 2
	var used := []
	for pid in roster:
		used.append(int(roster[pid]["slot"]))
	while slot in used:
		slot += 1
	roster[id] = {"slot": slot, "character": String(info.get("character", "")), "deployed": false}
	_ready_peers.erase(id)
	roster_changed.emit()
	var scene := get_tree().current_scene
	rpc_id(id, &"_welcome", {"slot": slot, "level": scene.scene_file_path if scene else ""})
	rpc(&"_roster", roster)


@rpc("authority", "call_remote", "reliable")
func _welcome(data: Dictionary) -> void:
	my_slot = int(data.get("slot", 2))
	var level := String(data.get("level", ""))
	print("net: welcome, player %d, level %s" % [my_slot, level])
	var scene := get_tree().current_scene
	if scene and scene.scene_file_path == level:
		# Already in the host's level (the usual case): no reload - the world
		# is brought in step with the host's (robots, barrels, the lift).
		level_ready(scene)
		return
	# The host is in another part: load it (the character select opens
	# again there).
	rejoin_select = true
	if level != "":
		LevelTransfer.swap(get_tree(), level)


@rpc("authority", "call_remote", "reliable")
func _roster(r: Dictionary) -> void:
	roster = r
	roster_changed.emit()
	_spawn_teammates()


## main.gd: a level has started on this device (online: ask the host for
## the state of the world; spawn the teammates already in).
func level_ready(_main: Node) -> void:
	if not online:
		return
	_set_puppets(not multiplayer.is_server())
	if not multiplayer.is_server():
		rpc_id(1, &"_want_world")
	_spawn_teammates()


## main.gd: this device's player has deployed (or arrived in a new part).
func local_deployed(player: PlayerController) -> void:
	my_character = player.character.id if player.character else my_character
	if not online:
		return
	rpc(&"_deployed", my_slot, String(my_character))
	_mark_deployed(multiplayer.get_unique_id(), my_slot, String(my_character))
	_spawn_teammates()


@rpc("any_peer", "call_remote", "reliable")
func _deployed(slot: int, character: String) -> void:
	_mark_deployed(multiplayer.get_remote_sender_id(), slot, character)
	_spawn_teammates()


func _mark_deployed(peer: int, slot: int, character: String) -> void:
	if not roster.has(peer):
		roster[peer] = {"slot": slot, "character": character, "deployed": true}
	else:
		roster[peer]["deployed"] = true
		roster[peer]["character"] = character
	roster_changed.emit()


func _main() -> Node:
	var scene := get_tree().current_scene
	return scene if scene and scene.has_method(&"spawn_player") and scene.get(&"players") is Dictionary else null


## Teammates who are in the game get their characters here.
func _spawn_teammates() -> void:
	var main := _main()
	if main == null or local_player(get_tree()) == null:
		return
	var players: Dictionary = main.get(&"players")
	for pid in roster:
		var r: Dictionary = roster[pid]
		var slot := int(r["slot"])
		if slot == my_slot or not r.get("deployed", false) or players.has(slot):
			continue
		var rosterres := CharacterRoster.load_default()
		var def := rosterres.find(StringName(r.get("character", ""))) if rosterres else null
		main.call(&"spawn_player", slot, false, def)
		print("net: teammate P%d in" % slot)


func _remove_player(slot: int) -> void:
	var main := _main()
	if main == null or slot == 0:
		return
	var players: Dictionary = main.get(&"players")
	if players.has(slot) and slot != my_slot:
		var p: Node = players[slot]
		players.erase(slot)
		if is_instance_valid(p):
			p.queue_free()


func _player_by_slot(slot: int) -> PlayerController:
	var main := _main()
	if main == null:
		return null
	return (main.get(&"players") as Dictionary).get(slot) as PlayerController


func _slot_of(player: Node) -> int:
	var pc := player as PlayerController
	return pc.player_id if pc else 0


# --- This device's player -> the others ---

func _hook_local_player() -> void:
	var p := local_player(get_tree())
	if p == _hooked_player:
		return
	_hooked_player = p
	if p == null:
		return
	p.command_processed.connect(func(cmd: PlayerCommand, _d: float) -> void:
		_last_cmd = cmd
		_presses["jp"] = _presses["jp"] or cmd.jump_pressed
		_presses["dp"] = _presses["dp"] or cmd.dodge_pressed
		_presses["mp"] = _presses["mp"] or cmd.melee_pressed)
	var holder := p.get_node_or_null("WeaponHolder") as WeaponHolder
	if holder:
		holder.slot_equipped.connect(func(side: String, def: WeaponDefinition) -> void:
			if online:
				rpc(&"_weapon", my_slot, side, String(def.id) if def else ""))


func _send_player() -> void:
	var p := _hooked_player
	if p == null or not is_instance_valid(p) or _last_cmd == null:
		return
	var scene := get_tree().current_scene
	var d := _last_cmd.to_dict()
	d["jp"] = _presses["jp"]
	d["dp"] = _presses["dp"]
	d["mp"] = _presses["mp"]
	_presses = {"jp": false, "dp": false, "mp": false}
	d["tp"] = NetPlayerInput.target_path(_last_cmd.target_id, scene)
	d["tlp"] = NetPlayerInput.target_path(_last_cmd.target_id_left, scene)
	d["pos"] = p.global_position
	d["vel"] = p.velocity
	d["hp"] = p.health
	d["ar"] = p.armour
	d["lvl"] = scene.scene_file_path if scene else ""
	_count(sent, &"player")
	if multiplayer.is_server():
		_to_ready(&"_player_state", [my_slot, d])
	else:
		rpc_id(1, &"_player_state", my_slot, d)  # the host passes it on


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _player_state(slot: int, d: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() != 1 and not multiplayer.is_server():
		return  # (joined devices only take these from the host)
	_count(received, &"player")
	if multiplayer.is_server():
		_to_ready(&"_player_state", [slot, d], multiplayer.get_remote_sender_id())
	var scene := get_tree().current_scene
	if scene == null or String(d.get("lvl", "")) != scene.scene_file_path:
		return
	var p := _player_by_slot(slot)
	if p == null or slot == my_slot:
		return
	var input := p.input as NetPlayerInput
	if input:
		input.push(d, scene)
	p.health = float(d.get("hp", p.health))
	p.armour = float(d.get("ar", p.armour))


@rpc("any_peer", "call_remote", "reliable")
func _weapon(slot: int, side: String, weapon_id: String) -> void:
	var p := _player_by_slot(slot)
	if p == null or slot == my_slot:
		return
	var holder := p.get_node_or_null("WeaponHolder") as WeaponHolder
	var reg := load("res://resources/weapons/weapon_registry.tres") as WeaponRegistry
	if holder == null:
		return
	if weapon_id == "":
		holder.unequip(side)
		return
	var def := reg.find(StringName(weapon_id)) if reg else null
	if def and (holder.weapon(side) == null or holder.weapon(side).definition != def):
		holder.switch_weapon(def, side)


# --- The world (host -> the others) ---

func _send_robots() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var out := []
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var r := e as Node3D
		if r == null or not r.get(&"alive"):
			continue
		var t = r.get(&"target")
		out.append([String(scene.get_path_to(r)), r.global_position, _slot_of(t) if t is Node else 0])
	_count(sent, &"robots")
	_to_ready(&"_robots", [scene.scene_file_path, out])


@rpc("authority", "call_remote", "unreliable_ordered")
func _robots(level: String, list: Array) -> void:
	_count(received, &"robots")
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != level:
		return
	for item in list:
		var r := scene.get_node_or_null(String(item[0]))
		if r == null or not r.has_method(&"net_follow"):
			continue
		r.call(&"net_follow", item[1], _player_by_slot(int(item[2])))


func _send_flow() -> void:
	var flow := get_tree().current_scene.get_node_or_null("LevelFlow") as LevelFlow if get_tree().current_scene else null
	if flow == null or flow.director == null:
		return
	var d := flow.director
	_to_ready(&"_flow", [get_tree().current_scene.scene_file_path, d.wave, int(d.state), d.remaining()])


@rpc("authority", "call_remote", "unreliable_ordered")
func _flow(level: String, wave: int, state: int, remaining: int) -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != level:
		return
	var flow := scene.get_node_or_null("LevelFlow") as LevelFlow
	if flow and flow.director:
		flow.director.wave = wave
		flow.director.state = state as WaveDirector.State
		flow.director.net_remaining = remaining


@rpc("authority", "call_remote", "reliable")
func _world_event(path: String, kind: StringName, args: Array) -> void:
	_count(received, kind)
	var scene := get_tree().current_scene
	var n := scene.get_node_or_null(path) if scene else null
	if n and n.has_method(&"net_event"):
		n.call(&"net_event", kind, args)


## A robot teleported in on the host (a wave): same robot here.
static func robot_spawned(robot: Node3D, parent: Node) -> void:
	if not is_online() or not instance.multiplayer.is_server():
		return
	var scene := robot.get_tree().current_scene
	instance._count(instance.sent, &"spawn")
	instance._to_ready(&"_robot_spawn", [String(scene.get_path_to(parent)), String(robot.name), robot.scene_file_path, robot.global_transform])


@rpc("authority", "call_remote", "reliable")
func _robot_spawn(parent_path: String, robot_name: String, scene_path: String, xf: Transform3D) -> void:
	_count(received, &"spawn")
	var scene := get_tree().current_scene
	var parent := scene.get_node_or_null(parent_path) if scene else null
	if parent == null or parent.has_node(robot_name) or not ResourceLoader.exists(scene_path):
		return
	var r := (load(scene_path) as PackedScene).instantiate() as Node3D
	r.name = robot_name
	r.set(&"respawn_time", -1.0)
	r.set(&"patrol_distance", 0.0)
	r.transform = xf
	parent.add_child(r)
	var visual := r.get(&"_visual") as Node3D
	Hologram.teleport_in(visual, 0.0, Color(1.0, 0.35, 0.3))


@rpc("any_peer", "call_remote", "reliable")
func _want_world() -> void:
	if not multiplayer.is_server():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	_ready_peers[multiplayer.get_remote_sender_id()] = true
	var robots := []
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var r := e as Node3D
		if r and r.get(&"alive"):
			robots.append([String(scene.get_path_to(r.get_parent())), String(r.name), r.scene_file_path, r.global_transform])
	var barrels := []
	for b in get_tree().get_nodes_in_group(&"toxic_barrels"):
		if not b.get(&"exploded"):
			barrels.append(String(scene.get_path_to(b)))
	var lift := get_tree().get_first_node_in_group(&"elevator_lift") as ElevatorLift
	var state := {
		"level": scene.scene_file_path,
		"robots": robots,
		"barrels": barrels,
		"lift": [int(lift.state), lift._t] if lift else [],
	}
	rpc_id(multiplayer.get_remote_sender_id(), &"_world", state)


## A joined device makes its world match the host's: robots the host no
## longer has are removed, ones it has added come in; barrels already blown
## are gone; the lift is where the host's is.
@rpc("authority", "call_remote", "reliable")
func _world(state: Dictionary) -> void:
	_count(received, &"world")
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != String(state.get("level", "")):
		return
	var keep := {}
	for item in state.get("robots", []):
		keep[String(item[0]) + "/" + String(item[1])] = item
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var r := e as Node3D
		var key := String(scene.get_path_to(r))
		if not keep.has(key):
			r.queue_free()
		else:
			keep.erase(key)
	for key in keep:
		var item: Array = keep[key]
		_robot_spawn(String(item[0]), String(item[1]), String(item[2]), item[3])
	var live := {}
	for p in state.get("barrels", []):
		live[String(p)] = true
	for b in get_tree().get_nodes_in_group(&"toxic_barrels"):
		if not live.has(String(scene.get_path_to(b))):
			b.queue_free()
	var lift := get_tree().get_first_node_in_group(&"elevator_lift") as ElevatorLift
	var ls: Array = state.get("lift", [])
	if lift and ls.size() == 2:
		lift.set_state_from_net(int(ls[0]), float(ls[1]))
	_set_puppets(true)
	print("net: world in step (%d robots)" % get_tree().get_nodes_in_group(&"enemies").size())


@rpc("authority", "call_remote", "reliable")
func _go_level(scene_path: String) -> void:
	LevelTransfer.go(get_tree(), scene_path, local_player(get_tree()))


## Robots here follow the host (joined) or think for themselves.
func _set_puppets(on: bool) -> void:
	if not is_inside_tree():
		return
	for e in get_tree().get_nodes_in_group(&"enemies"):
		e.set(&"net_puppet", on)
