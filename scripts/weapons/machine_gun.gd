class_name MachineGun
extends Weapon
## Arm-mounted plasma machine gun. Fires fast yellow plasma rounds (pooled
## PlasmaBolt) from its Muzzle_Exit along the barrel, with a rapid per-shot
## muzzle flash (MachineGunFlash) and yellow electric impacts (pooled
## PlasmaFx). Self-contained like every weapon: any WeaponSlot can hold it,
## and each copy keeps its own state (two guns can be at different rates and
## heat).
##
## Spin-up: while the trigger is held (the slot has a target) the fire rate
## climbs from `base_fire_rate` to `max_fire_rate` over `spin_up_time`, and
## winds back down after release.
## Heat: every round adds `heat_per_shot`; it cools at `cooling_rate` once the
## gun stops firing. At `max_heat` the gun overheats: it stops firing, vents,
## and fires again once `overheat_lockout` has passed and the heat is back
## under `resume_heat`.
## Every effect (barrel glow, orb, conduits, arcs, steam) reads one value,
## `energy` (0..1), built from spin and heat; see MachineGunEnergy.

@export_group("Fire rate")
## Rounds per second at the first shot / at full spin.
@export var base_fire_rate := 9.0
@export var max_fire_rate := 24.0
## Seconds of continuous fire to reach the maximum rate.
@export var spin_up_time := 2.4
## Seconds to wind down fully once the trigger is released.
@export var spin_down_time := 0.9
## Shape of the climb (1 = linear, > 1 = slow start, fast finish).
@export var spin_curve := 1.25

@export_group("Rounds")
@export var bolt_speed := 64.0
@export var damage := 0.22
@export var max_range := 44.0
## Random spread (degrees) at the base rate / at full spin.
@export var spread_deg := 0.5
@export var max_spread_deg := 1.4
## Within this angle of the target the round goes straight at it; otherwise
## it flies exactly where the barrel points.
@export var aim_snap_deg := 3.0
## Barrel aim correction: how fast the arm's aim is steered (1/s) so the
## barrel line itself meets the target, and the largest correction (deg).
@export var aim_correction_rate := 7.0
@export var aim_correction_max_deg := 14.0
@export var bolt_size := 0.55
@export var bolt_color := Color(1.0, 0.82, 0.06)
@export var bolt_hot_color := Color(1.0, 0.97, 0.62)
@export var trail_color := Color(1.0, 0.55, 0.05)
## How long the glowing impact mark lasts (s).
@export var impact_mark_life := 0.45
## Size of the yellow impact splash (1 = standard plasma impact).
@export var impact_scale := 0.6
## Bodies in this group are flown through (no friendly fire).
@export var pass_group := &"players"

@export_group("Heat")
@export var max_heat := 100.0
@export var heat_per_shot := 0.9
## Heat lost per second once the gun has stopped firing for `cool_delay` s.
@export var cooling_rate := 32.0
@export var cool_delay := 0.25
## Overheat: minimum time locked out, cooling rate while locked out, and the
## heat fraction it must be back under before it fires again.
@export var overheat_lockout := 1.6
@export var overheat_cooling_rate := 42.0
@export_range(0.0, 1.0) var resume_heat := 0.3

@export_group("Recoil")
## Arm kick per round (recoil_strength, on Weapon) grows by this much at full
## spin: rapid fire builds into a sustained push on the arm and chest.
@export var recoil_spin_boost := 0.6
## Mechanical shake of the gun itself (m / deg per round, decays fast).
@export var vibration := 1.0
@export var vibration_offset := 0.006
@export var vibration_angle_deg := 0.7

@export_group("Effects")
@export var muzzle_flash_intensity := 1.7

@export_group("Audio")
## The firing sound is a short burst; while the trigger is held it is
## restarted every `fire_sound_interval` s (overlapping, so it never cuts
## off), a little faster and higher as the barrel spins up. Letting go
## leaves the last one's tail ringing out.
@export var fire_volume_db := -2.0
@export var fire_sound_interval := 0.34
@export var fire_near := 6.0
@export var fire_far := 60.0
## Spin-down / venting after at least `cooldown_after` s of fire (louder
## the hotter the gun), and always on overheating.
@export var cooldown_volume_db := -4.0
@export var cooldown_after := 0.45
@export_group("")
## Glow of the hot front/barrel.
@export var barrel_glow_intensity := 1.0
## Electrical arcs around the barrel and in the orb.
@export var electric_intensity := 1.0
@export var steam_amount := 1.0
@export var orb_energy_intensity := 1.0
@export var conduit_energy_intensity := 1.0

## Shots fired by this gun (all time).
var shots_fired := 0
## 0..1: how far the fire rate has climbed.
var spin := 0.0
var heat := 0.0
var overheated := false
## Shared intensity of every effect (0..1).
var energy := 0.0
## Trigger held (a target is locked) this tick.
var trigger := false
## Times this gun has overheated.
var overheat_count := 0
## Last round: where it left and which way (for checks / debugging).
var last_from := Vector3.ZERO
var last_dir := Vector3.ZERO

