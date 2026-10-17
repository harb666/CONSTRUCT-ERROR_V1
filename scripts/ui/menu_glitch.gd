class_name MenuGlitch
extends Control
## The glitchy main menu (owner asked: "make the main menu go glitchy and
## turn into vector line wire meshes and frames"; ideas from the owner's
## glitch-video repo). Locked to the menu music's beat (133 BPM, measured
## from the track), it runs the video's merge schedule: a few clean bars,
## then bars where everything - the arena behind the menu, the panels,
## buttons and cards - slams into neon line art on the downbeat and
## dissolves back, flickers on the off-beats, or sinks bar by bar into lines
## and climbs back out, with band shifts, drop-outs, RGB split and
## magenta / green ghosts on the beat (menu_glitch.gdshader). The character
## preview merges with its real wire mesh (menu_wire_mix.gdshader, set by
## FrontEnd). All menu text is drawn crisp on top (HudStyle.defer_for), so
## the menus stay readable through it.

const SHADER := preload("res://scripts/ui/menu_glitch.gdshader")
## The main menu track's beat (measured: 133.0 BPM, first beat 0.428 s
## in, steady from the end of its intro to the end).
const BPM := 133.0
const FIRST_BEAT := 0.428
## Bars in one cycle of the schedule.
const CYCLE := 16

## 0 = the menu as drawn, 1 = all vector lines.
var wire := 0.0
## Band shifts / drop-outs / RGB split / ghosts.
var glitch := 0.0
## New pattern every 8th note.
var seed := 0.0
## Beat position (beats since the track's first beat) - tests.
var beats := 0.0
## Off: everything as drawn (fading out on DEPLOY).
var active := true
## A screen-UV rect the line pass leaves alone (the character preview).
var keep_rect := Rect2()
## The menu's text this frame (HudStyle.text calls collected while the
## menu draws), drawn on top.
var texts: Array = []

var _rect: ColorRect
var _mat: ShaderMaterial
var _clock := 0.0
## The music's last position seen, and the clock's offset to it.
var _music_t := -1.0
var _offset := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect = ColorRect.new()
	_rect.name = "Lines"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect.material = _mat
	_rect.visible = false
	_rect.show_behind_parent = true  # under this control's own drawing: the text
	add_child(_rect)


## Beats since the menu track's first beat: following the music while it's
## actually playing (so the glitches land on its beat), else carrying on at
## the same tempo (no sound yet / sound blocked: the track's position
## doesn't move).
func beat_position(delta: float) -> float:
	_clock += delta
	if Music.current() == Music.MAIN_MENU and Music._player:
		var mt := Music._player.get_playback_position()
		if mt != _music_t:
			_music_t = mt
			_offset = mt + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency() - _clock
	return (_clock + _offset - FIRST_BEAT) * BPM / 60.0


## How long the blocky front takes to sweep to its next level (beats): it
## zips there fast, then holds till the next beat (owner asked for the
## squares' moves up and down the screen to be faster, more glitchy; they
## used to creep there across the whole beat / bar).
const ZIP := 0.25


## The schedule at `b` beats: [wire, glitch].
static func schedule(b: float) -> Vector2:
	var beat := floori(b)
	var ph := b - beat
	var zip := minf(ph / ZIP, 1.0)  # this beat's sweep: 0 -> 1 in its first ZIP
	var bar := posmod(floori(beat / 4.0), CYCLE)
	var bib := posmod(beat, 4)
	var hit := exp(-ph * 6.0)  # a kick on every beat, fading
	match bar:
		4, 5:  # 'beat': slams in on the downbeat and the half bar, holds an 8th, zips away
			var h := fmod(bib + ph, 2.0)
			return Vector2(1.0 - clampf((h - 0.5) / (2.0 * ZIP), 0.0, 1.0), 0.55 * hit)
		6, 7:  # 'flicker': lines on the off-beat 8ths
			return Vector2(1.0 if (ph >= 0.5) == (beat % 2 == 0) else 0.0, 0.35 + 0.4 * hit)
		12, 13:  # 'in': sinks into lines, a step on every beat
			return Vector2(minf(1.0, ((bar - 12) * 4 + bib + zip) / 8.0), 0.25 * hit)
		14:  # all lines, the line art itself glitching on the beat
			return Vector2(1.0, 0.3 + 0.7 * hit)
		15:  # 'out': a step back on every beat
			return Vector2(maxf(0.0, 1.0 - (bib + zip) / 4.0), 0.4 * hit)
	# Clean bars: just a little kick on each bar's downbeat.
	return Vector2(0.0, 0.3 * hit if bib == 0 else 0.0)


func _process(delta: float) -> void:
	beats = beat_position(minf(delta, 0.1))
	var s := schedule(beats) if active else Vector2.ZERO
	wire = s.x
	glitch = s.y
	seed = floorf(beats * 2.0)
	var on := wire > 0.0 or glitch > 0.02
	_rect.visible = on
	if on:
		_mat.set_shader_parameter("wire", wire)
		_mat.set_shader_parameter("glitch", glitch)
		_mat.set_shader_parameter("seed", seed)
		_mat.set_shader_parameter("keep_rect", Vector4(keep_rect.position.x, keep_rect.position.y, keep_rect.end.x, keep_rect.end.y))
		var scale := get_viewport().get_final_transform().get_scale().x
		_mat.set_shader_parameter("line_px", clampf(1.5 * scale * 0.5, 1.0, 2.0))
	queue_redraw()


## The menu's text, crisp over the lines; on a strong glitch beat it gets a
## faint magenta / cyan fringe (still easy to read).
func _draw() -> void:
	var fringe := glitch > 0.45 and active
	# Over busy line art the text gets a dark outline, so it always reads.
	var backed := wire > 0.0 and active
	for t in texts:
		var col: Color = t[4]
		var outline: int = maxi(t[6], 5) if backed else t[6]
		if fringe:
			var o := Vector2(2.0 + 3.0 * glitch, 0.0)
			HudStyle.text(self, t[0], t[1] + o, t[2], t[3], Color(1.0, 0.25, 0.85, col.a * 0.35), t[5], 0)
			HudStyle.text(self, t[0], t[1] - o, t[2], t[3], Color(0.3, 0.95, 1.0, col.a * 0.35), t[5], 0)
		HudStyle.text(self, t[0], t[1], t[2], t[3], col, t[5], outline)
