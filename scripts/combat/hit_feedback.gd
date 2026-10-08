class_name HitFeedback
extends Node
## Hit and death feedback for light robots (RobotEnemy / RobotSkirmisher),
## reusable by any enemy with a skeleton and body mesh. Nothing here changes
## damage, AI or animation playback: reactions are layered on top.
##
## Per hit (`on_hit`): an additive upper-body lean + mechanical shake away
## from the shot (BossHitReact, the boss's reaction, reused), a very brief
## additive tint over the body in the weapon's colour, and electrical
## sparks at the nearest joint. Strength comes from the hit's severity
## (damage as a share of max health + impact force) and the weapon:
## plasma = medium jolt, machine gun = tiny twitches with occasional
## flicker, shotgun = big burst + scrap + stagger up close, black hole =
## heavy. Everything is throttled per robot so automatic fire never
## stacks or floods the effect pools. Beyond `fx_distance` only the lean
## and tint run.
##
## Per death (`on_death`): a burst at the killing hit, a spray of scrap
## chips (opaque, pooled particles, no physics) and the shared electrical
## failure (RobotDeathSparks) - sizes randomised so no two look the same.
## While a gravity well holds the robot it crackles and shudders.

enum Tier { LIGHT, MEDIUM, HEAVY }

const COLORS := {
	&"plasma": Color(0.35, 0.9, 1.0),
	&"machine_gun": Color(1.0, 0.85, 0.3),
	&"shotgun": Color(1.0, 0.55, 0.2),
	&"black_hole": Color(0.75, 0.35, 1.0),
	&"": Color(1.0, 1.0, 1.0),
}
## Per weapon: [lean kick multiplier, spark strength multiplier,
## min seconds between sparks, min seconds between body flashes, flash chance].
const PROFILES := {
	&"plasma": [1.0, 1.0, 0.08, 0.0, 1.0],
	&"machine_gun": [0.45, 0.6, 0.18, 0.1, 0.5],
	&"shotgun": [1.6, 1.6, 0.12, 0.0, 1.0],
	&"black_hole": [1.8, 1.4, 0.1, 0.0, 1.0],
	&"": [1.0, 1.0, 0.12, 0.0, 1.0],
}

## Severity = damage / max_health + force / force_scale.
@export var force_scale := 30.0
@export var medium_at := 0.25
@export var heavy_at := 0.5
## Lean kick per tier (BossHitReact strength).
@export var tier_kick := Vector3(0.18, 0.4, 0.8)
## Spark strength per tier (JointSparks strength).
@export var tier_sparks := Vector3(0.2, 0.4, 0.8)
## Body tint brightness and how long it shows (s).
@export var flash_strength := 0.9
@export var flash_time := 0.05
## Min seconds between staggers of one robot.
@export var stagger_cooldown := 1.2
## Particles / sparks only within this camera distance (m).
@export var fx_distance := 32.0
@export var scrap_chips := Vector2i(6, 12)

var robot: Node3D
var skeleton: Skeleton3D
var react: BossHitReact
## Meshes that get the brief tint (the drawn body).
var flash_meshes: Array[GeometryInstance3D] = []
## Called with the hit tier on a heavy hit (stagger is optional per robot).
var stagger: Callable

## Counters for tests / tuning.
var hits := 0
var flashes := 0
var sparks := 0
var staggers := 0
var last_tier := Tier.LIGHT

var _clock := 0.0
var _flash_left := 0.0
var _last_spark := -10.0
var _last_flash := -10.0
var _last_stagger := -10.0
var _last_burst := -10.0
var _well_t := 0.0

static var _overlays := {}
static var _shader: Shader
static var _chips: Array[CPUParticles3D] = []
const CHIP_POOL := 6


func setup(r: Node3D, skel: Skeleton3D, meshes: Array[GeometryInstance3D]) -> void:
	robot = r
	skeleton = skel
	flash_meshes = meshes
	react = BossHitReact.new()
	react.name = "HitReact"
	react.max_lean_deg = 9.0
	react.shake_deg = 2.2
	react.max_kick_speed = 12.0
	skel.add_child(react)
	# Before the arm aim so the cannons stay on target while the body jerks.
	var aim := skel.get_node_or_null("ArmAim")
	if aim:
		skel.move_child(react, aim.get_index())
	react.setup(skel)


