extends SceneTree
## Renders a transparent head-and-shoulders portrait for every character in
## the roster (HUD, character select):
##   godot --path . --rendering-driver opengl3 -s tools/render_character_portraits.gd
## (needs a display, e.g. xvfb-run). Writes assets/ui/portraits/<id>.png.

const SIZE := 256
const OUT := "res://assets/ui/portraits/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var roster := CharacterRoster.load_default()
	for def in roster.characters:
		var vp := SubViewport.new()
		vp.size = Vector2i(SIZE, SIZE)
		vp.transparent_bg = true
		vp.own_world_3d = true
		vp.msaa_3d = Viewport.MSAA_4X
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_CLEAR_COLOR
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.7, 0.8, 0.85)
		env.environment.ambient_light_energy = 1.0
		vp.add_child(env)
		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-25, 30, 0)
		key.light_energy = 1.3
		vp.add_child(key)
		var rim := DirectionalLight3D.new()
		rim.rotation_degrees = Vector3(-10, 160, 0)
		rim.light_color = Color(0.4, 0.9, 1.0)
		rim.light_energy = 1.2
		vp.add_child(rim)
		var model: Node3D = def.preview_model.instantiate()
		vp.add_child(model)
		model.rotation_degrees.y = def.preview_yaw_degrees
		if def.preview_caps:
			def.preview_caps.apply(model)
		var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and def.preview_animation != "":
			ap.play(def.preview_animation)
			ap.seek(0.0, true)
			ap.pause()
		var cam := Camera3D.new()
		cam.fov = 24
		vp.add_child(cam)
		await process_frame
		var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		var head := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_Head")).origin
		var aim := head + Vector3(0, 0.1, 0)
		cam.global_position = aim + Vector3(0.45, 0.12, 2.1)
		cam.look_at(aim)
		for i in 6:
			await process_frame
		var img := vp.get_texture().get_image()
		img.save_png(OUT + String(def.id) + ".png")
		print("portrait ", def.id)
		vp.queue_free()
	quit()
