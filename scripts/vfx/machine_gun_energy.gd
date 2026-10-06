class_name MachineGunEnergy
extends Node3D
## Every "energy" effect of one machine gun, all driven by the gun's single
## shared `energy` value (0..1, spin + heat) plus its heat/overheat state:
##  - Energy orb: stays transparent; inside it a pulsing core, swirling
##    plasma and flickering electrical arcs, more and brighter with energy.
##  - Conduits (orb -> barrel): plasma flowing to the front (shader), calm at
##    idle, brighter/faster/turbulent while firing, unstable near overheating.
##  - Front/barrel heat glow (additive overlay: yellow -> orange -> red,
##    creeping back from the muzzle), brighter light panels.
##  - Electrical arcs and sparks round the barrel (BarrelStatic, yellow).
##  - Yellow-tinted steam as it gets hot; a strong vent burst on overheating.
## Lives under the gun's Body (unscaled); `model_scale` converts the model's
## own coordinates. Nothing is allocated after _ready().

## Model-space landmarks of machine_gun.glb.
const ORB_CENTER := Vector3(0.0896, -0.0472, 0.0016)
const ORB_RADIUS := 0.083
const MUZZLE := Vector3(0.93, -0.072, 0.0)
const BARREL_START_X := 0.5
const CONDUIT_X := Vector2(0.31, 0.77)

const YELLOW := Color(1.0, 0.82, 0.1)
const HOT := Color(1.0, 0.96, 0.7)
const ORANGE := Color(1.0, 0.5, 0.06)
const CONDUIT_SHADER := preload("res://scripts/vfx/plasma_conduit.gdshader")
const HEAT_SHADER := preload("res://scripts/vfx/barrel_heat_glow.gdshader")

var gun: MachineGun
var model: Node3D
var model_scale := 1.0

var _t := 0.0
var _phase := 0.0
var _overload := 0.0
var _vent := 0.0
var _body_mi: MeshInstance3D
var _body_mat: StandardMaterial3D
var _body_emission := 1.0
var _orb_mat: StandardMaterial3D
var _orb_emission := 1.0
var _conduit_mat: ShaderMaterial
var _heat_mat: ShaderMaterial
var _orb_core: MeshInstance3D
var _orb_flare: MeshInstance3D
var _orb_swirl: MeshInstance3D
var _orb_arcs: Array[MeshInstance3D] = []
var _arc_a: Array[Vector3] = []
var _arc_b: Array[Vector3] = []
var _arc_t: Array[float] = []
var _static: BarrelStatic
var _steam: CPUParticles3D
var _vent_steam: CPUParticles3D
var _vent_sparks: CPUParticles3D


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if model:
		_setup_materials()
	_setup_orb()
	_static = BarrelStatic.new()
	_static.name = "BarrelStatic"
	var ms := model_scale
	_static.barrel_start_x = BARREL_START_X * ms
	_static.muzzle_x = MUZZLE.x * ms
	_static.bore_radius = 0.05 * ms
	_static.bore_center = Vector2(MUZZLE.y, MUZZLE.z) * ms
	_static.chamber_end_x = 0.86 * ms
	_static.chamber_radius_scale = 1.7
	_static.inner_arc_count = 5
	_static.muzzle_arc_count = 4
	_static.arc_width = 0.03
	_static.arc_color_a = HOT
	_static.arc_color_b = YELLOW
	_static.glow_color = Color(1.0, 0.7, 0.1)
	_static.spark_color = Color(1.0, 0.85, 0.3)
	_static.glow_size = Vector2(0.05, 0.16)
	add_child(_static)
	_steam = _make_steam(0.09, 14, 0.9, false)
	_vent_steam = _make_steam(0.17, 22, 1.2, true)
	_vent_sparks = Vfx.particles("glow", 0.03, 24, 0.45)
	_vent_sparks.one_shot = true
	_vent_sparks.explosiveness = 0.9
	_vent_sparks.local_coords = false
	_vent_sparks.position = MUZZLE * ms
	_vent_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_vent_sparks.emission_box_extents = Vector3(0.12, 0.03, 0.03)
	_vent_sparks.direction = Vector3(0.3, 1, 0)
	_vent_sparks.spread = 75.0
	_vent_sparks.initial_velocity_min = 1.5
	_vent_sparks.initial_velocity_max = 4.5
	_vent_sparks.gravity = Vector3(0, -9, 0)
	_vent_sparks.color_ramp = Vfx.ramp([Color(1, 0.97, 0.7, 1), Color(1, 0.72, 0.1, 1), Color(1, 0.3, 0.02, 0)], [0.0, 0.4, 1.0])
	_vent_sparks.emitting = false
	add_child(_vent_sparks)


