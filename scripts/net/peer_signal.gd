class_name PeerSignal
extends RefCounted
## Signalling for online co-op through ntfy.sh (a free public message
## service: no account, nothing to run). Phones only use it to find each
## other - a few small messages to set up the direct WebRTC link (offer /
## answer / network candidates) - then the game talks phone to phone.
## Each phone listens on its own topic (its id) over a WebSocket and sends
## to another's topic with an HTTP POST. (The game used the public PeerJS
## server before: it stopped passing messages between peers.)
##
## Same shape as before for Net: start(), send(), poll(), close(); signals
## opened / message / failed (`expired` is no longer sent: a joiner just
## keeps asking until it hears back).

signal opened
signal message(src: String, payload: Dictionary)
signal expired(dst: String)
signal failed(reason: String)

## ntfy sends a keepalive every 45 s; nothing for this long = link dead.
const SILENCE_LIMIT := 100.0

## Every message to / from the server, for the network log (Net.log).
static var log_hook: Callable

var id := ""
## (Kept for Net; ntfy topics aren't owned, so reconnecting needs nothing.)
var token := ""
var is_open := false
## Node the HTTP requests (sends) live under.
var host: Node
var base := ""
var _ws := WebSocketPeer.new()
var _was_open := false
var _closed := false
var _silence := 0.0
var sent := 0


## Listen as `peer_id` on `base_url` (e.g. https://ntfy.sh).
func start(base_url: String, peer_id: String, _key := "") -> Error:
	id = peer_id
	base = base_url.trim_suffix("/")
	var ws_url := base.replace("https://", "wss://").replace("http://", "ws://") + "/" + peer_id + "/ws"
	if log_hook.is_valid():
		log_hook.call("listen as %s" % _short(peer_id))
	return _ws.connect_to_url(ws_url)


## Post to another phone's topic.
func send(dst: String, payload: Dictionary, type := "OFFER") -> void:
	if host == null or not host.is_inside_tree() or _closed:
		return
	var body := JSON.stringify({"src": id, "type": type, "payload": payload})
	var r := HTTPRequest.new()
	r.timeout = 15.0
	host.add_child(r)
	var k := String(payload.get("k", ""))
	r.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		r.queue_free()
		if (result != HTTPRequest.RESULT_SUCCESS or code >= 300) and log_hook.is_valid():
			log_hook.call("send %s failed (%d / HTTP %d)" % [k, result, code]))
	var e := r.request(base + "/" + dst, PackedStringArray(["Content-Type: text/plain"]), HTTPClient.METHOD_POST, body)
	sent += 1
	if log_hook.is_valid():
		log_hook.call("> %s to %s%s" % [k, _short(dst), "" if e == OK else " (error %d)" % e])


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
		_was_open = true
		_silence += delta
		while _ws.get_available_packet_count() > 0:
			_silence = 0.0
			_handle(_ws.get_packet().get_string_from_utf8())
		if _silence > SILENCE_LIMIT:
			if log_hook.is_valid():
				log_hook.call("no keepalive from the server")
			_ws.close()
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
	match String(m.get("event", "")):
		"open":
			if not is_open:
				is_open = true
				if log_hook.is_valid():
					log_hook.call("listening")
				opened.emit()
		"message":
			var inner = JSON.parse_string(String(m.get("message", "")))
			if not (inner is Dictionary):
				return
			var src := String(inner.get("src", ""))
			var p = inner.get("payload")
			if src == "" or not (p is Dictionary):
				return
			if log_hook.is_valid():
				log_hook.call("< %s from %s" % [String(p.get("k", "")), _short(src)])
			message.emit(src, p)
