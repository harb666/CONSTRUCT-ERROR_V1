class_name PlayerMelee
extends Node
## The player's melee: pistol-cannon punch-shots (owner asked). The arm(s)
## a move uses switch to the pistol cannon at once (with its materialise
## flash), the player strikes and fires point blank as it lands:
##  - a grunt (or a Neon Sentinel) dies at once and is blown to pieces;
##  - a skirmisher is badly hurt and knocked back, stumbling;
##  - big enemies (the robot boss) can't be meleed (never picked).
##
## Glide (owner asked: "rapidly fly across and melee the enemy no matter
## what if within a suitable distance and no obstructions"): a locked enemy
## (either arm's lock) up to `glide_reach` away with a clear way to it - or,
## with nothing locked, the nearest on screen - is reached by power-gliding
## across the floor or through the air at `glide_speed`, glitching
## (GlitchGlide) with the camera pulled wide and low beside it, then struck.
## Close enemies (`reach`) are struck from where the player stands, as
## before. It works from the air too.
##
## Combo (owner asked: melees one after another all different, switching
## arms): a melee started within `chain_window` s of the last one is the
## next move of CHAIN - cannon jab (right), left hook, rising uppercut
## (right), glitch spin backfist (left), twin cannon slam (both) - then
## round again; after a pause it starts at the jab. Each move has its own
## timeline, pose (MeleePoseModifier), camera shot (CameraRig.melee_shot)
## and hit. The arms go back to the weapons they had `restore_delay` s after
## the last melee of a chain.
## Movement input, jumps and dodges wait while it plays (PlayerController).

signal started(target: RobotEnemy)
## The punch landed (killed = the enemy died from it).
signal struck(target: RobotEnemy, killed: bool)
signal finished

enum Move { JAB, HOOK, UPPERCUT, SPIN, SLAM }
## The combo, in order.
const CHAIN: Array[int] = [Move.JAB, Move.HOOK, Move.UPPERCUT, Move.SPIN, Move.SLAM]
## Per move: the arms whose cannons strike, its timeline (wind-up ends,
## the hit lands, the move ends; s), hit-stop, and its camera shot (yaw /
## pitch / roll offsets in radians, closer in by `close` m, an orbit
## `sweep` in radians, FOV punch at the hit).
const MOVES := {
	Move.JAB: {"name": "CANNON JAB", "arms": ["Right"], "windup": 0.12, "hit": 0.2, "duration": 0.62, "stop": 0.07,
		"cam": {"yaw": 0.3, "pitch": -0.06, "roll": 0.0, "close": 0.85, "sweep": 0.0, "fov": 9.0}},
	Move.HOOK: {"name": "LEFT HOOK", "arms": ["Left"], "windup": 0.13, "hit": 0.21, "duration": 0.62, "stop": 0.07,
		"cam": {"yaw": -0.5, "pitch": -0.1, "roll": -0.1, "close": 1.0, "sweep": 0.0, "fov": 10.0}},
	Move.UPPERCUT: {"name": "RISING UPPERCUT", "arms": ["Right"], "windup": 0.15, "hit": 0.24, "duration": 0.72, "stop": 0.08,
		"cam": {"yaw": 0.55, "pitch": 0.32, "roll": 0.08, "close": 1.1, "sweep": 0.0, "fov": 11.0}},
	Move.SPIN: {"name": "GLITCH SPIN", "arms": ["Left"], "windup": 0.05, "hit": 0.32, "duration": 0.74, "stop": 0.07,
		"cam": {"yaw": -0.2, "pitch": 0.05, "roll": 0.0, "close": 0.7, "sweep": 0.95, "fov": 10.0}},
	Move.SLAM: {"name": "TWIN CANNON SLAM", "arms": ["Right", "Left"], "windup": 0.2, "hit": 0.33, "duration": 0.82, "stop": 0.11,
		"cam": {"yaw": 0.25, "pitch": -0.5, "roll": 0.0, "close": 0.5, "sweep": 0.0, "fov": 14.0}},
}

