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
## Machine gun ("Raptor"): a short burst of rounds with its tail, and the
## venting / spin-down after sustained fire. Also the skirmishers' cannons.
const MG_FIRE := preload("res://assets/audio/machine_gun/raptor_firing.ogg")
const MG_COOLDOWN := preload("res://assets/audio/machine_gun/raptor_cooldown.ogg")
const WEAPON_PICKUP := preload("res://assets/audio/pickup/weapon_pickup.ogg")
## The player's pistol cannon (default weapon) firing sound - supplied by
## the game's owner. Keep this exact file; never replace or regenerate it
## without asking them.
const PISTOL_CANNON := preload("res://assets/audio/plasma/pistol_cannon_firing.ogg")
## The player's shotgun firing sound - supplied by the game's owner. Keep
## this exact file; never replace or regenerate it without asking them.
const SHOTGUN_FIRING := preload("res://assets/audio/plasma/shotgun_firing.mp3")
## Owner-supplied enemy sounds - keep these exact files; never replace or
## regenerate them without asking. ENEMY_TROOP_1_FIRING: the grunts' green
## cannons. MACHINE_DEATH: the robot boss starting to die.
const ENEMY_TROOP_1_FIRING := preload("res://assets/audio/enemies/enemy_troop_1_firing.mp3")
const MACHINE_DEATH := preload("res://assets/audio/enemies/machine_death.wav")
## SMALL_ROBOT_DEATH: a grunt killed by weapon fire (not when it breaks
## apart). MINI_BOSS_MG: the robot boss's chaingun - a recording of
## continuous fire; RobotBoss plays one shot out of it per round fired.
const SMALL_ROBOT_DEATH := preload("res://assets/audio/enemies/small_robot_death.mp3")
const MINI_BOSS_MG := preload("res://assets/audio/enemies/mini_boss_machine_gun_firing.mp3")
## The generated cannon shot (no longer used by the grunts) and the
## plasma shotgun's blast (generated: tools/make_weapon_sfx.py).
const CANNON_SHOT := preload("res://assets/audio/plasma/cannon_shot.ogg")
const SHOTGUN_BLAST := preload("res://assets/audio/plasma/shotgun_blast.ogg")
## Perfect dodge confirmation (generated electric zap + chime).
const PERFECT_DODGE := preload("res://assets/audio/combat/perfect_dodge.ogg")

## The local player is added to this group; distances are measured from it.
const LISTENER_GROUP := &"sfx_listener"


## Browser only: hands every game sound to the browser's audio engine at
## start-up (it decodes them while the game loads). Otherwise each sound is
## handed over - and decoded - the first time it plays, so the first shots,
## pickups etc. after loading are silent. Returns how many were registered.
static func preload_all() -> int:
	if not OS.has_feature("web"):
		return 0
	var n := 0
	var consts: Dictionary = (load("res://scripts/audio/sfx.gd") as Script).get_script_constant_map()
	for k in consts:
		if not (consts[k] is AudioStream):
			continue
		var st: AudioStream = consts[k]
		if not AudioServer.is_stream_registered_as_sample(st):
			AudioServer.register_stream_as_sample(st)
			n += 1
	return n


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


## `count` players of one rapid-fire sound under `parent`, used in turn by
## play_next (the browser plays separate voices reliably; one player
## restarted many times a second drops sounds there).
static func voices(parent: Node, stream: AudioStream, count: int, volume_db := 0.0,
		near := 4.0, far := 50.0, at := Vector3.ZERO) -> Array[DynamicSound]:
	var out: Array[DynamicSound] = []
	for i in count:
		var e := emitter(parent, stream, volume_db, near, far)
		e.name = "Voice%d" % i
		e.position = at
		out.append(e)
	return out


## Plays the next of `pool` (round robin via `index`), at a random pitch in
## `pitch`; returns the next index.
static func play_next(pool: Array[DynamicSound], index: int, pitch := Vector2(1.0, 1.0)) -> int:
	if pool.is_empty():
		return index
	var e := pool[index % pool.size()]
	if is_instance_valid(e) and e.is_inside_tree():
		e.pitch_scale = randf_range(pitch.x, pitch.y)
		e.play()
	return (index + 1) % pool.size()


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