static func weapon_of(info: DamageInfo) -> StringName:
	if info.weapon != &"":
		return info.weapon
	if info.damage_type == DamageInfo.Type.SUPERNOVA or info.source is BlackHoleProjectile:
		return &"black_hole"
	return &""


func severity(info: DamageInfo, max_health: float) -> float:
	return info.damage_amount / maxf(max_health, 0.01) + info.total_force() / force_scale


func tier_of(sev: float) -> int:
	return Tier.HEAVY if sev >= heavy_at else (Tier.MEDIUM if sev >= medium_at else Tier.LIGHT)


## A non-lethal hit.
func on_hit(info: DamageInfo, max_health: float) -> void:
	if skeleton == null or not is_instance_valid(skeleton):
		return
	hits += 1
	var w := weapon_of(info)
	var prof: Array = PROFILES.get(w, PROFILES[&""])
	var sev := severity(info, max_health)
	var tier := tier_of(sev)
	# Close shotgun blasts land as heavy hits.
	if w == &"shotgun" and info.impact_force >= 6.0:
		tier = Tier.HEAVY
	last_tier = tier
	# Upper-body jolt (springs back; stacking capped in BossHitReact).
	react.kick(tier_kick[tier] * prof[0], info.impact_direction)
	# Brief tint in the weapon's colour (machine gun: only now and then).
	if _clock - _last_flash >= prof[3] and randf() < prof[4]:
		_flash(COLORS.get(w, Color.WHITE), 1.0 if tier == Tier.LIGHT else 1.4)
	if tier == Tier.HEAVY and stagger.is_valid() and _clock - _last_stagger >= stagger_cooldown:
		_last_stagger = _clock
		staggers += 1
		stagger.call()
	if _cam_distance() > fx_distance:
		return
	# Electrical twitch at the nearest joint.
	if _clock - _last_spark >= prof[2]:
		_last_spark = _clock
		sparks += 1
		JointSparks.play_on_bone(skeleton, _nearest_bone(info.impact_position), tier_sparks[tier] * prof[1])
		# Medium+: a second joint malfunctions a moment later.
		if tier >= Tier.MEDIUM and randf() < 0.5:
			var b := _random_joint()
			get_tree().create_timer(randf_range(0.06, 0.16), false, true).timeout.connect(func() -> void:
				if is_instance_valid(skeleton) and skeleton.is_inside_tree():
					JointSparks.play_on_bone(skeleton, b, 0.25))
	# Shotgun / heavy: one bigger spark burst + scrap per volley.
	if (w == &"shotgun" or tier == Tier.HEAVY) and _clock - _last_burst >= 0.12:
		_last_burst = _clock
		var col: Color = COLORS.get(w, Color.WHITE)
		PlasmaFx.impact(get_tree(), info.impact_position, -info.impact_direction, false, col, Color(1, 0.95, 0.85), 0.3, true, 1.5 if tier == Tier.HEAVY else 1.2)
		_scrap(info.impact_position, info.impact_direction, randi_range(3, 6))


## The robot died from `info` (call once).
func on_death(info: DamageInfo, broke_apart: bool) -> void:
	if skeleton == null or not is_instance_valid(skeleton):
		return
	_flash(COLORS.get(weapon_of(info), Color.WHITE), 1.6)
	if _cam_distance() > fx_distance:
		return
	var w := weapon_of(info)
	var col: Color = COLORS.get(w, Color.WHITE)
	var big := randf_range(1.4, 2.1) + (0.4 if broke_apart else 0.0)
	PlasmaFx.impact(get_tree(), info.impact_position, -info.impact_direction, false, col, Color(1, 0.95, 0.85), 0.3, true, big)
	_scrap(info.impact_position, info.impact_direction, randi_range(scrap_chips.x, scrap_chips.y))
	RobotDeathSparks.play(skeleton, randf_range(0.8, 1.05) * (1.3 if broke_apart else 1.0))