var _cool := 0.0
var _since_shot := 99.0
var _trigger_t := 99.0
var _lock_t := 0.0
var _muzzle: Node3D
var _body: Node3D
var _kick := Vector3.ZERO
var _kick_v := Vector3.ZERO
var _aim_fix := Vector3.ZERO
var _flash: MachineGunFlash
var _fire_snd: DynamicSound
var _fire_voices: Array[DynamicSound] = []
var _voice := 0
var _cool_snd: DynamicSound
var _snd_t := 0.0
## Seconds of continuous fire (for the cooldown sound).
var _firing_for := 0.0
## Times the firing / cooldown sounds started (tests).
var fire_sounds := 0
var cooldown_sounds := 0
var _fx: MachineGunEnergy

signal overheat_started
signal overheat_ended


func _ready() -> void:
	_muzzle = find_marker(MUZZLE_MARKER)
	# Body: the model and its effects, so the gun can shake as one piece
	# (markers stay on the root; the slot places the root).
	var model := get_node_or_null("Model") as Node3D
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	move_child(_body, 0)
	var ms := 1.0
	if model:
		remove_child(model)
		_body.add_child(model)
		ms = model.scale.x
	_fx = MachineGunEnergy.new()
	_fx.name = "Energy"
	_fx.gun = self
	_fx.model = model
	_fx.model_scale = ms
	_body.add_child(_fx)
	_flash = MachineGunFlash.new()
	_flash.name = "MuzzleFlash"
	_flash.position = _muzzle.position if _muzzle else Vector3(0.44, 0, 0)
	_flash.length = 0.42
	_flash.flash_life = 0.045
	_flash.light_energy = 3.4
	_flash.light_range = 4.0
	_body.add_child(_flash)
	# Overlapping bursts: a few plain players used in turn (one voice each;
	# the browser's audio plays these reliably, unlike one restarted voice).
	for i in 3:
		var e := Sfx.emitter(self, Sfx.MG_FIRE, fire_volume_db, fire_near, fire_far)
		e.name = "FireSound%d" % i
		e.position = _flash.position
		_fire_voices.append(e)
	_fire_snd = _fire_voices[0]
	_cool_snd = Sfx.emitter(self, Sfx.MG_COOLDOWN, cooldown_volume_db, fire_near, fire_far * 0.75)
	_cool_snd.name = "CooldownSound"


## Rounds per second right now.
func fire_rate() -> float:
	return lerpf(base_fire_rate, max_fire_rate, pow(spin, spin_curve))


func heat_ratio() -> float:
	return clampf(heat / maxf(max_heat, 0.001), 0.0, 1.0)


## Called by the slot every tick it has a target: the trigger is held.
func update_aim(_point: Vector3) -> void:
	_trigger_t = 0.0


## World offset for the arm's aim point that brings the barrel line onto
## `point` (integrates the miss where the barrel line passes the target, so
## it also holds down the sustained recoil climb).
func aim_correction(point: Vector3) -> Vector3:
	var from := muzzle_position()
	var d := from.distance_to(point)
	if d < 0.5:
		return _aim_fix
	var miss := point - (from + get_barrel_direction() * d)
	_aim_fix += miss * aim_correction_rate * get_physics_process_delta_time()
	_aim_fix = _aim_fix.limit_length(d * tan(deg_to_rad(aim_correction_max_deg)))
	return _aim_fix


func can_fire() -> bool:
	return not overheated and _cool <= 0.0


func muzzle_position() -> Vector3:
	return _muzzle.global_position if _muzzle else global_position


func _physics_process(delta: float) -> void:
	_trigger_t += delta
	_since_shot += delta
	var was := trigger
	trigger = _trigger_t <= delta * 1.5
	_snd_t -= delta
	if trigger and not overheated:
		_firing_for += delta
	elif was and not overheated:
		# Let go after a proper burst: the barrel spins down and vents.
		if _firing_for >= cooldown_after:
			_play_cooldown(clampf(0.35 + heat_ratio(), 0.35, 1.0))
		_firing_for = 0.0
		_snd_t = 0.0
	if not trigger:
		_aim_fix = Vector3.ZERO
	if trigger and not overheated:
		spin = minf(spin + delta / maxf(spin_up_time, 0.01), 1.0)
	else:
		spin = maxf(spin - delta / maxf(spin_down_time, 0.01), 0.0)
	if _cool > 0.0:
		_cool -= delta
	elif not trigger:
		_cool = 0.0  # no banking shots while the trigger is up
	if overheated:
		_lock_t -= delta
		heat = maxf(heat - overheat_cooling_rate * delta, 0.0)
		if _lock_t <= 0.0 and heat_ratio() <= resume_heat:
			overheated = false
			_cool = 0.0
			overheat_ended.emit()
	elif _since_shot > cool_delay:
		heat = maxf(heat - cooling_rate * delta, 0.0)


