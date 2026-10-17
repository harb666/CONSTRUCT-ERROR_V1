class_name ToxicWorks
extends Node3D
## The Toxic Works (made by image-to-level as "slime_arena": level 1, part 2
## of 3; owner asked): the generator's game-ready package from
## res://levels/slime_arena/ (copied unchanged from its exports/), put
## together like Skyforge Arena (SkyforgeArena):
##   - mobile/level_mobile.glb, background_mobile.glb (the factory seen
##     through the windows) and collision.glb;
##   - the package's apply_mobile.gd (visibility ranges, hazard volumes, the
##     exit door trigger) and apply_effects.gd (fans, TV static, bubble
##     tubes, pods up the reactor columns, slime pours and ripples...);
##   - the map maker preview's look (SkyforgePreviewLook with this level's
##     own sky lighting, sky/ibl_atlas.png).
## The squad arrives on Skyforge's lift coming down through the roof
## (ElevatorLift in arrival mode; the package's own elevator car is hidden),
## seen by ArrivalCamera. The level's own gameplay (owner's map maker):
##   - the hall's 3 waves (WaveDirector, once the lift has landed) open the
##     laser gate into the Works (collision.json "encounters" / "gates");
##   - the working assembly lines, the crusher (kills on its pad) and the
##     pads that surge up out of the slime run in apply_effects.gd;
##   - the control terminal at the end of the pads opens the exit's laser
##     gate (walking up to it uses it);
##   - the turbine fan by the exit blows a player who comes into its air
##     stream straight off the walkway into the slime (owner asked);
##   - slime, the crusher or falling off sends a player back to the spawn
##     and kills a robot; the exit leads to part 3, not made yet.

signal level_exit_entered(target: String, body: Node)

const DIR := "res://levels/slime_arena"
## Loaded when the level starts (not preloaded: see SkyforgeArena).
const LEVEL := "res://levels/slime_arena/mobile/level_mobile.glb"
const BACKGROUND := "res://levels/slime_arena/mobile/background_mobile.glb"
const COLLISION := "res://levels/slime_arena/mobile/collision.glb"
const APPLY_MOBILE := preload("res://levels/slime_arena/mobile/apply_mobile.gd")
const APPLY_EFFECTS := preload("res://levels/slime_arena/fx/godot/apply_effects.gd")
const SKY_SHADER := preload("res://scripts/world/preview_sky.gdshader")
## The package's own elevator car (merged nodes of this group): hidden, the
## squad rides Skyforge's lift instead (owner asked).
const CAR_GROUP := "Elevator_Car"

## Below this a player goes back to spawn and a robot dies (the slime is at
## 0-1 m, the floors at 7-14 m).
@export var kill_y := -4.0
@export var effects_quality := "balanced"

var level: Node3D
var background: Node3D
var collision: Node3D
var mobile: Node3D
var effects: Node3D
var out_of_bounds: Area3D
var env_data: Dictionary = {}
var look: SkyforgePreviewLook
var hud: LevelFlowHud
## Car pieces hidden (tests).
var car_hidden := 0
## The hall's waves (WaveDirector), gates opened and terminals used so far.
var director: WaveDirector
var gates_open: PackedStringArray = []
## Each laser gate's look (LaserGateFX), by gate id.
var gate_fx := {}
var terminals_used: PackedStringArray = []
## The laser gate the hall's waves open (into the Works).
const WORKS_GATE := "Gate_Works_Laser"
var _exit_shown := false
var _camera_far := 800.0


