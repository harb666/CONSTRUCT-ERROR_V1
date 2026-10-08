extends Node3D
## Fills the test arena with a mixed robot army: `bosses` robot bosses,
## then grunts (RobotEnemy) and skirmishers alternating up to `total`.
## Spots are spread over the arena floor, clear of the arena's blocks and
## ramps and at least `min_spawn_distance` from the player spawn, so the
## fight starts at range rather than on top of the player.

const GRUNT := preload("res://scenes/enemies/robot_enemy.tscn")
const SKIRMISHER := preload("res://scenes/enemies/robot_skirmisher.tscn")
const BOSS := preload("res://scenes/enemies/robot_boss.tscn")

@export var total := 30
@export var bosses := 2
@export var min_spawn_distance := 16.0
## Kept clear round each block / ramp footprint (m).
@export var clearance := 2.5
@export var player_spawn := Vector3(0, 0, 4)

## Boss corners (big, kept well apart) and their sizes.
var _boss_spots := [[Vector3(-26, 0, -28), 4.0], [Vector3(27, 0, -27), 3.2]]


func _ready() -> void:
	var level := get_parent().get_node_or_null("TestArena")
	var spots := _free_spots(level)
	var n := 0
	for i in mini(bosses, _boss_spots.size()):
		var b: Node3D = BOSS.instantiate()
		b.name = "RobotBoss%d" % (i + 1)
		b.set("model_scale", _boss_spots[i][1])
		b.position = _boss_spots[i][0]
		add_child(b)
		n += 1
	var k := 0
	while n < total and k < spots.size():
		var at: Vector3 = spots[k]
		k += 1
		var r: RobotEnemy
		if n % 2 == 0:
			r = GRUNT.instantiate()
			r.name = "Grunt%d" % n
			r.patrol_distance = 3.0
			r.patrol_axis = Vector3.RIGHT if k % 2 == 0 else Vector3.BACK
		else:
			r = SKIRMISHER.instantiate()
			r.name = "Skirmisher%d" % n
		r.position = at
		r.rotation.y = randf() * TAU
		add_child(r)
		n += 1


## Grid of floor spots clear of the arena's geometry, shuffled with a fixed
## seed (same layout every run) and spread out.
func _free_spots(level: Node) -> Array[Vector3]:
	var blocks: Array = level.get("_blocks") if level else []
	var ramps: Array = level.get("_ramps") if level else []
	var half: float = (level.get("arena_size") if level else 80.0) * 0.5 - 4.0
	var out: Array[Vector3] = []
	var x := -half
	while x <= half:
		var z := -half
		while z <= half:
			var p := Vector3(x, 0, z)
			if p.distance_to(player_spawn) >= min_spawn_distance and _clear(p, blocks, ramps) and _boss_clear(p):
				out.append(p)
			z += 6.0
		x += 6.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 30
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := out[i]
		out[i] = out[j]
		out[j] = t
	return out


func _clear(p: Vector3, blocks: Array, ramps: Array) -> bool:
	for b in blocks + ramps:
		var c: Vector3 = b[0]
		var s: Vector3 = b[1]
		if absf(p.x - c.x) < s.x * 0.5 + clearance and absf(p.z - c.z) < s.z * 0.5 + clearance:
			return false
	return true


func _boss_clear(p: Vector3) -> bool:
	for b in _boss_spots:
		if p.distance_to(b[0]) < 9.0:
			return false
	return true