func fire_at(shooter: Node3D, target_point: Vector3) -> bool:
	_trigger_t = 0.0
	if not can_fire():
		return false
	# Several rounds can be due in one tick at high rates: each leaves at its
	# own moment (`late` seconds ago), already that far down the line.
	var interval := 1.0 / maxf(fire_rate(), 0.01)
	_cool = maxf(_cool, -interval)
	var n := 0
	while _cool <= 0.0 and n < 4 and not overheated:
		_shoot(shooter, target_point, -_cool)
		_cool += 1.0 / maxf(fire_rate(), 0.01)
		n += 1
	return n > 0


## Direction a round leaves in: straight at the target when the barrel is on
## it (within `aim_snap_deg`), otherwise exactly along the barrel.
func shot_direction(from: Vector3, target_point: Vector3) -> Vector3:
	var barrel := get_barrel_direction()
	var to := target_point - from
	if to.length_squared() < 1e-4:
		return barrel
	to = to.normalized()
	return to if barrel.angle_to(to) <= deg_to_rad(aim_snap_deg) else barrel


func _shoot(shooter: Node3D, target_point: Vector3, late: float) -> void:
	var from := muzzle_position()
	var dir := shot_direction(from, target_point)
	var spread := deg_to_rad(lerpf(spread_deg, max_spread_deg, spin))
	if spread > 0.0:
		var side := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
		dir = dir.rotated(side.rotated(dir, randf() * TAU), spread * sqrt(randf()))
	last_from = from
	last_dir = dir
	var b := PlasmaBolt.fire(get_tree(), from + dir * bolt_speed * minf(late, 0.05), dir, shooter, bolt_speed, damage,
		bolt_color, bolt_hot_color, pass_group)
	if b:
		b.weapon_tag = &"machine_gun"
		b.mark_life = impact_mark_life
		b.crackle = true
		b.size = bolt_size
		b.flicker = 0.35
		b.max_range = max_range
		b.impact_light = shots_fired % 2 == 0
		b.impact_scale = impact_scale
		b.set_trail_color(trail_color)
	shots_fired += 1
	_since_shot = 0.0
	heat += heat_per_shot
	if _flash:
		_flash.fire(energy, muzzle_flash_intensity)
	if not _fire_voices.is_empty() and _snd_t <= 0.0 and _fire_voices[0].is_inside_tree():
		_voice = (_voice + 1) % _fire_voices.size()
		_fire_snd = _fire_voices[_voice]
		_fire_snd.pitch_scale = (1.0 + 0.12 * spin) * randf_range(0.98, 1.02)
		_fire_snd.play()
		fire_sounds += 1
		_snd_t = fire_sound_interval / (1.0 + 0.35 * spin)
	# Rapid fire: small kicks that add up (arm/chest via the slot's spring),
	# plus the gun's own mechanical shake.
	recoiled.emit(recoil_strength * (1.0 + recoil_spin_boost * spin))
	var k := vibration * (0.7 + 0.6 * spin)
	_kick_v += Vector3(-randf_range(0.6, 1.0), randf_range(-0.4, 0.6), randf_range(-0.4, 0.4)) * k * 50.0
	if heat >= max_heat:
		_overheat()


func _overheat() -> void:
	heat = max_heat
	overheated = true
	overheat_count += 1
	_lock_t = overheat_lockout
	_cool = 0.0
	spin = minf(spin, 0.35)
	if _fx:
		_fx.vent()
	_play_cooldown(1.0)
	_firing_for = 0.0
	overheat_started.emit()


func _play_cooldown(loudness: float) -> void:
	if _cool_snd == null or not _cool_snd.is_inside_tree():
		return
	_cool_snd.fade = loudness
	_cool_snd.play()
	cooldown_sounds += 1


func _process(delta: float) -> void:
	# The one shared intensity: spin drives it up to 0.7, heat takes it to 1.
	var want := clampf(maxf(spin * 0.7, heat_ratio()), 0.0, 1.0)
	energy = move_toward(energy, want, delta * (4.0 if want > energy else 1.5))
	# Mechanical shake: a stiff, fast spring (~8 Hz, decays in ~0.1 s).
	if _body:
		var steps := 3
		var h := minf(delta, 1.0 / 30.0) / steps
		for i in steps:
			_kick_v += (-2500.0 * _kick - 50.0 * _kick_v) * h
			_kick += _kick_v * h
		_body.position = Vector3(_kick.x, _kick.y * 0.4, _kick.z * 0.4) * vibration_offset
		_body.rotation = Vector3(_kick.y * 0.5, _kick.z, _kick.y) * deg_to_rad(vibration_angle_deg)

