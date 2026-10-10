class_name RocketLauncher
extends Weapon
## Rocket Launcher: arm-mounted like the cannon / shotgun / machine gun
## (ARM_END, same sockets, either arm, one or two at once, each arm with its
## own target lock). One rocket (PlayerRocket) every `fire_interval` s.
##
## Firing: the rocket loaded in the bore (the model's own "Warhead" part)
## leaves from exactly where it sits; a big fire flash and jet out of the
## muzzle (RocketMuzzleFlash, solid fire that shows on bright backgrounds,
## over LauncherBlast - the boss launch's fire burst - sized by
## `blast_size`) with thick billowing grey smoke (LauncherBlast; two used in
## turn so a new shot never cuts the last one's smoke short), more smoke
## drifting out of the barrel for a
## while after, and a heavy recoil kick (`recoil_strength`). The next rocket
## slides back into the bore just before it's ready again. Each launch plays
## the owner's rocket launcher sound (Sfx.ROCKET_FIRING).

## Seconds between rockets.
@export var fire_interval := 2.5
## Muzzle flash / smoke size (LauncherBlast scale, ~ metres).
@export var blast_size := 0.6
## Muzzle smoke: puff size, speed and amount (x the boss launch's).
@export var smoke_scale := 1.5
@export var smoke_speed := 0.4
@export var smoke_amount := 1.5
## How long the barrel keeps smoking after a shot (s).
@export var barrel_smoke_time := 1.6
## The next rocket slides into the bore over this long before it's ready (s).
@export var reload_slide_time := 0.3
@export_group("Audio")
@export var fire_volume_db := 0.0
@export var fire_near := 5.0
@export var fire_far := 60.0
@export_group("")

## Where the warhead's base sits in the weapon (its rest place in the bore).
const WARHEAD_BASE := Vector3(0.386, -0.0188, 0.0)

var shots_fired := 0
## Launch sounds played (tests).
var fire_sounds := 0
var _voices: Array[DynamicSound] = []
var _voice := 0
var last_rocket: PlayerRocket
var _cool := 0.0
var _muzzle: Node3D
var _warhead: Node3D
var _warhead_rest := Transform3D.IDENTITY
var flash: RocketMuzzleFlash
var _blasts: Array[LauncherBlast] = []
var _blast_i := 0
var _barrel_smoke: CPUParticles3D
## Puffy cartoon smoke clouds blown out of the muzzle (ToonPuff), plus two
## fire puffs at the mouth.
var _puffs: Array[ToonPuff] = []
const SMOKE_PUFFS := 7
const FIRE_PUFFS := 2
var _smoke_t := 99.0


func _ready() -> void:
	_muzzle = find_marker(MUZZLE_MARKER)
	_warhead = find_child("Warhead", true, false) as Node3D
	if _warhead:
		_warhead_rest = _warhead.transform


func on_equipped(owner_player: Node) -> void:
	super.on_equipped(owner_player)
	if _blasts.is_empty():
		for k in 2:
			var b := LauncherBlast.new()
			b.smoke_scale = smoke_scale
			b.smoke_speed = smoke_speed
			# The thick smoke is the puffy 3D clouds below; the blast keeps
			# only a few wisps of its own.
			b.smoke_amount = 0.1
			# Clear at first so the fire flash shows, then thick grey smoke.
			b.smoke_ramp = Vfx.ramp([Color(0.9, 0.6, 0.35, 0.0), Color(0.55, 0.5, 0.46, 0.85), Color(0.4, 0.39, 0.38, 0.8), Color(0.38, 0.37, 0.36, 0.0)], [0.0, 0.07, 0.4, 1.0])
			add_child(b)
			_blasts.append(b)
		_barrel_smoke = _make_barrel_smoke()
		add_child(_barrel_smoke)
		flash = RocketMuzzleFlash.new()
		add_child(flash)
		# Two voices in turn (a launch sound outlasts the gap when dual
		# wielded - each arm has its own launcher anyway).
		_voices = Sfx.voices(self, Sfx.ROCKET_FIRING, 2, fire_volume_db, fire_near, fire_far)
		for k in SMOKE_PUFFS + FIRE_PUFFS:
			var pf := ToonPuff.new()
			pf.set_colors(Color(0.6, 0.58, 0.56))
			add_child(pf)
			_puffs.append(pf)


func _process(delta: float) -> void:
	_cool = maxf(_cool - delta, 0.0)
	# Reload: the next rocket slides forward into place.
	if _warhead:
		if _cool <= 0.0:
			_warhead.visible = true
			_warhead.transform = _warhead_rest
		elif _cool <= reload_slide_time:
			_warhead.visible = true
			var k := 1.0 - _cool / reload_slide_time
			# Model space: the tube goes deeper towards +X (the tip is at -X).
			_warhead.transform = _warhead_rest.translated_local(Vector3(0.3 * (1.0 - k * k * (3.0 - 2.0 * k)), 0, 0))
		else:
			_warhead.visible = false
	if _barrel_smoke:
		_smoke_t += delta
		_barrel_smoke.emitting = _smoke_t < barrel_smoke_time
		if _muzzle:
			_barrel_smoke.global_transform = Transform3D(_mouth_basis(), _muzzle.global_position)


