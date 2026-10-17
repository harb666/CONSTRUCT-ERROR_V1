extends Node3D
## image-to-level Stage 4 runtime starter for Godot 4 (UNTESTED in Godot here - treat as a starting point).
## Recreates effects.json on an imported level: liquid shaders, emission pulses/flicker, particles, mist sheets, sky drift.
## Setup: put the level folder at res://levels/<name>/, instance level.glb (and background.glb), add a Node3D at the
## world origin with this script, assign level_root (the instanced level.glb) and optionally environment.
## Particles use CPUParticles3D so they work in the Mobile and Compatibility renderers.
## kill_below_spawn (splash): droplets falling back are simply hidden by the opaque liquid surface here.

@export_file("*.json") var effects_path: String = "res://levels/toxic_arena/effects.json"
@export_enum("off", "performance", "balanced", "quality") var quality: String = "balanced"
@export var level_root: Node3D
@export var environment: WorldEnvironment
@export var hazard_group: StringName = &"hazard"  # Stage 72: crusher kill zones join this group while the ram is down (same as apply_mobile.gd)

var _base_dir: String = ""
var _anims: Array = []    # [material, base_energy, params, kind, next_change]
var _bursts: Array = []   # [CPUParticles3D, time_left, interval_min, interval_max]
var _sky_speed: float = 0.0
var _t: float = 0.0


var _spins: Array = []  # [rotor node, rad/s]
var _travel: Array = []  # [node, rest position, speed m/s, spacing m] (Stage 43: barrels up the column bores)
var _launch: Array = []  # [node, rest position, speed, period, phase, travel] (Stage 49: pods shooting up the columns)
var _crushers: Array = []  # Stage 72: [crusher dict, ram nodes, warning lamps, kill CollisionShape3D]
var _winds: Array = []  # Stage 82: [wind dict, rotor node, Area3D, CPUParticles3D streaks]
var _bobs: Array = []  # Stage 92: [bob dict, [[Node3D, rest Transform3D]...]]
var _risers: Array = []  # Stage 80: [riser dict, Skeleton3D, {bone name: index}, [[CollisionShape3D...] per pad], start time (-1: waiting)]
var _lines: Array = []  # Stage 61: working assembly lines - [line dict, move nodes, [[station, arm nodes, held nodes, scan nodes]]]


func _ready() -> void:
	if quality == "off":
		return
	_base_dir = effects_path.get_base_dir()
	# Construct Error: the mobile effects file lives in mobile/, the fx
	# textures / shaders and environment.json in the level folder above it.
	if _base_dir.ends_with("/mobile"):
		_base_dir = _base_dir.get_base_dir()
	var data = JSON.parse_string(FileAccess.get_file_as_string(effects_path))
	if data == null:
		push_error("effects.json missing or invalid: " + effects_path)
		return
	for fx in data["effects"]:
		var q: Dictionary = fx["quality"][quality]
		if not q["enabled"]:
			continue
		var p: Dictionary = q["params"]
		match fx["category"]:
			"surface_shader":
				_surface(fx, p)
			"material_animation":
				_material_anim(fx, p)
			"material_shader":  # Stage 26: tv_static on screen materials
				_material_shader(fx, p)
			"light":  # Stage 39: soft coloured lights (ceiling fans) - no shadows, mobile friendly
				for e in fx.get("emitters", []):
					var l := OmniLight3D.new()
					l.light_color = Color(p["color"][0], p["color"][1], p["color"][2])
					l.light_energy = float(p["energy"])
					l.omni_range = float(p["range"])
					l.shadow_enabled = false
					add_child(l)
					l.global_position = Vector3(e["pos"][0], e["pos"][1], e["pos"][2])
			"tube_bubbles":  # Stage 48: bubbles up the vat / column tubes (one shader-animated mesh)
				_bubbles(fx, p)
			"particles":
				_particles(fx, p)
			"transparent_mesh":
				_fog_sheet(fx, p)
			"cloud_layer":
				_cloud_layer(fx, p)
			"billboards":
				_cloud_puffs(fx, p)
			"flyby":
				_flyby(fx, p)
			"environment":
				_sky_speed = deg_to_rad(float(p.get("speed_deg_s", 0.0)))
			"assembly":  # Stage 61: conveyors with parcels, dipping arms and parts revealed past each arm
				_assembly(fx["line"])
			"crusher":  # Stage 72: a ram slamming down onto a pad - kills whatever stands there
				_crusher(fx["crusher"])
			"emerge":  # Stage 80: pads surging up out of the liquid when a player comes near
				_riser(fx["riser"])
			"wind":  # Stage 82: a turbine fan whose cycled blast blows players off the platform
				_wind(fx["wind"])
			"bob":  # Stage 92: a specimen drifting in its tank (rest transforms kept, turned about the pivot)
				var bb: Dictionary = fx["bob"]
				var bn: Array = []
				for nd in _group_nodes(String(bb["group"])):
					bn.append([nd, (nd as Node3D).transform])
				_bobs.append([bb, bn])
			"launch":  # Stage 49: each entry's nodes wait, shoot up `travel` m at `speed`, repeat every `period` s (own phase)
				for l in fx.get("launches", []):
					for n in l.get("targets", []):
						var nd := level_root.find_child(String(n), true, false) as Node3D
						if nd != null:
							_launch.append([nd, nd.position, float(p["speed"]), float(l["period"]), float(l["phase"]), float(l["travel"])])
			"translate_loop":  # Stage 43: move up by fmod(t * speed, spacing), all targets in step (wraps out of sight)
				for n in fx.get("targets", []):
					var nd := level_root.find_child(String(n), true, false) as Node3D
					if nd != null:
						_travel.append([nd, nd.position, float(p["speed"]), float(p["spacing"])])
			"transform_animation":  # spinning fan rotors (own nodes; origin = rotor centre, local +y = axis)
				for n in fx.get("targets", []):
					var nd := level_root.find_child(String(n), true, false) as Node3D
					if nd != null:
						_spins.append([nd, float(fx.get("speeds", {}).get(n, p.get("speed_rpm", 20.0))) * TAU / 60.0])


func _mesh(node_name: String) -> MeshInstance3D:
	if level_root == null:
		return null
	return level_root.find_child(node_name, true, false) as MeshInstance3D