func _ready() -> void:
	env_data = _json(DIR + "/environment.json")
	level = (load(LEVEL) as PackedScene).instantiate()
	level.name = "Level"
	add_child(level)
	background = (load(BACKGROUND) as PackedScene).instantiate()
	background.name = "Background"
	add_child(background)
	collision = (load(COLLISION) as PackedScene).instantiate()
	collision.name = "Collision"
	add_child(collision)
	for mi: MeshInstance3D in collision.find_children("*", "MeshInstance3D", true, false):
		mi.visible = false
	_open_roof()
	_hide_car()
	mobile = APPLY_MOBILE.new()
	mobile.name = "ApplyMobile"
	mobile.set("manifest_path", DIR + "/mobile/mobile_manifest.json")
	mobile.set("level_root", level)
	add_child(mobile)
	mobile.connect(&"level_exit_entered", _on_level_exit)
	mobile.connect(&"gate_opened", _on_gate_opened)
	_build_gate_fx()
	_setup_environment()
	effects = APPLY_EFFECTS.new()
	effects.name = "ApplyEffects"
	effects.set("effects_path", DIR + "/mobile/effects_mobile.json")
	effects.set("quality", effects_quality)
	effects.set("level_root", level)
	effects.set("environment", _world_environment())
	add_child(effects)
	look = SkyforgePreviewLook.new()
	look.name = "PreviewLook"
	add_child(look)
	look.setup(env_data, load(DIR + "/sky/ibl_atlas.png"))
	look.apply(level, _flows())
	look.apply(background)
	_find_belts()
	out_of_bounds = Area3D.new()
	out_of_bounds.name = "OutOfBounds"
	out_of_bounds.monitorable = false
	out_of_bounds.collision_mask = 0xFFFFFFFF
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1200, 200, 1200)
	cs.shape = box
	cs.position = Vector3(0, kill_y - 100.0, 0)
	out_of_bounds.add_child(cs)
	add_child(out_of_bounds)
	out_of_bounds.body_entered.connect(_on_fell)
	# The slime and the crusher: hazard volumes (group "hazard").
	_connect_hazards.call_deferred()
	_connect_terminals.call_deferred()
	_connect_flow.call_deferred()
	_shotgun_pad.call_deferred()
	_wind_streaks.call_deferred()
	var ui := get_parent().get_node_or_null(^"UI") if get_parent() else null
	if ui:
		hud = LevelFlowHud.new()
		hud.name = "LevelFlowHud"
		ui.add_child(hud)
		ui.move_child(hud, 0)


## The ceiling's collider came in as one convex hull, which closes the
## round opening the lift comes down through (5.6 m across): it gets its
## exact shape (collision.json's own triangles). Nothing else changes.
const ROOF := "Ceiling_Slab"
var roof_opened := false


func _open_roof() -> void:
	for c in _json(DIR + "/mobile/collision.json").get("colliders", []):
		if String(c.get("name", "")) != ROOF or c.get("shape") != "mesh":
			continue
		var body := collision.find_child(ROOF, true, false) as StaticBody3D
		var shapes := body.find_children("*", "CollisionShape3D", true, false) if body else []
		if shapes.is_empty():
			return
		var node := shapes[0] as CollisionShape3D
		var to_local := node.global_transform.affine_inverse()
		var v: Array = c.get("vertices", [])
		var faces := PackedVector3Array()
		for f in c.get("faces", []):
			for i in 3:
				var q: Array = v[int(f[i])]
				faces.append(to_local * Vector3(q[0], q[1], q[2]))
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		node.shape = shape
		roof_opened = true


## The package's elevator car is merged into a few level nodes (manifest
## group "Elevator_Car"): hidden, colliders kept (the floor at its rest).
func _hide_car() -> void:
	var m := _json(DIR + "/mobile/mobile_manifest.json")
	for n in m.get("nodes", []):
		if String(n.get("group", "")) != CAR_GROUP:
			continue
		var gi := level.find_child(String(n["node"]), true, false) as Node3D
		if gi:
			gi.visible = false
			car_hidden += 1


func _connect_hazards() -> void:
	for a in get_tree().get_nodes_in_group(&"hazard"):
		var area := a as Area3D
		if area and is_ancestor_of(area) and not area.body_entered.is_connected(_on_fell):
			area.collision_mask = 0xFFFFFFFF
			area.body_entered.connect(_on_fell)


## The hall fight (owner's level: collision.json "encounters"): the waves
## start once the lift has landed (WaveDirector, begin()); when the last is
## cleared, the gates it opens (the laser gate into the Works) open.
func _connect_flow() -> void:
	var main := get_parent()
	if main == null:
		return
	director = main.get_node_or_null(^"WaveDirector") as WaveDirector
	var lift := main.get_node_or_null(^"ElevatorLift") as ElevatorLift
	if director:
		director.wave_started.connect(_on_wave_started)
		director.wave_cleared.connect(_on_wave_cleared)
		director.all_cleared.connect(_on_waves_done)
		if lift and lift.arrival and lift.arriving():
			lift.arrival_finished.connect(director.begin)
		else:
			director.begin()


