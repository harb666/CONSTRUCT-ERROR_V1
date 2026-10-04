class_name Sfx
extends RefCounted
## Positional sound helpers. Every sound is a DynamicSound: panned in 3D and
## loud close to the local player, fading smoothly to silence with distance
## (each sound has its own near/far range; see SfxProfile values below).

const BH_LOOP := preload("res://assets/audio/black_hole/energy_loop.ogg")
const BH_FIRE := preload("res://assets/audio/black_hole/fire.ogg")
const BH_BURST := preload("res://assets/audio/black_hole/energy_burst.ogg")
const BH_EXPLODE := preload("res://assets/audio/black_hole/explode.ogg")
const BH_CHARGE := preload("res://assets/audio/black_hole/charge.ogg")

## The local player is added to this group; distances are measured from it.
const LISTENER_GROUP := &"sfx_listener"


## Positional player as a child of `parent` (follows it). Not started.
## Full volume within `near` metres, silent beyond `far`.
static func emitter(parent: Node, stream: AudioStream, volume_db := 0.0,
		near := 4.0, far := 50.0) -> DynamicSound:
	var p := DynamicSound.new()
	p.stream = stream
	p.base_db = volume_db
	p.near = near
	p.far = far
	parent.add_child(p)
	return p


## Fire-and-forget sound at a world position; frees itself when done.
static func play_at(parent: Node, stream: AudioStream, at: Vector3, volume_db := 0.0,
		near := 4.0, far := 60.0) -> DynamicSound:
	if parent == null:
		return null
	var p := emitter(parent, stream, volume_db, near, far)
	p.top_level = true
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()
	return p


## Fade a sound out over `time` seconds, then stop (and optionally free) it.
static func fade_out(p: DynamicSound, time: float, free_after := false) -> void:
	if p == null or not is_instance_valid(p) or not p.is_inside_tree():
		return
	var tw := p.create_tween()
	tw.tween_property(p, "fade", 0.0, time)
	tw.tween_callback(p.stop)
	if free_after:
		tw.tween_callback(p.queue_free)
