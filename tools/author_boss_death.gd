extends SceneTree
## Authors the robot boss's heavy death clip on its existing skeleton and
## writes it as JSON for tools/build_robot_boss.py:
##   godot --headless --path . -s tools/author_boss_death.gd -- out.json
##
## Key poses are rotations in the robot's own (standing) model space,
## layered on its Idle pose: hit flinch -> power fails, knees buckle ->
## topples forward -> slams down on its chest -> settles. Every frame the
## whole body is then lowered/raised so its lowest skinned vertex rests on
## the floor (it pivots over whatever touches the ground, like a heavy
## object, so the feet can't stay planted and nothing sinks or hovers).

const GLB := "res://assets/enemies/robot_boss/robot_boss.glb"
const CLIP := "Heavy_Death"
const FPS := 30.0
const LENGTH := 1.9

## [time, {bone: Vector3(x, y, z) degrees about the model axes}, root
## {"pitch": forward tilt, "roll": toward the chaingun (+X) side,
##  "z": forward shift (m)}, ease into this key ("smooth" / "in")]
const KEYS := [
	[0.0, {}, {}, "smooth"],
	# Hit: jolts back, arms flinch out.
	[0.16, {"Spine": Vector3(-10, 0, 0), "Spine2": Vector3(-6, 0, 0), "Neck": Vector3(-12, 0, 0),
		"LeftArm": Vector3(0, 0, 14), "RightArm": Vector3(0, 0, -14),
		"LeftForeArm": Vector3(-8, 0, 0), "RightForeArm": Vector3(-8, 0, 0)},
		{"pitch": -7.0, "z": -0.06}, "smooth"],
	# Power fails: knees buckle, the torso slumps forward, arms go heavy.
	[0.6, {"Spine": Vector3(14, 0, 0), "Spine2": Vector3(10, 0, 0), "Neck": Vector3(16, 0, 0),
		"LeftUpLeg": Vector3(-40, 0, 6), "RightUpLeg": Vector3(-34, 0, -6),
		"LeftLeg": Vector3(62, 0, 0), "RightLeg": Vector3(56, 0, 0),
		"LeftFoot": Vector3(-22, 0, 0), "RightFoot": Vector3(-22, 0, 0),
		"LeftArm": Vector3(8, 0, 6), "RightArm": Vector3(8, 0, -6),
		"LeftForeArm": Vector3(10, 0, 0), "RightForeArm": Vector3(10, 0, 0)},
		{"pitch": 14.0, "roll": -3.0, "z": 0.05}, "smooth"],
	# Topples forward under its own weight (accelerating).
	[0.98, {"Spine": Vector3(18, 0, 0), "Spine2": Vector3(8, 0, 0), "Neck": Vector3(10, 0, 0),
		"LeftUpLeg": Vector3(-18, 0, 4), "RightUpLeg": Vector3(-14, 0, -4),
		"LeftLeg": Vector3(38, 0, 0), "RightLeg": Vector3(34, 0, 0),
		"LeftFoot": Vector3(5, 0, 0), "RightFoot": Vector3(5, 0, 0),
		"LeftAim": [Vector3(0.9, -0.25, 0.25), Vector3(0.55, 0.25, 0.75)], "RightAim": [Vector3(-0.9, -0.25, 0.25), Vector3(-0.55, 0.25, 0.75)]},
		{"pitch": 52.0, "roll": -7.0, "z": 0.28}, "in"],
	# Slams down on its chest, arms and weapons thrown out to the sides.
	[1.24, {"Spine": Vector3(8, 0, 0), "Spine2": Vector3(4, 0, 0), "Neck": Vector3(6, 0, 0),
		"LeftUpLeg": Vector3(6, 0, 4), "RightUpLeg": Vector3(8, 0, -4),
		"LeftLeg": Vector3(12, 0, 0), "RightLeg": Vector3(10, 0, 0),
		"LeftFoot": Vector3(34, 0, 0), "RightFoot": Vector3(34, 0, 0),
		"LeftAim": [Vector3(0.92, 0.25, -0.2), Vector3(0.4, 0.92, 0.06)], "RightAim": [Vector3(-0.92, 0.25, -0.2), Vector3(-0.4, 0.92, 0.06)]},
		{"pitch": 88.0, "roll": -12.0, "z": 0.46}, "in"],
	# Small rebound ...
	[1.36, {"Spine": Vector3(10, 0, 0), "Spine2": Vector3(5, 0, 0), "Neck": Vector3(10, 0, 0),
		"LeftUpLeg": Vector3(2, 0, 4), "RightUpLeg": Vector3(4, 0, -4),
		"LeftLeg": Vector3(16, 0, 0), "RightLeg": Vector3(14, 0, 0),
		"LeftFoot": Vector3(30, 0, 0), "RightFoot": Vector3(30, 0, 0),
		"LeftAim": [Vector3(0.9, 0.3, -0.25), Vector3(0.45, 0.88, 0.02)], "RightAim": [Vector3(-0.9, 0.3, -0.25), Vector3(-0.45, 0.88, 0.02)]},
		{"pitch": 84.0, "roll": -13.0, "z": 0.48, "lift": 0.05}, "smooth"],
	# ... and settles, lying on its chest.
	[1.62, {"Spine": Vector3(8, 0, 0), "Spine2": Vector3(4, 0, 0), "Neck": Vector3(14, 0, 0),
		"LeftUpLeg": Vector3(6, 0, 5), "RightUpLeg": Vector3(8, 0, -5),
		"LeftLeg": Vector3(10, 0, 0), "RightLeg": Vector3(8, 0, 0),
		"LeftFoot": Vector3(38, 0, 0), "RightFoot": Vector3(38, 0, 0),
		"LeftAim": [Vector3(0.92, 0.25, -0.22), Vector3(0.38, 0.93, 0.03)], "RightAim": [Vector3(-0.92, 0.25, -0.22), Vector3(-0.38, 0.93, 0.03)]},
		{"pitch": 90.0, "roll": -14.0, "z": 0.48}, "smooth"],
	[LENGTH, {"Spine": Vector3(8, 0, 0), "Spine2": Vector3(4, 0, 0), "Neck": Vector3(14, 0, 0),
		"LeftUpLeg": Vector3(6, 0, 5), "RightUpLeg": Vector3(8, 0, -5),
		"LeftLeg": Vector3(10, 0, 0), "RightLeg": Vector3(8, 0, 0),
		"LeftFoot": Vector3(38, 0, 0), "RightFoot": Vector3(38, 0, 0),
		"LeftAim": [Vector3(0.92, 0.25, -0.22), Vector3(0.38, 0.93, 0.03)], "RightAim": [Vector3(-0.92, 0.25, -0.22), Vector3(-0.38, 0.93, 0.03)]},
		{"pitch": 90.0, "roll": -14.0, "z": 0.48}, "smooth"],
]

