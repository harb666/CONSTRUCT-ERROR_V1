extends SceneTree
## Records every kind of material drawn during play into
## res://assets/vfx/warm_up_library.tres (WarmUpLibrary): each level is
## loaded as the game does, `?fxsoak`'s sequence (every weapon, melee, kills,
## sentinel, barrel, boss, fall ...) is played, and every few frames each
## visible GeometryInstance3D's materials are looked at. The level's own
## scenery (in its scene file, not a character / robot) is left out - the
## level's look-round (Vfx.sweep_level) prepares that. Textures are swapped
## for a tiny stand-in (only whether a slot is used changes a shader), so
## the library holds no real textures.
##   godot --headless --fixed-fps 60 --path . -s tools/collect_warm_up_materials.gd
## (adds to the library already there; -- --fresh starts it again).

const OUT := "res://assets/vfx/warm_up_library.tres"
const LEVELS := ["res://scenes/battle_arena.tscn", "res://scenes/skyforge_arena.tscn", "res://scenes/toxic_works.tscn"]

var lib: WarmUpLibrary
var have := {}
var start_keys := {}
var sprite_have := {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	# A real window size: locked targets must be on screen for the guns to fire.
	root.size = Vector2i(1280, 720)
	var fresh := "--fresh" in OS.get_cmdline_user_args()
	lib = WarmUpLibrary.new() if fresh or not ResourceLoader.exists(OUT) else load(OUT).duplicate()
	for k in lib.keys:
		have[k] = true
	for sd in lib.sprites:
		sprite_have[str(sd)] = true
	var before := lib.materials.size()
	for path in LEVELS:
		var main: Node = load(path).instantiate()
		main.set(&"front_end_mode", 0)
		root.add_child(main)
		current_scene = main  # effects that go into the current scene
		for i in 10:
			await process_frame
		start_keys.clear()
		watch.clear()
		_scan(main, true, path)
		_scan(main, false, path)
		var p := main.get(&"players")[1] as PlayerController
		StressTest.fx_done = false
		StressTest.start_fx_soak(main, p)
		var frames := 0
		while not StressTest.fx_done and frames < 60 * 240:
			await process_frame
			frames += 1
			_scan_watched(path)
		print("%s: %d kinds so far (%d frames)" % [path.get_file(), lib.materials.size(), frames])
		main.queue_free()
		for i in 10:
			await process_frame
	print("collected %d new kinds, %d in all, %d sprite set-ups" % [lib.materials.size() - before, lib.materials.size(), lib.sprites.size()])
	var err := ResourceSaver.save(lib, OUT)
	print("saved ", OUT, " ", error_string(err))
	quit()


## Everything drawable that isn't the level's scenery (what's there at the
## start, and all added since): looked at each frame.
var watch: Array[GeometryInstance3D] = []


func _added(n: Node) -> void:
	if n is GeometryInstance3D:
		watch.append(n)


func _scan_watched(where: String) -> void:
	var keep: Array[GeometryInstance3D] = []
	for gi in watch:
		if is_instance_valid(gi):
			keep.append(gi)
			if gi.is_inside_tree() and gi.is_visible_in_tree():
				_look_at(gi, false, where)
	watch = keep


func _scan(main: Node, at_start: bool, where: String) -> void:
	if not node_added.is_connected(_added):
		node_added.connect(_added)
	# The whole tree: some effects go on the root, outside the level.
	for gi: GeometryInstance3D in root.find_children("*", "GeometryInstance3D", true, false):
		if at_start and not _scenery(gi, main):
			watch.append(gi)
		if not gi.is_visible_in_tree():
			continue
		_look_at(gi, at_start, where, main)


func _look_at(gi: GeometryInstance3D, at_start: bool, where: String, main: Node = null) -> void:
	if (gi is SpriteBase3D or gi is Label3D) and not at_start:
		var sd := WarmUpLibrary.sprite_key(gi)
		if not sprite_have.has(str(sd)):
			sprite_have[str(sd)] = true
			lib.sprites.append(sd)
	if at_start and not _scenery(gi, main):
		return
	for m in _materials_of(gi):
		_add(m, at_start, "%s %s" % [where.get_file().get_basename(), gi.name])


## Part of the level's own scenery: placed in the level's scene, not on a
## character or robot.
func _scenery(n: Node, main: Node) -> bool:
	if n.owner == null:
		return false
	while n and n != main:
		if n is CharacterBody3D or n is RigidBody3D or n is Weapon:
			return false
		n = n.get_parent()
	return true


func _materials_of(gi: GeometryInstance3D) -> Array[Material]:
	var out: Array[Material] = []
	for m in [gi.material_override, gi.material_overlay]:
		if m:
			out.append(m)
	var mesh: Mesh = null
	if gi is MeshInstance3D:
		var mi := gi as MeshInstance3D
		mesh = mi.mesh
		for i in mi.get_surface_override_material_count():
			if mi.get_surface_override_material(i):
				out.append(mi.get_surface_override_material(i))
	elif gi is CPUParticles3D:
		mesh = (gi as CPUParticles3D).mesh
	elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh:
		mesh = (gi as MultiMeshInstance3D).multimesh.mesh
	elif gi is GPUParticles3D:
		var gp := gi as GPUParticles3D
		if gp.process_material:
			out.append(gp.process_material)
		for i in gp.draw_passes:
			var dm := gp.get_draw_pass_mesh(i)
			if dm:
				for s in dm.get_surface_count():
					if dm.surface_get_material(s):
						out.append(dm.surface_get_material(s))
	if mesh:
		for s in mesh.get_surface_count():
			if mesh.surface_get_material(s):
				out.append(mesh.surface_get_material(s))
	return out


func _add(m: Material, at_start: bool, where: String) -> void:
	while m:
		var k := WarmUpLibrary.key_of(m)
		if at_start:
			start_keys[k] = true
		elif not have.has(k) and not start_keys.has(k):
			have[k] = true
			lib.materials.append(_portable(m))
			lib.keys.append(k)
			lib.seen.append(where)
		m = m.next_pass


## A copy that can be saved on its own (embedded shaders / textures copied
## in; ones in their own files referenced).
func _portable(m: Material) -> Material:
	var c := m.duplicate() as Material
	c.next_pass = null
	if c is ShaderMaterial:
		var sm := c as ShaderMaterial
		if sm.shader and (sm.shader.resource_path == "" or sm.shader.resource_path.contains("::")):
			sm.shader = sm.shader.duplicate()
		for p in sm.get_property_list():
			if String(p.name).begins_with("shader_parameter/"):
				var v = sm.get(p.name)
				if v is Resource and _embedded(v):
					sm.set(p.name, _copy(v))
	else:
		for p in c.get_property_list():
			if int(p.usage) & PROPERTY_USAGE_STORAGE and int(p.type) == TYPE_OBJECT and p.name != "next_pass":
				var v = c.get(p.name)
				if v is Resource and _embedded(v):
					c.set(p.name, _copy(v))
	return c


func _embedded(r: Resource) -> bool:
	return r is Texture or r.resource_path == "" or r.resource_path.contains("::")


## Textures: one tiny stand-in (only whether a slot is used changes the
## shader); other embedded resources copied.
func _copy(r: Resource) -> Resource:
	if r is Texture2D:
		if _stand_in == null:
			var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
			img.fill(Color.WHITE)
			_stand_in = ImageTexture.create_from_image(img)
		return _stand_in
	if r is Texture:
		return null
	return r.duplicate()


var _stand_in: ImageTexture