## Strike from where the player stands within this (m, level).
@export var reach := 4.6
## Glide in from this far (m, straight line) to a locked enemy.
@export var glide_reach := 20.0
@export var glide_speed := 30.0
## The crouch before it launches (s), and the longest a glide may take.
@export var glide_launch := 0.07
@export var glide_max_time := 1.0
## Distance from the enemy's middle the cannon lands at (m, level).
@export var contact_range := 1.25
@export var cooldown := 0.12
## A melee this soon after the last one is the next move of the combo.
@export var chain_window := 1.2
## The arms go back to their weapons this long after the last melee.
@export var restore_delay := 0.9
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
@export var hit_stop_scale := 0.05
static var hit_stop_enabled := true
## Chest height above the feet the glide lines up with the enemy's middle.
const CHEST := 1.1

var active := false
## Seconds into the strike (the move's timeline; 0 while gliding).
var t := 0.0
var target: RobotEnemy
## Where the cannon is driven (world): the enemy's middle.
var aim_point := Vector3.ZERO
var face_yaw := 0.0
## Level lunge velocity (x, z) the PlayerController uses while striking.
var lunge := Vector2.ZERO
## Vertical speed the PlayerController uses while `drives_vertical()`.
var vertical := 0.0
var hit_done := false
## Seconds into the move when the punch landed.
var strike_t := -1.0
## The move playing (Move) and its timeline.
var move := Move.JAB
var windup_time := 0.12
var hit_time := 0.2
var duration := 0.62
## Gliding in to the enemy (before the strike): its velocity and time.
var gliding := false
var glide_t := 0.0
var glide_velocity := Vector3.ZERO
## The strike started off the floor (no gravity until just after the hit).
var in_air := false
## This strike came straight out of a glide (the pose is already on).
var from_glide := false
## Spin of the whole body (radians; the glitch spin), for the pose.
var spin := 0.0
## Counters (tests).
var strikes := 0
var kills := 0
var whiffs := 0
var hit_stops := 0
var glides := 0
var history: Array[int] = []

var _cd := 0.0
var _chain := -1
var _since := 99.0
## Weapons the melee took off each arm (put back after the chain).
var _prev := {}
var _player: PlayerController
var _glitch: GlitchGlide
var _stuck := 0.0


func _ready() -> void:
	_player = get_parent() as PlayerController


func holder() -> WeaponHolder:
	return _player.get_node_or_null("WeaponHolder") as WeaponHolder if _player else null


## Grunts, skirmishers and sentinels; never the robot boss (too big).
static func can_punch(e: Object) -> bool:
	return e is RobotEnemy and not (e is RobotBoss) and is_instance_valid(e) and (e as RobotEnemy).alive


## Whether the current move's cannon(s) are on `side` (auto-fire waits).
func uses_arm(side: String) -> bool:
	return active and (MOVES[move].arms as Array).has(side)


## The move a melee started now would be.
func next_move() -> int:
	return CHAIN[(_chain + 1) % CHAIN.size()] if _since <= chain_window and _chain >= 0 else CHAIN[0]


func move_name(m := -1) -> String:
	return MOVES[move if m < 0 else m].name


## An enemy it could melee right now, or null: a locked one in glide reach
## with a clear way to it first, then the nearest in reach, then (nothing
## locked) the nearest on screen in glide reach with a clear way.
func find_target() -> RobotEnemy:
	if _player == null or not _player.is_inside_tree():
		return null
	var locks: Array = []
	for n in [^"TargetLock", ^"TargetLockLeft"]:
		var l := _player.get_node_or_null(n) as TargetLock
		if l and l.has_target() and l.current:
			locks.append(l)
	for l: TargetLock in locks:
		var e := l.current.get_parent() as RobotEnemy
		if can_punch(e) and _in_glide_reach(e) and path_clear(e):
			return e
	var best: RobotEnemy = null
	var best_d := INF
	var enemies := _player.get_tree().get_nodes_in_group(&"enemies")
	for n in enemies:
		var e := n as RobotEnemy
		if not can_punch(e):
			continue
		var off := e.global_position - _player.global_position
		if absf(off.y) > 1.6:
			continue
		var d := Vector2(off.x, off.z).length()
		if d <= reach and d < best_d:
			best_d = d
			best = e
	if best or not locks.is_empty():
		return best
	var view := _player.get_node_or_null(^"TargetLock") as TargetLock
	for n in enemies:
		var e := n as RobotEnemy
		if not can_punch(e) or not _in_glide_reach(e):
			continue
		var d := _player.global_position.distance_to(e.global_position)
		if d >= best_d or (view and not view.in_view(_aim_of(e))) or not path_clear(e):
			continue
		best_d = d
		best = e
	return best