func _surface(fx: Dictionary, p: Dictionary) -> void:
	var file := "liquid_surface.gdshader" if fx["type"] == "liquid_surface" else "liquid_flow.gdshader"
	var shader: Shader = load(_base_dir + "/fx/godot/" + file)
	for n in fx.get("targets", []):
		var mi := _mesh(n)
		if mi == null:
			continue
		var src := mi.get_active_material(0) as BaseMaterial3D
		var sm := ShaderMaterial.new()
		sm.shader = shader
		if src:
			sm.set_shader_parameter("albedo_tex", src.albedo_texture)
		if fx["type"] == "liquid_surface":
			sm.set_shader_parameter("scroll", Vector2(p["scroll"][0], p["scroll"][1]))
			sm.set_shader_parameter("swirl", p["swirl"])
			sm.set_shader_parameter("pulse_speed", p["pulse_speed"])
			sm.set_shader_parameter("pulse_amount", p["pulse_amount"])
			var rp: Array = []  # Stage 49: ripple points [x, z, amplitude, radius]
			for q in fx.get("ripples", []):
				rp.append(Vector4(q[0], q[1], q[2], q[3]))
			sm.set_shader_parameter("ripple_points", rp)
			sm.set_shader_parameter("ripple_count", rp.size())
			sm.set_shader_parameter("ripple", float(p.get("ripple", 1.0)))
			sm.set_shader_parameter("drops", float(p.get("drops", 1.0)))
			var rc: Array = p.get("ripple_color", [0.92, 1.0, 0.7])
			sm.set_shader_parameter("ripple_color", Color(rc[0], rc[1], rc[2]))
		else:
			sm.set_shader_parameter("uv_speed", float(p["speed"]) / float(fx.get("material_tile_m", 2.0)))
			sm.set_shader_parameter("wobble", p["wobble"])
			var f: Array = fx.get("flow_uv", [0.0, 1.0])
			sm.set_shader_parameter("flow_dir", Vector2(f[0], f[1]))
		sm.set_shader_parameter("glow_energy", p["glow_energy"])
		mi.material_override = sm


func _material_anim(fx: Dictionary, p: Dictionary) -> void:
	var seen := {}
	var meshes: Array = []
	if fx.has("target_material"):  # works for the dev AND the merged mobile export (node names differ, material names don't)
		for node in level_root.find_children("*", "MeshInstance3D", true, false):
			var mm := (node as MeshInstance3D).get_active_material(0)
			if mm and mm.resource_name.begins_with(fx["target_material"]):
				meshes.append(node)
	else:
		for n in fx.get("targets", []):
			meshes.append(_mesh(n))
	for mi in meshes:
		if mi == null:
			continue
		var m := (mi as MeshInstance3D).get_active_material(0) as BaseMaterial3D
		if m == null or seen.has(m):
			continue
		seen[m] = true
		m.emission_enabled = true
		_anims.append([m, m.emission_energy_multiplier, p, fx["type"], 0.0])


func _group_nodes(group: String) -> Array:
	return level_root.find_children(group + "__*", "Node3D", true, false)


func _assembly(line: Dictionary) -> void:
	var mv: Array = []
	for gname in line["move"]:
		mv.append_array(_group_nodes(String(gname)))
	var stations: Array = []
	var reveal_shader: Shader = load(_base_dir + "/fx/godot/assembly_reveal.gdshader")
	for st in line["stations"]:
		var arm: Array = []
		for gname in st["groups"]:
			arm.append_array(_group_nodes(String(gname)))
		var held: Array = []
		for gname in st["held"]:
			held.append_array(_group_nodes(String(gname)))
		var scan: Array = []
		for gname in st["scan"]:
			scan.append_array(_group_nodes(String(gname)))
		var ring: Array = []
		for gname in st.get("ring", []):
			ring.append_array(_group_nodes(String(gname)))
		var rv: Dictionary = st["reveal"]
		var mats: Array = []
		for nd in _group_nodes(String(rv["group"])):  # a part shows whole once its parcel reaches the arm
			var mi := nd as MeshInstance3D
			if mi == null:
				continue
			var src := mi.get_active_material(0) as BaseMaterial3D
			var sm := ShaderMaterial.new()
			sm.shader = reveal_shader
			if src:
				sm.set_shader_parameter("albedo_tex", src.albedo_texture if src.albedo_texture else src.emission_texture)
				sm.set_shader_parameter("tint", src.albedo_color)
			for k in ["s0", "spacing", "s_arm", "id_step"]:
				sm.set_shader_parameter(k, float(rv[k]))
			mi.material_override = sm
			mats.append(sm)
		var sk: Skeleton3D = null  # Stage 65: a skinned arm - one bone per joint (turret, shoulder, elbow, wrist, twist, 3 fingers)
		var bones := {}
		if st.has("rig"):
			for nd in arm:
				var mi := nd as MeshInstance3D
				if mi and mi.skin != null:
					sk = mi.get_node_or_null(mi.skeleton) as Skeleton3D
					if sk:
						break
			if sk:
				for role in st["rig"]["bones"]:
					bones[role] = sk.find_bone(String(st["rig"]["bones"][role]))
			for nd in arm + held + scan:  # bounds are the rest pose: never culled while the arm is swung out
				(nd as GeometryInstance3D).extra_cull_margin = 6.0
		stations.append([st, arm, held, scan, mats, ring, sk, bones])
	var belts: Array = []  # Stage 68: the belt surface runs with the parcels (UV offset on the belt's own material)
	if line.has("belt"):
		var bn := String(line["belt"]["material"])
		for node in level_root.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			for si in mi.get_surface_override_material_count():
				var bm := mi.get_active_material(si) as BaseMaterial3D
				if bm and (bm.resource_name == bn or bm.resource_name.begins_with(bn + "__")) and not belts.has(bm):
					belts.append(bm)
	_lines.append([line, mv, stations, belts])


