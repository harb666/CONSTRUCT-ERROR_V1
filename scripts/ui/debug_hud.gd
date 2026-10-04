extends Label
## Minimal on-screen readout to help tune movement on device.

var player: PlayerController
var _build := ""


func _ready() -> void:
	# Written by CI so you can confirm on the phone which build is running.
	if FileAccess.file_exists("res://build_info.txt"):
		_build = FileAccess.get_file_as_string("res://build_info.txt").strip_edges()


func _process(_delta: float) -> void:
	var t := "FPS %d" % Engine.get_frames_per_second()
	if player:
		var hv := Vector2(player.velocity.x, player.velocity.z).length()
		var state := "DODGE" if player.is_dodging else ("GROUND" if player.is_on_floor() else "AIR")
		t += "   speed %.1f   %s%s" % [hv, state, "  SPRINT" if player.is_sprinting else ""]
		var anim := player.get_node_or_null("Visual/GrinchVisual") as CharacterAnimator
		if anim:
			t += "   anim " + anim.current_state
		var holder := player.get_node_or_null("WeaponHolder") as WeaponHolder
		if holder and holder.current_definition:
			t += "   weapon " + holder.current_definition.display_name
	if _build:
		t += "\nbuild " + _build
	text = t
