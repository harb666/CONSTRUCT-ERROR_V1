class_name SkyforgeArena
extends Node3D
## Skyforge Arena (made by image-to-level, the first part of the first
## level; owner asked): the generator's game-ready mobile package from
## res://levels/skyforge_arena/ (copied unchanged from its exports/) put
## together the way its IMPORT_GODOT.md describes:
##   - mobile/level_mobile.glb (the decks), mobile/background_mobile.glb
##     (distant scenery, no collision) and mobile/collision.glb (its
##     -colonly / -convcolonly nodes become StaticBody3Ds on import);
##   - the package's own scripts: apply_mobile.gd (visibility ranges, shadow
##     flags, the elevator-shaft level-exit trigger) and apply_effects.gd
##     (steam, sparks, pulsing lights, cloud layers / puffs, fly-by ships,
##     sky drift);
##   - the look of the map maker's PREVIEW (owner asked: exactly like the
##     map maker): SkyforgePreviewLook gives every level / background
##     material the preview's lighting, fog and sky reflections, and the sky
##     is the panorama mapped the preview's way (unfogged). Values from
##     environment.json (the package's environment.tres is empty).
## Falling off (below `kill_y`, the level's own design value) or into the
## elevator shaft in the hub sends a player back to their spawn; robots
## that fall die. The shaft's `level_exit_entered` is re-emitted for when a
## next level exists.

signal level_exit_entered(target: String, body: Node)

const DIR := "res://levels/skyforge_arena"
## Loaded when the level starts, not preloaded: the script stays cached
## after the level is gone (the hub lift), and preloads would keep the whole
## level's meshes and textures in memory with it.
const LEVEL := "res://levels/skyforge_arena/mobile/level_mobile.glb"
const BACKGROUND := "res://levels/skyforge_arena/mobile/background_mobile.glb"
const COLLISION := "res://levels/skyforge_arena/mobile/collision.glb"
const APPLY_MOBILE := preload("res://levels/skyforge_arena/mobile/apply_mobile.gd")
const SKY_SHADER := preload("res://scripts/world/preview_sky.gdshader")
const APPLY_EFFECTS := preload("res://levels/skyforge_arena/fx/godot/apply_effects.gd")

## Below this height a player goes back to spawn and a robot dies (the
## decks are at 37-43 m; level.json gameplay.design.kill_y).
@export var kill_y := 25.0
## Effect quality for apply_effects.gd ("balanced" = the package default).
@export var effects_quality := "balanced"

var level: Node3D
var background: Node3D
var collision: Node3D
var mobile: Node3D
var effects: Node3D
var out_of_bounds: Area3D
var env_data: Dictionary = {}
var look: SkyforgePreviewLook


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
	# The collision meshes are only for shapes: never drawn.
	for mi: MeshInstance3D in collision.find_children("*", "MeshInstance3D", true, false):
		mi.visible = false
	_open_shaft()
	mobile = APPLY_MOBILE.new()
	mobile.name = "ApplyMobile"
	mobile.set("manifest_path", DIR + "/mobile/mobile_manifest.json")
	mobile.set("level_root", level)
	add_child(mobile)
	mobile.connect(&"level_exit_entered", _on_level_exit)
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
	look.setup(env_data)
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


## The package exports every mesh collider as a convex hull ("-convcolonly")
## and its rim / ring as solid discs, so the hub's rings round the elevator
## shaft (floor, trim, body, underframe, the shaft's own liner, the rim and
## outer ring) filled the shaft with an invisible lid at floor level: the
## shaft couldn't be fallen into and the lift couldn't come up it. Those
## pieces get their exact shapes (collision.json's own triangles; the rims
## as rings round the shaft opening). Nothing else in the level changes.
const SHAFT_MESHES: Array[String] = ["Hub_Floor", "Hub_Trim", "Hub_Body", "Hub_Underframe", "Elevator_Liner"]
const SHAFT_RINGS: Array[String] = ["Elevator_Rim", "Elevator_OuterRing"]
const SHAFT_RADIUS := 5.5
var shaft_opened := 0


