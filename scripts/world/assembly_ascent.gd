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
##     each (clearing the upper deck's would open the exit's laser gate -
##     it's open by then: both gates open with the mini boss's death);
##   - on the arena the jet screen flies over; its big red button (walk up
##     to it) slows the saws over the yard bridge (owner asked; the map
##     maker had it open the yard's laser gate);
##   - the boss lift: the first time a player steps onto the showcase deck
##     it comes down its shaft with the mini boss (the robot boss) standing
##     on it (owner asked: "make sure the mini boss comes down on lift ...
##     make it epic"): it's carried down on the car, a shot from low on the
##     deck shows it coming out of the roof (BossIntroCamera), and it lands
##     with a stomp; when the boss dies both laser gates open (owner asked)
##     and the conveyor ramps (faster than a sprint) spin down and stop, so
##     they can be climbed to the exit;
##   - flyers through the roof (owner asked: "2-3 flying robots that
##     continue to come through the roofs"): from the first fight on, Neon
##     Sentinels dive in through the round lattice skylight (or, once the
##     boss lift is down, its open shaft) and hunt the squad - 2 at a time,
##     3 once the mini boss has landed, another `sky_respawn` s after each
##     one dies (routes: FlightNav over gameplay/flight_graph.res);
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
const SENTINEL_SCENE := "res://scenes/enemies/robot_sentinel.tscn"

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
## The boss lift has started down / landed (each device runs its own).
var boss_lift_started := false
var boss_lift_down := false
## The boss is being carried down on the car (its own walking held).
var boss_riding := false
var _boss_detect := 45.0
var intro_camera: BossIntroCamera
## The boss intro shot is only for players this near the shaft (m).
@export var intro_within := 45.0

## Flyers through the roof (owner asked): how many at a time, before and
## after the mini boss has landed, the first one's delay after the first
## fight starts, the wait after one dies, and their dive in (m/s).
@export var sky_hunters := 2
@export var sky_hunters_late := 3
@export var sky_first_delay := 3.0
@export var sky_respawn := 6.0
@export var sky_dive_speed := 15.0
## The round lattice skylight over the conveyors (its opening's centre -
## ~18 m across - and the ring flyers come in within: clear of its edge and
## the lattice's middle hub), the
## boss shaft (open once the lift is down), where they start (above the
## roof, 34.5-35.5 m) and how low they dive.
const DOME := Vector3(15.0, 0.0, -34.0)
const DOME_RING := Vector2(4.0, 13.0)
const SHAFT := Vector3(-30.0, 0.0, -39.5)
const SKY_FROM_Y := 52.0
const SKY_TO_Y := 24.0
var sky: Array[RobotSentinel] = []
var sky_spawned := 0
var _sky_on := false
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
	# The mini boss is warmed up with the robots (its shaders made under the
	# level's cover, not as the lift starts).
	Vfx.level_robots = [BOSS_SCENE]
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
	_open_roof()
	_connect_hazards.call_deferred()
	_connect_terminals.call_deferred()
	_build_encounters.call_deferred()
	var ui := get_parent().get_node_or_null(^"UI") if get_parent() else null
	if ui:
		hud = LevelFlowHud.new()
		hud.name = "LevelFlowHud"
		ui.add_child(hud)
		ui.move_child(hud, 0)


## The roof's colliders came in as convex hulls, which close its openings
## - the round lattice skylight and the boss shaft (the flyers through the
## roof couldn't get in): they get their exact shapes (collision.json's own
## triangles), as in the Toxic Works. Nothing else changes.
const ROOF_SLABS := ["Ceiling_Slab", "Ceiling_BossShaft_Slab"]
var roof_opened := 0


func _open_roof() -> void:
	for c in col_data.get("colliders", []):
		var nm := String(c.get("name", ""))
		if not nm in ROOF_SLABS or c.get("shape") != "mesh":
			continue
		var body := collision.find_child(nm, true, false) as StaticBody3D
		var shapes := body.find_children("*", "CollisionShape3D", true, false) if body else []
		if shapes.is_empty():
			continue
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
		roof_opened += 1


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
	start_sky()


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


func _on_gate_opened(gate_id: String) -> void:
	var flight := get_parent().get_node_or_null(^"FlightNav") as FlightNav
	if flight:
		flight.open_gate(gate_id)


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
	# (The map maker had it open the yard's laser gate: the gates open when
	# the mini boss dies now - owner asked. Its "activates" is emptied so the
	# package's terminal handler - the jet screen flying home - opens none.)
	var tms = mobile.get(&"_terminals")
	if tms is Dictionary and (tms as Dictionary).has(id):
		tms[id]["activates"] = []
	mobile.call(&"activate_terminal", id)
	slow_saws()
	if hud:
		hud.banner("BUTTON PRESSED", "THE SAWS ARE SLOWING DOWN")


## The jet screen's button (owner asked: "just to slow down the saws so the
## player can jump across in time"): the saws over the yard bridge ease down
## to `saw_slow` of their speed, for good.
@export var saw_slow := 0.4
var saws_slowed := false


