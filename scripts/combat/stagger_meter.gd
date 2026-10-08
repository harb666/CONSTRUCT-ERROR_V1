class_name StaggerMeter
extends RefCounted
## Stagger (stability) for tougher enemies: hits fill it, and when full the
## enemy is staggered for `duration` s (attacks interrupted, more
## vulnerable). Shared enemy state - one meter per enemy, fed by every
## player's hits - so it stays consistent when hits arrive from several
## players. Light troops don't get one (they stay fast and fragile).
##
## Per hit: damage x weapon factor (shotgun more up close) x 1.25 when the
## same player's OTHER arm hit this enemy within `dual_window` s
## (concentrated fire) x that player's perfect-dodge counter bonus.
## Drains after `decay_delay` s without hits. After a stagger it can't
## build for `immune_time` s (no stun-locks).

signal staggered(duration: float)

var threshold := 9.0
var duration := 1.25
var decay_delay := 1.0
## Fraction of the threshold drained per second once decaying.
var decay_rate := 0.3
var dual_bonus := 0.25
var dual_window := 0.4
var immune_time := 3.0
var weapon_factor := {&"plasma": 1.0, &"machine_gun": 0.45, &"shotgun": 1.0, &"black_hole": 1.5, &"": 1.0}
## Shotgun: up to this much extra at point-blank (scaled by impact force).
var shotgun_close_bonus := 1.0

var value := 0.0
var stagger_left := 0.0
## Counters for tests / tuning.
var staggers := 0
var dual_hits := 0

var _idle := 0.0
var _immune := 0.0
## shooter instance id -> {arm: time of last hit}
var _arm_hits := {}
var _clock := 0.0


func is_staggered() -> bool:
	return stagger_left > 0.0


## 0..1 fill (for effects).
func fill() -> float:
	return clampf(value / maxf(threshold, 0.01), 0.0, 1.0)


## Amount this hit adds (before the immunity check).
func amount_for(info: DamageInfo) -> float:
	var f: float = weapon_factor.get(info.weapon, 1.0)
	if info.weapon == &"shotgun":
		f *= 1.0 + shotgun_close_bonus * clampf((info.impact_force - 2.0) / 7.0, 0.0, 1.0)
	var a := info.damage_amount * f
	if info.source and info.arm != &"":
		var key := info.source.get_instance_id()
		var arms: Dictionary = _arm_hits.get(key, {})
		var other := &"Left" if info.arm == &"Right" else &"Right"
		if arms.has(other) and _clock - float(arms[other]) <= dual_window:
			a *= 1.0 + dual_bonus
			dual_hits += 1
		arms[info.arm] = _clock
		_arm_hits[key] = arms
	if info.source:
		a *= PerfectDodge.stagger_scale_for(info.source)
	return a


## Feed a hit; true if it just staggered the enemy.
func add(info: DamageInfo) -> bool:
	var a := amount_for(info)
	_idle = 0.0
	if is_staggered() or _immune > 0.0:
		return false
	value += a
	if value >= threshold:
		value = 0.0
		stagger_left = duration
		_immune = duration + immune_time
		staggers += 1
		staggered.emit(duration)
		return true
	return false


func update(delta: float) -> void:
	_clock += delta
	stagger_left = maxf(stagger_left - delta, 0.0)
	_immune = maxf(_immune - delta, 0.0)
	_idle += delta
	if _idle > decay_delay and value > 0.0:
		value = maxf(value - threshold * decay_rate * delta, 0.0)
	if _arm_hits.size() > 8:
		_arm_hits.clear()
