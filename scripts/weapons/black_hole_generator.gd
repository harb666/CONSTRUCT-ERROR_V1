class_name BlackHoleGenerator
extends Weapon
## Black Hole Generator: spawns a BlackHoleCore inside the containment chamber
## (at the model's Black_Hole_Projectile_Spawn marker). Firing releases that
## core as a BlackHoleProjectile; a new core then forms in the chamber.

signal fired(projectile: BlackHoleProjectile)

const CHAMBER_MARKER := "Black_Hole_Projectile_Spawn"

@export var core_scene: PackedScene
@export var projectile_scene: PackedScene
## Size of the core inside the chamber (m across).
@export var core_size := 0.28
## Orientation of the core in the chamber (degrees).
@export var core_rotation_degrees := Vector3(90, 0, 0)  # disk faces the side windows
## Slow tumble of the contained core (rad/s around chamber X, Y, Z) so the
## accretion disk is seen from changing angles. Applied to a pivot, not to
## the core's own animation.
@export var tumble_speed := Vector3(0.55, 0.37, 0.23)
## Seconds after firing before a new core starts forming.
@export var recharge_delay := 0.6
## Seconds for the new core to grow to full size.
@export var recharge_grow := 0.4

var core: BlackHoleCore
var _tumble: Node3D
var _arcs: ChamberArcs
var _lens: MeshInstance3D
## Subtle gravity distortion around the contained core: disc diameter (m)
## and strength, kept small so only the chamber area bends, not the gun.
@export var chamber_lens_size := 0.38
@export var chamber_lens_strength := 0.22
var _t := 0.0
var _recharge := 0.0      # >0 while waiting for a new core
var _grow := 1.0          # 0..1 growth of the current core


func _ready() -> void:
	_spawn_core()
	_grow = 1.0
	_apply_core_scale()


func _spawn_core() -> void:
	var chamber := find_marker(CHAMBER_MARKER)
	if chamber == null or core_scene == null:
		return
	if _tumble == null:
		_tumble = Node3D.new()
		_tumble.name = "CoreTumble"
		chamber.add_child(_tumble)
		_arcs = ChamberArcs.new()
		_arcs.name = "ChamberArcs"
		chamber.add_child(_arcs)
		if Vfx.distortion_enabled:
			_lens = MeshInstance3D.new()
			_lens.name = "ChamberLens"
			_lens.mesh = QuadMesh.new()
			var m := ShaderMaterial.new()
			m.shader = BlackHoleFlightVfx.DISTORTION
			m.render_priority = -1
			m.set_shader_parameter("strength", chamber_lens_strength)
			m.set_shader_parameter("swirl", 1.2)
			m.set_shader_parameter("spin_speed", 0.9)
			m.set_shader_parameter("tint_amount", 0.06)
			_lens.material_override = m
			_lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			chamber.add_child(_lens)
	core = core_scene.instantiate()
	core.name = "BlackHoleCore"
	core.rotation_degrees = core_rotation_degrees
	_tumble.add_child(core)
	_grow = 0.0
	_apply_core_scale()


func _apply_core_scale() -> void:
	if core:
		var g := ease(clampf(_grow, 0.0, 1.0), 0.4)
		core.scale = Vector3.ONE * maxf(core_size * g, 0.001)


func _process(delta: float) -> void:
	_t += delta
	if _tumble:
		_tumble.rotation = tumble_speed * _t
	if core == null and _recharge > 0.0:
		_recharge -= delta
		if _recharge <= 0.0:
			_spawn_core()
	if core and _grow < 1.0:
		_grow = minf(_grow + delta / recharge_grow, 1.0)
		_apply_core_scale()
	if _arcs:
		_arcs.intensity = _grow if core else 0.0
	if _lens:
		# Grows with the core; gone while the chamber is empty.
		var k := ease(clampf(_grow, 0.0, 1.0), 0.4) if core else 0.0
		_lens.visible = k > 0.01
		_lens.scale = Vector3.ONE * maxf(chamber_lens_size * k, 0.001)


func can_fire() -> bool:
	return core != null and _grow >= 1.0 and projectile_scene != null


func fire_at(shooter: Node3D, target_point: Vector3) -> bool:
	if not can_fire():
		return false
	var start := core.global_position
	var dir := (target_point - start).normalized()
	var barrel := get_barrel_direction()
	# Never shoot backwards/sideways out of the gun.
	if dir.dot(barrel) < 0.3:
		dir = barrel
	var world: Node = get_tree().current_scene
	if world == null:
		world = get_tree().root
	var projectile: BlackHoleProjectile = projectile_scene.instantiate()
	world.add_child(projectile)
	projectile.global_position = start
	var c := detach_core()
	var muzzle := find_marker(MUZZLE_MARKER)
	if muzzle:
		MuzzleFlash.spawn(muzzle)
	projectile.launch(c, dir, shooter)
	_recharge = recharge_delay
	fired.emit(projectile)
	return true


## Release the core (keeps its world pose; caller re-parents it).
func detach_core() -> BlackHoleCore:
	var c := core
	if c:
		var xf := c.global_transform
		c.get_parent().remove_child(c)
		c.transform = xf
	core = null
	return c
