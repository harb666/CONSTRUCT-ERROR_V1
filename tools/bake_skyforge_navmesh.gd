extends SceneTree
## Bakes Skyforge's navigation mesh (where robots can walk) from the level's
## collision and saves it: levels/skyforge_arena/gameplay/navmesh.res. The
## robots hunting the players there follow paths over it (WaveDirector
## hunt_players), so they find the way round walls and down the ramps
## instead of getting stuck. Run after the level's collision changes:
##   godot --headless --path . -s tools/bake_skyforge_navmesh.gd
## The Toxic Works' (its hall waves hunt the same way):
##   godot --headless --path . -s tools/bake_skyforge_navmesh.gd -- --level=works

const LEVELS := {
	"skyforge": ["res://scenes/skyforge_arena.tscn", "SkyforgeArena/Collision", "res://levels/skyforge_arena/gameplay/navmesh.res"],
	"works": ["res://scenes/toxic_works.tscn", "ToxicWorks/Collision", "res://levels/slime_arena/gameplay/navmesh.res"],
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var which := "skyforge"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			which = a.trim_prefix("--level=")
	var L: Array = LEVELS[which]
	var OUT: String = L[2]
	var arena: Node3D = load(L[0]).instantiate()
	arena.set(&"front_end_mode", 0)
	root.add_child(arena)
	for i in 5:
		await physics_frame
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.75
	nm.agent_height = 3.4  # skirmishers stand 3.3 m tall (twice size)
	nm.agent_max_climb = 0.6
	nm.agent_max_slope = 50.0
	nm.region_min_size = 4.0
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, arena.get_node(L[1]))
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	var e := ResourceSaver.save(nm, OUT)
	print("NAVMESH polygons %d vertices %d -> %s (%s)" % [nm.get_polygon_count(), nm.vertices.size(), OUT, error_string(e)])
	quit()