func _open_shaft() -> void:
	var data := _json(DIR + "/mobile/collision.json")
	for c in data.get("colliders", []):
		var nm := String(c.get("name", ""))
		var body := collision.find_child(nm, true, false) as StaticBody3D
		if body == null:
			continue
		var cs := body.find_children("*", "CollisionShape3D", true, false)
		if cs.is_empty():
			continue
		var node := cs[0] as CollisionShape3D
		var to_local := node.global_transform.affine_inverse()
		var faces := PackedVector3Array()
		if nm in SHAFT_MESHES and c.get("shape") == "mesh":
			var v: Array = c.get("vertices", [])
			for f in c.get("faces", []):
				for i in 3:
					var p: Array = v[int(f[i])]
					faces.append(to_local * Vector3(p[0], p[1], p[2]))
		elif nm in SHAFT_RINGS and c.get("shape") == "cylinder":
			var ctr: Array = c["center"]
			var h := float(c["height"]) * 0.5
			faces = _ring_faces(Vector3(ctr[0], ctr[1], ctr[2]), SHAFT_RADIUS, float(c["radius"]), h, to_local)
		else:
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		node.shape = shape
		shaft_opened += 1


## A flat ring (top, bottom, inner and outer walls) as triangles.
func _ring_faces(c: Vector3, r_in: float, r_out: float, h: float, xf: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := 32
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		for y: float in [h, -h]:
			var up: Vector3 = Vector3.UP * y
			out.append_array([xf * (c + d0 * r_in + up), xf * (c + d0 * r_out + up), xf * (c + d1 * r_out + up)])
			out.append_array([xf * (c + d0 * r_in + up), xf * (c + d1 * r_out + up), xf * (c + d1 * r_in + up)])
		for r: float in [r_in, r_out]:
			out.append_array([xf * (c + d0 * r + Vector3.UP * h), xf * (c + d0 * r - Vector3.UP * h), xf * (c + d1 * r - Vector3.UP * h)])
			out.append_array([xf * (c + d0 * r + Vector3.UP * h), xf * (c + d1 * r - Vector3.UP * h), xf * (c + d1 * r + Vector3.UP * h)])
	return out


func _json(path: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


func _world_environment() -> WorldEnvironment:
	return get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment if get_parent() else null


func _col(a: Array) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2]))


## The scene around the level, as in the preview: the sunset panorama as
## the sky (mapped the preview's way, no fog on it, no tonemapping or colour
## adjustments, no glow). The level's own fog / lighting is in its
## materials (SkyforgePreviewLook); the WorldEnvironment's sky light and
## the sun node (placed where the preview's sun is) light the players and
## robots and give them their shadows.
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
		sun.global_transform = Transform3D(Basis.looking_at(-to_sun), Vector3(0, 60, 0))
		sun.light_color = Color(s["color"][0], s["color"][1], s["color"][2]).linear_to_srgb()
		sun.light_energy = 1.2
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 40.0
	_camera_far = float(env_data.get("camera", {}).get("far", 800.0))


## Scrolling liquids (effects "liquid_flow"): mesh -> [flow dir, speed /
## tile, wobble], as the preview moves them.
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


## The level's distant scenery (mountains, spire city) is hundreds of
## metres out: the cameras see that far here (the game's default is 200 m).
func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and cam.far < _camera_far:
		cam.far = _camera_far


var _camera_far := 800.0


## Fell off the decks: a player goes back to their spawn, a robot dies.
func _on_fell(body: Node3D) -> void:
	if body is PlayerController and (body as PlayerController).is_remote:
		return
	if body is PlayerController:
		(body as PlayerController).respawn()
	elif (body is RobotEnemy or body is RobotBoss) and body.alive:
		body.apply_damage(DamageInfo.make(1.0e6, DamageInfo.Type.ENERGY, body.global_position, Vector3.DOWN, 0.0))


## Into the elevator shaft in the hub while the lift is down at the bottom:
## a fall (back to spawn). Once the lift is up or riding down (ElevatorLift)
## the shaft is the way on, not a fall.
func _on_level_exit(target: String, body: Node) -> void:
	level_exit_entered.emit(target, body)
	var lift := get_tree().get_first_node_in_group(&"elevator_lift") as ElevatorLift
	if lift and lift.state != ElevatorLift.State.DOWN:
		return
	if body is Node3D:
		_on_fell(body as Node3D)


## Robot spots for the stress test: on the decks.
func stress_spawn_points(n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in [Vector3(-10, 40, 6), Vector3(10, 40, 6), Vector3(-10, 40, -8), Vector3(10, 40, -8), Vector3(0, 40, -12),
			Vector3(42, 40, -6), Vector3(-36, 40, -5), Vector3(2.5, 40, -33), Vector3(-38, 37, -32), Vector3(37, 37, 33), Vector3(-31, 37, 36)]:
		out.append(p)
	out.resize(mini(n, out.size()))
	return out
