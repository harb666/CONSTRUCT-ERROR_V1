class_name HealthPickup
extends Node3D
## A health pick-up placed in a level (owner asked: "3d holographic health
## pickups around the map"): a small projector on the floor - dark disc, a
## glowing green ring - throwing a faint beam of light up into a big green
## holographic "+" (hologram.gdshader: see-through, scan lines running up,
## a bright rim) that bobs, turns and glitches now and then like the
## dropped pick-ups. Walk through it with health missing: `heal` back, the
## cross bursts and is gone, and `respawn_time` s later it materialises
## again (Hologram.teleport_in). Each device runs its own (its own player
## takes it - co-op: every player has their own). No sound (none of the
## owner's for it). Levels list them under a "HealthPickups" node. Its
## materials are kinds the warm-up already makes (the hologram shader, the
## pick-ups' glowing material, the glow quad).

const GROUP := &"health_pickups"
const GREEN := Color(0.25, 1.0, 0.4)

@export var heal := 25.0
@export var respawn_time := 30.0
## Taken by a player within this (m, across) and `reach_up` above / below.
@export var radius := 1.2
@export var reach_up := 1.8
## Not drawn beyond this (m): five draws each, and level 3's fights were
## already heavy on phones (owner: "the fps drops significantly").
@export var draw_distance := 45.0

var available := true
var taken := 0
var _t := 0.0
var _back_in := 0.0
var _burst := -1.0
var _glitch_in := 1.0
var _glitch_left := 0.0
var cross: MeshInstance3D
var beam: MeshInstance3D
var _ring: MeshInstance3D
var _glow: MeshInstance3D
var _holder: Node3D


func _ready() -> void:
	add_to_group(GROUP)
	_t = randf() * 10.0
	_glitch_in = randf_range(0.5, 3.0)
	_build()


func _build() -> void:
	var base := MeshInstance3D.new()
	base.name = "Projector"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.42
	disc.bottom_radius = 0.48
	disc.height = 0.1
	disc.radial_segments = 20
	disc.rings = 1
	disc.material = RecoveryDrops._material(Color(0.08, 0.1, 0.12), 0.05)
	base.mesh = disc
	base.position.y = 0.05
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(base)
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	var tor := TorusMesh.new()
	tor.inner_radius = 0.3
	tor.outer_radius = 0.37
	tor.rings = 24
	tor.ring_segments = 6
	tor.material = RecoveryDrops._material(GREEN, 1.2)
	_ring.mesh = tor
	_ring.position.y = 0.11
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	beam = MeshInstance3D.new()
	beam.name = "Beam"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.5
	cone.bottom_radius = 0.3
	cone.height = 0.95
	cone.radial_segments = 20
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	cone.material = RecoveryDrops.hologram_material(GREEN, 0.1)
	beam.mesh = cone
	beam.position.y = 0.6
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	_holder = Node3D.new()
	_holder.name = "Cross"
	_holder.position.y = 1.25
	add_child(_holder)
	cross = MeshInstance3D.new()
	cross.mesh = cross_mesh()
	cross.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_holder.add_child(cross)
	_glow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 1.3
	_glow.mesh = q
	_glow.material_override = Vfx.material("glow", GREEN * 0.45, BaseMaterial3D.BILLBOARD_ENABLED)
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_holder.add_child(_glow)
	for gi: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		gi.visibility_range_end = draw_distance


## The big holographic "+" (shared): a thick 3D cross ~0.6 m across.
static func cross_mesh() -> Mesh:
	if RecoveryDrops._meshes.has("health_holo"):
		return RecoveryDrops._meshes["health_holo"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sz: Vector3 in [Vector3(0.62, 0.2, 0.2), Vector3(0.2, 0.62, 0.2)]:
		var b := BoxMesh.new()
		b.size = sz
		st.append_from(b, 0, Transform3D.IDENTITY)
	st.generate_normals()
	st.set_material(RecoveryDrops.hologram_material(GREEN, 0.55))
	var m := st.commit()
	RecoveryDrops._meshes["health_holo"] = m
	return m


func _physics_process(delta: float) -> void:
	_t += delta
	if not available:
		_back_in -= delta
		if _back_in <= 0.0:
			_appear()
	else:
		for p in get_tree().get_nodes_in_group(&"local_player"):
			var pc := p as PlayerController
			if pc == null or pc.is_remote or pc.health >= pc.max_health:
				continue
			var off := pc.global_position - global_position
			if Vector2(off.x, off.z).length() <= radius and off.y > -1.0 and off.y < reach_up:
				_take(pc)
				break
	_animate(delta)


func _take(pc: PlayerController) -> void:
	pc.heal(heal)
	available = false
	taken += 1
	_back_in = respawn_time
	_burst = 0.0
	DebugHud.note("health pickup")


func _appear() -> void:
	available = true
	_burst = -1.0
	_holder.visible = true
	_holder.scale = Vector3.ONE
	Hologram.teleport_in(_holder, 0.8, GREEN)


func _animate(delta: float) -> void:
	# Taken: the cross swells and fades out fast, the beam dims.
	if _burst >= 0.0:
		_burst += delta
		var k := clampf(_burst / 0.25, 0.0, 1.0)
		_holder.scale = Vector3.ONE * (1.0 + 0.8 * k)
		_holder.visible = k < 1.0
	beam.visible = available
	_ring.scale = Vector3.ONE * (1.0 + (0.06 * sin(_t * 5.0) if available else -0.15))
	if not available:
		return
	_holder.position.y = 1.25 + sin(_t * 2.2) * 0.08
	cross.rotation.y = _t * 1.6
	_glow.scale = Vector3.ONE * (1.0 + 0.12 * sin(_t * 6.0))
	# A glitch now and then (a jump sideways, a stretch, a flash).
	_glitch_in -= delta
	if _glitch_in <= 0.0:
		_glitch_in = randf_range(1.2, 3.0)
		_glitch_left = randf_range(0.06, 0.12)
		cross.material_override = RecoveryDrops._glitch_material(randi() % 2)
		cross.scale = Vector3(randf_range(1.15, 1.35), randf_range(0.8, 0.95), 1.0)
		cross.position.x = randf_range(-0.07, 0.07)
	if _glitch_left > 0.0:
		_glitch_left -= delta
		if _glitch_left <= 0.0:
			cross.material_override = null
			cross.scale = Vector3.ONE
			cross.position.x = 0.0