func slow_saws() -> void:
	if saws_slowed:
		return
	saws_slowed = true
	var tw := create_tween()
	tw.tween_property(effects, ^"saw_speed", saw_slow, 1.5).set_trans(Tween.TRANS_SINE)


# --- The mini boss ----------------------------------------------------------

## The boss lift (apply_effects.gd's, one): its state there.
func _boss_lift() -> Dictionary:
	var lifts = effects.get(&"_boss_lifts") if effects else null
	return lifts[0] if lifts is Array and not (lifts as Array).is_empty() else {}


## How far down the shaft the car is (0 parked up, 1 landed).
func boss_lift_progress() -> float:
	var B := _boss_lift()
	if B.is_empty() or String(B["phase"]) == "top":
		return 0.0
	var d: Dictionary = B["d"]
	var e := float(effects.get(&"_t")) - float(B["t0"]) - float(d["delay"]) - float(d["warn"])
	return clampf(e / float(d["duration"]), 0.0, 1.0)


## The top of the car's deck (where the boss stands), now.
func boss_car_top() -> Vector3:
	var B := _boss_lift()
	if B.is_empty():
		return SHAFT
	return (B["body"] as Node3D).global_position + Vector3.UP * 0.7


## The lift's under way (a player stepped onto the showcase deck): the
## mini boss steps onto the car up the shaft and rides it down, and the
## players near get the intro shot.
func _on_boss_lift_started() -> void:
	boss_lift_started = true
	if hud:
		hud.banner("WARNING", "HEAVY UNIT DESCENDING")
	if Net.is_authority() and boss == null:
		_spawn_boss(boss_car_top())
	boss_riding = true
	var me := _local_player()
	var B := _boss_lift()
	if me and not B.is_empty():
		var c: Array = B["d"]["center"]
		var ctr := Vector3(float(c[0]), float(B["d"]["deck_y"]), float(c[2]))
		if Vector2(me.global_position.x - ctr.x, me.global_position.z - ctr.z).length() < intro_within:
			intro_camera = BossIntroCamera.new()
			intro_camera.name = "BossIntroCamera"
			intro_camera.level = self
			intro_camera.center = ctr
			# (Starts as the car is about to come out of the roof.)
			_intro_pending = true


var _intro_pending := false


func _spawn_boss(at: Vector3) -> void:
	var scene := load(BOSS_SCENE) as PackedScene
	if scene == null:
		return
	boss = scene.instantiate() as RobotBoss
	boss.name = "MiniBoss"
	boss.respawn_time = -1.0  # once beaten it stays down
	# Facing the nearest player (down on the deck).
	var yaw := 0.0
	var near := _nearest_player(at)
	if near:
		var off := near.global_position - at
		yaw = atan2(off.x, off.z)
	boss.transform = Transform3D(Basis(Vector3.UP, yaw), at + Vector3.UP * 0.05)
	var holder := get_parent().get_node_or_null(^"BossHolder")
	if holder == null:
		holder = get_parent()
	holder.add_child(boss)
	Net.robot_spawned(boss, holder)
	boss.died.connect(_on_boss_died, CONNECT_ONE_SHOT)


## The boss here (the host's, or this device's copy of it).
func _the_boss() -> RobotBoss:
	if boss and is_instance_valid(boss):
		return boss
	var holder := get_parent().get_node_or_null(^"BossHolder") if get_parent() else null
	if holder:
		for c in holder.get_children():
			if c is RobotBoss:
				return c
	return null


## Carried down on the car: stands on its deck, not fighting yet.
func _carry_boss() -> void:
	var b := _the_boss()
	if b == null or not b.alive:
		return
	if b.detect_range > 0.0:
		_boss_detect = b.detect_range
		b.detect_range = 0.0
	var top := boss_car_top()
	var p := b.global_position
	b.global_position = Vector3(p.x, top.y + 0.05, p.z)
	b.ground_y = top.y
	b.linear_velocity = Vector3.ZERO


## The boss lift has landed on its dais (apply_effects.gd): the mini boss
## steps off fighting, with a stomp (its shockwave); the intro shot holds
## on it, then hands back.
func _on_boss_lift_landed(_id: String, spawn: Vector3) -> void:
	boss_lift_down = true
	boss_riding = false
	if hud:
		hud.banner("MINI BOSS", "DESTROY IT TO STOP THE CONVEYORS")
	if intro_camera and is_instance_valid(intro_camera):
		intro_camera.landed()
	var b := _the_boss()
	if b:
		b.detect_range = _boss_detect
		b.set(&"_spawn_xf", b.global_transform)  # holds its ground here
		if Net.is_authority() and b.alive:
			b.call(&"_start_stomp")
	elif Net.is_authority() and boss == null:
		# (The lift ran without the boss aboard - e.g. a test started it.)
		_spawn_boss(spawn)
		boss.set(&"_spawn_xf", boss.global_transform)
	# One more flyer through the roof from now on.
	if Net.is_authority() and _sky_on:
		get_tree().create_timer(4.0, false).timeout.connect(_spawn_sky_hunter)


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
	# The laser gates open with it (owner asked): the yard's and the exit's.
	for g in col_data.get("gates", []):
		open_gate(String(g["id"]))
	if hud:
		hud.banner("MINI BOSS DESTROYED", "LASER GATES OPEN - CONVEYORS STOPPING")