var sk: Skeleton3D
var base_rot: Array[Quaternion] = []
var base_pos: Array[Vector3] = []
var base_global: Array[Basis] = []
## Sampled vertices for the floor contact: [bone weights..., local pos]
var samples := []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_path: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ProjectSettings.globalize_path("res://tools/robot_boss_heavy_death.json")
	var model: Node3D = load(GLB).instantiate()
	root.add_child(model)
	sk = model.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	ap.play(&"Idle")
	ap.seek(0.0, true)
	ap.active = false
	for b in sk.get_bone_count():
		base_rot.append(sk.get_bone_pose_rotation(b))
		base_pos.append(sk.get_bone_pose_position(b))
	for b in sk.get_bone_count():
		var basis := Basis(base_rot[b])
		var p := sk.get_bone_parent(b)
		base_global.append(basis if p < 0 else base_global[p] * basis)
	_collect_samples(model)
	_weapon_axes(model)
	_prepare_keys()
	var frames := int(round(LENGTH * FPS)) + 1
	var rot_tracks := {}
	var hips_pos := []
	var times := []
	var min_ys := []
	for f in frames:
		var t := minf(f / FPS, LENGTH)
		var pose := _pose_at(t)
		_apply(pose)
		var low := _lowest()
		var hips := sk.find_bone("mixamorig_Hips")
		var hp := sk.get_bone_pose_position(hips)
		hp.y += -low + float(pose.root.get("lift", 0.0))
		sk.set_bone_pose_position(hips, hp)
		times.append(t)
		hips_pos.append([hp.x, hp.y, hp.z])
		min_ys.append(_lowest())
		for b in sk.get_bone_count():
			var q := sk.get_bone_pose_rotation(b)
			if not rot_tracks.has(b):
				rot_tracks[b] = []
			rot_tracks[b].append([q.x, q.y, q.z, q.w])
	var tracks := []
	for b in rot_tracks:
		tracks.append({"node": _gltf_name(sk.get_bone_name(b)), "path": "rotation", "times": times, "values": rot_tracks[b]})
	tracks.append({"node": "mixamorig:Hips", "path": "translation", "times": times, "values": hips_pos})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"name": CLIP, "tracks": tracks}))
	f.close()
	print("wrote %s: %d frames, %d tracks; lowest point %.3f..%.3f m; final hips height %.2f m" % [out_path, frames, tracks.size(), min_ys.min(), min_ys.max(), hips_pos[-1][1]])
	quit()


