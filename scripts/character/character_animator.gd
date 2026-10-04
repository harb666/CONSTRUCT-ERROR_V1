class_name CharacterAnimator
extends Node3D
## Drives the character's AnimationTree from a PlayerController's state.
## Purely visual: reads the controller, never moves it (no root motion).
## Works for any player (local or, later, replicated) since it only reads
## velocity / floor / dodge state and controller signals.

@export var controller_path: NodePath = ^"../.."
@export var model_path: NodePath = ^"Model"

@export_group("Locomotion")
## Horizontal speeds (m/s) at which each clip is fully weighted. Clips appear
## twice so blend zones between different gaits stay narrow.
@export var walk_from := 1.2
@export var walk_to := 4.5
@export var run_from := 6.0
@export var run_to := 9.5
@export var sprint_from := 10.8
## Playback-rate curve vs speed (clips are authored slower than gameplay).
@export var walk_rate := 1.35
@export var run_rate := 1.3
@export var sprint_rate := 1.35

@export_group("Air")
@export var fall_delay := 0.12
@export var long_fall_time := 1.1
@export var long_fall_lift := 0.75
@export var min_land_impact := 5.0

@export_group("Turning")
## Body yaw rate (rad/s) needed to trigger turn clips.
@export var idle_turn_rate := 3.0
@export var idle_turn_max_speed := 2.0
@export var sharp_turn_rate := 7.0
@export var sharp_turn_min_speed := 6.0

const HIPS := "mixamorig_Hips"

# name -> clip setup. a = segment start (s), speed = playback multiplier,
# min = minimum time (s) before gameplay may leave a one-shot state.
const ONE_SHOTS := {
	"Jump": {"anim": "Regular Jump", "a": 0.50, "speed": 1.15, "lock_yaw": true, "xfade": 0.08},
	"AirJump": {"anim": "Regular Jump", "a": 0.52, "speed": 1.4, "lock_yaw": true, "xfade": 0.1},
	"Land": {"anim": "Regular Jump", "a": 1.06, "speed": 1.5, "lock_yaw": true, "xfade": 0.06, "min": 0.22},
	"Dodge": {"anim": "slide right", "a": 0.22, "speed": 2.2, "strip_xz": true, "xfade": 0.05},
	"TurnLeft": {"anim": "Idle Turn Left", "a": 0.08, "speed": 1.7, "strip_xz": true, "lock_yaw": true, "xfade": 0.12, "min": 0.3},
	"TurnRight": {"anim": "Idle Turn Right", "a": 0.08, "speed": 1.7, "strip_xz": true, "lock_yaw": true, "xfade": 0.12, "min": 0.3},
	"SharpTurnRight": {"anim": "Run Sharp Turn Right", "a": 0.78, "speed": 1.5, "strip_xz": true, "lock_yaw": true, "xfade": 0.08, "min": 0.25},
	"Dead": {"anim": "Dead", "a": 0.0, "speed": 1.0, "strip_xz": true, "xfade": 0.15},
	"Climb": {"anim": "Climb Attempt and Fall 5", "a": 0.0, "speed": 1.0, "strip_xz": true, "xfade": 0.15},
}
const LOOPS := {
	"Fall": {"anim": "Fall2", "xfade": 0.18},
	"LongFall": {"anim": "Fall1", "xfade": 0.45, "lift": true},
}

var controller: PlayerController
var anim_tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var current_state := "Locomotion"
var is_dead := false

var _anim_player: AnimationPlayer
var _hips_pos_track := {}  # anim name -> track idx
var _hips_rot_track := {}
var _yaw_ref := 0.0
var _hips_ref_xz := Vector2.ZERO
var _prev_yaw := 0.0
var _yaw_rate := 0.0
var _air_time := 0.0
var _fall_time := 0.0
var _pending_jump := ""
var _pending_land := false
var _state_time := 0.0


func _ready() -> void:
	controller = get_node(controller_path) as PlayerController
	var model := get_node(model_path)
	_anim_player = model.find_child("AnimationPlayer", true, false)
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]

	_cache_hips_tracks(skeleton)
	_build_tree()

	var corrector := HipsCorrector.new()
	corrector.name = "HipsCorrector"
	corrector.bone = skeleton.find_bone(HIPS)
	corrector.provider = _hips_correction
	skeleton.add_child(corrector)

	if controller:
		controller.jumped.connect(_on_jumped)
		controller.landed.connect(_on_landed)
		_prev_yaw = controller.global_rotation.y


