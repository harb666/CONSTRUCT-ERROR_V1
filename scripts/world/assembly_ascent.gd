class_name AssemblyAscent
extends Node3D
## Assembly Ascent (made by image-to-level as "assembly_ascent": level 1,
## part 3 of 3 - "Map 3"; owner asked to import it): the generator's
## game-ready package from res://levels/assembly_ascent/ (copied unchanged
## from its exports/), put together like the Toxic Works (ToxicWorks):
##   - mobile/level_mobile.glb, background_mobile.glb and collision.glb;
##   - the package's apply_mobile.gd (visibility ranges, hazard and spike
##     volumes, gates, terminals, the exit trigger) and apply_effects.gd
##     (spinner tower, saws, spike press, conveyor ramps, floating and
##     sinking platforms, the pad lift, the rising arena, the flying jet
##     screen, the boss lift, steam, the specimen in her vat ...);
##   - the map maker preview's look (SkyforgePreviewLook with this level's
##     own sky lighting, sky/ibl_atlas.png baked from its panorama by
##     tools/bake_skyforge_ibl.py).
## The squad comes out of the black hallway at the entrance (from the Toxic
## Works' exit). The level's own gameplay (owner's map maker):
##   - three fights (collision.json "encounters"), each starting the first
##     time a player steps onto its deck (the robot yard's ring, the upper
##     deck, the arena that rises in front of the overlook) - a WaveDirector
##     each; clearing the upper deck's opens the exit's laser gate;
##   - on the arena the jet screen flies over; its big red button (walk up
##     to it) opens the yard's laser gate;
##   - the boss lift: the first time a player steps onto the showcase deck
##     it comes down its shaft with the mini boss (the robot boss) on it;
##     when the boss dies the conveyor ramps (faster than a sprint) spin
##     down and stop, so they can be climbed to the exit;
##   - slime, spikes, saws, the spinner, the press or falling off sends a
##     player back to the spawn one health bar down and kills a robot; the
##     exit leads to level 2, not made yet.

signal level_exit_entered(target: String, body: Node)

const DIR := "res://levels/assembly_ascent"
## Loaded when the level starts (not preloaded: see SkyforgeArena).
const LEVEL := "res://levels/assembly_ascent/mobile/level_mobile.glb"
const BACKGROUND := "res://levels/assembly_ascent/mobile/background_mobile.glb"
const COLLISION := "res://levels/assembly_ascent/mobile/collision.glb"
const APPLY_MOBILE := preload("res://levels/assembly_ascent/mobile/apply_mobile.gd")
const APPLY_EFFECTS := preload("res://levels/assembly_ascent/fx/godot/apply_effects.gd")
const SKY_SHADER := preload("res://scripts/world/preview_sky.gdshader")
const BOSS_SCENE := "res://scenes/enemies/robot_boss.tscn"

## Below this a player goes back to spawn and a robot dies (the slime is at
## 0-1 m, the floors at 6-25 m).
@export var kill_y := -4.0
@export var effects_quality := "balanced"
## Encounter id -> its WaveDirector (sibling node name).
const DIRECTORS := {"Yard_Waves": "YardWaves", "Deck_Waves": "DeckWaves", "Arena_Waves": "ArenaWaves"}
## How high above an encounter's deck its trigger reaches (m).
const TRIGGER_HEIGHT := 4.0

var level: Node3D
var background: Node3D
var collision: Node3D
var mobile: Node3D
var effects: Node3D
var out_of_bounds: Area3D
var env_data: Dictionary = {}
var col_data: Dictionary = {}
var look: SkyforgePreviewLook
var hud: LevelFlowHud
var gates_open: PackedStringArray = []
var gate_fx := {}
var terminals_used: PackedStringArray = []
## Encounters started (ids) and finished.
var encounters_started: PackedStringArray = []
var encounters_done: PackedStringArray = []
var encounter_triggers: Array[Area3D] = []
## The mini boss once it's down from its lift, and whether it's beaten.
var boss: RobotBoss
var boss_beaten := false
var _exit_shown := false
var _camera_far := 800.0


func _ready() -> void:
	env_data = _json(DIR + "/environment.json")
	col_data = _json(DIR + "/mobile/collision.json")
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
	effects.connect(&"boss_lift_landed", _on_boss_lift_landed)
	look = SkyforgePreviewLook.new()
	look.name = "PreviewLook"
	add_child(look)
	look.setup(env_data, load(DIR + "/sky/ibl_atlas.png"))
	look.apply(level, _flows())
	look.apply(background)
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
	_connect_hazards.call_deferred()
	_connect_terminals.call_deferred()
	_build_encounters.call_deferred()
	var ui := get_parent().get_node_or_null(^"UI") if get_parent() else null
	if ui:
		hud = LevelFlowHud.new()
		hud.name = "LevelFlowHud"
		ui.add_child(hud)
		ui.move_child(hud, 0)


