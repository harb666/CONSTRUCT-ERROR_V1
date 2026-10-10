class_name PlayerMelee
extends Node
## The player's melee: a pistol-cannon punch-shot (owner asked). The right
## arm switches to the pistol cannon (instantly, with its materialise flash),
## the player sets one foot back, coils and lunges at the enemy, swings the
## cannon into it like a punch and fires it point blank as it lands:
##  - a grunt (RobotEnemy) dies at once and is blown to pieces, sent far;
##  - a skirmisher is badly hurt and knocked back, stumbling;
##  - big enemies (the robot boss) can't be meleed (never picked).
## Quick (`duration` ~0.62 s): wind-up, strike at `hit_time`, a beat of
## hit-stop, follow-through, recover. The camera swings a little round to the
## side and back in time (CameraRig.melee_camera). Afterwards the right arm
## switches back to the weapon it had. The full-body pose is drawn by
## MeleePoseModifier (CharacterAnimator) from this node's timeline.
## Movement input, jumps and dodges wait while it plays (PlayerController).

signal started(target: RobotEnemy)
## The punch landed (killed = the enemy died from it).
signal struck(target: RobotEnemy, killed: bool)
signal finished

@export var reach := 4.6
## Distance from the enemy's middle the cannon lands at (m, level).
@export var contact_range := 1.25
@export var windup_time := 0.12
@export var hit_time := 0.2
@export var duration := 0.62
@export var cooldown := 0.3
## Fastest lunge (m/s).
@export var max_lunge_speed := 24.0
## Grunts: blown apart with this force (the rocket's is 44).
@export var grunt_kill_force := 72.0
## Skirmishers: damage (their health is 1.4), hit force and knock-back.
@export var skirmisher_damage := 0.9
@export var skirmisher_force := 14.0
@export var knock_back_speed := 9.0
@export var stumble_time := 0.85
## Hit-stop: the world almost freezes for a beat as the punch lands.
@export var hit_stop_time := 0.07
@export var hit_stop_scale := 0.05
static var hit_stop_enabled := true

var active := false
## Seconds into the move.
var t := 0.0
var target: RobotEnemy
## Where the cannon is driven (world): the enemy's middle.
var aim_point := Vector3.ZERO
var face_yaw := 0.0
## Level lunge velocity (x, z) the PlayerController uses while active.
var lunge := Vector2.ZERO
var hit_done := false
## Seconds into the move when the punch landed.
var strike_t := -1.0
## Counters (tests).
var strikes := 0
var kills := 0
var whiffs := 0
var hit_stops := 0

var _cd := 0.0
var _prev_def: WeaponDefinition
var _player: PlayerController


func _ready() -> void:
	_player = get_parent() as PlayerController


func holder() -> WeaponHolder:
	return _player.get_node_or_null("WeaponHolder") as WeaponHolder if _player else null


## An enemy it could punch right now (nearest in reach; the locked target
## first), or null.
func find_target() -> RobotEnemy:
	if _player == null or not _player.is_inside_tree():
		return null
	var best: RobotEnemy = null
	var best_d := INF
	var lock := _player.get_node_or_null("TargetLock") as TargetLock
	var locked: Node = lock.current.get_parent() if lock and lock.has_target() and lock.current else null
	for n in _player.get_tree().get_nodes_in_group(&"enemies"):
		var e := n as RobotEnemy
		if not can_punch(e):
			continue
		var off := e.global_position - _player.global_position
		if absf(off.y) > 1.6:
			continue
		var d := Vector2(off.x, off.z).length()
		if d > reach:
			continue
		if e == locked:
			d -= 100.0
		if d < best_d:
			best_d = d
			best = e
	return best


## Grunts and skirmishers; never the robot boss (too big).
static func can_punch(e: Object) -> bool:
	return e is RobotEnemy and not (e is RobotBoss) and is_instance_valid(e) and (e as RobotEnemy).alive


func available() -> bool:
	return not active and _cd <= 0.0 and find_target() != null


func try_start() -> bool:
	if active or _cd > 0.0 or _player == null:
		return false
	var e := find_target()
	if e == null:
		return false
	target = e
	active = true
	t = 0.0
	hit_done = false
	strike_t = -1.0
	lunge = Vector2.ZERO
	_update_aim()
	# The right arm takes the pistol cannon (the default weapon), at once.
	var h := holder()
	if h and h.default_weapon:
		var slot := h.slot("Right")
		if slot and slot.target_definition() != h.default_weapon:
			_prev_def = slot.target_definition()
			slot.switch_phase = 0
			slot.switch_scale = 1.0
			h.equip(h.default_weapon, "Right")
			if slot._fx:
				slot._fx.play(h.default_weapon.accent_color, 0.9, 0.2)
		elif slot and slot.switch_phase != 0:
			slot.switch_phase = 0
			slot.switch_scale = 1.0
	for r in _player.get_tree().get_nodes_in_group(&"camera_rigs"):
		if r is CameraRig and (r as CameraRig).target == _player:
			(r as CameraRig).melee_camera(duration)
	DebugHud.note("melee")
	started.emit(e)
	return true