func _cache_hips_tracks(skeleton: Skeleton3D) -> void:
	var path := NodePath(str(_anim_player.get_node(_anim_player.root_node).get_path_to(skeleton)) + ":" + HIPS)
	for n in _anim_player.get_animation_list():
		var a := _anim_player.get_animation(n)
		_hips_pos_track[n] = a.find_track(path, Animation.TYPE_POSITION_3D)
		_hips_rot_track[n] = a.find_track(path, Animation.TYPE_ROTATION_3D)
	# Reference "facing forward" yaw: the idle's hips orientation.
	_yaw_ref = _hips_yaw("Idle 9", 0.0)
	var ip := _hips_pos("Idle 9", 0.0)
	_hips_ref_xz = Vector2(ip.x, ip.z)


func _build_tree() -> void:
	var sm := AnimationNodeStateMachine.new()

	# Locomotion: speed-driven 1D blend, then a playback-rate scale.
	var bs := AnimationNodeBlendSpace1D.new()
	bs.sync = true
	bs.min_space = 0.0
	bs.max_space = 14.0
	var points := [["Idle 9", 0.0], ["Walking", walk_from], ["Walking", walk_to], ["Running", run_from],
			["Running", run_to], ["RunFast", sprint_from], ["RunFast", 14.0]]
	for i in points.size():
		var an := AnimationNodeAnimation.new()
		an.animation = points[i][0]
		bs.add_blend_point(an, points[i][1], -1, "p%d" % i)
	var loco := AnimationNodeBlendTree.new()
	loco.add_node("bs", bs, Vector2(0, 0))
	loco.add_node("ts", AnimationNodeTimeScale.new(), Vector2(200, 0))
	loco.connect_node("ts", 0, "bs")
	loco.connect_node("output", 0, "ts")
	sm.add_node("Locomotion", loco)

	for s in ONE_SHOTS:
		var d: Dictionary = ONE_SHOTS[s]
		var an := AnimationNodeAnimation.new()
		an.animation = d.anim
		var length := _anim_player.get_animation(d.anim).length
		# Play the clip from `a` at `speed`: anim_time = a + node_time * speed.
		an.use_custom_timeline = true
		an.stretch_time_scale = true
		an.timeline_length = length / d.speed
		an.start_offset = d.a / d.speed
		an.loop_mode = Animation.LOOP_NONE
		sm.add_node(s, an)
	for s in LOOPS:
		var an := AnimationNodeAnimation.new()
		an.animation = LOOPS[s].anim
		sm.add_node(s, an)

	var names: Array = ["Locomotion"] + ONE_SHOTS.keys() + LOOPS.keys()
	for from in names:
		for to in names:
			if from == to:
				continue
			var t := AnimationNodeStateMachineTransition.new()
			t.xfade_time = _xfade_into(to, from)
			t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
			t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
			sm.add_transition(from, to, t)
	sm.add_transition("Start", "Locomotion", AnimationNodeStateMachineTransition.new())

	anim_tree = AnimationTree.new()
	anim_tree.name = "AnimationTree"
	anim_tree.tree_root = sm
	add_child(anim_tree)
	anim_tree.anim_player = anim_tree.get_path_to(_anim_player)
	anim_tree.active = true
	playback = anim_tree.get("parameters/playback")
	playback.start("Locomotion")


func _xfade_into(to: String, from: String) -> float:
	if to == "Locomotion":
		if from == "Land":
			return 0.2
		if from == "Dodge":
			return 0.18
		return 0.15
	if ONE_SHOTS.has(to):
		return ONE_SHOTS[to].xfade
	return LOOPS[to].xfade


func _on_jumped(is_air_jump: bool) -> void:
	_pending_jump = "AirJump" if is_air_jump else "Jump"


func _on_landed(impact_speed: float) -> void:
	_pending_land = impact_speed >= min_land_impact


func play_death() -> void:
	is_dead = true


func revive() -> void:
	is_dead = false


func _process(delta: float) -> void:
	if controller == null:
		return
	var vel := controller.velocity
	var speed := Vector2(vel.x, vel.z).length()
	var on_floor := controller.is_on_floor()

	var yaw := controller.global_rotation.y
	var raw_rate := wrapf(yaw - _prev_yaw, -PI, PI) / maxf(delta, 0.0001)
	_prev_yaw = yaw
	_yaw_rate = lerpf(_yaw_rate, raw_rate, 1.0 - exp(-25.0 * delta))

	if on_floor:
		_air_time = 0.0
		_fall_time = 0.0
	else:
		_air_time += delta
		if vel.y < 0.0:
			_fall_time += delta

	# Locomotion parameters always update so it is ready to blend back into.
	anim_tree.set("parameters/Locomotion/bs/blend_position", speed)
	anim_tree.set("parameters/Locomotion/ts/scale", _loco_rate(speed))

	_state_time += delta
	var want := _choose_state(on_floor, speed, vel.y)
	_pending_jump = ""
	_pending_land = false
	if want != current_state:
		current_state = want
		_state_time = 0.0
		playback.travel(want)


