class_name SentinelEyeBurst
extends Node3D
## The Neon Sentinel's death (owner asked: "its eye to smash and burst
## dramatically followed by a puff of smoke and electric discharge from its
## eye socket that's clearly visible"). On top of the model's own eye burst
## (Death_Eye_Burst: the 24 glass shards flying out, the plasma bulb
## collapsing) and its branching arcs (SentinelFlex):
##   - a big cel flash, white-hot to plasma yellow, blasting out of the eye;
##   - a spray of glinting glass splinters;
##   - a puff of cartoon smoke rolling out of the socket, then a smoke trail
##     streaming from it as the wreck falls;
##   - electric discharge from the socket: lightning bolts lashing out of it
##     (to its rim and out into the air, re-striking every few hundredths
##     of a second), a throbbing glow in it, yellow sparks spitting out and
##     a flickering yellow light (effect lights off on phones: Vfx), all
##     dying away.
## Follows the eye (`skeleton`, `bone`) while the body falls; frees itself.

const YELLOW := Color(1.0, 0.86, 0.1)
const HOT := Color(1.0, 1.0, 0.85)

@export var duration := 3.6
var skeleton: Skeleton3D
var bone := -1
## The way the eye faces (world), at the moment it bursts.
var facing := Vector3.FORWARD
var scale_m := 1.0
var _t := 0.0
var _light: OmniLight3D
var _sparks: CPUParticles3D
var _glass: CPUParticles3D
var _smoke: SmokeTrail
var _puffs: Array[ToonPuff] = []
var _bolts: Array[MeshInstance3D] = []
var _bolt_end: Array[Vector3] = []
var _bolt_t: Array[float] = []
var _glow: MeshInstance3D
## Bolts showing this frame (tests).
var bolts_lit := 0
## Times it has been spawned (tests).
static var spawned := 0


static func spawn(tree: SceneTree, skel: Skeleton3D, eye_bone: int, face: Vector3, size := 1.0) -> SentinelEyeBurst:
	var fx := SentinelEyeBurst.new()
	fx.skeleton = skel
	fx.bone = eye_bone
	fx.facing = face.normalized() if face.length_squared() > 0.001 else Vector3.FORWARD
	fx.scale_m = size
	var world := tree.current_scene if tree.current_scene else tree.root
	world.add_child(fx)
	spawned += 1
	return fx