func _update_lines() -> void:
	for ln in _lines:
		var line: Dictionary = ln[0]
		var ax := Vector3(line["axis"][0], line["axis"][1], line["axis"][2])
		var d := fmod(_t * float(line["speed"]), float(line["spacing"]))
		var off := ax * d
		for nd in ln[1]:
			(nd as Node3D).position = off
		if line.has("belt"):
			var sc: Array = line["belt"]["scroll"]
			for bm in ln[3]:
				(bm as BaseMaterial3D).uv1_offset = Vector3(fposmod(float(sc[0]) * _t, 1.0), fposmod(float(sc[1]) * _t, 1.0), 0.0)
		for sa in ln[2]:
			var st: Dictionary = sa[0]
			for sm in sa[4]:
				(sm as ShaderMaterial).set_shader_parameter("offset", d)
			var P := float(st["period"])
			var W := float(st["window"])
			var tau := fposmod(_t - float(st["t0"]), P)
			var u := fposmod(_t - float(st["t0"]) + W * 0.5, P)
			var k := 0.5 - 0.5 * cos(TAU * u / W) if u < W else 0.0  # dip to the parcel, deepest when it is under the claw
			var ang := deg_to_rad(float(st["angle_deg"])) * k
			var psi := 0.0
			var kb := 0.0
			var t_pick := 0.6 * P
			var picked := tau > 0.6 * P
			if st.has("bin_yaw_deg"):  # Stage 63: turn to the bin, reach in for the next canister, turn back
				var ty := float(st["turn"])
				var wb := float(st["bin_window"])
				var a := W * 0.5
				var b := a + ty
				var c := b + wb
				var pb := deg_to_rad(float(st["bin_yaw_deg"]))
				if tau >= a and tau < b:
					psi = pb * smoothstep(0.0, 1.0, (tau - a) / ty)
				elif tau >= b and tau < c:
					psi = pb
					kb = 0.5 - 0.5 * cos(TAU * (tau - b) / wb)
					ang += deg_to_rad(float(st["bin_angle_deg"])) * kb
				elif tau >= c and tau < c + ty:
					psi = pb * (1.0 - smoothstep(0.0, 1.0, (tau - c) / ty))
				t_pick = b + wb * 0.5
				picked = tau >= t_pick
			var sk := sa[6] as Skeleton3D
			var held_on := picked
			var scanning := absf(u - W * 0.5) < W * 0.35
			var ring_e := 0.0
			var ring_f := clampf((u - 0.15 * W) / (0.7 * W), 0.0, 1.0)
			if sk:  # Stage 66: a motion program (pipeline/arm_motion.py) - servo moves through the joints only, no sway
				var rig: Dictionary = st["rig"]
				var pg: Dictionary = rig["program"]
				var v := float(line["speed"])
				var s0 := float(pg["start"])
				var x := _t - float(st["t0"]) - s0
				var n := floorf(x / P)
				var tq := x - n * P + s0
				var J := _arm_joints(rig, pg, tq, v, P)
				var A := {"yaw": J[0], "shoulder": J[1], "elbow": J[2], "wrist": -(J[1] + J[2]),
					"twist": deg_to_rad(float(pg["twist_cycle"]) * n + _keyed(pg["twist"], tq, 0.0))}
				var fa := deg_to_rad(_keyed(pg["fingers"], tq, float(pg["fingers_start"])))
				for i in 3:
					A["finger%d" % (i + 1)] = fa
				var bones: Dictionary = sa[7]
				for role in A:
					if bones.has(role) and int(bones[role]) >= 0:
						var axv: Array = rig["axes"][role]
						sk.set_bone_pose_rotation(int(bones[role]), Quaternion(Vector3(axv[0], axv[1], axv[2]).normalized(), float(A[role])))
				var hh = pg.get("held_hidden")
				held_on = not (hh != null and tq >= float(hh[0]) and tq < float(hh[1]))
				var sc = pg.get("scan")
				scanning = sc != null and tq >= float(sc[0]) and tq < float(sc[1])
				if sc != null:  # the laser frame rides along with the parcel it scans
					ring_e = v * tq
					ring_f = clampf((tq - float(sc[0])) / (float(sc[1]) - float(sc[0])), 0.0, 1.0)
			if sk == null:  # no skeleton: the whole upper arm swings as one piece (Stage 61)
				# Construct Error: this transform was dropped upstream (0abdb30) but is still used here.
				var hinge := Vector3(st["hinge"][0], st["hinge"][1], st["hinge"][2]).normalized()
				var pv := Vector3(st["pivot"][0], st["pivot"][1], st["pivot"][2])
				var bas := Basis(Vector3.UP, psi) * Basis(hinge, ang)
				var xf := Transform3D(bas, pv - bas * pv)
				for nd in sa[1] + sa[2] + sa[3]:
					(nd as Node3D).transform = xf
			for nd in sa[2]:  # the held canister: gone from the drop until it is lifted out of the bin
				(nd as Node3D).visible = held_on
			for nd in sa[3]:  # the scan beam shows while the arm is down
				(nd as Node3D).visible = scanning
			for nd in sa[5]:  # the laser frame sweeps up and down the parcel while it scans
				(nd as Node3D).visible = scanning
				(nd as Node3D).position = ax * ring_e + Vector3(0.0, float(st.get("ring_travel", 0.6)) * (0.5 - 0.5 * cos(TAU * float(st.get("sweeps", 2)) * ring_f)), 0.0)


func _crusher(c: Dictionary) -> void:
	var lo := Vector3(c["kill"][0][0], c["kill"][0][1], c["kill"][0][2])
	var hi := Vector3(c["kill"][1][0], c["kill"][1][1], c["kill"][1][2])
	var area := Area3D.new()
	area.name = String(c["id"]) + "_Kill"
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = hi - lo
	cs.shape = bx
	cs.position = (lo + hi) * 0.5
	cs.disabled = true  # only while the ram is down
	area.add_child(cs)
	level_root.add_child(area)
	area.add_to_group(hazard_group)
	_crushers.append([c, _group_nodes(String(c["group"])), _group_nodes(String(c["warn_group"])), cs])


