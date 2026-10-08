class_name PerfectDodge
extends Node
## Perfect dodge: dodging an enemy shot that was about to hit grants a short
## counterattack window (more stagger, see StaggerMeter). One per player
## (child of its PlayerController); the reward belongs to that player.
##
## Only real near misses count: at the dodge, each enemy bolt in flight is
## projected along its actual path against the player's body; it qualifies
## if it would have hit within `window` s. The reward is granted only once
## that same bolt (by launch serial) is confirmed to have missed - it flew
## on, hit something else or expired without damaging this player. Each
## bolt can reward once; rewards refresh the window, never stack.

signal perfect_dodge(counter_time: float)

@export var enabled := true
## Dodge must start within this time before the predicted impact (s).
@export var window := 0.18
## A bolt passing within this distance of the body centre line would hit
## (capsule radius 0.4 + bolt size + a little).
@export var hit_radius := 0.55
@export var counter_duration := 2.0
## Extra stagger dealt during the counter window (0.35 = +35 %).
@export var stagger_bonus := 0.35
## Seconds a candidate bolt is watched before it's judged.
@export var confirm_time := 0.6

var player: PlayerController
## Seconds of counterattack left.
var counter_left := 0.0
## Perfect dodges granted (tests / tuning).
var count := 0

## serial -> [bolt, seconds watched]
var _pending := {}
## Serials that hit this player recently.
var _hit_serials := {}
var _rewarded := {}
var _fx_t := 0.0


func _ready() -> void:
	player = get_parent() as PlayerController
	if player:
		player.dodged.connect(_on_dodged)
		player.damaged.connect(_on_damaged)


func counter_active() -> bool:
	return counter_left > 0.0


## Stagger multiplier for hits made by `shooter` right now.
static func stagger_scale_for(shooter: Node) -> float:
	var pd := shooter.get_node_or_null("PerfectDodge") as PerfectDodge if shooter else null
	return 1.0 + pd.stagger_bonus if pd and pd.counter_active() else 1.0


func _on_damaged(info: DamageInfo) -> void:
	if info.projectile_serial != 0:
		_hit_serials[info.projectile_serial] = true
		_pending.erase(info.projectile_serial)


func _on_dodged(_dir: Vector3) -> void:
	if not enabled or player == null:
		return
	var c := player.global_position + Vector3.UP * 0.9
	for b in PlasmaBolt.in_flight():
		if b.shooter is PlayerController or _rewarded.has(b.serial) or _pending.has(b.serial):
			continue
		if would_hit(b.global_position, b.velocity, c):
			_pending[b.serial] = [b, 0.0]


## True if a bolt at `pos` moving at `vel` reaches within `hit_radius` of the
## body (vertical segment through `centre`, +-0.6 m) within `window` s.
func would_hit(pos: Vector3, vel: Vector3, centre: Vector3) -> bool:
	var v2 := vel.length_squared()
	if v2 < 1e-4:
		return false
	# Closest approach of the bolt's line to the body's centre line,
	# ignoring height first, then checking the height at that moment.
	var rel := centre - pos
	var hv := Vector3(vel.x, 0, vel.z)
	var hrel := Vector3(rel.x, 0, rel.z)
	var hv2 := hv.length_squared()
	var t := hrel.dot(hv) / hv2 if hv2 > 1e-4 else rel.dot(vel) / v2
	if t < 0.0 or t > window:
		return false
	var at := pos + vel * t
	var flat := Vector2(at.x - centre.x, at.z - centre.z).length()
	return flat <= hit_radius and absf(at.y - centre.y) <= 0.6 + hit_radius * 0.5


func _physics_process(delta: float) -> void:
	if counter_left > 0.0:
		counter_left = maxf(counter_left - delta, 0.0)
		_fx_t -= delta
		if _fx_t <= 0.0 and counter_left > 0.0:
			_fx_t = 0.5
			_cannon_surge(0.45)
	if _pending.is_empty():
		if not _hit_serials.is_empty():
			_hit_serials.clear()
		return
	for serial in _pending.keys():
		var e: Array = _pending[serial]
		e[1] += delta
		var b: PlasmaBolt = e[0]
		var gone: bool = not is_instance_valid(b) or not b.active or b.serial != serial
		var past := false
		if not gone:
			# Flying away from the player again: it has passed.
			var rel := player.global_position + Vector3.UP * 0.9 - b.global_position
			past = rel.dot(b.velocity) < 0.0 and rel.length() > hit_radius
		if gone or past or e[1] >= confirm_time:
			_pending.erase(serial)
			if not _hit_serials.has(serial):
				_reward(serial)


func _reward(serial: int) -> void:
	_rewarded[serial] = true
	if _rewarded.size() > 64:
		_rewarded.clear()
	var fresh := not counter_active()
	counter_left = counter_duration
	count += 1
	perfect_dodge.emit(counter_duration)
	if fresh:
		_fx_t = 0.5
		_cannon_surge(1.0)
		var at := player.global_position + Vector3.UP
		Sfx.play_at(get_tree().current_scene if get_tree().current_scene else get_tree().root,
			Sfx.PERFECT_DODGE, at, -2.0, 5.0, 30.0)


## Electrical surge on both arm cannons (forearm joints).
func _cannon_surge(k: float) -> void:
	var sk := player.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		return
	var s: Skeleton3D = sk[0]
	for b in ["mixamorig_RightForeArm", "mixamorig_LeftForeArm"]:
		var i := s.find_bone(b)
		if i >= 0:
			JointSparks.play_on_bone(s, i, k)
