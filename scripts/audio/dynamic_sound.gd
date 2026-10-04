class_name DynamicSound
extends AudioStreamPlayer3D
## A 3D sound whose loudness follows its distance to the local player:
## full volume within `near`, then a smooth fall-off to silence at `far`.
## (Godot's own distance attenuation is disabled so the curve is predictable
## on every platform; panning still comes from the camera.)

## Volume (dB) at full loudness.
@export var base_db := 0.0
@export var near := 4.0
@export var far := 50.0
## Extra 0..1 multiplier (used for fades).
@export var fade := 1.0

## 0..1 loudness from the last update (for tests/debug).
var gain := 1.0


func _init() -> void:
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	max_distance = 0.0


func _ready() -> void:
	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	gain = distance_gain(global_position.distance_to(_listener_position())) * clampf(fade, 0.0, 1.0)
	volume_db = base_db + linear_to_db(maxf(gain, 0.0001))


## 1 within `near`, easing down to 0 at `far` (perceived loudness drops
## steadily, so far-off black holes are a faint rumble).
func distance_gain(d: float) -> float:
	if d <= near:
		return 1.0
	if d >= far:
		return 0.0
	var k := 1.0 - (d - near) / (far - near)
	return k * k


func _listener_position() -> Vector3:
	var l := get_tree().get_first_node_in_group(Sfx.LISTENER_GROUP) as Node3D
	if l:
		return l.global_position
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam else global_position