func _in_glide_reach(e: RobotEnemy) -> bool:
	return (_player.global_position + Vector3.UP * CHEST).distance_to(_aim_of(e)) <= glide_reach


func _aim_of(e: RobotEnemy) -> Vector3:
	var tg := e.get_node_or_null("Targetable") as Targetable
	return tg.get_aim_point() if tg else e.global_position + Vector3.UP


## Nothing of the level in the way of a glide to `e`: lines from the
## player's chest, head and knees to where it would strike from (robots
## and players don't block; only level geometry - static bodies - does).
func path_clear(e: RobotEnemy) -> bool:
	var space := _player.get_world_3d().direct_space_state
	var to := _aim_of(e)
	var from := _player.global_position + Vector3.UP * CHEST
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var dir := flat.normalized() if flat.length() > 0.01 else -_player.global_basis.z
	var end := to - dir * contact_range * 0.8
	var side := dir.cross(Vector3.UP).normalized() * 0.3
	for off in [Vector3.ZERO, Vector3.UP * 0.6, Vector3.DOWN * 0.7, side, -side]:
		if not _line_clear(space, from + off, end + off, e):
			return false
	return true


func _line_clear(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3, e: RobotEnemy) -> bool:
	var ex: Array[RID] = [_player.get_rid()]
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	for i in 4:
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.collider == e:
			return true
		if hit.collider is StaticBody3D:
			return false
		ex.append(hit.rid)
	return true


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
	move = next_move()
	_chain = CHAIN.find(move)
	var m: Dictionary = MOVES[move]
	windup_time = m.windup
	hit_time = m.hit
	duration = m.duration
	t = 0.0
	hit_done = false
	strike_t = -1.0
	lunge = Vector2.ZERO
	vertical = 0.0
	spin = 0.0
	in_air = false
	from_glide = false
	_update_aim()
	# Far off (or up in the air): glide in first.
	var off := aim_point - (_player.global_position + Vector3.UP * CHEST)
	gliding = Vector2(off.x, off.z).length() > reach or absf(off.y) > 1.6
	glide_t = 0.0
	glide_velocity = Vector3.ZERO
	_stuck = 0.0
	if gliding:
		glides += 1
		_glitch_on()
	_take_cannons()
	_camera(func(r: CameraRig) -> void:
		if gliding:
			r.melee_glide(true))
	if not gliding:
		_begin_strike()
	history.append(move)
	DebugHud.note("melee %s%s" % [move_name(), " glide" if gliding else ""])
	started.emit(e)
	return true


## The arms this move uses take the pistol cannon (the default weapon), at
## once; the weapons they had are kept to give back after the chain.
func _take_cannons() -> void:
	var h := holder()
	if h == null or h.default_weapon == null:
		return
	for side: String in MOVES[move].arms:
		var slot := h.slot(side)
		if slot == null:
			continue
		if slot.target_definition() != h.default_weapon:
			if not _prev.has(side):
				_prev[side] = slot.target_definition()
			slot.switch_phase = 0
			slot.switch_scale = 1.0
			h.equip(h.default_weapon, side)
			if slot._fx:
				slot._fx.play(h.default_weapon.accent_color, 0.9, 0.2)
		elif slot.switch_phase != 0:
			slot.switch_phase = 0
			slot.switch_scale = 1.0


func _give_back() -> void:
	var h := holder()
	if h:
		for side in _prev:
			if _prev[side]:
				h.switch_weapon(_prev[side], side)
	_prev.clear()


func _camera(f: Callable) -> void:
	if _player.is_remote:
		return
	for r in _player.get_tree().get_nodes_in_group(&"camera_rigs"):
		if r is CameraRig and (r as CameraRig).target == _player:
			f.call(r)


func _begin_strike() -> void:
	from_glide = gliding
	gliding = false
	t = 0.0
	in_air = not _player.is_on_floor() or move == Move.UPPERCUT or move == Move.SLAM or move == Move.SPIN
	_camera(func(r: CameraRig) -> void:
		r.melee_glide(false)
		r.melee_shot(MOVES[move].cam, duration))
	if move == Move.SPIN:
		_glitch_on()  # it glitches round
	elif _glitch:
		_glitch.stop()
		_glitch = null