func _on_wave_started(index: int, total: int) -> void:
	Net.world_event(self, &"wave_started", [index, total])
	if hud:
		hud.banner("WAVE %d / %d" % [index, total], "CLEAR THE HALL" if index == 1 else "ENEMIES INBOUND")


func _on_wave_cleared(index: int, total: int) -> void:
	Net.world_event(self, &"wave_cleared", [index, total])
	if hud and index < total:
		hud.banner("WAVE CLEARED", "NEXT WAVE INCOMING")


## The hall is clear: its gates open (the world's owner decides; online,
## everyone follows).
func _on_waves_done() -> void:
	Net.world_event(self, &"waves_done")
	for g in _json(DIR + "/mobile/collision.json").get("gates", []):
		var on: Dictionary = g.get("opens_on", {})
		if String(on.get("type", "")) == "waves_cleared":
			open_gate(String(g["id"]))


func open_gate(gate_id: String) -> void:
	if gates_open.has(gate_id):
		return
	gates_open.append(gate_id)
	if gate_fx.has(gate_id) and is_instance_valid(gate_fx[gate_id]):
		(gate_fx[gate_id] as LaserGateFX).open()
	mobile.call(&"open_gate", gate_id)


## The shotgun platform (owner asked: "sort out the centre of that platform
## and have the spawn pad for the shotgun with the gun on it"): the map
## maker left a post with a red cap at its centre for a pickup ("spawn your
## own shotgun model at center"). The post is flattened into the deck (its
## vertices; the platform is one skinned mesh) and its colliders go, and
## the game's shotgun spawn pad - the gun spinning over it, orange glow as
## in the battle arena - sits at the centre, riding the platform's bone up
## out of the slime with it.
const PAD_SCENE := preload("res://scenes/props/weapon_spawn_pad.tscn")
const SHOTGUN := preload("res://resources/weapons/shotgun.tres")
const SHOTGUN_RISER := "Shotgun_Platform"
var shotgun_pad: WeaponSpawnPad
## Post vertices flattened (tests).
var post_flattened := 0


func _shotgun_pad() -> void:
	var rec: Array = []
	for r in effects.get(&"_risers"):
		if String(r[0]["id"]) == SHOTGUN_RISER:
			rec = r
	if rec.is_empty():
		return
	var pad: Dictionary = rec[0]["pads"][0]
	var pickup := {}
	for pk in _json(DIR + "/mobile/collision.json").get("pickups", []):
		if String(pk.get("riser", "")) == SHOTGUN_RISER:
			pickup = pk
	var c: Array = pickup.get("center", pad["center"])
	var deck_y := float(pad["center"][1])  # the deck's top
	var centre := Vector3(c[0], deck_y, c[2])
	# The post: everything above the deck within its cap's radius, flattened.
	for mi: MeshInstance3D in level.find_children(String(rec[0]["group"]) + "__*", "MeshInstance3D", true, false):
		post_flattened += _flatten(mi, centre, 0.8)
	# Its colliders (named after the post) go for good.
	for cols in rec[3]:
		for cs in (cols as Array).duplicate():
			if String((cs as Node).name).begins_with(SHOTGUN_RISER + "_Pedestal") or String((cs as Node).get_parent().name).begins_with(SHOTGUN_RISER + "_Pedestal"):
				(cols as Array).erase(cs)
				(cs as CollisionShape3D).disabled = true
	# The pad on the platform's bone, at the centre when the platform is up.
	var sk := rec[1] as Skeleton3D
	var bi: int = rec[2].get(String(pad["joint"]), -1)
	if sk == null or bi < 0:
		return
	var ba := BoneAttachment3D.new()
	ba.name = "ShotgunPadMount"
	ba.bone_name = String(pad["joint"])
	sk.add_child(ba)
	shotgun_pad = PAD_SCENE.instantiate() as WeaponSpawnPad
	shotgun_pad.name = "ShotgunSpawnPad"
	shotgun_pad.weapon = SHOTGUN
	shotgun_pad.glow_color = Color(1, 0.42, 0.05, 1)
	var rest := sk.global_transform * sk.get_bone_global_rest(bi)
	shotgun_pad.transform = rest.affine_inverse() * Transform3D(Basis.IDENTITY, centre)
	ba.add_child(shotgun_pad)