func _gltf_name(bone: String) -> String:
	return bone.replace("mixamorig_", "mixamorig:")


## Per key: {bone: Quaternion delta in standing model space}.
var key_quats := []
## Weapon axis (rest model space) for each forearm, from its mesh.
var weapon_axis := {}


func _prepare_keys() -> void:
	for k in KEYS:
		var q := {}
		for name in k[1]:
			var v = k[1][name]
			if v is Vector3:
				q[name] = _model_rot(v).get_rotation_quaternion()
			else:
				var side: String = name.trim_suffix("Aim")
				var arm := sk.find_bone("mixamorig_%sArm" % side)
				var fore := sk.find_bone("mixamorig_%sForeArm" % side)
				var up_base := (base_global_pos(fore) - base_global_pos(arm)).normalized()
				var d_arm := _arc(up_base, (v[0] as Vector3).normalized())
				var w_base: Vector3 = weapon_axis[side]
				var d_fore := _arc(w_base, d_arm.inverse() * (v[1] as Vector3).normalized())
				q["%sArm" % side] = d_arm
				q["%sForeArm" % side] = d_fore
		key_quats.append(q)


func _arc(from: Vector3, to: Vector3) -> Quaternion:
	var axis := from.cross(to)
	if axis.length() < 1e-6:
		return Quaternion()
	return Quaternion(axis.normalized(), from.angle_to(to))


func base_global_pos(b: int) -> Vector3:
	var p := Vector3.ZERO
	var basis := Basis()
	var chain := []
	var i := b
	while i >= 0:
		chain.push_front(i)
		i = sk.get_bone_parent(i)
	for c in chain:
		p += basis * base_pos[c]
		basis = basis * Basis(base_rot[c])
	return p


## Key pose at time t: {"bones": {name: Quaternion}, "root": {...}}.
func _pose_at(t: float) -> Dictionary:
	var i := 0
	while i < KEYS.size() - 2 and t > KEYS[i + 1][0]:
		i += 1
	var a: Array = KEYS[i]
	var b: Array = KEYS[i + 1]
	var u := clampf((t - a[0]) / maxf(b[0] - a[0], 1e-4), 0.0, 1.0)
	u = u * u if b[3] == "in" else u * u * (3.0 - 2.0 * u)
	var bones := {}
	for k in key_quats[i].keys() + key_quats[i + 1].keys():
		bones[k] = (key_quats[i].get(k, Quaternion()) as Quaternion).slerp(key_quats[i + 1].get(k, Quaternion()), u)
	var rt := {}
	for k in ["pitch", "roll", "z", "lift"]:
		rt[k] = lerpf(float(a[2].get(k, 0.0)), float(b[2].get(k, 0.0)), u)
	return {"bones": bones, "root": rt}