func _eye() -> Vector3:
	if skeleton and is_instance_valid(skeleton) and bone >= 0:
		return (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin
	return global_position


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_position = _eye()
	var up := Vector3.UP if absf(facing.y) < 0.95 else Vector3.RIGHT
	var basis_out := Basis.looking_at(facing, up)  # -Z = out of the eye
	# The burst: a big flash out of the eye.
	var flash := CelFlash.shared(get_tree(), "sentinel_eye", YELLOW, HOT, func(n: CelFlash) -> void:
		n.size = 1.5
		n.cone_length = 2.6
		n.cones = 6
		n.sparks = 12
		n.duration = 0.2
		n.glow_size = 4.2
		n.glow_strength = 1.4)
	flash.fire(global_position, facing, 1.0)
	# Glass splinters glinting as they fly.
	_glass = _particles(46, 0.9, Vector2(4.0, 9.0), 55.0, Vector3(0, -6.0, 0), Vector2(0.025, 0.06),
		Color(0.9, 1.0, 1.0), Color(0.6, 0.85, 1.0, 0.0))
	_glass.transform = Transform3D(basis_out, Vector3.ZERO)
	_glass.one_shot = true
	_glass.explosiveness = 0.95
	_glass.emitting = true
	# Electric sparks spitting out of the socket for a while.
	_sparks = _particles(34, 0.45, Vector2(2.0, 6.5), 70.0, Vector3(0, -4.0, 0), Vector2(0.03, 0.05),
		Color(1.0, 1.0, 0.7), Color(1.0, 0.7, 0.05, 0.0))
	_sparks.transform = Transform3D(basis_out, Vector3.ZERO)
	_sparks.emitting = true
	# A puff of smoke rolling out of the socket.
	for i in 7:
		var p := ToonPuff.new()
		add_child(p)
		p.size = randf_range(0.32, 0.55) * scale_m
		p.life = randf_range(1.2, 1.8)
		p.rise = randf_range(0.6, 1.1)
		p.delay = 0.08 + i * 0.05
		p.drift = facing * randf_range(0.4, 0.9) + Vector3(randf_range(-0.35, 0.35), 0.0, randf_range(-0.35, 0.35))
		p.set_colors(Color(0.5, 0.5, 0.53))
		p.play(global_position + facing * 0.15 * scale_m, false)
		_puffs.append(p)
	# The wreck trails smoke from the socket as it falls.
	_smoke = SmokeTrail.new()
	_smoke.lifetime = 1.8
	_smoke.start_width = 0.25 * scale_m
	_smoke.end_width = 1.3 * scale_m
	_smoke.spacing = 0.35
	_smoke.smoke_color = Color(0.25, 0.25, 0.27)
	_smoke.hot_color = Color(1.0, 0.85, 0.3)
	add_child(_smoke)
	_smoke.emitting = true
	# The discharge's light.
	_light = OmniLight3D.new()
	_light.light_color = YELLOW
	_light.omni_range = 6.0 * scale_m
	_light.light_energy = 6.0
	_light.shadow_enabled = false
	add_child(_light)
	Vfx.tame_light(_light)
	# Lightning out of the socket, and its glow.
	for i in 6:
		var q := Vfx.quad("bolt", Color(1.0, 0.95, 0.45), Vector2.ONE)
		q.top_level = true
		add_child(q)
		_bolts.append(q)
		_bolt_end.append(Vector3.ZERO)
		_bolt_t.append(0.0)
	_glow = Vfx.quad("glow", Color(1.0, 0.85, 0.2), Vector2.ONE * 0.9 * scale_m, BaseMaterial3D.BILLBOARD_ENABLED)
	add_child(_glow)
	if skeleton and bone >= 0:
		JointSparks.play_on_bone(skeleton, bone, 1.6)


func _particles(n: int, life: float, speed: Vector2, spread: float, grav: Vector3, size: Vector2, c0: Color, c1: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = n
	p.lifetime = life
	p.local_coords = false
	p.direction = Vector3(0, 0, -1)
	p.spread = spread
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.gravity = grav
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(size.y, size.x) * scale_m
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	p.color_ramp = g
	add_child(p)
	return p


func _process(delta: float) -> void:
	_t += delta
	var k := 1.0 - clampf(_t / duration, 0.0, 1.0)
	var at := _eye()
	global_position = at
	if _smoke:
		_smoke.feed(at)
		if _t > 2.6:
			_smoke.emitting = false
	if _sparks:
		_sparks.emitting = _t < duration * 0.8 and randf() < 0.3 + 0.7 * k
	if _light and not _light.has_meta(&"tamed"):
		# Flickering discharge, strongest at first.
		_light.light_energy = (2.0 + 6.0 * k) * (randf() if randf() < 0.6 else 0.15) * k
	_strike_bolts(delta, k)


## The discharge: each bolt re-strikes every few hundredths of a second from
## the socket to a new end - round its rim or lashing out into the air -
## fewer and shorter as it dies away.
func _strike_bolts(delta: float, k: float) -> void:
	bolts_lit = 0
	var cam := get_viewport().get_camera_3d()
	var on_any := k > 0.0 and cam != null and skeleton and is_instance_valid(skeleton)
	if _glow:
		_glow.visible = on_any
		if on_any:
			_glow.global_position = _eye()
			Vfx.set_alpha(_glow, k * randf_range(0.5, 1.0))
	if not on_any:
		for b in _bolts:
			b.visible = false
		return
	var eye := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	var fwd := eye.basis.z.normalized()
	var right := eye.basis.x.normalized()
	var up := eye.basis.y.normalized()
	var r := 0.3 * scale_m
	for i in _bolts.size():
		_bolt_t[i] -= delta
		if _bolt_t[i] <= 0.0:
			_bolt_t[i] = randf_range(0.03, 0.08)
			_bolts[i].visible = randf() < 0.25 + 0.75 * k
			var a := randf() * TAU
			if randf() < 0.55:
				_bolt_end[i] = (right * cos(a) + up * sin(a)) * r * randf_range(0.8, 1.2) + fwd * randf_range(0.0, 0.15) * scale_m
			else:
				_bolt_end[i] = fwd * randf_range(0.4, 1.2) * scale_m * (0.5 + 0.5 * k) + (right * cos(a) + up * sin(a)) * randf_range(0.2, 0.7) * scale_m
			Vfx.set_alpha(_bolts[i], randf_range(0.7, 1.0))
		if not _bolts[i].visible:
			continue
		var a := eye.origin
		var b := a + _bolt_end[i]
		var axis := b - a
		var len := axis.length()
		if len < 1e-4:
			continue
		var y := axis / len
		var to_cam := (cam.global_position - (a + b) * 0.5).normalized()
		var x := y.cross(to_cam).normalized()
		var z := x.cross(y)
		var w := randf_range(0.14, 0.24) * scale_m * (1.0 if randf() < 0.5 else -1.0)
		_bolts[i].global_transform = Transform3D(Basis(x * w, y * len, z), (a + b) * 0.5)
		bolts_lit += 1
	if _t >= duration + 2.0:
		queue_free()