func _riser(r: Dictionary) -> void:
	var sk: Skeleton3D = null
	for nd in _group_nodes(String(r["group"])):
		var mi := nd as MeshInstance3D
		if mi and mi.skin != null:
			sk = mi.get_node_or_null(mi.skeleton) as Skeleton3D
			(mi as GeometryInstance3D).extra_cull_margin = float(r["pads"][0]["rise"]) + 2.0  # bounds are the raised pose
	if sk == null:
		push_warning("rising pads " + String(r["id"]) + ": no skinned mesh / skeleton found")
		return
	var bones := {}
	for i in sk.get_bone_count():
		bones[sk.get_bone_name(i)] = i
	var cols: Array = []  # each pad's colliders (collision.glb nodes named after the cap) stay off until it is up
	for pd in r["pads"]:
		var cs: Array = []
		for cn in pd["colliders"]:
			# Construct Error: the import names the StaticBody3D after the
			# collider, its shape is just "CollisionShape3D" - take those too.
			for n in get_tree().root.find_children(String(cn) + "*", "", true, false):
				var shapes: Array = [n] if n is CollisionShape3D else n.find_children("*", "CollisionShape3D", false, false)
				for c in shapes:
					if not cs.has(c):
						(c as CollisionShape3D).disabled = true
						cs.append(c)
		cols.append(cs)
	var tr: Dictionary = r["trigger"]  # a player entering this sphere starts the sequence
	var area := Area3D.new()
	area.name = String(r["id"]) + "_Trigger"
	var sh := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = float(tr["radius"])
	sh.shape = sp
	sh.position = Vector3(tr["center"][0], tr["center"][1], tr["center"][2])
	area.add_child(sh)
	level_root.add_child(area)
	var drips: Array = []  # Stage 89: goo dripping off a platform's rim once it is up (falling drops into the pool)
	for pd in r["pads"]:
		drips.append(_drips(pd) if pd.has("drips") else null)
	var rec := [r, sk, bones, cols, -1.0, drips]
	area.body_entered.connect(func(b: Node3D) -> void:
		if rec[4] < 0.0 and b is CharacterBody3D:
			rec[4] = _t)
	_risers.append(rec)
	_pose_riser(rec, -1.0)


## Stage 80: start a riser sequence from game code (e.g. a cutscene) instead of the trigger sphere.
func raise_pads(riser_id: String) -> void:
	for rec in _risers:
		if String(rec[0]["id"]) == riser_id and rec[4] < 0.0:
			rec[4] = _t


func _pose_riser(rec: Array, t: float) -> void:  # t: seconds since the trigger (< 0: still waiting)
	var r: Dictionary = rec[0]
	var sk: Skeleton3D = rec[1]
	var bones: Dictionary = rec[2]
	var D := float(r["rise_s"])
	for k in r["pads"].size():
		var pd: Dictionary = r["pads"][k]
		var tk: float = t - k * float(r["stagger"]) if t >= 0.0 else -1.0
		var off := -float(pd["rise"])
		if tk >= 0.0 and tk < D:
			off = -float(pd["rise"]) * pow(1.0 - tk / D, 3.0)  # bursts up, decelerates
		elif tk >= D:
			var tb := tk - D
			off = 0.22 * sin(9.0 * tb) * exp(-4.0 * tb) if tb < 1.4 else 0.0  # settles with a damped bob
		var rs := 0.4
		var ry := -3.0
		var r0 := 0.35 * D
		if tk >= r0:  # surge ring bursts out where the pad breaks the surface, sinking back under it
			var f := clampf((tk - r0) / 1.6, 0.0, 1.0)
			var e := 1.0 - pow(1.0 - f, 2.0)
			rs = 0.4 + 2.6 * e
			ry = -0.9 * f * f if f < 1.0 else -3.0
		var bi: int = bones.get(String(pd["joint"]), -1)
		if bi >= 0:
			sk.set_bone_pose_position(bi, sk.get_bone_rest(bi).origin + Vector3(0.0, off, 0.0))
		var ri: int = bones.get(String(pd["ring"]), -1)
		if ri >= 0:
			sk.set_bone_pose_position(ri, sk.get_bone_rest(ri).origin + Vector3(0.0, ry, 0.0))
			sk.set_bone_pose_scale(ri, Vector3(rs, 1.0, rs))
		for c in rec[3][k]:
			(c as CollisionShape3D).disabled = tk < 0.85 * D
		var gf := 0.0  # Stage 91: the goo drains away "hold" s after the pad is up, over "fade" s (smoothstep)
		if pd.has("goo"):
			var go: Dictionary = pd["goo"]
			gf = clampf((tk - D - float(go["hold"])) / float(go["fade"]), 0.0, 1.0) if tk >= 0.0 else 0.0
			gf = gf * gf * (3.0 - 2.0 * gf)
			var gi: int = bones.get(String(go["drips"]), -1)
			if gi >= 0:  # drips shrink up into the lip while sliding down a little
				sk.set_bone_pose_position(gi, sk.get_bone_rest(gi).origin + Vector3(0.0, -0.6 * gf, 0.0))
				sk.set_bone_pose_scale(gi, Vector3(1.0, maxf(1.0 - gf, 0.001), 1.0))
			var si: int = bones.get(String(go["strands"]), -1)
			if si >= 0:  # strands fall into the pool (shrink to their bottom at the surface) and thin out
				sk.set_bone_pose_scale(si, Vector3(maxf(1.0 - 0.6 * gf, 0.001), maxf(1.0 - gf, 0.001), maxf(1.0 - 0.6 * gf, 0.001)))
		var dp = rec[5][k]
		if dp != null:
			(dp as CPUParticles3D).emitting = tk >= D and gf < 0.5
		if pd.has("pickup"):  # Stage 89: the item area (apply_mobile.gd) is live once the platform is up
			for pa in get_tree().root.find_children(String(pd["pickup"]) + "_Pickup", "Area3D", true, false):
				(pa as Area3D).set_deferred("monitoring", tk >= 0.85 * D)


func _drips(pd: Dictionary) -> CPUParticles3D:  # drops falling from the rim points to the liquid
	var pts := PackedVector3Array()
	for q in pd["drips"]:
		pts.append(Vector3(q[0], q[1], q[2]))
	var h := maxf(pts[0].y - float(pd["drip_to"]), 0.5)
	var p := CPUParticles3D.new()
	p.name = String(pd["joint"]) + "_Drips"
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	p.emission_points = pts
	p.amount = maxi(8, pts.size() * 2)
	p.lifetime = sqrt(2.0 * h / 9.8) + 0.1
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.3
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	p.local_coords = false
	var m := SphereMesh.new()
	m.radius = 0.06
	m.height = 0.2
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.55, 1.0, 0.2)
	m.material = mat
	p.mesh = m
	p.emitting = false
	level_root.add_child(p)
	return p


func _update_risers() -> void:
	for rec in _risers:
		if rec[4] >= 0.0 and _t - rec[4] < 60.0:
			_pose_riser(rec, _t - rec[4])


