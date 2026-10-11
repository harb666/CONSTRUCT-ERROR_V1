extends Node3D
## image-to-level Stage 9 OPTIONAL scatter path for Godot 4 (UNTESTED in Godot here).
## The level GLB already contains scatter merged per cell (works with no code). This script instead builds one
## MultiMeshInstance3D per prop variant + role from terrain.json "instances" and props/props.glb (shared meshes), and
## hides the merged SC_/SCN_ nodes. Use it when you want per-instance culling / LOD in Godot.
## Setup: instance props/props.glb somewhere (can be hidden) and assign props_root; assign level_root (the level GLB).

@export_file("*.json") var terrain_json: String = "res://levels/test_valley/terrain.json"
@export var props_root: Node3D
@export var level_root: Node3D


func _ready() -> void:
	var t = JSON.parse_string(FileAccess.get_file_as_string(terrain_json))
	if t == null or props_root == null:
		push_error("terrain.json or props_root missing")
		return
	for sid in t["instances"]:
		var sc = t["instances"][sid]
		for kind in sc["kinds"]:
			var k = sc["kinds"][kind]
			var by_variant := {}
			for tr in k["transforms_xyz_yaw_scale_variant"]:
				by_variant.get_or_add(int(tr[5]), []).append(tr)
			for v in by_variant:
				for child in props_root.find_children("%s_%s_%d_*" % [kind, sc["style"], v], "MeshInstance3D", true, false):
					var mm := MultiMesh.new()
					mm.transform_format = MultiMesh.TRANSFORM_3D
					mm.mesh = (child as MeshInstance3D).mesh
					mm.instance_count = by_variant[v].size()
					for i in by_variant[v].size():
						var tr = by_variant[v][i]
						var b := Basis(Vector3.UP, deg_to_rad(tr[3])).scaled(Vector3.ONE * tr[4])
						mm.set_instance_transform(i, Transform3D(b, Vector3(tr[0], tr[1], tr[2])))
					var mmi := MultiMeshInstance3D.new()
					mmi.multimesh = mm
					mmi.visibility_range_end = float(sc["view_distance"][kind])
					mmi.name = "MM_%s_%s_%d_%s" % [sid, kind, v, child.name.get_slice("_", child.name.get_slice_count("_") - 1)]
					add_child(mmi)
	if level_root:
		for n in level_root.find_children("SC*", "MeshInstance3D", true, false):
			n.visible = false
