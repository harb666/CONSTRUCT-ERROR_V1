class_name BlackHoleGenerator
extends Weapon
## Black Hole Generator: spawns a BlackHoleCore inside the containment chamber
## (at the model's Black_Hole_Projectile_Spawn marker). The core stays its own
## node so firing can later detach it and send it out of Muzzle_Exit.

const CHAMBER_MARKER := "Black_Hole_Projectile_Spawn"

@export var core_scene: PackedScene
## Size of the core inside the chamber (m across).
@export var core_size := 0.28
## Orientation of the core in the chamber (degrees).
@export var core_rotation_degrees := Vector3(90, 0, 0)  # disk faces the side windows
## Slow tumble of the contained core (rad/s around chamber X, Y, Z) so the
## accretion disk is seen from changing angles. Applied to a pivot, not to
## the core's own animation.
@export var tumble_speed := Vector3(0.55, 0.37, 0.23)

var core: BlackHoleCore
var _tumble: Node3D
var _t := 0.0


func _ready() -> void:
	var chamber := find_marker(CHAMBER_MARKER)
	if chamber and core_scene:
		core = core_scene.instantiate()
		core.name = "BlackHoleCore"
		core.scale = Vector3.ONE * core_size
		core.rotation_degrees = core_rotation_degrees
		_tumble = Node3D.new()
		_tumble.name = "CoreTumble"
		chamber.add_child(_tumble)
		_tumble.add_child(core)


func _process(delta: float) -> void:
	if _tumble == null or core == null:
		return
	_t += delta
	_tumble.rotation = tumble_speed * _t


## For later: release the core (e.g. to fire it). Caller re-parents it.
func detach_core() -> BlackHoleCore:
	var c := core
	if c:
		var xf := c.global_transform
		c.get_parent().remove_child(c)
		c.transform = xf
	core = null
	return c
