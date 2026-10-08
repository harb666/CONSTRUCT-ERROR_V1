extends SceneTree
## Measures each locomotion clip's feet: the ground speed of the planted
## foot (what the body speed must match at 1x for no sliding), sole height
## and foot pitch while planted.
## godot --headless --path . -s tools/measure_gait.gd

const MODELS := {
	"grunt": "res://assets/characters/robot/robot_enemy.glb",
	"skirmisher": "res://assets/enemies/robot_skirmisher/robot_skirmisher.glb",
}

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	for key in MODELS:
		var m: Node3D = load(MODELS[key]).instantiate()
		root.add_child(m)
		var sk := m.find_child("Skeleton3D", true, false) as Skeleton3D
		var ap := m.find_child("AnimationPlayer", true, false) as AnimationPlayer
		print("== ", key, " clips: ", ap.get_animation_list())
		for clip in [&"Walking", &"Running"]:
			if not ap.has_animation(clip):
				continue
			_measure(key, sk, ap, clip)
		m.queue_free()
	quit()


func _bone(sk: Skeleton3D, names: Array) -> int:
	for n in names:
		var i := sk.find_bone(n)
		if i >= 0:
			return i
	return -1


func _measure(key: String, sk: Skeleton3D, ap: AnimationPlayer, clip: StringName) -> void:
	var a := ap.get_animation(clip)
	var L := a.length
	var feet := {}
	for side in ["Left", "Right"]:
		feet[side] = [_bone(sk, ["mixamorig_%sFoot" % side, "%sFoot" % side, "mixamorig:%sFoot" % side]),
			_bone(sk, ["mixamorig_%sToeBase" % side, "%sToeBase" % side])]
	var hips := _bone(sk, ["mixamorig_Hips", "Hips"])
	var N := 120
	var samples := {"Left": [], "Right": []}
	var hip_y := []
	ap.play(clip)
	for i in N + 1:
		var t := L * i / N
		ap.seek(t, true)
		var xf := sk.global_transform
		hip_y.append((xf * sk.get_bone_global_pose(hips).origin).y)
		for side in feet:
			var f: Vector3 = xf * sk.get_bone_global_pose(feet[side][0]).origin
			var toe: Vector3 = xf * sk.get_bone_global_pose(feet[side][1]).origin if feet[side][1] >= 0 else f
			samples[side].append([t, f, toe])
	# Standing pose: the time both ankles are lowest together (both planted).
	var best_t := 0.0
	var best := INF
	var amins := {}
	for side in samples:
		var mn := INF
		for e in samples[side]:
			mn = minf(mn, e[1].y)
		amins[side] = mn
	for i in N:
		var worst := 0.0
		for side in samples:
			worst = maxf(worst, samples[side][i][1].y - amins[side])
		if worst < best:
			best = worst
			best_t = samples["Left"][i][0]
	print("   GAIT %s: ankle_min %.3f, stand_time %.3f (both feet within %.3f m)" % [clip, minf(amins["Left"], amins["Right"]), best_t, best])
	print("-- %s %s length %.3f s, hips y %.3f..%.3f" % [key, clip, L, hip_y.min(), hip_y.max()])
	for side in samples:
		var s: Array = samples[side]
		var miny := INF
		for e in s:
			miny = minf(miny, minf(e[1].y, e[2].y))
		# Planted: ankle within 2.5 cm of its lowest height.
		var ankle_min := INF
		for e in s:
			ankle_min = minf(ankle_min, e[1].y)
		var spd := []
		var pitch := []
		var planted := 0
		for i in range(1, s.size()):
			var e0: Array = s[i - 1]
			var e1: Array = s[i]
			if e1[1].y < ankle_min + 0.025 and e0[1].y < ankle_min + 0.025:
				planted += 1
				var dp: Vector3 = (e1[1] - e0[1]) / (e1[0] - e0[0])
				spd.append(Vector2(dp.x, dp.z))
				var ft: Vector3 = e1[2] - e1[1]
				pitch.append(rad_to_deg(atan2(ft.y, Vector2(ft.x, ft.z).length())))
		var avg := Vector2.ZERO
		for v in spd:
			avg += v
		avg /= maxf(spd.size(), 1)
		var pmin := 999.0
		var pmax := -999.0
		for p in pitch:
			pmin = minf(pmin, p)
			pmax = maxf(pmax, p)
		print("   %s: lowest %.3f, ankle min %.3f, planted %d%% of cycle, planted-foot ground vel (x,z) %s = %.3f m/s, toe pitch %.1f..%.1f deg" %
			[side, miny, ankle_min, roundi(100.0 * planted / N), avg, avg.length(), pmin, pmax])
