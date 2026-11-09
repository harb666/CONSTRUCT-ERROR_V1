extends SceneTree
## Run by the smoke test in a fresh process: opens the menus' own scene (the
## game's start) and prints which heavy models are in memory. The menus must
## not load the robots', the boss's or the weapons' models (owner: "WebGL
## context lost" on the character select; they were all loaded from the
## title on).
const HEAVY := [
	"res://assets/enemies/robot_boss/robot_boss.glb",
	"res://assets/characters/robot/robot_enemy.glb",
	"res://assets/enemies/robot_skirmisher/robot_skirmisher.glb",
	"res://assets/enemies/sentinel/sentinel.glb",
	"res://assets/weapons/rocket_launcher/rocket_launcher.glb",
	"res://assets/vfx/supernova/supernova_finish_baked.scn",
	"res://assets/audio/music/level_1_music.ogg",
	"res://assets/weapons/black_hole_generator/black_hole_generator.glb",
	"res://assets/weapons/frost_byte/frost_byte.glb",
	"res://assets/weapons/machine_gun/machine_gun.glb",
]


func _init() -> void:
	var main: Node = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 30:
		await process_frame
	(main.front_end as FrontEnd).press_start()
	for i in 30:
		await process_frame
	var loaded := []
	for p in HEAVY:
		if ResourceLoader.has_cached(p):
			loaded.append(p.get_file())
	print("MENU HEAVY LOADED: ", ",".join(loaded) if not loaded.is_empty() else "none")
	quit()