## Flatten `mi`'s vertices above `centre` (within `radius` across) down onto
## its height. Returns how many moved.
func _flatten(mi: MeshInstance3D, centre: Vector3, radius: float) -> int:
	var src := mi.mesh as ArrayMesh
	if src == null:
		return 0
	var to_local := mi.global_transform.affine_inverse()
	var lc := to_local * centre
	var moved := 0
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var arrays := src.surface_get_arrays(si)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in v.size():
			var p := v[i]
			if Vector2(p.x - lc.x, p.z - lc.z).length() < radius and p.y > lc.y + 0.01:
				v[i] = Vector3(p.x, lc.y, p.z)
				moved += 1
		arrays[Mesh.ARRAY_VERTEX] = v
		var flags := 0
		if arrays[Mesh.ARRAY_BONES] != null and arrays[Mesh.ARRAY_BONES].size() == v.size() * 8:
			flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(src.surface_get_primitive_type(si), arrays, [], {}, flags)
		out.surface_set_material(si, src.surface_get_material(si))
		out.surface_set_name(si, src.surface_get_name(si))
	if moved > 0:
		var overrides: Array = []
		for si in src.get_surface_count():
			overrides.append(mi.get_surface_override_material(si))
		mi.mesh = out
		for si in overrides.size():
			mi.set_surface_override_material(si, overrides[si])
	return moved


## The laser gates' look (LaserGateFX; owner asked for them to look
## amazing): one over each gate's beams.
func _build_gate_fx() -> void:
	for g in _json(DIR + "/mobile/collision.json").get("gates", []):
		var laser := level.find_child(String(g["group"]) + "__laser", true, false) as MeshInstance3D
		if laser == null:
			continue
		var fx := LaserGateFX.new()
		fx.name = String(g["id"]) + "_FX"
		add_child(fx)
		fx.build(laser)
		gate_fx[String(g["id"])] = fx


## The control terminal(s): walking up to one uses it (the level's own
## interaction area) - its gates open (the exit's laser gate).
func _connect_terminals() -> void:
	for a in get_tree().get_nodes_in_group(&"terminal"):
		var area := a as Area3D
		if area and is_ancestor_of(area):
			area.collision_mask = 0xFFFFFFFF
			area.monitorable = false
			var id := String(area.get_meta(&"terminal_id", ""))
			area.body_entered.connect(func(b: Node3D) -> void:
				if b is PlayerController and Net.is_authority():
					use_terminal(id))


func use_terminal(id: String) -> void:
	if terminals_used.has(id):
		return
	terminals_used.append(id)
	Net.world_event(self, &"terminal", [id])
	for t in _json(DIR + "/mobile/collision.json").get("terminals", []):
		if String(t["id"]) == id:
			for gid in t.get("activates", []):
				if gate_fx.has(String(gid)) and is_instance_valid(gate_fx[String(gid)]):
					(gate_fx[String(gid)] as LaserGateFX).open()
				if not gates_open.has(String(gid)):
					gates_open.append(String(gid))
	mobile.call(&"activate_terminal", id)
	if hud:
		hud.banner("TERMINAL ACTIVATED", "EXIT GATE OPEN")


func _on_gate_opened(gate_id: String) -> void:
	if hud and gate_id == WORKS_GATE:
		hud.banner("HALL CLEARED", "THE WORKS GATE IS OPEN")


## The host's events, here too (online).
func net_event(kind: StringName, args: Array) -> void:
	match kind:
		&"wave_started":
			_on_wave_started(int(args[0]), int(args[1]))
		&"wave_cleared":
			_on_wave_cleared(int(args[0]), int(args[1]))
		&"waves_done":
			_on_waves_done()
		&"terminal":
			use_terminal(String(args[0]))


