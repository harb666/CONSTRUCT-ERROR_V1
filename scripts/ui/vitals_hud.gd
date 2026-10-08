class_name VitalsHud
extends Control
## Compact health (green) and armour (blue) bars, top-left under the debug
## readout, plus a "+25%" tag while the kill-streak bonus runs. Bars flash
## when a shard is collected.

const HEALTH := Color(0.3, 1.0, 0.4)
const ARMOUR := Color(0.35, 0.65, 1.0)
const BAR := Vector2(150, 9)

var player: PlayerController
var _flash := [0.0, 0.0]
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(60, 60)
	size = Vector2(260, 34)
	_font = get_theme_default_font()


func _process(delta: float) -> void:
	for i in 2:
		_flash[i] = maxf(_flash[i] - delta * 3.0, 0.0)
	var drops := RecoveryDrops.get_for(get_tree()) if is_inside_tree() else null
	if drops and not drops.collected.is_connected(_on_collected):
		drops.collected.connect(_on_collected)
	queue_redraw()


func _on_collected(kind: int, _amount: float) -> void:
	_flash[kind] = 1.0


func _draw() -> void:
	if player == null:
		return
	_bar(0.0, player.health / maxf(player.max_health, 1.0), HEALTH, _flash[0], "%d" % ceili(player.health))
	_bar(14.0, player.armour / maxf(player.max_armour, 1.0), ARMOUR, _flash[1], "%d" % ceili(player.armour))
	var drops := get_tree().get_first_node_in_group(RecoveryDrops.GROUP) as RecoveryDrops
	if drops and drops.bonus_active():
		draw_string(_font, Vector2(0, 42), "RECOVERY +%d%%" % roundi(drops.streak_bonus * 100.0),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.85, 0.3))


func _bar(y: float, frac: float, color: Color, flash: float, text: String) -> void:
	draw_rect(Rect2(Vector2(0, y), BAR), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(Vector2(0, y), Vector2(BAR.x * clampf(frac, 0.0, 1.0), BAR.y)), color.lerp(Color.WHITE, flash * 0.6))
	draw_string(_font, Vector2(BAR.x + 6, y + BAR.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