func _wind(w: Dictionary) -> void:
	var o := Vector3(w["origin"][0], w["origin"][1], w["origin"][2])
	var d := Vector3(w["dir"][0], w["dir"][1], w["dir"][2]).normalized()
	var L := float(w["length"])
	var rmax := float(w["radius"]) + float(w["spread"]) * L
	var area := Area3D.new()  # bounding box of the cone: bodies inside are tested against the cone each frame
	area.name = String(w["id"]) + "_Wind"
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(2.0 * rmax, 2.0 * rmax, L)
	cs.shape = bx
	area.add_child(cs)
	level_root.add_child(area)
	area.global_transform = Transform3D(Basis.looking_at(-d, Vector3.UP), o + d * (L * 0.5))
	var pr := CPUParticles3D.new()  # wind streaks
	pr.amount = 70
	pr.lifetime = L / 20.0
	pr.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	pr.emission_sphere_radius = float(w["radius"]) * 0.8
	pr.direction = Vector3(0, 0, -1)
	pr.spread = rad_to_deg(atan(float(w["spread"])))
	pr.gravity = Vector3.ZERO
	pr.initial_velocity_min = 16.0
	pr.initial_velocity_max = 22.0
	pr.particle_flag_align_y = true
	var qm := QuadMesh.new()
	qm.size = Vector2(0.05, 1.1)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.albedo_color = Color(0.85, 1.0, 0.8, 0.28)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = sm
	pr.mesh = qm
	pr.emitting = false
	level_root.add_child(pr)
	pr.global_transform = Transform3D(Basis.looking_at(d, Vector3.UP), o)
	var rotor := level_root.find_child(String(w["rotor"]), true, false) as Node3D
	var rec := [w, rotor, area, pr, -1.0]  # [4]: time the stop trigger fired (-1: still blowing)
	if w.has("trigger"):  # Stage 85: full force until a player reaches the trigger sphere, then it spins down for good
		var ta := Area3D.new()
		ta.name = String(w["id"]) + "_Stop"
		var tcs := CollisionShape3D.new()
		var tsp := SphereShape3D.new()
		tsp.radius = float(w["trigger"]["radius"])
		tcs.shape = tsp
		tcs.position = Vector3(w["trigger"]["center"][0], w["trigger"]["center"][1], w["trigger"]["center"][2])
		ta.add_child(tcs)
		level_root.add_child(ta)
		ta.body_entered.connect(func(b: Node3D) -> void:
			if rec[4] < 0.0 and b is CharacterBody3D:
				rec[4] = _t)
	_winds.append(rec)


## Stage 85: stop a turbine's wind from game code (it spins down over spin_down s).
func stop_wind(wind_id: String) -> void:
	for wr in _winds:
		if String(wr[0]["id"]) == wind_id and wr[4] < 0.0:
			wr[4] = _t


func _wind_strength(wr: Array, t: float) -> float:  # 0..1: triggered - 1 until the stop, then down over spin_down; else the cycle
	var w: Dictionary = wr[0]
	if w.has("trigger"):
		return 1.0 if wr[4] < 0.0 else 1.0 - smoothstep(0.0, float(w["spin_down"]), t - wr[4])
	var ra := float(w["ramp"])
	var bl := float(w["blast"])
	var u := fposmod(t + float(w["phase"]), 2.0 * ra + bl + float(w["calm"]))
	if u < ra:
		return smoothstep(0.0, ra, u)
	if u < ra + bl:
		return 1.0
	if u < 2.0 * ra + bl:
		return 1.0 - smoothstep(0.0, ra, u - ra - bl)
	return 0.0


func _physics_process(delta: float) -> void:
	for wr in _winds:
		var w: Dictionary = wr[0]
		var s := _wind_strength(wr, _t)
		if s <= 0.01:
			continue
		var o := Vector3(w["origin"][0], w["origin"][1], w["origin"][2])
		var d := Vector3(w["dir"][0], w["dir"][1], w["dir"][2]).normalized()
		for b in (wr[2] as Area3D).get_overlapping_bodies():
			var cb := b as CharacterBody3D
			if cb == null:
				continue
			var rel := cb.global_position + Vector3(0.0, 0.9, 0.0) - o
			var along := rel.dot(d)
			if along < 0.0 or along > float(w["length"]):
				continue
			if (rel - d * along).length() > float(w["radius"]) + float(w["spread"]) * along:
				continue
			cb.move_and_collide(d * float(w["push"]) * s * (1.0 - 0.35 * along / float(w["length"])) * delta)
			if not cb.is_on_floor():
				cb.velocity.y += float(w["lift"]) * s * delta  # airborne: lifted - a jump only carries them further out


func _update_winds(delta: float) -> void:
	for wr in _winds:
		var w: Dictionary = wr[0]
		var s := _wind_strength(wr, _t)
		if wr[1] != null:
			(wr[1] as Node3D).rotate_object_local(Vector3.UP, float(w["rpm"]) * TAU / 60.0 * (float(w["idle"]) + (1.0 - float(w["idle"])) * s) * delta)
		(wr[3] as CPUParticles3D).emitting = s > 0.25


func _update_crushers() -> void:
	for cr in _crushers:
		var c: Dictionary = cr[0]
		var P := float(c["period"])
		var tr := float(c["travel"])
		var wa := float(c["warn"])
		var dn := float(c["down"])
		var ho := float(c["hold"])
		var ri := float(c["rise"])
		var t0 := P - wa - dn - ho - ri
		var u := fposmod(_t + float(c["phase"]), P)
		var off := 0.0
		var warn := u >= t0 and u < t0 + wa
		if u >= t0 + wa and u < t0 + wa + dn:  # slam: accelerating
			var f := (u - t0 - wa) / dn
			off = -tr * f * f
		elif u >= t0 + wa + dn and u < t0 + wa + dn + ho:
			off = -tr
		elif u >= t0 + wa + dn + ho:  # climb back, eased
			off = -tr * (1.0 - smoothstep(0.0, 1.0, (u - t0 - wa - dn - ho) / ri))
		for nd in cr[1]:
			(nd as Node3D).position = Vector3(0.0, off, 0.0)
		for nd in cr[2]:  # warning lamps blink before the slam
			(nd as Node3D).visible = not warn or int(_t * 8.0) % 2 == 0
		(cr[3] as CollisionShape3D).set_deferred("disabled", tr + off > 1.8)  # deadly once the head is lower than a player


