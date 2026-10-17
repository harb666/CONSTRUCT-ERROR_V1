class_name DeathWipe
extends ColorRect
## Falling into the slime / off the level, or dying (owner asked: "that same
## stream of pixels that run down the screen quickly" as the main menu's
## glitch): the local player's screen breaks up like the menu - a ragged,
## blocky front of neon line art streaks down from the top with band
## shifts, RGB split and ghosts (menu_glitch.gdshader), the player is put
## back at their spawn while it covers the screen, and it streaks on down
## off the bottom to show them there. Only on the device of the player it
## happens to.

const SHADER := preload("res://scripts/ui/menu_glitch.gdshader")
const GROUP := &"death_wipe"
## Seconds: streaking down over the screen, all lines (the respawn happens
## at its start), streaking on down off it.
@export var cover_time := 0.22
@export var hold_time := 0.14
@export var clear_time := 0.3
@export var glitch := 0.7
## Seconds since it started (-1: not playing), and times played (tests).
var t := -1.0
var plays := 0
var wire := 0.0
var _then := Callable()
var _mat: ShaderMaterial


## The local player's wipe, if the level has one.
static func find(tree: SceneTree) -> DeathWipe:
	for n in tree.get_nodes_in_group(GROUP):
		if not n.is_queued_for_deletion():
			return n as DeathWipe
	return null


func _ready() -> void:
	name = "DeathWipe"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat
	visible = false
	add_to_group(GROUP)


func playing() -> bool:
	return t >= 0.0


## Streak down over the screen; `then` (the respawn) runs once it's covered.
## Again while it's still clearing: it comes back down from where it is.
func play(then: Callable) -> void:
	if playing() and t < cover_time:
		then.call()  # already coming down: just run it too
		return
	t = wire * cover_time if playing() else 0.0
	_then = then
	plays += 1
	visible = true
	if get_parent():
		get_parent().move_child(self, -1)  # over everything, the HUD too


func _process(delta: float) -> void:
	if not playing():
		return
	t += minf(delta, 0.05)
	var top := t < cover_time + hold_time
	if t < cover_time:
		wire = t / cover_time
	elif top:
		wire = 1.0
	else:
		wire = 1.0 - (t - cover_time - hold_time) / clear_time
	if t >= cover_time and _then.is_valid():
		var cb := _then
		_then = Callable()
		cb.call()
	if wire <= 0.0:
		wire = 0.0
		t = -1.0
		visible = false
		return
	_mat.set_shader_parameter("wire", wire)
	_mat.set_shader_parameter("glitch", glitch)
	_mat.set_shader_parameter("seed", floorf(t * 24.0))
	_mat.set_shader_parameter("from_top", top)
	var scale := get_viewport().get_final_transform().get_scale().x
	_mat.set_shader_parameter("line_px", clampf(1.5 * scale * 0.5, 1.0, 2.0))