func _glitch_on() -> void:
	if _glitch and is_instance_valid(_glitch):
		return
	_glitch = GlitchGlide.start(_player)


func _update_aim() -> void:
	if target and is_instance_valid(target) and target.alive:
		aim_point = _aim_of(target)
	var to := aim_point - _player.global_position
	to.y = 0.0
	if to.length_squared() > 1e-4:
		face_yaw = atan2(-to.x, -to.z)


## The vertical speed comes from the move (gliding, or a strike in the air
## until just after its hit), not gravity.
func drives_vertical() -> bool:
	return active and (gliding or (in_air and (not hit_done or t < strike_t + 0.12)))


## Advance the move (PlayerController.simulate, every tick).
func tick(delta: float) -> void:
	_cd = maxf(_cd - delta, 0.0)
	if not active:
		_since += delta
		if _since >= restore_delay and not _prev.is_empty():
			_give_back()
		return
	_camera(func(r: CameraRig) -> void:
		r.melee_face(face_yaw))
	if gliding:
		_glide(delta)
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
		vertical = _vertical_before_hit()
		if move == Move.SPIN:
			spin = TAU * smoothstep(0.0, hit_time, t)
		if t >= hit_time or (t >= hit_time - 0.05 and dist <= contact_range + 0.15 and move != Move.SPIN and move != Move.SLAM):
			_strike(dir)
	else:
		lunge = lunge.move_toward(Vector2.ZERO, 30.0 * delta)
		vertical = move_toward(vertical, 0.0, 20.0 * delta)
	if t >= duration:
		_end()


## The move's own up / down: the uppercut rises with the punch, the slam
## hops then hammers down, the spin hops; in the air otherwise it hangs.
func _vertical_before_hit() -> float:
	match move:
		Move.UPPERCUT:
			return lerpf(0.0, 5.5, smoothstep(windup_time, hit_time, t))
		Move.SLAM:
			var high := (aim_point.y - CHEST) - _player.global_position.y
			return 4.5 if t < windup_time and high > -1.0 else -14.0
		Move.SPIN:
			return 2.2 if t < hit_time * 0.6 else -1.5
	return 0.0


## Glide: crouch a beat, then fly straight at the point it strikes from
## (beside the enemy, chest to its middle), steering after it as it moves.
func _glide(delta: float) -> void:
	glide_t += delta
	if target == null or not is_instance_valid(target) or not target.alive:
		_end()
		return
	_update_aim()
	var flat := Vector3(aim_point.x - _player.global_position.x, 0.0, aim_point.z - _player.global_position.z)
	var dir := flat.normalized() if flat.length() > 0.01 else -_player.global_basis.z
	var goal := aim_point - dir * contact_range - Vector3.UP * CHEST
	if _player.is_on_floor() and goal.y < _player.global_position.y + 0.4:
		goal.y = minf(goal.y, _player.global_position.y)  # along the floor
	var to := goal - _player.global_position
	var d := to.length()
	if glide_t < glide_launch:
		glide_velocity = Vector3.ZERO
	else:
		var k := smoothstep(glide_launch, glide_launch + 0.1, glide_t)
		glide_velocity = to / maxf(d, 0.001) * minf(glide_speed * lerpf(0.4, 1.0, k), d / maxf(delta, 0.001))
	# Something in the way after all (another robot, a closing door): stop
	# and strike from here.
	var moved := _player.get_real_velocity().length()
	_stuck = _stuck + delta if glide_t > glide_launch + 0.1 and moved < glide_speed * 0.25 and d > 0.5 else 0.0
	if d < 0.45 or glide_t >= glide_max_time or _stuck > 0.12:
		glide_velocity = Vector3.ZERO
		_begin_strike()