static func _smoother(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * x * (x * (6.0 * x - 15.0) + 10.0)


static func _keyed(keys: Array, tau: float, v0: float) -> float:
	var val := v0
	for k in keys:
		if tau >= float(k[1]):
			val = float(k[3])
		elif tau >= float(k[0]):
			return float(k[2]) + (float(k[3]) - float(k[2])) * _smoother((tau - float(k[0])) / (float(k[1]) - float(k[0])))
	return val


static func _arm_target(rig: Dictionary, q: Dictionary, tau: float, v: float) -> Vector3:
	if q["k"] == "bin":
		return Vector3(rig["bin"][0], float(rig["bin"][1]) + float(q["h"]), rig["bin"][2])
	var e := v * tau if q["k"] == "track" else float(q["e"])
	return Vector3(float(rig["tip"][0]) + float(rig["axis"][0]) * e, float(rig["tip"][1]) + float(q["h"]), float(rig["tip"][2]) + float(rig["axis"][2]) * e)


static func _arm_ik(rig: Dictionary, p: Vector3) -> Array:  # [yaw, shoulder, elbow] offsets from the rest pose (arm_motion.ik)
	var l1 := float(rig["l1"])
	var l2 := float(rig["l2"])
	var dx := p.x - float(rig["base"][0])
	var dz := p.z - float(rig["base"][1])
	var r := sqrt(dx * dx + dz * dz)
	var dy := p.y + float(rig["claw"]) - float(rig["py"])
	var D := clampf(sqrt(r * r + dy * dy), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var b1 := atan2(r, dy) - acos(clampf((l1 * l1 + D * D - l2 * l2) / (2.0 * l1 * D), -1.0, 1.0))
	var b2 := atan2(r - l1 * sin(b1), dy - l1 * cos(b1))
	var yw := fposmod(atan2(dx, dz) - float(rig["yaw0"]) + PI, TAU) - PI
	return [yw, b1 - float(rig["a1"]), (b2 - b1) - (float(rig["a2"]) - float(rig["a1"]))]


static func _arm_joints(rig: Dictionary, pg: Dictionary, tau: float, v: float, period: float) -> Array:
	for sg in pg["segs"]:
		var a := float(sg[0])
		var b := float(sg[1])
		if b <= a:
			b += period
		if tau >= a and tau < b:
			var w := _smoother((tau - a) / (b - a))
			var pa := _arm_target(rig, sg[3], tau, v)
			var pb := _arm_target(rig, sg[4], tau, v)
			if sg[2] == "lin":
				return _arm_ik(rig, pa.lerp(pb, w))
			var ja := _arm_ik(rig, pa)
			var jb := _arm_ik(rig, pb)
			return [lerpf(ja[0], jb[0], w), lerpf(ja[1], jb[1], w), lerpf(ja[2], jb[2], w)]
	return [0.0, 0.0, 0.0]


func _bubbles(fx: Dictionary, p: Dictionary) -> void:
	var tubes: Array = fx.get("tubes", [])
	if tubes.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 48
	var verts := PackedVector3Array(); var uvs := PackedVector2Array(); var uv2s := PackedVector2Array()
	var cols := PackedColorArray(); var idx := PackedInt32Array()
	var lo := Vector3(INF, INF, INF); var hi := -lo
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for t in tubes:
		var c := Vector3(t[0], t[1], t[2]); var h := float(t[3]); var r := float(t[4])
		lo = lo.min(c - Vector3(r, 0, r)); hi = hi.max(c + Vector3(r, h + 1.0, r))
		var n := clampi(int(round(float(p["density"]) * h * r)), 12, 140)
		for i in n:
			var seed := Color(rng.randf(), rng.randf(), rng.randf(), rng.randf())
			var b := verts.size()
			for k in 4:
				verts.append(c); uvs.append(corners[k]); uv2s.append(Vector2(h, r)); cols.append(seed)
			idx.append_array(PackedInt32Array([b, b + 1, b + 2, b, b + 2, b + 3]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts; arr[Mesh.ARRAY_TEX_UV] = uvs; arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_COLOR] = cols; arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = load(_base_dir + "/fx/godot/tube_bubbles.gdshader")
	mat.render_priority = -1  # drawn before the tinted glass, so the glass shades them
	for k in ["wobble", "alpha", "nozzles"]:
		mat.set_shader_parameter(k, float(p[k]))
	mat.set_shader_parameter("size_range", Vector2(p["size"][0], p["size"][1]))
	mat.set_shader_parameter("speed_range", Vector2(p["speed"][0], p["speed"][1]))
	mat.set_shader_parameter("tint", Color(p["color"][0], p["color"][1], p["color"][2]))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh; mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(lo, hi - lo)  # vertices sit at the tube bottoms; the shader lifts them
	add_child(mi)


func _material_shader(fx: Dictionary, p: Dictionary) -> void:
	var shader: Shader = load(_base_dir + "/fx/godot/tv_static.gdshader")
	var made := {}  # one ShaderMaterial per source material (merged mobile cells share it)
	for node in level_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var src := mi.get_active_material(0) as BaseMaterial3D
		if src == null or not src.resource_name.begins_with(String(fx.get("target_material", "?"))):
			continue
		if not made.has(src):
			var sm := ShaderMaterial.new()
			sm.shader = shader
			sm.set_shader_parameter("albedo_tex", src.albedo_texture)
			for k in ["amount", "grain", "fps", "signal_every", "signal_len", "roll_speed", "glow", "seed"]:
				sm.set_shader_parameter(k, float(p[k]))
			for k in ["egg_id", "egg_every", "egg_len"]:  # Stage 52: easter egg on one screen
				if p.has(k):
					sm.set_shader_parameter(k, float(p[k]))
			if p.has("egg_rect"):
				sm.set_shader_parameter("egg_rect", Vector4(p["egg_rect"][0], p["egg_rect"][1], p["egg_rect"][2], p["egg_rect"][3]))
			made[src] = sm
		mi.material_override = made[src]


func _gradient(c: Array, a: float) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(c[0], c[1], c[2], 0.0))
	g.set_color(1, Color(c[0], c[1], c[2], 0.0))
	g.add_point(0.15, Color(c[0], c[1], c[2], a))
	return g


func _particles(fx: Dictionary, p: Dictionary) -> void:
	var tex: Texture2D = load(_base_dir + "/fx/" + str(p["texture"]) + ".png")
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	if p.get("blend", "alpha") == "add":
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var quad := QuadMesh.new()
	quad.material = mat
	var spots: Array = []
	if fx.has("emitters"):
		for e in fx["emitters"]:
			spots.append(e)
	elif fx.has("area"):
		spots.append({"area": fx["area"]})
	if fx.get("merge_emitters", false) and spots.size() > 1:
		# one draw call for the whole effect: a single system emitting from every point
		var pts := PackedVector3Array()
		for e in spots:
			pts.append(Vector3(e["pos"][0], e["pos"][1], e["pos"][2]))
		spots = [{"points": pts}]
	for e in spots:
		var cp := CPUParticles3D.new()
		cp.mesh = quad
		cp.lifetime = float(p["lifetime"])
		if p.has("count"):
			cp.amount = int(p["count"])
			cp.preprocess = cp.lifetime
		elif p.has("burst"):
			cp.amount = int(p["burst"])
			cp.one_shot = true
			cp.explosiveness = 1.0
			cp.emitting = false
			_bursts.append([cp, randf_range(p["interval"][0], p["interval"][1]), p["interval"][0], p["interval"][1]])
		else:
			cp.amount = max(1, int(ceil(float(p["rate"]) * cp.lifetime))) * (e["points"].size() if e.has("points") else 1)
		if e.has("points"):
			cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
			cp.emission_points = e["points"]
		elif e.has("area"):
			var a: Array = e["area"]
			var top: bool = p.has("rate") and not p.has("count")
			var y0: float = a[1] if top else (a[1] + a[4]) * 0.5
			cp.position = Vector3((a[0] + a[3]) * 0.5, y0, (a[2] + a[5]) * 0.5)
			cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			cp.emission_box_extents = Vector3((a[3] - a[0]) * 0.5, 0.05 if top else (a[4] - a[1]) * 0.5, (a[5] - a[2]) * 0.5)
		else:
			cp.position = Vector3(e["pos"][0], e["pos"][1], e["pos"][2])
			var r: float = float(e.get("radius", p.get("radius", 0.0)))
			if r > 0.0:
				cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
				cp.emission_sphere_radius = r
		cp.direction = Vector3(0, 1, 0)
		cp.spread = float(p.get("spread", 15))
		cp.initial_velocity_min = float(p["speed"][0])
		cp.initial_velocity_max = float(p["speed"][1])
		var wind: Array = p.get("wind", [0, 0, 0])
		cp.gravity = Vector3(wind[0], float(p.get("gravity", 0.0)), wind[2])
		var s0: float = float(p["size"][0])
		var s1: float = float(p["size"][1])
		var smax: float = max(s0, s1)
		cp.scale_amount_min = smax
		cp.scale_amount_max = smax
		var cv := Curve.new()
		cv.add_point(Vector2(0.0, s0 / smax))
		cv.add_point(Vector2(1.0, s1 / smax))
		cp.scale_amount_curve = cv
		cp.color_ramp = _gradient(p["color"], float(p["alpha"]))
		add_child(cp)


func _fog_sheet(fx: Dictionary, p: Dictionary) -> void:
	if not fx.has("area"):
		return
	var a: Array = fx["area"]
	var shader: Shader = load(_base_dir + "/fx/godot/fog_sheet.gdshader")
	for i in range(int(p.get("layers", 1))):
		var mi := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(a[3] - a[0], a[5] - a[2])
		mi.mesh = plane
		var sm := ShaderMaterial.new()
		sm.shader = shader
		sm.set_shader_parameter("color", Color(p["color"][0], p["color"][1], p["color"][2]))
		sm.set_shader_parameter("opacity", float(p["opacity"]) / (1.0 + i))
		sm.set_shader_parameter("scroll", Vector2(p["scroll"][0], p["scroll"][1]) * (1.0 + 0.5 * i))
		mi.material_override = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3((a[0] + a[3]) * 0.5, a[1] + float(p["height"]) + 0.6 * i, (a[2] + a[5]) * 0.5)
		add_child(mi)


func _sun_dir() -> Vector3:
	# direction TO the sun: from environment.json next to effects.json (same values the browser preview uses)
	var env = JSON.parse_string(FileAccess.get_file_as_string(_base_dir + "/environment.json"))
	if env == null:
		return Vector3(0.0, 0.3, -1.0)
	var d: Array = env["sun"]["direction_to_sun"]
	return Vector3(d[0], d[1], d[2]).normalized()


func _cloud_layer(fx: Dictionary, p: Dictionary) -> void:
	var shader: Shader = load(_base_dir + "/fx/godot/cloud_layer.gdshader")
	var c: Array = fx.get("center", [0.0, 0.0])
	for i in range(int(p["layers"])):
		var r := float(p["radius"]) * (1.0 - 0.1 * i)
		var mi := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(2.0 * r, 2.0 * r)   # square mesh, the shader fades it to a disc
		plane.subdivide_width = 8
		plane.subdivide_depth = 8
		mi.mesh = plane
		var sm := ShaderMaterial.new()
		sm.shader = shader
		for k in ["color", "shade", "glow"]:
			sm.set_shader_parameter(k, Color(p[k][0], p[k][1], p[k][2]))
		sm.set_shader_parameter("opacity", float(p["opacity"]) * (0.7 if i > 0 else 1.0))
		sm.set_shader_parameter("coverage", float(p["coverage"]) + 0.06 * i)
		sm.set_shader_parameter("scale", float(p["scale"]) * (1.0 + 0.31 * i))
		sm.set_shader_parameter("scroll", Vector2(p["scroll"][0], p["scroll"][1]))
		sm.set_shader_parameter("center", Vector2(c[0], c[1]))
		sm.set_shader_parameter("radius", r)
		sm.set_shader_parameter("inner", float(p["inner"]))
		sm.set_shader_parameter("seed", 17.3 * i)
		sm.set_shader_parameter("sun_dir", _sun_dir())
		mi.material_override = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(c[0], float(p["y"]) + float(p["spacing"]) * i, c[1])
		add_child(mi)


func _cloud_puffs(fx: Dictionary, p: Dictionary) -> void:
	## all puffs of one effect = ONE MultiMeshInstance3D (one draw call); billboard StandardMaterial3D, per-instance colour
	var em: Array = fx.get("emitters", [])
	var idx: Array = fx.get("emitters_by_quality", {}).get(quality, range(em.size()))
	if idx.is_empty():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, float(p["squash"]))
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = load(_base_dir + "/fx/cloud.png")
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 4.0
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 1.5
	mat.distance_fade_max_distance = 9.0
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = idx.size()
	var sun := _sun_dir()
	var lit := Color(p["color"][0], p["color"][1], p["color"][2])
	var glo := Color(p["glow"][0], p["glow"][1], p["glow"][2])
	for k in range(idx.size()):
		var e: Dictionary = em[int(idx[k])]
		var s := float(e["size"])
		var pos := Vector3(e["pos"][0], e["pos"][1], e["pos"][2])
		mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3(s, s, s)), pos))
		# sun-side puffs glow warmer (baked per instance; the browser preview computes it per view)
		var side: float = clamp(Vector2(pos.x, pos.z).normalized().dot(Vector2(sun.x, sun.z).normalized()), 0.0, 1.0)
		var c := lit.lerp(glo, 0.35 * side)
		c.a = float(p["opacity"])
		mm.set_instance_color(k, c)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