# --- Hazards --------------------------------------------------------------

## Slime, spike boxes, saws, the spinner, the press: the package's hazard
## areas (group "hazard"); some (the moving ones) are made later, so this
## also runs each second.
func _connect_hazards() -> void:
	for a in get_tree().get_nodes_in_group(&"hazard"):
		var area := a as Area3D
		if area and is_ancestor_of(area) and not area.has_meta(&"hazard_hooked"):
			area.set_meta(&"hazard_hooked", true)
			area.collision_mask = 0xFFFFFFFF
			area.body_entered.connect(_on_hazard.bind(area))


var _hazard_t := 0.0


## Into the slime a player makes a splash and sinks in first; the rest
## (spikes, blades, the press) send them straight back.
func _on_hazard(body: Node3D, area: Area3D) -> void:
	if body is PlayerController and _is_slime(area):
		var p := body as PlayerController
		var top := _area_top(area, p.global_position.y)
		SlimeSplash.spawn(get_tree(), Vector3(p.global_position.x, top, p.global_position.z))
		if not p.is_remote:
			p.fell(top)
		return
	_on_fell(body)


func _is_slime(area: Area3D) -> bool:
	var n := String(area.name)
	return n.begins_with("HazardFluid") or n.contains("Slime")


func _area_top(area: Area3D, at_y: float) -> float:
	for cs: CollisionShape3D in area.find_children("*", "CollisionShape3D", false, false):
		var bx := cs.shape as BoxShape3D
		if bx:
			return minf(cs.global_position.y + bx.size.y * 0.5, at_y)
	return at_y


## A player back to their spawn one health bar down (PlayerController.fell),
## a robot dies.
func _on_fell(body: Node3D) -> void:
	if body is PlayerController and (body as PlayerController).is_remote:
		return
	if body is PlayerController:
		(body as PlayerController).fell()
	elif (body is RobotEnemy or body is RobotBoss) and body.alive:
		body.apply_damage(DamageInfo.make(1.0e6, DamageInfo.Type.ENERGY, body.global_position, Vector3.DOWN, 0.0))


# --- Encounters -----------------------------------------------------------

## Each fight (collision.json "encounters"): a trigger area over its deck
## ("enter:<deck>": the deck's floor collider) starts its WaveDirector the
## first time a player steps in.
func _build_encounters() -> void:
	var main := get_parent()
	if main == null:
		return
	for enc in col_data.get("encounters", []):
		var id := String(enc["id"])
		var d := main.get_node_or_null(NodePath(String(DIRECTORS.get(id, "")))) as WaveDirector
		if d == null:
			continue
		d.wave_started.connect(_on_wave_started.bind(id))
		d.wave_cleared.connect(_on_wave_cleared.bind(id))
		d.all_cleared.connect(_on_encounter_done.bind(id))
		var trig := String(enc.get("trigger", ""))
		var area := _deck_area(trig.trim_prefix("enter:"))
		if area == null:
			continue
		area.name = id + "_Trigger"
		add_child(area)
		encounter_triggers.append(area)
		area.body_entered.connect(func(b: Node3D) -> void:
			if b is PlayerController and Net.is_authority():
				start_encounter(id))