func _json(path: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


func _world_environment() -> WorldEnvironment:
	return get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment if get_parent() else null


## As SkyforgeArena: the panorama as the sky (never seen here - the hall is
## roofed - but it lights the players and robots), the level's own lighting
## and fog in its materials, the sun placed where the preview's is, giving
## players and robots their shadows (the level casts none, so the roof
## doesn't darken the hall).
func _setup_environment() -> void:
	var we := _world_environment()
	if we == null or env_data.is_empty():
		return
	var e := Environment.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("panorama", load(DIR + "/sky/panorama.jpg"))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = e
	var sun := get_parent().get_node_or_null("Sun") as DirectionalLight3D
	var s: Dictionary = env_data.get("sun", {})
	if sun and not s.is_empty():
		var d: Array = s["direction_to_sun"]
		var to_sun := Vector3(d[0], d[1], d[2]).normalized()
		sun.global_transform = Transform3D(Basis.looking_at(-to_sun), Vector3(0, 40, 0))
		sun.light_color = Color(s["color"][0], s["color"][1], s["color"][2]).linear_to_srgb()
		sun.light_energy = 1.2
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 40.0
	_camera_far = float(env_data.get("camera", {}).get("far", 800.0))


## Scrolling liquids (effects "liquid_flow"), as SkyforgeArena._flows.
func _flows() -> Dictionary:
	var out := {}
	var fx := _json(DIR + "/mobile/effects_mobile.json")
	for f in fx.get("effects", []):
		if f.get("type", "") != "liquid_flow":
			continue
		var q: Dictionary = f["quality"].get(effects_quality, {})
		if not q.get("enabled", false):
			continue
		var p: Dictionary = q["params"]
		var fu: Array = f.get("flow_uv", [0.0, 1.0])
		for t in f.get("targets", []):
			out[String(t)] = [Vector2(fu[0], fu[1]), float(p["speed"]) / float(f.get("material_tile_m", 2.0)), float(p.get("wobble", 0.0))]
	return out


## The conveyor belts run with their parcels (effects "assembly_line"
## "belt": apply_effects.gd scrolls the original material's UVs; the look's
## converted material gets the same scroll here).
var _belts: Array = []  # [ShaderMaterial, rest offset, scroll per second]
var _belt_t := 0.0


func _find_belts() -> void:
	var scroll := {}
	for f in _json(DIR + "/mobile/effects_mobile.json").get("effects", []):
		var line: Dictionary = f.get("line", {})
		if f.get("type", "") == "assembly_line" and line.has("belt"):
			var sc: Array = line["belt"]["scroll"]
			scroll[String(line["belt"]["material"])] = Vector2(sc[0], sc[1])
	if scroll.is_empty():
		return
	var seen := {}
	for mi: MeshInstance3D in level.find_children("*", "MeshInstance3D", true, false):
		for si in mi.get_surface_override_material_count():
			var sm := mi.get_surface_override_material(si) as ShaderMaterial
			if sm == null or seen.has(sm):
				continue
			for bn: String in scroll:
				if sm.resource_name == bn or sm.resource_name.begins_with(bn + "__"):
					seen[sm] = true
					_belts.append([sm, sm.get_shader_parameter("uv_offset"), scroll[bn]])


func _process(delta: float) -> void:
	_belt_t += delta
	for b in _belts:
		var sc: Vector2 = b[2]
		var rest = b[1]
		var base: Vector2 = rest if rest is Vector2 else Vector2.ZERO
		(b[0] as ShaderMaterial).set_shader_parameter("uv_offset", base + Vector2(fposmod(sc.x * _belt_t, 1.0), fposmod(sc.y * _belt_t, 1.0)))
	var cam := get_viewport().get_camera_3d()
	if cam and cam.far < _camera_far:
		cam.far = _camera_far


## The turbine fan by the exit (owner asked: "make the wind instantly blow
## the character off the edge, no jumping over"): while it blows, a player
## who comes into its air stream - at any height up to well over a double
## jump, so jumping doesn't clear it - is knocked flying backwards
## (PlayerKnockdown: no moving, jumping or dodging against it) and carried
## on the wind until they're past the walkway's edge; where the stream ends
## the wind lets go and they drop into the slime (not on out onto the
## column base further across). Each
## device does its own character. Robots keep the package's push.
@export var wind_blow_speed := 22.0
@export var wind_blow_up := 5.0
## While carried, the wind holds them up: rising at least this fast (m/s).
@export var wind_carry_lift := 1.5
## How far above / below the fan's centre the stream catches a player (m;
## the walkway is 3.8 m below it).
@export var wind_catch_above := 9.0
@export var wind_catch_below := 6.0
## How much of the blow speed is left as the stream lets go of a player.
@export var wind_release := 0.35
const WIND_STREAK := preload("res://scripts/vfx/wind_streak.gdshader")
## Players blown away (tests).
var winds_blown := 0
var _carried := {}  # players on the wind (PlayerController -> true)


func _physics_process(_delta: float) -> void:
	if effects == null:
		return
	var winds = effects.get("_winds")
	if not winds is Array or (winds as Array).is_empty():
		return
	var t: float = effects.get("_t")
	var carried := {}
	for wr in winds:
		if float(effects.call("_wind_strength", wr, t)) < 0.25:
			continue
		var w: Dictionary = wr[0]
		for n in get_tree().get_nodes_in_group(&"players"):
			var p := n as PlayerController
			if p == null or p.is_remote or p.knockdown == null or not in_wind(w, p.global_position):
				continue
			var d := Vector3(w["dir"][0], 0.0, w["dir"][2]).normalized()
			var kd := p.knockdown
			carried[p] = true
			if kd.phase != PlayerKnockdown.Phase.FLYING:
				kd.knock(p.global_position - d, wind_blow_speed, wind_blow_up)
				winds_blown += 1
			else:
				kd.horiz = Vector2(d.x, d.z) * wind_blow_speed
				p.velocity.y = maxf(p.velocity.y, wind_carry_lift)
	for p in _carried:
		if not carried.has(p) and is_instance_valid(p) and (p as PlayerController).knockdown.phase == PlayerKnockdown.Phase.FLYING:
			(p as PlayerController).knockdown.horiz *= wind_release
	_carried = carried


## `pos` (a player's feet) is in the fan `w`'s air stream: along its cone,
## within its widening radius across, and anywhere from the walkway to well
## above a jump.
func in_wind(w: Dictionary, pos: Vector3) -> bool:
	var o := Vector3(w["origin"][0], w["origin"][1], w["origin"][2])
	var d := Vector2(w["dir"][0], w["dir"][2]).normalized()
	var rel := pos - o
	var rh := Vector2(rel.x, rel.z)
	var along := rh.dot(d)
	if along < -0.5 or along > float(w["length"]):
		return false
	if rel.y > wind_catch_above or rel.y < -wind_catch_below:
		return false
	return (rh - d * along).length() < float(w["radius"]) + float(w["spread"]) * maxf(along, 0.0) + 0.4


## The fan's streaks as lines along the wind (wind_streak.gdshader).
func _wind_streaks() -> void:
	var winds = effects.get("_winds") if effects else null
	if not winds is Array:
		return
	for wr in winds:
		var pr := wr[3] as CPUParticles3D
		var qm := pr.mesh as QuadMesh if pr else null
		if qm == null:
			continue
		var old := qm.material as StandardMaterial3D
		var sm := ShaderMaterial.new()
		sm.shader = WIND_STREAK
		if old:
			sm.set_shader_parameter("color", old.albedo_color)
		qm.material = sm


## In the slime or off the level: a player back to their spawn, a robot dies.
func _on_fell(body: Node3D) -> void:
	if body is PlayerController and (body as PlayerController).is_remote:
		return
	if body is PlayerController:
		(body as PlayerController).respawn()
	elif (body is RobotEnemy or body is RobotBoss) and body.alive:
		body.apply_damage(DamageInfo.make(1.0e6, DamageInfo.Type.ENERGY, body.global_position, Vector3.DOWN, 0.0))


## The exit door: part 3 isn't made yet.
func _on_level_exit(target: String, body: Node) -> void:
	level_exit_entered.emit(target, body)
	if body is PlayerController and hud and not _exit_shown:
		_exit_shown = true
		hud.banner("TOXIC WORKS - EXIT", "PART 3 COMING SOON")
		get_tree().create_timer(6.0).timeout.connect(func() -> void: _exit_shown = false)