# --- Flyers through the roof -------------------------------------------

## From the first fight on (owner asked: "2-3 flying robots that continue
## to come through the roofs").
func start_sky() -> void:
	if _sky_on or not Net.is_authority():
		return
	_sky_on = true
	for i in sky_hunters:
		get_tree().create_timer(sky_first_delay + 2.5 * i, false).timeout.connect(_spawn_sky_hunter)


func sky_wanted() -> int:
	return sky_hunters_late if boss_lift_down else sky_hunters


## A Neon Sentinel diving in through a roof opening (the one nearest the
## squad, now and then the other), hunting them wherever they are.
func _spawn_sky_hunter() -> void:
	if not is_inside_tree() or not Net.is_authority():
		return
	sky = sky.filter(func(r: RobotSentinel) -> bool: return is_instance_valid(r) and r.alive)
	if sky.size() >= sky_wanted():
		return
	var way := sky_entry()
	var from: Vector3 = way[0]
	var to: Vector3 = way[1]
	var scene := load(SENTINEL_SCENE) as PackedScene
	var r := scene.instantiate() as RobotSentinel
	sky_spawned += 1
	r.name = "SkyHunter%d" % sky_spawned
	r.respawn_time = -1.0
	r.patrol_distance = 0.0
	r.entry_speed = sky_dive_speed
	var yaw := 0.0
	var near := _nearest_player(to)
	if near:
		var off := near.global_position - to
		yaw = atan2(off.x, off.z)
	r.transform = Transform3D(Basis(Vector3.UP, yaw), from)
	var holder := get_parent().get_node_or_null(^"Targets")
	if holder == null:
		holder = get_parent()
	holder.add_child(r)
	# Hunting: wherever the squad is, routed through the open air.
	r.detect_range = 400.0
	r.lose_range = 400.0
	r.hunt_nav = true
	r.fly_in(to)
	Net.robot_spawned(r, holder)
	sky.append(r)
	r.died.connect(func(_info: DamageInfo) -> void:
		if is_inside_tree():
			get_tree().create_timer(sky_respawn, false).timeout.connect(_spawn_sky_hunter), CONNECT_ONE_SHOT)
	if sky_spawned == 1:
		_sky_banner()
		Net.world_event(self, &"sky")
	DebugHud.note("sky hunter %d" % sky_spawned)


func _sky_banner() -> void:
	if hud:
		hud.banner("INCOMING", "FLYERS THROUGH THE ROOF")


## [from, to]: above a roof opening and down through it - a spot in the
## skylight's ring (clear of its edge and hub), or the
## boss shaft once its lift is down; the one nearer the squad, a third of
## the time the other.
func sky_entry() -> Array:
	var spots: Array[Vector3] = []
	var a := randf() * TAU
	var r := randf_range(DOME_RING.x, DOME_RING.y)
	spots.append(DOME + Vector3(cos(a), 0.0, sin(a)) * r)
	if boss_lift_down:
		spots.append(SHAFT + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0)))
	var squad := Vector3.ZERO
	var n := 0
	for pl in get_tree().get_nodes_in_group(&"players"):
		squad += (pl as Node3D).global_position
		n += 1
	if n > 0:
		squad /= n
	spots.sort_custom(func(x: Vector3, y: Vector3) -> bool:
		return Vector2(x.x - squad.x, x.z - squad.z).length() < Vector2(y.x - squad.x, y.z - squad.z).length())
	var pick := spots[0] if spots.size() == 1 or randf() > 0.33 else spots[1]
	return [Vector3(pick.x, SKY_FROM_Y, pick.z), Vector3(pick.x, SKY_TO_Y if pick.distance_to(SHAFT) > 5.0 else 20.0, pick.z)]


func _nearest_player(at: Vector3) -> Node3D:
	var best: Node3D = null
	for pl in get_tree().get_nodes_in_group(&"players"):
		var n := pl as Node3D
		if n and (best == null or n.global_position.distance_to(at) < best.global_position.distance_to(at)):
			best = n
	return best


func _local_player() -> PlayerController:
	for pl in get_tree().get_nodes_in_group(&"local_player"):
		if pl is PlayerController:
			return pl
	return null


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
	_watch_boss_lift()


func _watch_boss_lift() -> void:
	var B := _boss_lift()
	if B.is_empty():
		return
	if not boss_lift_started and String(B["phase"]) != "top":
		_on_boss_lift_started()
	if boss_riding:
		_carry_boss()
	# The intro shot starts as the car's about to come out of the roof.
	if _intro_pending and boss_lift_progress() >= 0.2:
		_intro_pending = false
		if intro_camera and is_instance_valid(intro_camera):
			get_parent().add_child(intro_camera)


func _exit_tree() -> void:
	Vfx.level_robots = []


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
		&"sky":
			_sky_banner()


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
