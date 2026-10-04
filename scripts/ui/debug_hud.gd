extends Label
## Minimal on-screen readout to help tune movement on device.

var player: PlayerController
var _build := ""


func _ready() -> void:
	# Written by CI so you can confirm on the phone which build is running.
	var f := FileAccess.open("res://build_info.txt", FileAccess.READ)
	if f:
		_build = f.get_as_text().strip_edges()


func _process(_delta: float) -> void:
	var t := "FPS %d" % Engine.get_frames_per_second()
	if player:
		var hv := Vector2(player.velocity.x, player.velocity.z).length()
		var state := "DODGE" if player.is_dodging else ("GROUND" if player.is_on_floor() else "AIR")
		t += "   speed %.1f   %s%s" % [hv, state, "  SPRINT" if player.is_sprinting else ""]
	if _build:
		t += "\nbuild " + _build
	text = t