func _model_rot(deg: Vector3) -> Basis:
	return Basis(Vector3.BACK, deg_to_rad(deg.z)) * Basis(Vector3.UP, deg_to_rad(deg.y)) * Basis(Vector3.RIGHT, deg_to_rad(deg.x))


func _apply(pose: Dictionary) -> void:
	for b in sk.get_bone_count():
		var name := sk.get_bone_name(b).replace("mixamorig_", "")
		var local := Basis(base_rot[b])
		var p := sk.get_bone_parent(b)
		if pose.bones.has(name):
			var d := Basis(pose.bones[name] as Quaternion)
			var pg := base_global[p] if p >= 0 else Basis()
			local = pg.inverse() * d * pg * local
		var pos := base_pos[b]
		if p < 0:
			# Root: tip forward / roll about the hips, shift forward.
			var r: Dictionary = pose.root
			var d := Basis(Vector3.BACK, deg_to_rad(r.roll)) * Basis(Vector3.RIGHT, deg_to_rad(r.pitch))
			local = d * local
			pos = base_pos[b] + Vector3(0, 0, r.z)
		sk.set_bone_pose_rotation(b, local.get_rotation_quaternion())
		sk.set_bone_pose_position(b, pos)
	sk.force_update_all_bone_transforms()


## Long axis of each forearm's weapon (rest model space), pointing away
## from the elbow: principal axis of the vertices bound to the forearm.
func _weapon_axes(model: Node3D) -> void:
	var body: MeshInstance3D = null
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.skin:
			body = mi
	var arrays := body.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / verts.size()
	for side in ["Left", "Right"]:
		var fore := sk.find_bone("mixamorig_%sForeArm" % side)
		var pts := PackedVector3Array()
		for i in range(0, verts.size(), 5):
			for k in per:
				if weights[i * per + k] > 0.5 and sk.find_bone(body.skin.get_bind_name(bones[i * per + k])) == fore:
					pts.append(verts[i])
		var c := Vector3.ZERO
		for p in pts:
			c += p
		c /= pts.size()
		var axis := Vector3(1, 1, 1).normalized()
		for it in 30:
			var acc := Vector3.ZERO
			for p in pts:
				var d := p - c
				acc += d * d.dot(axis)
			axis = acc.normalized()
		var elbow := base_global_pos(fore)
		if axis.dot(c - elbow) < 0.0:
			axis = -axis
		weapon_axis[side] = axis
		print("%s weapon axis %s (%d verts)" % [side, axis.snapped(Vector3.ONE * 0.01), pts.size()])


func _collect_samples(model: Node3D) -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var arrays := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if mi.skin:
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / verts.size()
			for i in range(0, verts.size(), 11):
				var infl := []
				for k in per:
					var w := weights[i * per + k]
					if w > 0.01:
						var bind := bones[i * per + k]
						infl.append([sk.find_bone(mi.skin.get_bind_name(bind)), mi.skin.get_bind_pose(bind), w])
				samples.append([infl, verts[i], null])
		else:
			# Rigid part on a bone (BoneAttachment3D): bone pose * offsets.
			var att := mi.get_parent()
			var off := mi.transform
			while att and not (att is BoneAttachment3D):
				off = (att as Node3D).transform * off
				att = att.get_parent()
			if att == null:
				continue
			var bone := sk.find_bone((att as BoneAttachment3D).bone_name)
			for i in range(0, verts.size(), 7):
				samples.append([[[bone, off, 1.0]], verts[i], true])


func _lowest() -> float:
	var low := INF
	for s in samples:
		var p := Vector3.ZERO
		for inf in s[0]:
			p += (sk.get_bone_global_pose(inf[0]) * (inf[1] as Transform3D) * (s[1] as Vector3)) * float(inf[2])
		low = minf(low, p.y)
	return low
