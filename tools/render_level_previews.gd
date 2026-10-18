extends SceneTree
## Renders the level select's preview images (FrontEnd.LEVELS) from each
## level as it looks in the game:
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s tools/render_level_previews.gd
## Writes assets/ui/levels/<id>.png (800 x 450); players and the HUD hidden.

const OUT := "res://assets/ui/levels/"
const SIZE := Vector2i(800, 450)
## id -> [scene, camera position, looking at]
const SHOTS := {
	"skyforge": ["res://scenes/skyforge_arena.tscn", Vector3(40, 60, 60), Vector3(0, 30, 0)],
	"works": ["res://scenes/toxic_works.tscn", Vector3(0, 24, 30), Vector3(0, 4, -30)],
	"battle": ["res://scenes/battle_arena.tscn", Vector3(0, 10, 28), Vector3(0, 1, -6)],
}


func _init() -> void:
	root.size = Vector2i(1280, 720)
	for id in SHOTS:
		var shot: Array = SHOTS[id]
		var m: Node = load(shot[0]).instantiate()
		m.set("front_end_mode", 0)
		root.add_child(m)
		for i in 90:
			await process_frame
		for p in m.get_tree().get_nodes_in_group(&"players"):
			(p as Node3D).visible = false
		var ui := m.get_node_or_null("UI") as CanvasLayer
		if ui:
			ui.visible = false
		var cam := Camera3D.new()
		cam.fov = 55.0
		cam.far = 2000.0
		m.add_child(cam)
		cam.make_current()
		cam.global_position = shot[1]
		cam.look_at(shot[2])
		for i in 8:
			await process_frame
		var img := root.get_texture().get_image()
		img.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
		img.save_png(ProjectSettings.globalize_path(OUT + "%s.png" % id))
		print("level preview: ", id)
		m.queue_free()
		for i in 5:
			await process_frame
	quit()
