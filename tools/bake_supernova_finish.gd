extends SceneTree
## Bakes assets/vfx/supernova/supernova_finish.glb (a 50-frame, 657k-vertex
## Sketchfab "timeframe" flipbook whose layers pile up into an expanding
## plasma burst) into a light scene for mobile: a subset of its layers, each
## MeshInstance3D tagged with the time it appears in the original (meta
## "appear", seconds of the original 8.82 s clip) and the original length
## (root meta "source_length"), plus the burst's size (root meta "extent").
## Run: godot --headless --path . -s tools/bake_supernova_finish.gd

const SRC := "res://assets/vfx/supernova/supernova_finish.glb"
const OUT := "res://assets/vfx/supernova/supernova_finish_baked.scn"
## Original appear times of the layers to keep (spread across the burst).
const KEEP := [0.0, 1.11, 1.21, 1.61, 2.41, 3.61, 5.01, 6.41, 8.61]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var s: Node3D = load(SRC).instantiate()
	root.add_child(s)
	await process_frame
	var ap: AnimationPlayer = s.find_child("AnimationPlayer", true, false)
	var anim_name: StringName = ap.get_animation_list()[0]
	var length := ap.get_animation(anim_name).length
	ap.play(anim_name)
	var meshes: Array = s.find_children("*", "MeshInstance3D", true, false)
	var appear := {}
	var t := 0.0
	while t <= length + 0.02:
		ap.seek(t, true)
		for mi in meshes:
			if not appear.has(mi) and (mi as MeshInstance3D).global_transform.basis.get_scale().x > 1e-4:
				appear[mi] = snappedf(t, 0.01)
		t += 0.01
	ap.seek(length, true)  # everything at full size
	var out := Node3D.new()
	out.name = "SupernovaFinish"
	var box := AABB()
	var first := true
	var verts := 0
	for mi: MeshInstance3D in meshes:
		var at: float = appear.get(mi, -1.0)
		var keep := false
		for k in KEEP:
			if absf(at - k) < 0.005:
				keep = true
		if not keep:
			continue
		var m := MeshInstance3D.new()
		m.mesh = mi.mesh.duplicate(true)
		m.transform = s.global_transform.affine_inverse() * mi.global_transform
		m.set_meta("appear", at)
		out.add_child(m)
		m.owner = out
		var a: AABB = m.transform * m.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
		verts += m.mesh.surface_get_array_len(0)
	out.set_meta("source_length", length)
	out.set_meta("extent", maxf(box.size.x, maxf(box.size.y, box.size.z)))
	out.set_meta("center", box.get_center())
	var ps := PackedScene.new()
	ps.pack(out)
	print("baked ", out.get_child_count(), " layers, ", verts, " verts, extent ", out.get_meta("extent"), " -> ", ResourceSaver.save(ps, OUT))
	quit()
