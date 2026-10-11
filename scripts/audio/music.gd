class_name Music
extends RefCounted
## Background music (the owner's tracks, assets/audio/music; originals kept
## untouched in source/, the game plays 112 kbps OGG copies). One player on
## the scene tree's root, so a track carries on across level loads (the hub
## lift into the next part); asking for the track already playing keeps it
## going, another one cross-fades. Loops.

const MAIN_MENU := preload("res://assets/audio/music/main_menu_music.ogg")
const LEVEL_1 := preload("res://assets/audio/music/level_1_music.ogg")
## Title / character select.
const MENU_DB := -9.0
## In game: under the guns and robots, enough to make the map feel alive.
const LEVEL_DB := -17.0
const SILENT_DB := -60.0

static var _player: AudioStreamPlayer
static var _tween: Tween
static var plays := 0


static func current() -> AudioStream:
	return _player.stream if _player and is_instance_valid(_player) and _player.playing else null


## Play `stream` at `db` (fading in over `fade` s). The track already
## playing just eases to the new volume.
static func play(tree: SceneTree, stream: AudioStream, db: float, fade := 1.5) -> void:
	if stream == null:
		return
	_ensure(tree)
	if _player.playing and _player.stream == stream:
		_fade_to(db, fade)
		return
	if _player.playing:
		# Out with the old, then in with the new.
		_fade_to(SILENT_DB, 0.6, func() -> void: _start(stream, db, fade))
	else:
		_start(stream, db, fade)


## Fade out and stop.
static func stop(fade := 1.0) -> void:
	if _player == null or not is_instance_valid(_player) or not _player.playing:
		return
	_fade_to(SILENT_DB, fade, func() -> void: _player.stop())


static func _start(stream: AudioStream, db: float, fade: float) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_player.stream = stream
	_player.volume_db = SILENT_DB
	if _player.is_inside_tree():
		_player.play()
	else:
		_player.play.call_deferred()  # (joins the tree at the end of this frame)
	plays += 1
	_fade_to(db, fade)


static func _fade_to(db: float, time: float, then := Callable()) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = _player.create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_player, "volume_db", db, maxf(time, 0.01))
	if then.is_valid():
		_tween.tween_callback(then)


static func _ensure(tree: SceneTree) -> void:
	if _player and is_instance_valid(_player):
		return
	_player = AudioStreamPlayer.new()
	_player.name = "Music"
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child.call_deferred(_player)