var _flyers: Array = []   # [MultiMesh, ships Array]


func _flyby(fx: Dictionary, p: Dictionary) -> void:
	## background ships on deterministic arcs (effects.json "ships"), one MultiMesh per design, unshaded vertex colours
	var by := {}
	for sh in p["ships"]:
		if not by.has(sh["design"]):
			by[sh["design"]] = []
		by[sh["design"]].append(sh)
	var hc := Color(p["color"][0], p["color"][1], p["color"][2])
	var gc := Color(p["glow"][0], p["glow"][1], p["glow"][2])
	var ac := Color(p["accent"][0], p["accent"][1], p["accent"][2]) if p.get("accent") != null else gc  # Stage 95: glow flag 2
	for d in by.keys():
		var g: Dictionary = fx["meshes"][d]
		var verts := PackedVector3Array(); var cols := PackedColorArray(); var idx := PackedInt32Array()
		for i in range(g["v"].size()):
			verts.append(Vector3(g["v"][i][0], g["v"][i][1], g["v"][i][2])); cols.append(ac if int(g["glow"][i]) == 2 else (gc if int(g["glow"][i]) == 1 else hc))
		for f in g["f"]:
			idx.append(int(f[0])); idx.append(int(f[2])); idx.append(int(f[1]))  # Godot front faces are clockwise
		var arr := []; arr.resize(Mesh.ARRAY_MAX); arr[Mesh.ARRAY_VERTEX] = verts; arr[Mesh.ARRAY_COLOR] = cols; arr[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := StandardMaterial3D.new(); mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mat.vertex_color_use_as_albedo = true
		mesh.surface_set_material(0, mat)
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = mesh; mm.instance_count = by[d].size()
		var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm; mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi); _flyers.append([mm, by[d]])