func _setup_materials() -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var src := mi.get_active_material(0) as StandardMaterial3D
		if src == null:
			continue
		if mi.name.begins_with("Weapon_Body"):
			_body_mi = mi
			_body_mat = src.duplicate() as StandardMaterial3D
			_body_emission = src.emission_energy_multiplier
			mi.material_override = _body_mat
			_heat_mat = ShaderMaterial.new()
			_heat_mat.shader = HEAT_SHADER
			_heat_mat.set_shader_parameter("emission_tex", src.emission_texture)
			_heat_mat.set_shader_parameter("front_x", MUZZLE.x + 0.04)
		elif mi.name.begins_with("Yellow_Energy_Orb"):
			# Stays see-through; plain alpha blending (no depth pre-pass) so
			# the energy inside shows through it.
			_orb_mat = src.duplicate() as StandardMaterial3D
			_orb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_orb_emission = src.emission_energy_multiplier
			mi.material_override = _orb_mat
		elif mi.name.begins_with("Yellow_Forward_Energy_Conduits"):
			_conduit_mat = ShaderMaterial.new()
			_conduit_mat.shader = CONDUIT_SHADER
			_conduit_mat.set_shader_parameter("albedo_tex", src.albedo_texture)
			_conduit_mat.set_shader_parameter("emission_tex", src.emission_texture)
			_conduit_mat.set_shader_parameter("base_alpha", src.albedo_color.a)
			_conduit_mat.set_shader_parameter("base_emission", src.emission.r * src.emission_energy_multiplier)
			_conduit_mat.set_shader_parameter("start_x", CONDUIT_X.x)
			_conduit_mat.set_shader_parameter("end_x", CONDUIT_X.y)
			mi.material_override = _conduit_mat


func _setup_orb() -> void:
	_orb_swirl = _orb_quad("twirl", Color(1.0, 0.62, 0.08))
	_orb_core = _orb_quad("glow", HOT)
	_orb_flare = _orb_quad("star", Color(1.0, 0.9, 0.45))
	for i in 6:
		var a := _orb_quad("bolt", HOT if i % 2 == 0 else Color(1.0, 0.9, 0.3))
		a.top_level = true
		a.visible = false
		_orb_arcs.append(a)
		_arc_a.append(Vector3.ZERO)
		_arc_b.append(Vector3.ZERO)
		_arc_t.append(0.0)


## Effect quad drawn after the (transparent) orb glass so it shows inside it.
func _orb_quad(tex: String, col: Color) -> MeshInstance3D:
	var q := Vfx.quad(tex, col, Vector2.ONE)
	(q.material_override as StandardMaterial3D).render_priority = 1
	q.position = ORB_CENTER * model_scale
	add_child(q)
	return q


func _make_steam(size: float, amount: int, life: float, burst: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	q.material = Vfx.mix_material("smoke")
	p.mesh = q
	p.amount = maxi(int(round(amount * clampf(gun.steam_amount if gun else 1.0, 0.1, 3.0))), 2)
	p.lifetime = life
	p.local_coords = false
	p.one_shot = burst
	p.explosiveness = 0.85 if burst else 0.0
	var ms := model_scale
	p.position = Vector3(0.72, -0.05, 0.0) * ms
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.24, 0.08, 0.06) * ms
	p.direction = Vector3(0.2, 1, 0)
	p.spread = 35.0 if not burst else 70.0
	p.initial_velocity_min = 0.2 if not burst else 1.0
	p.initial_velocity_max = 0.6 if not burst else 2.4
	p.gravity = Vector3(0, 0.8, 0)
	p.damping_min = 0.5 if not burst else 2.0
	p.damping_max = 1.0 if not burst else 3.0
	p.scale_amount_curve = Vfx.curve([Vector2(0, 0.35), Vector2(1, 1.5)])
	p.color_ramp = Vfx.ramp([Color(1.0, 0.92, 0.55, 0.0), Color(0.95, 0.88, 0.55, 0.55), Color(0.75, 0.72, 0.6, 0.0)], [0.0, 0.2, 1.0])
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	add_child(p)
	return p


## Overheated: a strong burst of steam, sparks and electricity.
func vent() -> void:
	_vent = 1.0
	_vent_steam.restart()
	_vent_steam.emitting = true
	_vent_sparks.restart()
	_vent_sparks.emitting = true