func can_fire() -> bool:
	return is_equipped and _cool <= 0.0


func muzzle_position() -> Vector3:
	return _muzzle.global_position if _muzzle else global_position


## Seconds until the next rocket can fire (0 = loaded).
func reload_left() -> float:
	return _cool


func fire_at(shooter: Node3D, _target_point: Vector3) -> bool:
	if not can_fire():
		return false
	_cool = fire_interval
	var mouth := _mouth_basis()
	var start := Transform3D(mouth, global_transform * WARHEAD_BASE)
	last_rocket = PlayerRocket.launch(get_tree().current_scene if get_tree().current_scene else get_tree().root,
		start, _locked_target(shooter), shooter, arm_side)
	if _warhead:
		_warhead.visible = false
	if not _blasts.is_empty():
		_blasts[_blast_i].fire(Transform3D(mouth, muzzle_position()), blast_size)
		_blast_i = (_blast_i + 1) % _blasts.size()
	if flash:
		flash.fire(Transform3D(mouth, muzzle_position()))
	_puff_out(mouth.z, muzzle_position())
	_voice = Sfx.play_next(_voices, _voice, Vector2(0.96, 1.04))
	fire_sounds += 1
	if _barrel_smoke:
		_barrel_smoke.restart()
		_smoke_t = 0.0
	shots_fired += 1
	recoiled.emit(recoil_strength)
	return true


## Thick puffy smoke blown out of the muzzle along `dir`, spreading and
## rolling upwards; two short fire puffs right at the mouth.
func _puff_out(dir: Vector3, at: Vector3) -> void:
	if _puffs.is_empty():
		return
	var side := dir.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	var up := side.cross(dir).normalized()
	for i in _puffs.size():
		var p := _puffs[i]
		if i < FIRE_PUFFS:
			p.size = randf_range(0.32, 0.42) * smoke_scale * 0.8
			p.burn_time = 0.16
			p.life = 0.55
			p.rise = 0.1
			p.drift = dir * 0.5
			p.delay = 0.0
			p.play(at + dir * (0.1 + 0.15 * i), true)
			continue
		var k := float(i - FIRE_PUFFS) / maxf(SMOKE_PUFFS - 1, 1)
		var spread := (side * randf_range(-1, 1) + up * randf_range(-0.6, 1)) * (0.15 + 0.35 * k)
		p.size = lerpf(0.28, 0.55, k) * randf_range(0.85, 1.15) * smoke_scale * 0.5
		p.burn_time = 0.0
		p.life = randf_range(1.1, 1.6)
		p.rise = randf_range(0.4, 0.8)
		p.drift = dir * (0.5 + 1.3 * k) * smoke_speed * 2.0 + spread * 1.5
		p.delay = 0.02 + 0.05 * k
		p.play(at + dir * (0.15 + 0.5 * k) + spread * 0.3, false)


## +Z out of the barrel.
func _mouth_basis() -> Basis:
	var fwd := get_barrel_direction()
	var up := global_basis.y.normalized()
	if absf(fwd.dot(up)) > 0.98:
		up = Vector3.UP
	return Basis.looking_at(-fwd, up)


## The target this arm is locked on (the rocket steers towards it).
func _locked_target(shooter: Node) -> Targetable:
	var holder := shooter.get_node_or_null("WeaponHolder") as WeaponHolder if shooter else null
	if holder == null or arm_side == &"":
		return null
	var s := holder.slot(String(arm_side))
	return s.lock.current if s and s.lock else null


## Smoke drifting out of the barrel for a while after each shot.
func _make_barrel_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.22
	q.material = Vfx.mix_material("smoke")
	p.mesh = q
	p.amount = 24
	p.lifetime = 1.8
	p.local_coords = false
	p.top_level = true
	p.direction = Vector3(0, 0, 1)
	p.spread = 25.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0, 0.9, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.angle_max = 180.0
	p.angular_velocity_min = -25.0
	p.angular_velocity_max = 25.0
	p.scale_amount_curve = Vfx.curve([Vector2(0, 0.5), Vector2(1, 3.0)])
	p.color_ramp = Vfx.ramp([Color(0.5, 0.48, 0.46, 0.0), Color(0.48, 0.46, 0.44, 0.6), Color(0.55, 0.54, 0.53, 0.0)], [0.0, 0.15, 1.0])
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.emitting = false
	return p
