class_name PeerSignal
extends RefCounted
## Signalling for online co-op over a PeerJS server (the free public one at
## 0.peerjs.com by default: no account, no server of our own). Phones find
## each other through it - a few small messages to set up the direct
## WebRTC link (offer / answer / network candidates) - then the game talks
## peer to peer. Speaks the PeerJS server's WebSocket protocol: connect with
## an id, get OPEN (or ID-TAKEN), send {type, dst, payload}, receive
## {type, src, payload}; a HEARTBEAT every few seconds keeps it open.

signal opened
signal message(src: String, payload: Dictionary)
## The other side isn't there (the server couldn't deliver to it).
signal expired(dst: String)
signal failed(reason: String)

const HEARTBEAT := 5.0

## Every message to / from the server, for the network log (Net.log).
static var log_hook: Callable

var id := ""
## Kept for reconnecting: the server takes the same id back with the same
## token (a phone that slept loses its connection; the room keeps its code).
var token := ""
var is_open := false
var _ws := WebSocketPeer.new()
var _beat := 0.0
var _was_open := false
var _closed := false
var _reconnect := false


## Connect as `peer_id` to `base_url` (e.g. wss://0.peerjs.com:443/peerjs).
func start(base_url: String, peer_id: String, key := "peerjs") -> Error:
	id = peer_id
	# Same token = taking our id back after the link dropped: the server
	# then hands the id over without an OPEN message.
	_reconnect = token != ""
	if token == "":
		token = "%x%x" % [randi(), randi()]
	var url := "%s?key=%s&id=%s&token=%s&version=1.5.4" % [base_url, key, peer_id.uri_encode(), token]
	if log_hook.is_valid():
		log_hook.call("connect as %s" % _short(peer_id))
	return _ws.connect_to_url(url)


func send(dst: String, payload: Dictionary, type := "OFFER") -> void:
	if not is_open:
		return
	_ws.send_text(JSON.stringify({"type": type, "dst": dst, "payload": payload}))
	if log_hook.is_valid() and String(payload.get("k", "")) != "ice":
		log_hook.call("> %s %s to %s" % [type, payload.get("k", ""), _short(dst)])


## Still connected (or connecting) to the server.
func alive() -> bool:
	return not _closed


func close() -> void:
	_closed = true
	is_open = false
	_ws.close()


## Call every frame.
func poll(delta: float) -> void:
	if _closed:
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _was_open and _reconnect:
			# Our id back (the server sends no OPEN for a reconnect; if the
			# id had gone meanwhile it registers us fresh and OPEN follows).
			is_open = true
			_beat = HEARTBEAT
			if log_hook.is_valid():
				log_hook.call("reconnected")
			opened.emit()
		_was_open = true
		_beat -= delta
		if _beat <= 0.0 and is_open:
			_beat = HEARTBEAT
			_ws.send_text(JSON.stringify({"type": "HEARTBEAT"}))
		while _ws.get_available_packet_count() > 0:
			_handle(_ws.get_packet().get_string_from_utf8())
	elif st == WebSocketPeer.STATE_CLOSED:
		_closed = true
		var was := is_open
		is_open = false
		if log_hook.is_valid():
			log_hook.call("socket closed (code %d)" % _ws.get_close_code())
		failed.emit("signalling closed" if was or _was_open else "couldn't reach the signalling server")


static func _short(s: String) -> String:
	return s.replace("construct-error-v1-room-", "room-")


func _handle(text: String) -> void:
	var m = JSON.parse_string(text)
	if not (m is Dictionary):
		return
	if log_hook.is_valid():
		var p = m.get("payload")
		var k := String(p.get("k", "")) if p is Dictionary else ""
		if k != "ice":
			log_hook.call("< %s %s from %s" % [m.get("type", "?"), k, _short(String(m.get("src", "")))])
	match String(m.get("type", "")):
		"OPEN":
			var again := is_open
			is_open = true
			_beat = HEARTBEAT
			if not again:
				opened.emit()
		"ID-TAKEN":
			failed.emit("id taken")
		"ERROR", "INVALID-KEY":
			failed.emit(String((m.get("payload", {}) as Dictionary).get("msg", "server error")) if m.get("payload") is Dictionary else "server error")
		"EXPIRE":
			expired.emit(String(m.get("src", "")))
		"LEAVE":
			expired.emit(String(m.get("src", "")))
		"OFFER", "ANSWER", "CANDIDATE":
			var p = m.get("payload")
			if p is Dictionary:
				message.emit(String(m.get("src", "")), p)
