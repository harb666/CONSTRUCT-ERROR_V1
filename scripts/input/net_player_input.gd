class_name NetPlayerInput
extends PlayerInput
## A teammate's input in online co-op: their device sends what they're
## doing (stick, camera yaw, buttons pressed, the targets each arm has
## locked) a few times a second; their character on this device plays it
## through the same movement / weapons code, so it moves, aims and fires
## like they do. Presses (jump, dodge, melee) are kept until used, so one
## is never lost between packets. Their device also sends where they really
## are: small differences are smoothed out, a big one (a teleport, lag) is
## snapped. Targets travel as paths in the level (each device numbers its
## targets differently).

## Further off than this from where they really are: snap there.
@export var snap_distance := 3.0
## How quickly a small difference is closed (per second).
@export var correction_rate := 8.0

var _cmd := PlayerCommand.new()
var _jump := false
var _dodge := false
var _melee := false
var _pos := Vector3.INF
var _vel := Vector3.ZERO
var _age := 0.0
var packets := 0
var snaps := 0


## One packet from their device. `scene` resolves target paths.
func push(d: Dictionary, scene: Node) -> void:
	packets += 1
	_cmd = PlayerCommand.from_dict(d)
	_cmd.target_id = _target_id(String(d.get("tp", "")), scene)
	_cmd.target_id_left = _target_id(String(d.get("tlp", "")), scene)
	_jump = _jump or bool(d.get("jp", false))
	_dodge = _dodge or bool(d.get("dp", false))
	_melee = _melee or bool(d.get("mp", false))
	_pos = d.get("pos", Vector3.INF)
	_vel = d.get("vel", Vector3.ZERO)
	_age = 0.0


func get_command() -> PlayerCommand:
	var c := PlayerCommand.new()
	c.move = _cmd.move
	c.view_yaw = _cmd.view_yaw
	c.jump_held = _cmd.jump_held
	c.sprint_held = _cmd.sprint_held
	c.target_id = _cmd.target_id
	c.target_id_left = _cmd.target_id_left
	c.jump_pressed = _jump
	c.dodge_pressed = _dodge
	c.melee_pressed = _melee
	_jump = false
	_dodge = false
	_melee = false
	return c


func _physics_process(delta: float) -> void:
	var pc := get_parent() as PlayerController
	if pc == null or _pos == Vector3.INF:
		return
	_age += delta
	# Where they should be now (the last report, moved on by their speed).
	var want := _pos + _vel * minf(_age, 0.25)
	var err := want - pc.global_position
	if err.length() > snap_distance:
		pc.global_position = want
		pc.velocity = _vel
		pc.reset_physics_interpolation()
		snaps += 1
	else:
		pc.global_position += err * clampf(correction_rate * delta, 0.0, 1.0)


## Path of the node a Targetable belongs to, relative to the level (for
## sending).
static func target_path(id: int, scene: Node) -> String:
	if id == 0 or scene == null:
		return ""
	var t := Targetable.find_by_id(id)
	if t == null or not t.is_inside_tree():
		return ""
	return String(scene.get_path_to(t.get_parent()))


static func _target_id(path: String, scene: Node) -> int:
	if path == "" or scene == null:
		return 0
	var n := scene.get_node_or_null(path)
	if n == null:
		return 0
	for c in n.get_children():
		if c is Targetable:
			return (c as Targetable).target_id
	return 0
