class_name Sfx
extends RefCounted
## Small positional-audio helpers. Volume falls off with distance from the
## listener (the active camera), so sounds are loudest close to their source.

const BH_LOOP := preload("res://assets/audio/black_hole/energy_loop.ogg")
const BH_FIRE := preload("res://assets/audio/black_hole/fire.ogg")
const BH_BURST := preload("res://assets/audio/black_hole/energy_burst.ogg")
const BH_EXPLODE := preload("res://assets/audio/black_hole/explode.ogg")
const BH_COOLDOWN := preload("res://assets/audio/black_hole/cooldown_charge.ogg")


## Positional player as a child of `parent` (follows it). Not started.
static func emitter(parent: Node, stream: AudioStream, volume_db := 0.0,
		unit_size := 4.0, max_distance := 50.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.max_distance = max_distance
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	parent.add_child(p)
	return p


## Fire-and-forget sound at a world position; frees itself when done.
static func play_at(parent: Node, stream: AudioStream, at: Vector3, volume_db := 0.0,
		unit_size := 4.0, max_distance := 60.0) -> AudioStreamPlayer3D:
	if parent == null:
		return null
	var p := emitter(parent, stream, volume_db, unit_size, max_distance)
	p.top_level = true
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()
	return p


## Fade a player out over `time` seconds, then stop (and optionally free) it.
static func fade_out(p: AudioStreamPlayer3D, time: float, free_after := false) -> void:
	if p == null or not is_instance_valid(p) or not p.is_inside_tree():
		return
	var tw := p.create_tween()
	tw.tween_property(p, "volume_db", -60.0, time)
	tw.tween_callback(p.stop)
	if free_after:
		tw.tween_callback(p.queue_free)
