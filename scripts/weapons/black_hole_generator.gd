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
## Charge-up before launch: the core swells and the chamber crackles.
@export var charge_time := 0.18
## Mechanical parts animated on recoil (existing separate meshes in the GLB).
@export var bore_kick := 0.14        # muzzle bore slams back (m)
@export var interior_spin_deg := 120.0

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
var _charge := -1.0       # >=0 while charging a shot (seconds elapsed)
var _charge_target := Vector3.ZERO
var _charge_shooter: Node3D
var _mech_t := 99.0
var _bore: Node3D
var _bore_rest := Transform3D.IDENTITY
var _interior: Node3D
var _interior_rest := Transform3D.IDENTITY
var _spin_from := 0.0


func _ready() -> void:
	_spawn_core()
	_grow = 1.0
	_apply_core_scale()
	_bore = find_child("Front_Muzzle_Deep_Bore", true, false) as Node3D
	if _bore:
		_bore_rest = _bore.transform
	_interior = find_child("Finished_Containment_Interior", true, false) as Node3D
	if _interior:
		_interior_rest = _interior.transform


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
		var charge := _charge_amount()
		# Charging: swell and shudder.
		var pulse := 1.0 + charge * (0.28 + 0.08 * sin(_t * 70.0))
		core.scale = Vector3.ONE * maxf(core_size * g * pulse, 0.001)


func _charge_amount() -> float:
	return clampf(_charge / charge_time, 0.0, 1.0) if _charge >= 0.0 else 0.0


func _process(delta: float) -> void:
	_t += delta
	if _tumble:
		_tumble.rotation += tumble_speed * delta * (1.0 + _charge_amount() * 6.0)
	if _charge >= 0.0:
		_charge += delta
		_apply_core_scale()
		if _charge >= charge_time:
			_launch()
	_animate_mechanics(delta)
	if core == null and _recharge > 0.0:
		_recharge -= delta
		if _recharge <= 0.0:
			_spawn_core()
	if core and _grow < 1.0:
		_grow = minf(_grow + delta / recharge_grow, 1.0)
		_apply_core_scale()
	var charge := _charge_amount()
	if _arcs:
		_arcs.intensity = _grow if core else 0.0
		_arcs.frenzy = charge
	if _lens:
		# Grows with the core; gone while the chamber is empty; surges on charge.
		var k := ease(clampf(_grow, 0.0, 1.0), 0.4) if core else 0.0
		_lens.visible = k > 0.01
		_lens.scale = Vector3.ONE * maxf(chamber_lens_size * k * (1.0 + charge * 0.4), 0.001)
		(_lens.material_override as ShaderMaterial).set_shader_parameter("strength", chamber_lens_strength * (1.0 + charge * 1.5))


func can_fire() -> bool:
	return core != null and _grow >= 1.0 and _charge < 0.0 and projectile_scene != null


## Start a shot: charge briefly, then launch at the (latest) target point.
func fire_at(shooter: Node3D, target_point: Vector3) -> bool:
	if not can_fire():
		return false
	_charge = 0.0
	_charge_target = target_point
	_charge_shooter = shooter
	return true


## Keep the charging shot aimed at a moving target.
func update_aim(target_point: Vector3) -> void:
	if _charge >= 0.0:
		_charge_target = target_point


func _launch() -> void:
	_charge = -1.0
	if core == null:
		return
	var shooter := _charge_shooter
	var target_point := _charge_target
	_apply_core_scale()
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
	_mech_t = 0.0
	fired.emit(projectile)
	recoiled.emit(recoil_strength)


## Muzzle bore slams back and rebounds; containment interior spins a notch.
func _animate_mechanics(delta: float) -> void:
	_mech_t += delta
	if _bore:
		var k := 0.0
		if _mech_t < 0.035:
			k = _mech_t / 0.035
		elif _mech_t < 0.6:
			var t := _mech_t - 0.035
			k = exp(-t * 9.0) * cos(t * 26.0)
		_bore.transform = _bore_rest.translated_local(Vector3(-bore_kick * k, 0, 0))
	if _interior and _mech_t < 0.6:
		var k := ease(clampf(_mech_t / 0.5, 0.0, 1.0), 0.3)
		var angle := _spin_from + deg_to_rad(interior_spin_deg) * k
		_interior.transform = _interior_rest * Transform3D(Basis(Vector3.RIGHT, angle), Vector3.ZERO)
		if k >= 1.0:
			_spin_from = fmod(angle, TAU)


## Release the core (keeps its world pose; caller re-parents it).
func detach_core() -> BlackHoleCore:
	var c := core
	if c:
		var xf := c.global_transform
		c.get_parent().remove_child(c)
		c.transform = xf
	core = null
	return c