func _update_aim() -> void:
	if target and is_instance_valid(target) and target.alive:
		var tg := target.get_node_or_null("Targetable") as Targetable
		aim_point = tg.get_aim_point() if tg else target.global_position + Vector3.UP
	var to := aim_point - _player.global_position
	to.y = 0.0
	if to.length_squared() > 1e-4:
		face_yaw = atan2(-to.x, -to.z)


## Advance the move (PlayerController.simulate, every tick).
func tick(delta: float) -> void:
	_cd = maxf(_cd - delta, 0.0)
	if not active:
		return
	t += delta
	if not hit_done:
		_update_aim()
	var to := aim_point - _player.global_position
	to.y = 0.0
	var dist := to.length()
	var dir := Vector2(to.x, to.z) / dist if dist > 0.01 else Vector2.ZERO
	if not hit_done:
		if t < 0.03:
			lunge = Vector2.ZERO  # a beat of anticipation
		else:
			var gap := maxf(dist - contact_range, 0.0)
			lunge = dir * minf(gap / maxf(hit_time - t, 0.04), max_lunge_speed)
		if t >= hit_time or (t >= hit_time - 0.05 and dist <= contact_range + 0.15):
			_strike(dir)
	else:
		lunge = lunge.move_toward(Vector2.ZERO, 30.0 * delta)
	if t >= duration:
		_end()


func _strike(dir2: Vector2) -> void:
	hit_done = true
	strike_t = t
	var dir := Vector3(dir2.x, 0.0, dir2.y)
	if dir.length_squared() < 0.5:
		dir = -_player.global_basis.z
	lunge = -dir2 * 1.6  # bounce back off the hit
	var h := holder()
	var cannon := h.weapon("Right") as PlasmaCannon if h else null
	var from := cannon.muzzle_position() if cannon else _player.global_position + Vector3.UP * 1.2
	var shot_dir := (aim_point - from).normalized() if aim_point.distance_to(from) > 0.05 else dir
	if cannon:
		cannon.melee_shot(shot_dir)
	var tree := _player.get_tree()
	var e := target
	var landed := e != null and is_instance_valid(e) and e.alive and Vector2(e.global_position.x - _player.global_position.x, e.global_position.z - _player.global_position.z).length() <= contact_range + 1.2
	if not landed:
		whiffs += 1
		return
	var at := aim_point - dir * 0.25
	var col := cannon.bolt_color if cannon else Color(0.1, 0.8, 1.0)
	var hot := cannon.bolt_hot_color if cannon else Color.WHITE
	HitStar.spawn(tree, at, col, 1.1)
	PlasmaFx.impact(tree, at, -dir, false, col, hot)
	var push := (dir + Vector3.UP * 0.45).normalized()
	var killed := false
	if e is RobotSkirmisher:
		var info := DamageInfo.make(skirmisher_damage, DamageInfo.Type.ENERGY, at, push, skirmisher_force, 0.0, _player)
		info.weapon = &"melee"
		info.arm = &"Right"
		e.apply_damage(info)
		killed = not e.alive
		if not killed:
			(e as RobotSkirmisher).knock_back(dir, knock_back_speed, stumble_time)
	else:
		# Grunts: dead at once, blown to pieces and sent flying.
		var info := DamageInfo.make(maxf(e.health, 0.0) + 1.0, DamageInfo.Type.EXPLOSION, at, push, 0.0, grunt_kill_force, _player)
		info.weapon = &"melee"
		info.arm = &"Right"
		e.apply_damage(info)
		killed = true
		var host: Node = tree.current_scene if tree.current_scene else tree.root
		MissileBlast.spawn(host, at, 1.4, 0.4, false)
	strikes += 1
	if killed:
		kills += 1
	_hit_stop()
	for r in tree.get_nodes_in_group(&"camera_rigs"):
		if r is CameraRig and (r as CameraRig).target == _player:
			(r as CameraRig).melee_impact()
	struck.emit(e, killed)


func _hit_stop() -> void:
	if not hit_stop_enabled or hit_stop_time <= 0.0:
		return
	Engine.time_scale = hit_stop_scale
	hit_stops += 1
	_player.get_tree().create_timer(hit_stop_time, true, false, true).timeout.connect(func() -> void:
		Engine.time_scale = 1.0)


func _end() -> void:
	active = false
	lunge = Vector2.ZERO
	_cd = cooldown
	target = null
	# Back to the weapon the right arm had (the usual switch sequence).
	if _prev_def:
		var h := holder()
		if h:
			h.switch_weapon(_prev_def, "Right")
		_prev_def = null
	finished.emit()


## Stop at once (respawn etc.).
func cancel() -> void:
	if active:
		t = duration
		_end()
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