## An Area3D over a deck's floor (its floor collider: "<deck>_Floor" or
## "<deck>"), from its top up `TRIGGER_HEIGHT`.
func _deck_area(deck: String) -> Area3D:
	for c in col_data.get("colliders", []):
		var n := String(c.get("name", ""))
		if n != deck + "_Floor" and n != deck:
			continue
		var a := Area3D.new()
		a.monitorable = false
		a.collision_mask = 0xFFFFFFFF
		var cs := CollisionShape3D.new()
		var ctr: Array = c["center"]
		var top := float(ctr[1])
		if c.get("shape") == "cylinder":
			var cy := CylinderShape3D.new()
			cy.radius = float(c["radius"])
			cy.height = TRIGGER_HEIGHT
			cs.shape = cy
			top += float(c.get("height", 0.0)) * 0.5
		else:
			var b := BoxShape3D.new()
			var sz: Array = c["size"]
			b.size = Vector3(float(sz[0]), TRIGGER_HEIGHT, float(sz[2]))
			cs.shape = b
			top += float(sz[1]) * 0.5
			var r: Array = c.get("rotation", [0, 0, 0, 1])
			cs.basis = Basis(Quaternion(float(r[0]), float(r[1]), float(r[2]), float(r[3])))
		cs.position = Vector3(float(ctr[0]), top + TRIGGER_HEIGHT * 0.5, float(ctr[2]))
		a.add_child(cs)
		return a
	# A deck with no floor collider (the arena: its tiles rise out of the
	# slime) is named by a trigger box elsewhere (the jet screen's / the boss
	# lift's {name, min, max, y}).
	for k in ["jets", "boss_lifts"]:
		for j in col_data.get(k, []):
			var tr: Dictionary = j.get("trigger", {})
			if String(tr.get("name", "")) != deck:
				continue
			var lo: Array = tr["min"]
			var hi: Array = tr["max"]
			var a := Area3D.new()
			a.monitorable = false
			a.collision_mask = 0xFFFFFFFF
			var cs := CollisionShape3D.new()
			var b := BoxShape3D.new()
			b.size = Vector3(float(hi[0]) - float(lo[0]), TRIGGER_HEIGHT, float(hi[1]) - float(lo[1]))
			cs.shape = b
			cs.position = Vector3((float(lo[0]) + float(hi[0])) * 0.5, float(tr["y"]) + TRIGGER_HEIGHT * 0.5, (float(lo[1]) + float(hi[1])) * 0.5)
			a.add_child(cs)
			return a
	return null


func start_encounter(id: String) -> void:
	if encounters_started.has(id):
		return
	encounters_started.append(id)
	var d := get_parent().get_node_or_null(NodePath(String(DIRECTORS.get(id, "")))) as WaveDirector
	if d:
		d.begin()


func _on_wave_started(index: int, total: int, id: String) -> void:
	Net.world_event(self, &"wave_started", [index, total, id])
	if hud:
		hud.banner("WAVE %d / %d" % [index, total], String(ENCOUNTER_TITLES.get(id, "ROBOTS INBOUND")) if index == 1 else "ENEMIES INBOUND")


const ENCOUNTER_TITLES := {"Yard_Waves": "THE ROBOT YARD", "Deck_Waves": "THE UPPER DECK", "Arena_Waves": "THE ARENA"}


func _on_wave_cleared(index: int, total: int, id: String) -> void:
	Net.world_event(self, &"wave_cleared", [index, total, id])
	if hud and index < total:
		hud.banner("WAVE CLEARED", "NEXT WAVE INCOMING")


## A fight won: the gates it opens open (the upper deck's: the exit).
func _on_encounter_done(id: String) -> void:
	if encounters_done.has(id):
		return
	encounters_done.append(id)
	Net.world_event(self, &"encounter_done", [id])
	var opened := false
	for g in col_data.get("gates", []):
		var on: Dictionary = g.get("opens_on", {})
		if String(on.get("type", "")) == "waves_cleared" and String(on.get("encounter", "")) == id:
			open_gate(String(g["id"]))
			opened = true
	if hud:
		hud.banner("AREA CLEARED", "THE EXIT GATE IS OPEN" if opened else String(ENCOUNTER_TITLES.get(id, "")) + " IS CLEAR")


func open_gate(gate_id: String) -> void:
	if gates_open.has(gate_id):
		return
	gates_open.append(gate_id)
	if gate_fx.has(gate_id) and is_instance_valid(gate_fx[gate_id]):
		(gate_fx[gate_id] as LaserGateFX).open()
	mobile.call(&"open_gate", gate_id)


func _on_gate_opened(_gate_id: String) -> void:
	pass


## The laser gates' look (LaserGateFX, as in the Toxic Works): over each
## gate's beams that the level has as one mesh ("<group>__laser").
func _build_gate_fx() -> void:
	for g in col_data.get("gates", []):
		var laser := level.find_child(String(g["group"]) + "__laser", true, false) as MeshInstance3D
		if laser == null:
			continue
		var fx := LaserGateFX.new()
		fx.name = String(g["id"]) + "_FX"
		add_child(fx)
		fx.build(laser)
		gate_fx[String(g["id"])] = fx


# --- The jet screen's button ----------------------------------------------

## The big red button on the jet screen (collision.json "terminals"): live
## once the screen has flown over to the arena (apply_mobile keeps its area
## out of group "terminal" until then); walking up to it presses it - the
## yard's laser gate opens and the screen flies home.
var _terminal_areas: Array[Area3D] = []


