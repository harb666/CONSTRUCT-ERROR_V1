class_name Suppression
extends RefCounted
## Split-fire suppression for light troops. When a player has each arm
## locked on a DIFFERENT enemy, that player's hits rattle the enemies they
## land on: sustained hits widen their aim spread (up to `max_spread_scale`
## x), and once the level passes `delay_at` the enemy's current burst is cut
## short and its next one delayed (`burst_delay` s) - at most every
## `delay_cooldown` s per enemy. Movement and dodging are never affected
## and it drains quickly, so it never becomes a stun. Shared enemy state.

var per_hit := {&"plasma": 0.14, &"machine_gun": 0.07, &"shotgun": 0.12, &"black_hole": 0.3, &"": 0.1}
var decay_delay := 0.5
var decay_rate := 0.45
var max_spread_scale := 3.0
var delay_at := 0.5
var burst_delay := 0.7
var delay_cooldown := 2.5

var level := 0.0
## Counters for tests / tuning.
var delays := 0
var _idle := 0.0
var _cd := 0.0


## Is `shooter` (a player) splitting its arms over two different targets?
static func split_fire(shooter: Node) -> bool:
	if shooter == null:
		return false
	var a := shooter.get_node_or_null("TargetLock") as TargetLock
	var b := shooter.get_node_or_null("TargetLockLeft") as TargetLock
	return a and b and a.has_target() and b.has_target() and a.current != b.current


## Feed a hit; true if it should cut this enemy's attack short now.
func add(info: DamageInfo) -> bool:
	if not (info.source is PlayerController) or not split_fire(info.source):
		return false
	_idle = 0.0
	level = minf(level + float(per_hit.get(info.weapon, 0.1)), 1.0)
	if level >= delay_at and _cd <= 0.0:
		_cd = delay_cooldown
		delays += 1
		return true
	return false


func spread_scale() -> float:
	return 1.0 + (max_spread_scale - 1.0) * level


func update(delta: float) -> void:
	_cd = maxf(_cd - delta, 0.0)
	_idle += delta
	if _idle > decay_delay:
		level = maxf(level - decay_rate * delta, 0.0)