func _update_flyers() -> void:
	for f in _flyers:
		var mm: MultiMesh = f[0]
		for i in range(f[1].size()):
			var sh: Dictionary = f[1][i]
			var cyc: float = sh["travel"] + sh["gap"]
			var lp: bool = int(sh.get("loop", 0)) == 1  # Stage 95: circling a spot for good
			var k: float = (fposmod(_t + sh["phase"], sh["travel"]) if lp else fmod(_t + sh["phase"], cyc)) / sh["travel"]
			if k >= 1.0:
				mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)); continue
			var env: float = 1.0 if lp else smoothstep(0.0, 0.2, k) * (1.0 - smoothstep(0.8, 1.0, k))  # grow + approach / shrink + recede
			var R: float = sh["r"] + float(sh["recede"]) * (1.0 - env) if sh.has("recede") else sh["r"] * (1.0 + 0.5 * (1.0 - env))
			var az: float = deg_to_rad(sh["a0"] + (sh["a1"] - sh["a0"]) * k); var dir: float = sign(sh["a1"] - sh["a0"])
			var pos := Vector3(float(sh.get("cx", 0.0)) + R * sin(az), sh["y"] + (0.0 if lp else 18.0 * (1.0 - env)) + sh["bob"] * sin(_t * 0.7 + sh["phase"]), float(sh.get("cz", 0.0)) - R * cos(az))
			var b := Basis.from_euler(Vector3(0.0, atan2(-cos(az) * dir, -sin(az) * dir), 0.12 * dir)).scaled(Vector3.ONE * max(float(sh["size"]) * env, 0.001))
			mm.set_instance_transform(i, Transform3D(b, pos))


func _process(delta: float) -> void:
	_t += delta
	for sp in _spins:
		(sp[0] as Node3D).rotate_object_local(Vector3.UP, float(sp[1]) * delta)
	_update_lines()
	_update_crushers()
	_update_risers()
	_update_winds(delta)
	for br in _bobs:  # Stage 92: lift + sway about the pivot (world)
		var b: Dictionary = br[0]
		var P := float(b["period"])
		var sw := deg_to_rad(float(b["sway"]))
		var tp := _t + float(b["phase"])
		var basis := Basis.from_euler(Vector3(sw * sin(TAU * tp / (P * 1.3)), sw * 0.6 * sin(TAU * tp / (P * 2.3)), sw * cos(TAU * tp / (P * 1.7))))
		var pv := Vector3(b["pivot"][0], b["pivot"][1], b["pivot"][2])
		var tr := Transform3D(basis, pv - basis * pv + Vector3(0.0, float(b["amp"]) * sin(TAU * tp / P), 0.0))
		for nr in br[1]:
			(nr[0] as Node3D).transform = tr * (nr[1] as Transform3D)
	for la in _launch:
		(la[0] as Node3D).position = (la[1] as Vector3) + Vector3.UP * minf(fmod(_t + float(la[4]), float(la[3])) * float(la[2]), float(la[5]))
	for tv in _travel:
		(tv[0] as Node3D).position = (tv[1] as Vector3) + Vector3.UP * fmod(_t * float(tv[2]), float(tv[3]))
	_update_flyers()
	for an in _anims:
		var m: BaseMaterial3D = an[0]
		var p: Dictionary = an[2]
		if an[3] == "pulse_light":
			m.emission_energy_multiplier = an[1] * (1.0 + float(p["amount"]) * sin(TAU * float(p["speed"]) * _t + float(p["phase"])))
		else:
			an[4] -= delta
			if an[4] <= 0.0:
				an[4] = 1.0 / float(p["rate"])
				m.emission_energy_multiplier = an[1] * (1.0 - float(p["amount"]) * randf())
	for b in _bursts:
		b[1] -= delta
		if b[1] <= 0.0:
			(b[0] as CPUParticles3D).restart()
			b[1] = randf_range(b[2], b[3])
	if _sky_speed != 0.0 and environment and environment.environment:
		environment.environment.sky_rotation.y += _sky_speed * delta