func _connect_terminals() -> void:
	for a in find_children("*", "Area3D", true, false):
		var area := a as Area3D
		if area.has_meta(&"terminal_id") and not _terminal_areas.has(area):
			area.collision_mask = 0xFFFFFFFF
			area.monitorable = false
			_terminal_areas.append(area)


func _check_terminals() -> void:
	if not Net.is_authority():
		return
	for area in _terminal_areas:
		if not is_instance_valid(area) or not area.is_in_group(&"terminal"):
			continue
		var id := String(area.get_meta(&"terminal_id", ""))
		if terminals_used.has(id):
			continue
		for b in area.get_overlapping_bodies():
			if b is PlayerController:
				use_terminal(id)
				break


func use_terminal(id: String) -> void:
	if terminals_used.has(id):
		return
	terminals_used.append(id)
	Net.world_event(self, &"terminal", [id])
	for t in col_data.get("terminals", []):
		if String(t["id"]) == id:
			for gid in t.get("activates", []):
				if gate_fx.has(String(gid)) and is_instance_valid(gate_fx[String(gid)]):
					(gate_fx[String(gid)] as LaserGateFX).open()
				if not gates_open.has(String(gid)):
					gates_open.append(String(gid))
	mobile.call(&"activate_terminal", id)
	if hud:
		hud.banner("BUTTON PRESSED", "THE YARD GATE IS OPEN")


# --- The mini boss ----------------------------------------------------------

## The boss lift has landed on its dais (apply_effects.gd): the mini boss -
## the robot boss - stands on it. When it dies the conveyor ramps stop.
func _on_boss_lift_landed(_id: String, spawn: Vector3) -> void:
	if hud:
		hud.banner("WARNING", "MINI BOSS")
	if not Net.is_authority() or boss != null:
		return
	var scene := load(BOSS_SCENE) as PackedScene
	if scene == null:
		return
	boss = scene.instantiate() as RobotBoss
	boss.name = "MiniBoss"
	boss.respawn_time = -1.0  # once beaten it stays down
	var holder := get_parent().get_node_or_null(^"BossHolder")
	if holder == null:
		holder = get_parent()
	holder.add_child(boss)
	boss.global_position = spawn + Vector3.UP * 0.05
	# Facing the way down the showcase deck (towards the players' side).
	boss.look_at(spawn + Vector3(0, 0, 10), Vector3.UP)
	Net.robot_spawned(boss, holder)
	boss.died.connect(_on_boss_died, CONNECT_ONE_SHOT)


func _on_boss_died(_info: DamageInfo = null) -> void:
	boss_defeated()


## The mini boss is down: the conveyors spin down and stop (apply_effects.gd
## boss_defeated); online everyone follows the host.
func boss_defeated() -> void:
	if boss_beaten:
		return
	boss_beaten = true
	Net.world_event(self, &"boss_defeated")
	effects.call(&"boss_defeated")
	if hud:
		hud.banner("MINI BOSS DESTROYED", "THE CONVEYORS ARE STOPPING")


# --- Exit -----------------------------------------------------------------

## The exit hallway: level 2 isn't made yet.
func _on_level_exit(target: String, body: Node) -> void:
	level_exit_entered.emit(target, body)
	if body is PlayerController and hud and not _exit_shown:
		_exit_shown = true
		hud.banner("ASSEMBLY ASCENT - EXIT", "LEVEL 2 COMING SOON")
		get_tree().create_timer(6.0).timeout.connect(func() -> void: _exit_shown = false)


# --- Every frame ------------------------------------------------------------

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and cam.far < _camera_far:
		cam.far = _camera_far
	_hazard_t += delta
	if _hazard_t > 1.0:
		_hazard_t = 0.0
		_connect_hazards()
		_connect_terminals()


func _physics_process(_delta: float) -> void:
	_check_terminals()


## The host's events, here too (online).
func net_event(kind: StringName, args: Array) -> void:
	match kind:
		&"wave_started":
			_on_wave_started(int(args[0]), int(args[1]), String(args[2]))
		&"wave_cleared":
			_on_wave_cleared(int(args[0]), int(args[1]), String(args[2]))
		&"encounter_done":
			_on_encounter_done(String(args[0]))
		&"terminal":
			use_terminal(String(args[0]))
		&"boss_defeated":
			boss_defeated()


# --- Set-up helpers (as ToxicWorks) ---------------------------------------

func _json(path: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


func _world_environment() -> WorldEnvironment:
	return get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment if get_parent() else null


## As ToxicWorks: the panorama as the sky (lights the players and robots),
## the level's own lighting and fog in its materials, the sun placed where
## the preview's is, giving players and robots their shadows (the level
## casts none: it's indoors).
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