func _process(delta: float) -> void:
	if gun == null:
		return
	_t += delta
	var e := gun.energy
	var heat := gun.heat_ratio()
	var hot := gun.overheated
	_vent = maxf(_vent - delta / 1.2, 0.0)
	_overload = move_toward(_overload, 1.0 if hot else smoothstep(0.78, 1.0, heat), delta * (6.0 if hot else 1.5))
	var gs := global_basis.get_scale().x
	var flick := randf_range(-1.0, 1.0) * _overload
	# Plasma flow: calm at idle, faster/brighter as the gun spins and heats.
	_phase += delta * (3.5 + 24.0 * e)
	if _conduit_mat:
		_conduit_mat.set_shader_parameter("flow_phase", _phase)
		_conduit_mat.set_shader_parameter("energy", e)
		_conduit_mat.set_shader_parameter("overload", _overload)
		_conduit_mat.set_shader_parameter("strength", gun.conduit_energy_intensity)
	if _body_mat:
		_body_mat.emission_energy_multiplier = _body_emission * (1.0 + 0.5 * e + 0.35 * flick)
	if _body_mi:
		var glow := heat * gun.barrel_glow_intensity
		if glow > 0.01:
			if _body_mi.material_overlay != _heat_mat:
				_body_mi.material_overlay = _heat_mat
			_heat_mat.set_shader_parameter("heat", heat)
			_heat_mat.set_shader_parameter("strength", gun.barrel_glow_intensity)
			_heat_mat.set_shader_parameter("flicker", 0.25 * flick + 0.1 * sin(_t * 37.0) * e)
		elif _body_mi.material_overlay:
			_body_mi.material_overlay = null
	_update_orb(delta, e, gs)
	# Electrical activity round the barrel grows with heat.
	var elec := clampf(smoothstep(0.3, 1.0, heat) * 0.85 + 0.12 * e * float(gun.trigger) + 0.8 * _vent + 0.3 * _overload, 0.0, 1.0)
	_static.intensity = elec * gun.electric_intensity
	# Steam: wisps once hot, thick while venting/locked out.
	var steam := clampf(smoothstep(0.5, 1.0, heat) * 0.7 + (0.5 if hot else 0.0), 0.0, 1.0) * gun.steam_amount
	_steam.emitting = steam > 0.04
	_steam.color = Color(1, 1, 1, clampf(steam, 0.0, 1.0))


func _update_orb(delta: float, e: float, gs: float) -> void:
	var s := gun.orb_energy_intensity
	var r := ORB_RADIUS * model_scale * gs
	var beat := 0.5 + 0.5 * sin(_t * (3.0 + 14.0 * e))
	var jitter := randf_range(0.85, 1.15) if e > 0.3 else 1.0
	if _orb_mat:
		# The glass glows only softly (you look into it); the energy inside
		# does the work.
		_orb_mat.emission_energy_multiplier = _orb_emission * (0.45 + (0.25 + 0.9 * e) * beat * s + 0.6 * _overload * randf())
	Vfx.face_camera(_orb_core, r * (1.0 + 0.6 * e) * (0.85 + 0.25 * beat) * jitter, _t * 2.0)
	Vfx.set_alpha(_orb_core, clampf((0.6 + 0.4 * e) * s, 0.0, 1.0))
	_orb_flare.visible = e > 0.15
	if _orb_flare.visible:
		Vfx.face_camera(_orb_flare, r * (0.8 + 1.0 * e) * randf_range(0.8, 1.2), randf() * TAU)
		Vfx.set_alpha(_orb_flare, clampf(e * 1.3 * s, 0.0, 1.0))
	Vfx.face_camera(_orb_swirl, r * (1.6 + 0.2 * beat), -_t * (2.5 + 11.0 * e))
	Vfx.set_alpha(_orb_swirl, clampf((0.55 + 0.45 * e) * s, 0.0, 1.0))
	var cam := get_viewport().get_camera_3d()
	var c := global_transform * (ORB_CENTER * model_scale)
	for i in _orb_arcs.size():
		_arc_t[i] -= delta
		if _arc_t[i] <= 0.0:
			_arc_t[i] = randf_range(0.03, 0.09) * (1.3 - 0.7 * e)
			# From near the core to the inside of the glass, or across it.
			var d1 := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
			var d2 := (d1 * -0.4 + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))).normalized()
			_arc_a[i] = d1 * randf_range(0.05, 0.3)
			_arc_b[i] = d2 * randf_range(0.7, 0.9)
			var on := randf() < (0.35 + 0.65 * e) * s * (1.0 if i < 3 else e)
			_orb_arcs[i].visible = on
			if on:
				Vfx.set_alpha(_orb_arcs[i], randf_range(0.5, 1.0))
		if _orb_arcs[i].visible and cam:
			var basis := global_basis.orthonormalized()
			MachineGunFlash._stretch(_orb_arcs[i], c + basis * (_arc_a[i] * r), c + basis * (_arc_b[i] * r), r * (0.45 + 0.3 * e), cam)