func _process(delta: float) -> void:
	_clock += delta
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			for m in flash_meshes:
				if is_instance_valid(m):
					m.material_overlay = null
	# Held by a gravity well: crackles and shudders now and then.
	if robot and robot.has_method(&"in_gravity_well") and robot.in_gravity_well():
		_well_t -= delta
		if _well_t <= 0.0:
			_well_t = randf_range(0.25, 0.55)
			react.kick(0.25, Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)))
			if _cam_distance() <= fx_distance:
				JointSparks.play_on_bone(skeleton, _random_joint(), 0.3)
			_flash(COLORS[&"black_hole"], 0.6)


func flash_active() -> bool:
	return _flash_left > 0.0


func _flash(col: Color, k: float) -> void:
	_last_flash = _clock
	flashes += 1
	var mat := _overlay(col, flash_strength * k)
	for m in flash_meshes:
		if is_instance_valid(m) and m.visible:
			m.material_overlay = mat
	_flash_left = flash_time * (1.0 + 0.5 * (k - 1.0))


## Shared additive tint per colour/brightness (no per-robot copies): a
## glow round the silhouette edges plus a faint fill, so the robot's own
## texture still reads through it.
static func _overlay(col: Color, k: float) -> ShaderMaterial:
	var key := "%s|%.2f" % [col.to_html(), k]
	if _overlays.has(key):
		return _overlays[key]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, skip_vertex_transform;
uniform vec3 tint : source_color;
uniform float strength = 0.4;
void vertex() {
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = tint * strength * (0.18 + 0.82 * rim * rim);
}
"""
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter(&"tint", col)
	m.set_shader_parameter(&"strength", k)
	_overlays[key] = m
	return m


func _cam_distance() -> float:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	return cam.global_position.distance_to(robot.global_position) if cam and robot else 0.0


func _nearest_bone(p: Vector3) -> int:
	var best := 0
	var bd := INF
	var xf := skeleton.global_transform
	for i in skeleton.get_bone_count():
		var d := (xf * skeleton.get_bone_global_pose(i)).origin.distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func _random_joint() -> int:
	var names := [&"mixamorig_Neck", &"mixamorig_Spine2", &"mixamorig_LeftArm", &"mixamorig_RightArm", &"mixamorig_LeftForeArm", &"mixamorig_RightForeArm", &"mixamorig_LeftUpLeg", &"mixamorig_RightUpLeg"]
	return maxi(skeleton.find_bone(names[randi() % names.size()]), 0)


## Small dark metal chips flung from `at` (opaque mesh particles, pooled,
## no physics bodies, gone in under a second).
func _scrap(at: Vector3, dir: Vector3, n: int) -> void:
	var p := _take_chips()
	if p == null:
		return
	p.global_position = at
	p.direction = (-dir + Vector3.UP * 0.6).normalized()
	p.amount = maxi(n, 1)
	p.restart()


func _take_chips() -> CPUParticles3D:
	var host: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	_chips = _chips.filter(func(c: CPUParticles3D) -> bool: return is_instance_valid(c) and c.is_inside_tree())
	for c in _chips:
		if not c.emitting:
			return c
	if _chips.size() >= CHIP_POOL:
		return _chips[randi() % _chips.size()]
	var c := CPUParticles3D.new()
	c.name = "ScrapChips"
	c.one_shot = true
	c.emitting = false
	c.explosiveness = 1.0
	c.lifetime = 0.8
	c.amount = 12
	c.spread = 60.0
	c.initial_velocity_min = 2.5
	c.initial_velocity_max = 5.5
	c.gravity = Vector3(0, -14, 0)
	c.angular_velocity_min = -720.0
	c.angular_velocity_max = 720.0
	c.scale_amount_min = 0.5
	c.scale_amount_max = 1.2
	c.local_coords = false
	c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.02, 0.035)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.22, 0.24)
	mat.metallic = 0.8
	mat.roughness = 0.45
	box.material = mat
	c.mesh = box
	host.add_child(c)
	_chips.append(c)
	return c


static func chips_active() -> int:
	var n := 0
	for c in _chips:
		if is_instance_valid(c) and c.emitting:
			n += 1
	return n
