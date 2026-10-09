extends SceneTree
## Renders a transparent icon for every weapon in the registry:
##   godot --path . --rendering-driver opengl3 -s tools/render_weapon_icons.gd
## (needs a display, e.g. xvfb-run). Writes assets/ui/weapon_icons/<id>.png.
## ONLY=<id> renders just that weapon's icon (the others are left as they are).

const SIZE := 256
const OUT := "res://assets/ui/weapon_icons/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var reg: WeaponRegistry = load("res://resources/weapons/weapon_registry.tres")
	var only := OS.get_environment("ONLY")
	for def in reg.weapons:
		if only != "" and String(def.id) != only:
			continue
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
		env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
		env.environment.ambient_light_energy = 1.2
		vp.add_child(env)
		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-35, 40, 0)
		key.light_energy = 1.3
		vp.add_child(key)
		var rim := DirectionalLight3D.new()
		rim.rotation_degrees = Vector3(-20, -150, 0)
		rim.light_energy = 0.6
		vp.add_child(rim)
		var w: Weapon = def.weapon_scene.instantiate()
		w.definition = def
		vp.add_child(w)
		w.on_displayed()
		# Barrel (+X) pointing to the upper right, seen slightly from above.
		w.rotation_degrees = Vector3(0, -32, 28)
		var cam := Camera3D.new()
		cam.fov = 26
		vp.add_child(cam)
		await process_frame
		var box := w.global_transform * w.get_local_aabb()
		var c := box.get_center()
		var r := box.size.length() * 0.5
		var dist := r / tan(deg_to_rad(cam.fov * 0.5)) * 0.74
		cam.global_position = c + Vector3(0, 0.15, 1.0).normalized() * dist
		cam.look_at(c)
		for i in 6:
			await process_frame
		var img := vp.get_texture().get_image()
		img.save_png(OUT + String(def.id) + ".png")
		print("icon ", def.id)
		vp.queue_free()
	quit()