func _choose_state(on_floor: bool, speed: float, vy: float) -> String:
	if is_dead:
		return "Dead"
	if controller.is_dodging:
		return "Dodge"
	if _pending_jump != "":
		# Double jump while already in Jump re-triggers via the AirJump twin.
		if _pending_jump == current_state:
			return "AirJump" if current_state == "Jump" else "Jump"
		return _pending_jump

	if not on_floor:
		if current_state in ["Jump", "AirJump"] and vy > -1.0:
			return current_state
		if _fall_time > long_fall_time:
			return "LongFall"
		if current_state in ["Fall", "LongFall"]:
			return current_state
		if _air_time > fall_delay or vy < -3.0 or current_state in ["Jump", "AirJump", "Dodge"]:
			return "Fall"
		return current_state if current_state == "Locomotion" else "Locomotion"

	if _pending_land and speed < 6.0:
		return "Land"
	if _holding_one_shot(speed):
		return current_state
	if speed >= sharp_turn_min_speed and _yaw_rate < -sharp_turn_rate:
		return "SharpTurnRight"
	if speed <= idle_turn_max_speed and absf(_yaw_rate) > idle_turn_rate:
		return "TurnLeft" if _yaw_rate > 0.0 else "TurnRight"
	return "Locomotion"


## Grounded one-shots play for at least their "min" time, and leave early
## once gameplay clearly moved on (e.g. started running out of a landing).
func _holding_one_shot(speed: float) -> bool:
	if not ONE_SHOTS.has(current_state):
		return false
	var d: Dictionary = ONE_SHOTS[current_state]
	if not d.has("min") or _state_time >= d.min:
		return false
	match current_state:
		"Land":
			return speed < 4.0 or _state_time < 0.1
		"TurnLeft", "TurnRight":
			return speed <= idle_turn_max_speed
		"SharpTurnRight":
			return speed >= sharp_turn_min_speed * 0.6
	return true


func _loco_rate(speed: float) -> float:
	if speed <= walk_to:
		return lerpf(1.0, walk_rate, clampf(speed / walk_to, 0.0, 1.0))
	if speed <= run_to:
		return lerpf(walk_rate, run_rate, (speed - walk_to) / (run_to - walk_to))
	return lerpf(run_rate, sprint_rate, clampf((speed - run_to) / (14.0 - run_to), 0.0, 1.0))


# --- Hips correction (called by HipsCorrector right after the pose is applied) ---

func _hips_correction() -> Dictionary:
	var out := {"xz": Vector2.ZERO, "y": 0.0, "yaw": 0.0}
	if playback == null:
		return out
	var cur := String(playback.get_current_node())
	var from := String(playback.get_fading_from_node())
	var w := 1.0
	if from != "" and playback.get_fading_length() > 0.0:
		w = clampf(playback.get_fading_position() / playback.get_fading_length(), 0.0, 1.0)
	_accumulate(out, cur, playback.get_current_play_position(), w)
	if from != "" and w < 1.0:
		_accumulate(out, from, playback.get_fading_from_play_position(), 1.0 - w)
	return out


func _accumulate(out: Dictionary, state: String, node_time: float, weight: float) -> void:
	if LOOPS.has(state):
		if LOOPS[state].get("lift", false):
			out.y += long_fall_lift * weight
		return
	if not ONE_SHOTS.has(state):
		return
	var d: Dictionary = ONE_SHOTS[state]
	var anim: String = d.anim
	var length := _anim_player.get_animation(anim).length
	var t := minf(d.a + node_time * d.speed, length)
	if d.get("strip_xz", false):
		# Pull the hips back over the capsule (where in-place clips keep them).
		var p := _hips_pos(anim, t)
		out.xz += (_hips_ref_xz - Vector2(p.x, p.z)) * weight
	if d.get("lock_yaw", false):
		out.yaw += wrapf(_yaw_ref - _hips_yaw(anim, t), -PI, PI) * weight


func _hips_pos(anim: String, t: float) -> Vector3:
	var idx: int = _hips_pos_track.get(anim, -1)
	if idx < 0:
		return Vector3.ZERO
	return _anim_player.get_animation(anim).position_track_interpolate(idx, t)


func _hips_yaw(anim: String, t: float) -> float:
	var idx: int = _hips_rot_track.get(anim, -1)
	if idx < 0:
		return 0.0
	var q := _anim_player.get_animation(anim).rotation_track_interpolate(idx, t)
	var f := q * Vector3.BACK  # hips local +Z = character forward (Mixamo)
	return atan2(f.x, f.z)