func _strike(dir2: Vector2) -> void:
	hit_done = true
	strike_t = t
	spin = TAU if move == Move.SPIN else 0.0
	var dir := Vector3(dir2.x, 0.0, dir2.y)
	if dir.length_squared() < 0.5:
		dir = -_player.global_basis.z
	lunge = -dir2 * 1.6  # bounce back off the hit
	var h := holder()
	var tree := _player.get_tree()
	var col := Color(0.1, 0.8, 1.0)
	var hot := Color.WHITE
	for side: String in MOVES[move].arms:
		var cannon := h.weapon(side) as PlasmaCannon if h else null
		if cannon == null:
			continue
		var from := cannon.muzzle_position()
		var shot_dir := (aim_point - from).normalized() if aim_point.distance_to(from) > 0.05 else dir
		cannon.melee_shot(shot_dir, 2.2 if move == Move.SLAM else 1.6)
		col = cannon.bolt_color
		hot = cannon.bolt_hot_color
	var e := target
	var reach_ok := e != null and is_instance_valid(e) and e.alive
	if reach_ok:
		var off := _aim_of(e) - (_player.global_position + Vector3.UP * CHEST)
		reach_ok = Vector2(off.x, off.z).length() <= contact_range + 1.2 and absf(off.y) <= 2.2
	if move == Move.SLAM:
		# The shockwave races out along the floor under the slam (none if
		# it's struck high in the air).
		var from := _player.global_position + Vector3.UP * 0.5
		var down := _player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0, 1, [_player.get_rid()]))
		if not down.is_empty():
			StompShockwave.spawn(tree, down.position, 3.4)
	if not reach_ok:
		whiffs += 1
		return
	var at := aim_point - dir * 0.25
	HitStar.spawn(tree, at, col, 1.1 if move != Move.SLAM else 1.6)
	PlasmaFx.impact(tree, at, -dir, false, col, hot)
	var push := _push(dir)
	var killed := false
	var arm: StringName = &"Left" if MOVES[move].arms == ["Left"] else &"Right"
	if e is RobotSkirmisher:
		var info := DamageInfo.make(skirmisher_damage, DamageInfo.Type.ENERGY, at, push, skirmisher_force, 0.0, _player)
		info.weapon = &"melee"
		info.arm = arm
		e.apply_damage(info)
		killed = not e.alive
		if not killed:
			(e as RobotSkirmisher).knock_back(push, knock_back_speed, stumble_time)
	else:
		# Grunts (and sentinels): dead at once, blown to pieces, sent flying.
		var info := DamageInfo.make(maxf(e.health, 0.0) + 1.0, DamageInfo.Type.EXPLOSION, at, push, 0.0, grunt_kill_force, _player)
		info.weapon = &"melee"
		info.arm = arm
		e.apply_damage(info)
		killed = true
		var host: Node = tree.current_scene if tree.current_scene else tree.root
		MissileBlast.spawn(host, at, 1.4, 0.4, false)
	strikes += 1
	if killed:
		kills += 1
	_hit_stop(MOVES[move].stop)
	_camera(func(r: CameraRig) -> void:
		r.melee_impact(1.5 if move == Move.SLAM else 1.0))
	struck.emit(e, killed)


## Which way each move sends the enemy: the jab straight on, the hook
## across, the uppercut up, the spin straight on, the slam out and down.
func _push(dir: Vector3) -> Vector3:
	var across := dir.cross(Vector3.UP).normalized()
	match move:
		Move.HOOK:
			return (dir + across * 0.7 + Vector3.UP * 0.35).normalized()
		Move.UPPERCUT:
			return (dir * 0.35 + Vector3.UP).normalized()
		Move.SLAM:
			return (dir + Vector3.UP * 0.15).normalized()
	return (dir + Vector3.UP * 0.45).normalized()


func _hit_stop(time: float) -> void:
	# (A teammate's punch shown here doesn't stop this device's game.)
	if not hit_stop_enabled or time <= 0.0 or _player.is_remote:
		return
	Engine.time_scale = hit_stop_scale
	hit_stops += 1
	_player.get_tree().create_timer(time, true, false, true).timeout.connect(func() -> void:
		Engine.time_scale = 1.0)


func _end() -> void:
	active = false
	gliding = false
	lunge = Vector2.ZERO
	vertical = 0.0
	glide_velocity = Vector3.ZERO
	spin = 0.0
	_cd = cooldown
	_since = 0.0
	target = null
	if _glitch:
		_glitch.stop()
		_glitch = null
	_camera(func(r: CameraRig) -> void:
		r.melee_glide(false)
		r.melee_face(0.0, false))
	finished.emit()


## Stop at once (respawn etc.).
func cancel() -> void:
	if active:
		t = duration
		_end()
	if not _prev.is_empty():
		_give_back()
	if Engine.time_scale != 1.0:
		Engine.time_scale = 1.0
