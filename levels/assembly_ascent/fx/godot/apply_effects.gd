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
var _shake: float = 0.0  # Stage 103: camera shake left from a press impact (h/v offset, decays)
var _boss_lifts: Array = []  # Stage 173: {"d", "nodes", "lamps", "body", "trig", "phase", "t0"}
signal boss_lift_landed(id: String, spawn: Vector3)  # Stage 173: spawn the mini boss at 'spawn' (the car's deck)


var _spins: Array = []  # [rotor node, rad/s]
var _travel: Array = []  # [node, rest position, speed m/s, spacing m] (Stage 43: barrels up the column bores)
var _launch: Array = []  # [node, rest position, speed, period, phase, travel] (Stage 49: pods shooting up the columns)
var _crushers: Array = []  # Stage 72: [crusher dict, ram nodes, warning lamps, kill CollisionShape3D]
var _winds: Array = []  # Stage 82: [wind dict, rotor node, Area3D, CPUParticles3D streaks]
var _saws: Array = []  # Stage 97/101: [saw dict, [[joint, [[node, rest]...]]...], kill Area3D]
var _sweepers: Array = []  # Stage 98: [sweeper dict, [[rotor node, rest]...], pivot Node3D carrying the kill areas]
var _belts: Array = []  # Stage 97: [belt dict, [[chevron node, rest position]...], rider Area3D]
var _pod_paths: Array = []  # Stage 186: {"d": pod_path dict, "sk": Skeleton3D, "bones": {name: index}}
var _boss_dead := false  # Stage 190: set by boss_defeated() - the conveyors stop
var _floaters: Array = []  # Stage 123: {"d": floater rig dict, "sk": Skeleton3D, "bones": {name: index}, "bodies": [AnimatableBody3D per pad]}
var _jets: Array = []  # Stage 119: {"d": jet dict, "parts": {key: [[node, rest]...]}, "trig": Area3D, "use": terminal Area3D, "phase", "t0"}
var _lifts: Array = []  # Stage 108: {"d": lift dict, "nodes": [Node3D], "body": AnimatableBody3D, "ride": Area3D, "calls": [[call dict, Area3D]], "s", "dir", "p", "board"}
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
			"saw":  # Stage 97: a saw blade chopping across a walkway (kill zone follows the blade)
				_saw(fx["saw"])
			"sweeper":  # Stage 98: spinner arms sweeping a deck (bars to jump, spiked balls to dodge)
				_sweeper(fx["sweeper"])
			"lift":  # Stage 108: a ride-on lift pad
				_lift(fx["lift"])
			"boss_lift":  # Stage 173: the car coming down the roof shaft with the mini boss
				_boss_lift(fx["boss_lift"])
			"jet":  # Stage 119: a jetpack screen with a big red button
				_jet(fx["jet"])
			"floater":  # Stage 123: a floating (bobbing) walkable pad
				_floater(fx["floater"])
			"pod_path":  # Stage 186: pods riding the bent roof pipes (one skinned rig, a bone per pod)
				_pod_path(fx["pod_path"])
			"character":  # Stage 152: an animated character (the specimen in the vat): idle loop, alert when players come close, bob
				_character(fx["character"])
			"belt":  # Stage 97: a conveyor ramp - chevrons slide, riders are carried
				_belt(fx["belt"])
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
				# Construct Error: this transform was dropped upstream but is still used here.
				var hv: Array = st.get("hinge", [1, 0, 0])
				var pa: Array = st.get("pivot", [0, 0, 0])
				var hinge := Vector3(hv[0], hv[1], hv[2]).normalized()
				var pv := Vector3(pa[0], pa[1], pa[2])
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


func _saw(w: Dictionary) -> void:
	var links: Array = []  # Stage 101: [joint dict, [[node, rest]...]] shoulder -> elbow -> wrist (the last one also spins the blade)
	var J: Array = w.get("joints", [{"group": w["arm"], "pivot": w["pivot"], "amp": w["amp"], "lag": 0.0}, {"group": w["blade"], "pivot": w["center"], "amp": 0.0, "lag": 0.0}])
	for j in J:
		var nodes: Array = []
		for nd in _group_nodes(String(j["group"])):
			nodes.append([nd, (nd as Node3D).transform])
		links.append([j, nodes])
	var spin: Array = []  # Stage 102: a separate spin group (the blade) riding on the last joint
	if w.has("spin") and not J.any(func(j): return String(j["group"]) == String(w["spin"])):
		for nd in _group_nodes(String(w["spin"])):
			spin.append([nd, (nd as Node3D).transform])
	var area := Area3D.new()
	area.name = String(w["id"]) + "_Kill"
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = float(w["radius"]) + 0.1
	cy.height = 1.4
	cs.shape = cy
	area.add_child(cs)
	level_root.add_child(area)
	area.add_to_group(hazard_group)
	_saws.append([w, links, area, spin])


func _sweeper(sw: Dictionary) -> void:
	var rot: Array = []
	for nd in _group_nodes(String(sw["group"])):
		rot.append([nd, (nd as Node3D).transform])
	var piv := Node3D.new()
	piv.name = String(sw["id"]) + "_KillPivot"
	piv.position = Vector3(sw["center"][0], sw["center"][1], sw["center"][2])
	level_root.add_child(piv)
	var r0 := float(sw["r0"])
	var r1 := float(sw["r1"])
	for a0 in sw["arms"]:
		var a := deg_to_rad(float(a0))
		var d := Vector3(sin(a), 0.0, cos(a))
		var bar := Area3D.new()
		var bcs := CollisionShape3D.new()
		var bb := BoxShape3D.new()
		bb.size = Vector3(0.5, 2.0 * float(sw["bar_half"]), r1 - r0)
		bcs.shape = bb
		bar.add_child(bcs)
		bar.position = d * ((r0 + r1) * 0.5) + Vector3(0.0, float(sw["bar_y"]), 0.0)
		bar.rotation.y = a
		bar.add_to_group(hazard_group)
		piv.add_child(bar)
		var ball := Area3D.new()
		var scs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = float(sw["ball_r"])
		scs.shape = sp
		ball.add_child(scs)
		ball.position = d * r1 + Vector3(0.0, float(sw["ball_y"]), 0.0)
		ball.add_to_group(hazard_group)
		piv.add_child(ball)
	var stages: Array = []  # Stage 103: press stages [[node, frac]...] and the head's warning glow
	var lamps: Array = []
	if sw.has("drive"):
		var D: Dictionary = sw["drive"]
		for s in D["stages"]:
			for nd in _group_nodes(String(s["group"])):
				stages.append([nd, float(s["frac"])])
		var ln := level_root.find_child(String(D["lamps"]), true, false)
		if ln != null:
			lamps.append(ln)
	var pmats: Array = []  # Stage 155: the plasma chambers' material(s) [[material, base emission energy]...]
	if sw.has("drive") and sw["drive"].has("plasma"):
		var seen := {}
		for node in level_root.find_children("*", "MeshInstance3D", true, false):
			var pm := (node as MeshInstance3D).get_active_material(0) as BaseMaterial3D
			if pm and pm.resource_name.begins_with(String(sw["drive"]["plasma"])) and not seen.has(pm):
				seen[pm] = true
				pmats.append([pm, pm.emission_energy_multiplier])
	var amats: Array = []  # Stage 157: the slam's lightning layer [[material, base emission energy]...]; the impact light
	var plight: OmniLight3D = null
	if sw.has("drive") and sw["drive"].has("arcs"):
		var seen_a := {}
		for node in level_root.find_children("*", "MeshInstance3D", true, false):
			var am := (node as MeshInstance3D).get_active_material(0) as BaseMaterial3D
			if am and am.resource_name.begins_with(String(sw["drive"]["arcs"])) and not seen_a.has(am):
				seen_a[am] = true
				am.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				amats.append([am, am.emission_energy_multiplier])
	if sw.has("drive") and sw["drive"].has("light"):
		var LD: Dictionary = sw["drive"]["light"]
		plight = OmniLight3D.new()
		plight.light_color = Color(LD["color"][0], LD["color"][1], LD["color"][2])
		plight.omni_range = float(LD["range"])
		plight.light_energy = 0.0
		plight.position = Vector3(LD["pos"][0], LD["pos"][1], LD["pos"][2])
		level_root.add_child(plight)
	_sweepers.append([sw, rot, piv, stages, lamps, [-1], pmats, amats, plight])


static func plasma_energy(D: Dictionary, u: float) -> float:
	# Stage 158 (same as assembly.plasma_energy / viewer.html): 0 until the impact, 1 while the ram is down, then a smooth fade
	# over spin_down (the ram lifting, the maces coasting to a stop)
	var sl := float(D["slam"])
	var ho := sl + float(D["hold"])
	if u < sl:
		return 0.0
	if u < ho:
		return 1.0
	var f := (u - ho) / float(D["spin_down"])
	return 1.0 - f * f * (3.0 - 2.0 * f) if f < 1.0 else 0.0


static func press_profile(D: Dictionary, t: float) -> Array:
	# Stage 103 (same as assembly.press_profile / viewer.html): [ram offset, rotor angle deg, u, cycle]
	var P := float(D["period"])
	var tp := t + float(D.get("phase", 0.0))
	var k := floorf(tp / P)
	var u := tp - k * P
	var sl := float(D["slam"])
	var ho := float(D["hold"])
	var ri := float(D["rise"])
	var su := float(D["spin_up"])
	var sd := float(D["spin_down"])
	var w := float(D["peak"])
	var tr := float(D["travel"])
	var off := 0.0
	if u < sl:  # slam: accelerating
		off = -tr * (u / sl) * (u / sl)
	elif u < sl + ho:
		off = -tr
	elif u < sl + ho + ri:  # climb back, eased
		off = -tr * (1.0 - smoothstep(0.0, 1.0, (u - sl - ho) / ri))
	var d := u - sl
	var th := 0.0
	if d <= 0.0:
		th = 0.0
	elif d < su:  # spin up from the impact
		th = w * d * d / (2.0 * su)
	elif d < ho:
		th = w * (d - su * 0.5)
	elif d < ho + sd:  # coast down once released
		var e := d - ho
		th = w * (ho - su * 0.5) + w * (e - e * e / (2.0 * sd))
	else:
		th = w * (ho - su * 0.5 + sd * 0.5)
	return [off, k * 360.0 * float(D["turns"]) + th, u, int(k)]


static func float_pose(F: Dictionary, t: float) -> Array:
	# Stage 123 (same as viewer.html floatPose): [dy, yaw, roll, pitch (deg), flame scale]
	var tp := t + float(F.get("phase", 0.0))
	var P := float(F["bob"][1])
	return [float(F["bob"][0]) * sin(TAU * tp / P), float(F["yaw"]) * sin(0.7 * tp), float(F["tilt"]) * sin(TAU * tp / (P * 1.7)), float(F["tilt"]) * 0.8 * sin(TAU * tp / (P * 1.3)),
		1.0 + 0.18 * sin(31.0 * t + 5.0 * float(F.get("phase", 0.0))) + 0.1 * sin(17.0 * t)]


static func float_xform(F: Dictionary, t: float, off_y: float) -> Transform3D:
	# about the deck centre: T(c + (0, off + dy, 0)) * R * T(-c)
	var p := float_pose(F, t)
	var c := Vector3(F["center"][0], F["center"][1], F["center"][2])
	var B := Basis.from_euler(Vector3(deg_to_rad(float(p[3])), deg_to_rad(float(p[1])), deg_to_rad(float(p[2]))), EULER_ORDER_YXZ)
	return Transform3D(B, c + Vector3(0.0, off_y + float(p[0]), 0.0) - B * c)


static func flame_xform(F: Dictionary, t: float, M: Transform3D) -> Transform3D:
	var s := float(float_pose(F, t)[4])
	var y := float(F["flame_y"])
	return M * Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, s, 1.0)), Vector3(0.0, y - y * s, 0.0))


func _floater(d: Dictionary) -> void:
	var sk: Skeleton3D = null
	for nd in _group_nodes(String(d["group"])):
		var mi := nd as MeshInstance3D
		if mi and mi.skin != null:
			sk = mi.get_node_or_null(mi.skeleton) as Skeleton3D
			(mi as GeometryInstance3D).extra_cull_margin = 2.0
	var bones := {}
	if sk != null:
		for i in sk.get_bone_count():
			bones[sk.get_bone_name(i)] = i
	var bodies: Array = []
	for pd in d["pads"]:  # each pad's deck collider rides its bob (no static collider is exported for floater parts)
		var body := AnimatableBody3D.new()
		body.sync_to_physics = true
		var cs := CollisionShape3D.new()
		if pd.get("deck_size") != null:  # Stage 133: square decks (floating stepping platforms): a box turned by deck_yaw
			var bx := BoxShape3D.new()
			bx.size = Vector3(float(pd["deck_size"][0]), 0.45, float(pd["deck_size"][1]))
			cs.shape = bx
			cs.position = Vector3(0.0, -0.225, 0.0)
			cs.rotation = Vector3(0.0, deg_to_rad(float(pd.get("deck_yaw", 0.0))), 0.0)
		else:
			var cy := CylinderShape3D.new()
			cy.radius = float(pd["deck_radius"]) * cos(PI / 8.0)
			cy.height = 0.6
			cs.shape = cy
			cs.position = Vector3(0.0, -0.3, 0.0)
		body.add_child(cs)
		level_root.add_child(body)
		bodies.append(body)
	var sink: Array = []  # Stage 189: per pad {"load", "t0", "dp", "drip", "on": Area3D over the deck, particles}
	if d.has("sink"):
		var S: Dictionary = d["sink"]
		for i in d["pads"].size():
			var pd: Dictionary = d["pads"][i]
			var ar := Area3D.new()  # who is standing on the deck (rides with the pad's body)
			var ash := CollisionShape3D.new()
			var abx := BoxShape3D.new()
			var ds: Array = pd.get("deck_size", [float(pd["deck_radius"]) * 1.8, float(pd["deck_radius"]) * 1.8])
			abx.size = Vector3(float(ds[0]) + 0.4, 1.4, float(ds[1]) + 0.4)
			ash.shape = abx
			ash.position = Vector3(0.0, 0.7, 0.0)
			ar.add_child(ash)
			(bodies[i] as Node3D).add_child(ar)
			var h := float(ds[0]) / 2.0
			var c := Vector3(pd["center"][0], float(S["liquid"]) + 0.05, pd["center"][2])
			var sp := _slime_drops(int(S["splash"]["burst"]), true)  # ring splash (going under / breaking the surface)
			sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			sp.emission_ring_axis = Vector3.UP
			sp.emission_ring_radius = h * 1.15
			sp.emission_ring_inner_radius = h * 0.95
			sp.emission_ring_height = 0.1
			sp.direction = Vector3.UP
			sp.spread = 35.0
			sp.initial_velocity_min = float(S["splash"]["speed"][0])
			sp.initial_velocity_max = float(S["splash"]["speed"][1])
			sp.position = c
			var bo := _slime_drops(40, false)  # the slime boiling over the drowned deck
			bo.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			bo.emission_box_extents = Vector3(h, 0.05, h)
			bo.direction = Vector3.UP
			bo.spread = 20.0
			bo.initial_velocity_min = 1.4
			bo.initial_velocity_max = 3.0
			bo.lifetime = 0.9
			bo.position = c
			var dp := _slime_drops(60, false)  # drips off the rim as it rises
			dp.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			dp.emission_ring_axis = Vector3.UP
			dp.emission_ring_radius = h
			dp.emission_ring_inner_radius = h * 0.9
			dp.emission_ring_height = 0.05
			dp.direction = Vector3.DOWN
			dp.initial_velocity_max = 0.4
			var stm := CPUParticles3D.new()  # a hiss of steam as the thruster hits / leaves the slime
			stm.amount = 26
			stm.lifetime = 1.6
			stm.one_shot = true
			stm.explosiveness = 0.9
			stm.emitting = false
			stm.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			stm.emission_sphere_radius = 0.9
			stm.direction = Vector3.UP
			stm.spread = 25.0
			stm.initial_velocity_min = 2.2
			stm.initial_velocity_max = 4.0
			stm.gravity = Vector3(0.0, 0.6, 0.0)
			stm.damping_min = 1.0
			stm.damping_max = 2.0
			stm.scale_amount_min = 1.2
			stm.scale_amount_max = 2.6
			var sq := QuadMesh.new()
			sq.size = Vector2(1.0, 1.0)
			var smt := StandardMaterial3D.new()
			smt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			smt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			smt.albedo_color = Color(0.93, 0.97, 0.93, 0.45)
			smt.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			sq.material = smt
			stm.mesh = sq
			stm.position = c + Vector3(0.0, 0.15, 0.0)
			level_root.add_child(stm)
			sink.append({"load": 0.0, "t0": -1.0, "dp": 0.0, "drip": 0.0, "on": ar, "splash": sp, "boil": bo, "drips": dp, "steam": stm})
	_floaters.append({"d": d, "sk": sk, "bones": bones, "bodies": bodies, "sink": sink})


## Stage 189: same as assembly.sink_profile / viewer.html - u = s since the deck gave way -> [depth 0..1, flame 0..1].
static func sink_profile(S: Dictionary, u: float) -> Array:
	var sk := float(S["sink"])
	var un := float(S["under"])
	var ri := float(S["rise"])
	if u < 0.0:
		return [0.0, 1.0]
	if u < sk:
		var q := u / sk
		return [q * q * (3.0 - 2.0 * q) * (0.35 + 0.65 * q), maxf(0.0, 1.0 - u / (0.3 * sk))]
	if u < sk + un:
		return [1.0, 0.0]
	if u < sk + un + ri:
		var q2 := (u - sk - un) / ri
		return [1.0 - q2 * q2 * (3.0 - 2.0 * q2), minf(1.0, q2 * 1.6)]
	return [0.0, 1.0]


func _player_on(ar: Area3D) -> bool:
	for b in ar.get_overlapping_bodies():
		if b is CharacterBody3D:
			return true
	return false


func _pod_path(d: Dictionary) -> void:
	var sk: Skeleton3D = null
	for nd in _group_nodes(String(d["group"])):
		var mi := nd as MeshInstance3D
		if mi and mi.skin != null:
			sk = mi.get_node_or_null(mi.skeleton) as Skeleton3D
			(mi as GeometryInstance3D).extra_cull_margin = 80.0  # the pods travel far from their rest bounds
	if sk == null:
		return  # (level.glb has no rig: the pods stay at rest)
	var bones := {}
	for i in sk.get_bone_count():
		bones[sk.get_bone_name(i)] = i
	_pod_paths.append({"d": d, "sk": sk, "bones": bones})


## Stage 186: same as factory.pod_pose / viewer.html - up "rise", a quarter bend of "radius" toward +x, then along +x.
## Returns [position Vector3, theta (rad, from +y toward +x)].
static func pod_pose(P: Dictionary, s: float) -> Array:
	var o: Array = P["origin"]
	var L1 := float(P["rise"])
	var R := float(P["radius"])
	var L2 := R * PI / 2.0
	if s <= L1:
		return [Vector3(o[0], float(o[1]) + s, o[2]), 0.0]
	if s <= L1 + L2:
		var a := (s - L1) / R
		return [Vector3(float(o[0]) + R - R * cos(a), float(o[1]) + L1 + R * sin(a), o[2]), a]
	return [Vector3(float(o[0]) + R + (s - L1 - L2), float(o[1]) + L1 + R, o[2]), PI / 2.0]


func _update_pod_paths() -> void:
	for f in _pod_paths:
		var sk: Skeleton3D = f["sk"]
		var D: Dictionary = f["d"]
		for P in D["paths"]:
			var dd := fposmod(_t * float(D["speed"]), float(P["spacing"]))
			for pd in P["pods"]:
				var bi: int = f["bones"].get(String(pd["joint"]), -1)
				if bi < 0:
					continue
				var q := pod_pose(P, float(pd["s0"]) + dd)
				var q0 := pod_pose(P, float(pd["s0"]))
				sk.set_bone_pose_position(bi, q[0])
				sk.set_bone_pose_rotation(bi, Quaternion(Vector3(0.0, 0.0, 1.0), -(float(q[1]) - float(q0[1]))))


func _update_floaters() -> void:
	for f in _floaters:
		var sk: Skeleton3D = f["sk"]
		var pads: Array = f["d"]["pads"]
		var dt := get_physics_process_delta_time()
		for i in pads.size():
			var pd: Dictionary = pads[i]
			var p := float_pose(pd, _t)
			var dep := 0.0  # Stage 189: how far the deck has sunk
			var fl := 1.0
			var w := 0.0
			if f["sink"].size() > i:
				var S: Dictionary = f["d"]["sink"]
				var st: Dictionary = f["sink"][i]
				if float(st["t0"]) < 0.0:
					var on := _player_on(st["on"])
					st["load"] = minf(float(S["hold"]), float(st["load"]) + dt) if on else maxf(0.0, float(st["load"]) - 2.0 * dt)
					if float(st["load"]) >= float(S["hold"]):
						st["t0"] = _t
				elif _t - float(st["t0"]) >= float(S["sink"]) + float(S["under"]) + float(S["rise"]):
					st["t0"] = -1.0
					st["load"] = 0.0
				w = float(st["load"]) / float(S["hold"]) if float(st["t0"]) < 0.0 else 0.0
				var q := sink_profile(S, -1.0 if float(st["t0"]) < 0.0 else _t - float(st["t0"]))
				dep = float(q[0]) * float(pd["sink_depth"])
				fl = float(q[1])
				_sink_fx(S, pd, st, dep, dt)
				st["dp"] = dep
			var B := Basis.from_euler(Vector3(deg_to_rad(float(p[3]) + w * 1.8 * sin(53.0 * _t + i)), deg_to_rad(float(p[1])), deg_to_rad(float(p[2]) + w * 1.8 * sin(47.0 * _t + 2.0 * i))), EULER_ORDER_YXZ)
			var dy := float(p[0]) - dep - 0.12 * w
			if sk != null:
				var bi: int = f["bones"].get(String(pd["joint"]), -1)
				if bi >= 0:
					sk.set_bone_pose_position(bi, sk.get_bone_rest(bi).origin + Vector3(0.0, dy, 0.0))
					sk.set_bone_pose_rotation(bi, B.get_rotation_quaternion())
				var fi: int = f["bones"].get(String(pd["flame_joint"]), -1)
				if fi >= 0:
					var spt := 1.0
					if w > 0.0:
						spt = 1.0 - 0.8 * w * ((0.5 + 0.5 * sin(41.0 * _t + 3.0 * i)) if sin(13.0 * _t + i) > 0.0 else 1.0)  # the thruster sputters ...
					sk.set_bone_pose_scale(fi, Vector3(1.0, maxf(0.001, float(p[4]) * fl * spt), 1.0))  # ... dies as it sinks, relights as it rises
			(f["bodies"][i] as AnimatableBody3D).global_transform = Transform3D(B, Vector3(pd["center"][0], float(pd["center"][1]) + dy, pd["center"][2]))


func _sink_fx(S: Dictionary, pd: Dictionary, st: Dictionary, dep: float, dt: float) -> void:  # Stage 189 (same events as viewer.html)
	var L := float(S["liquid"])
	var eJ := float(pd["center"][1]) - float(S["jet_drop"]) - L  # the thruster nozzle reaches the slime
	var eD := float(pd["center"][1]) - L  # the deck goes under
	var d0 := float(st["dp"])
	if (d0 < eJ and dep >= eJ) or (d0 >= eJ and dep < eJ):
		(st["steam"] as CPUParticles3D).restart()
	if d0 < eD and dep >= eD:
		(st["splash"] as CPUParticles3D).restart()
	if d0 >= eD and dep < eD:
		(st["splash"] as CPUParticles3D).restart()
		st["drip"] = float(S["splash"]["drips"])
	(st["boil"] as CPUParticles3D).emitting = dep >= eD - 0.2
	var dr := st["drips"] as CPUParticles3D
	if float(st["drip"]) > 0.0:
		st["drip"] = maxf(0.0, float(st["drip"]) - dt)
		dr.position = Vector3(pd["center"][0], float(pd["center"][1]) - dep - 0.1, pd["center"][2])
	dr.emitting = float(st["drip"]) > 0.0


func _jet(d: Dictionary) -> void:
	var parts := {}
	for k in ["body", "flame", "hatch", "cap"]:
		var arr: Array = []
		for nd in _group_nodes(String(d[k])):
			arr.append([nd, (nd as Node3D).transform])
		parts[k] = arr
	var trig: Area3D = null
	if d.get("trigger") != null:  # the player stepping onto this floor sends it flying over
		var T: Dictionary = d["trigger"]
		trig = Area3D.new()
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(float(T["max"][0]) - float(T["min"][0]), 2.4, float(T["max"][1]) - float(T["min"][1]))
		cs.shape = bx
		trig.add_child(cs)
		level_root.add_child(trig)
		trig.global_position = Vector3((float(T["min"][0]) + float(T["max"][0])) * 0.5, float(T["y"]) + 1.2, (float(T["min"][1]) + float(T["max"][1])) * 0.5)
	var rec := {"d": d, "parts": parts, "trig": trig, "use": null, "phase": "home", "t0": 0.0}
	_jets.append(rec)
	call_deferred("_jet_hook", rec)


func _jet_hook(rec: Dictionary) -> void:
	# the button's terminal area (apply_mobile.gd "<id>_Use") stays off until the screen has arrived; using it -> press
	var bid := String(rec["d"]["button"])
	var u := get_tree().root.find_child(bid + "_Use", true, false) as Area3D
	if u != null:
		u.monitorable = false
		u.monitoring = false
		if u.is_in_group(&"terminal"):
			u.remove_from_group(&"terminal")
		rec["use"] = u
	var cb := func(tid: String) -> void:  # the game used the button (apply_mobile.gd activate_terminal) -> press, spin, fly home
		if tid == bid and String(rec["phase"]) == "wait":
			rec["phase"] = "press"
			rec["t0"] = _t
	for n in get_tree().root.find_children("*", "Node", true, false):
		if n.has_signal("terminal_activated"):
			n.connect("terminal_activated", cb)
			break


static func _bez3(a: Array, b: Array, c: Array, d: Array, u: float) -> Vector3:
	var m := 1.0 - u
	var f := func(i: int) -> float: return m * m * m * float(a[i]) + 3.0 * m * m * u * float(b[i]) + 3.0 * m * u * u * float(c[i]) + u * u * u * float(d[i])
	return Vector3(f.call(0), f.call(1), f.call(2))


static func jet_pose(J: Dictionary, ph: String, t: float) -> Array:
	# Stage 119 (same as assembly.jet_pose / viewer.html): [pos, yaw, pitch, roll (deg), hatch 0..1, cap 0..1, flame scale]
	var H: Array = J["home"]
	var A: Array = J["arrive"]
	var TM: Dictionary = J["times"]
	var amp := float(J["bob"][0])
	var per := float(J["bob"][1])
	var hv := Vector3(H[0], H[1], H[2])
	var av := Vector3(A[0], A[1], A[2])
	var fl := func(tt: float, k: float) -> float: return k * (1.0 + 0.18 * sin(tt * 31.0) + 0.1 * sin(tt * 17.0))
	if ph == "home":
		return [hv + Vector3(0, amp * sin(TAU * t / per), 0), float(J["yaw0"]) + 3.0 * sin(t * 0.7), 0.0, 2.5 * sin(TAU * t / (per * 1.7)), 0.0, 0.0, fl.call(t, 1.0)]
	if ph == "fly":
		var tk := float(TM["take"])
		var tf := float(TM["fly"])
		var ts := float(TM["settle"])
		if t < tk:
			var u := t / tk
			return [hv + Vector3(0, 1.4 * sin(PI * u), 0), float(J["yaw0"]) + 360.0 * smoothstep(0.0, 1.0, u), 0.0, 0.0, 0.0, 0.0, fl.call(t, 1.6)]
		if t < tk + tf:
			var u := (t - tk) / tf
			var q := u * u * (3.0 - 2.0 * u)
			var p := _bez3(H, J["ctrl1"], J["ctrl2"], A, q)
			var n := _bez3(H, J["ctrl1"], J["ctrl2"], A, minf(1.0, q + 0.02))
			var hd := rad_to_deg(atan2(n.x - p.x, n.z - p.z)) if absf(n.x - p.x) + absf(n.z - p.z) > 1e-6 else float(J["arrive_yaw"])
			var w := 0.9 * sin(3.0 * PI * u) * sin(PI * u)
			p += Vector3(w * cos(deg_to_rad(hd)), 0.5 * sin(5.0 * PI * u), -w * sin(deg_to_rad(hd)))
			var ky := clampf((u - 0.75) / 0.25, 0.0, 1.0)
			var f := clampf((u - 0.4) / 0.25, 0.0, 1.0)
			return [p, hd + wrapf(float(J["arrive_yaw"]) - hd, -180.0, 180.0) * smoothstep(0.0, 1.0, ky), -14.0 * sin(PI * u), fmod(360.0 * smoothstep(0.0, 1.0, f), 360.0), 0.0, 0.0, fl.call(t, 1.8)]
		var s := t - tk - tf
		if s < ts:
			var fr := deg_to_rad(float(J["arrive_yaw"]))
			var k := 1.6 * sin(7.0 * s) * exp(-4.0 * s)
			return [av + Vector3(k * sin(fr), 0.4 * sin(9.0 * s) * exp(-3.0 * s), k * cos(fr)), float(J["arrive_yaw"]) + 14.0 * sin(11.0 * s) * exp(-3.5 * s), float(J.get("arrive_pitch", 0.0)) * smoothstep(0.0, 1.0, minf(1.0, s / ts)), 10.0 * sin(8.0 * s) * exp(-3.0 * s), 0.0, 0.0, fl.call(t, 1.3)]
		return jet_pose(J, "wait", s - ts)
	if ph == "wait":
		var h := minf(1.0, t / float(TM["open"]))
		h = 1.0 + 2.2 * pow(h - 1.0, 3.0) + 1.2 * pow(h - 1.0, 2.0) if h < 1.0 else 1.0
		return [av + Vector3(0, 0.5 * amp * sin(TAU * t / per), 0), float(J["arrive_yaw"]), float(J.get("arrive_pitch", 0.0)), 1.5 * sin(TAU * t / per), h, 0.0, fl.call(t, 1.0)]
	if ph == "press":
		var c := maxf(0.0, 1.0 - absf(t - 0.12) / 0.12) if t < 0.24 else 0.0
		var sp := smoothstep(0.0, 1.0, clampf((t - 0.3) / 0.8, 0.0, 1.0))
		return [av + Vector3(0, 0.6 * sin(PI * sp), 0), float(J["arrive_yaw"]) + 360.0 * sp, float(J.get("arrive_pitch", 0.0)), 0.0, 1.0, c, fl.call(t, 1.2)]
	var hb := maxf(0.0, 1.0 - t / 0.5)
	var ub := minf(1.0, t / float(TM["back"]))
	var qb := ub * ub * (3.0 - 2.0 * ub)
	var pb := _bez3(A, J.get("back1", [A[0], float(A[1]) + 9.0, A[2]]), J.get("back2", [H[0], float(H[1]) + 9.0, H[2]]), H, qb)  # Stage 170: planned (collision-free) return
	return [pb, float(J["arrive_yaw"]) + wrapf(float(J["yaw0"]) - float(J["arrive_yaw"]), -180.0, 180.0) * qb, -10.0 * sin(PI * ub) + float(J.get("arrive_pitch", 0.0)) * (1.0 - qb), 0.0, hb, 0.0, fl.call(t, 1.5)]


func _update_jets() -> void:
	for rec in _jets:
		var J: Dictionary = rec["d"]
		var TM: Dictionary = J["times"]
		var ph := String(rec["phase"])
		var tt := _t - float(rec["t0"])
		if ph == "home" and rec["trig"] != null:
			for b in (rec["trig"] as Area3D).get_overlapping_bodies():
				if b is CharacterBody3D:
					rec["phase"] = "fly"
					rec["t0"] = _t
					break
		elif ph == "fly" and tt >= float(TM["take"]) + float(TM["fly"]) + float(TM["settle"]):
			rec["phase"] = "wait"
			rec["t0"] = _t
			var u: Area3D = rec["use"]
			if u != null:  # the button goes live
				u.monitorable = true
				u.monitoring = true
				u.add_to_group(&"terminal")
		elif ph == "press" and tt >= 1.6:
			rec["phase"] = "back"
			rec["t0"] = _t
		elif ph == "back" and tt >= float(TM["back"]):
			rec["phase"] = "home"
		ph = String(rec["phase"])
		var r := jet_pose(J, ph, _t if ph == "home" else _t - float(rec["t0"]))
		var D := PI / 180.0
		var P := Transform3D(Basis.from_euler(Vector3(float(r[2]) * D, float(r[1]) * D, float(r[3]) * D), EULER_ORDER_YXZ), r[0])
		var Linv := Transform3D(Basis(Vector3.UP, float(J["yaw0"]) * D), Vector3(J["home"][0], J["home"][1], J["home"][2])).affine_inverse()
		var fy := float(J["flame_y"])
		var X_f := Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, float(r[6]), 1.0)), Vector3(0, fy - fy * float(r[6]), 0))
		var X_h := Transform3D(Basis.IDENTITY, Vector3(0, 0, float(r[4]) * float(J["slide"])))
		var X_c := Transform3D(Basis.IDENTITY, Vector3(0, -float(r[5]) * float(J["press"]), float(r[4]) * float(J["slide"])))
		for k in ["body", "flame", "hatch", "cap"]:
			var M := P * (X_f if k == "flame" else X_h if k == "hatch" else X_c if k == "cap" else Transform3D.IDENTITY) * Linv
			for nr in rec["parts"][k]:
				(nr[0] as Node3D).transform = M * (nr[1] as Transform3D)


func _lift(d: Dictionary) -> void:
	var c := Vector3(d["center"][0], d["center"][1], d["center"][2])
	var body := AnimatableBody3D.new()  # carries the deck collider (the static collider is not exported for lift parts)
	body.name = String(d["id"]) + "_Body"
	body.sync_to_physics = true
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = float(d["deck_radius"]) * cos(PI / 8.0)
	cy.height = 0.6
	cs.shape = cy
	cs.position = Vector3(0.0, -0.3, 0.0)
	body.add_child(cs)
	var ride := Area3D.new()  # who stands on it
	var rs := CollisionShape3D.new()
	var rc := CylinderShape3D.new()
	rc.radius = float(d["radius"])
	rc.height = 1.0
	rs.shape = rc
	rs.position = Vector3(0.0, 0.5, 0.0)
	ride.add_child(rs)
	body.add_child(ride)
	level_root.add_child(body)
	body.global_position = c
	var calls: Array = []
	for cl in d.get("calls", []):
		var ar := Area3D.new()
		var s := CollisionShape3D.new()
		var cc := CylinderShape3D.new()
		cc.radius = float(cl["radius"])
		cc.height = 3.0
		s.shape = cc
		ar.add_child(s)
		level_root.add_child(ar)
		ar.global_position = Vector3(cl["center"][0], cl["center"][1] + 1.0, cl["center"][2])
		calls.append([cl, ar])
	_lifts.append({"d": d, "nodes": _group_nodes(String(d["group"])), "body": body, "ride": ride, "calls": calls, "s": 0.0, "dir": 0, "p": 0.0, "board": 0.0})


func _boss_lift(d: Dictionary) -> void:
	var body := AnimatableBody3D.new()  # the car's deck collider (the boss and the players stand on it once it is down)
	body.name = String(d["id"]) + "_Body"
	body.sync_to_physics = true
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = float(d["radius"])
	cy.height = float(d["thickness"])
	cs.shape = cy
	cs.position = Vector3(0.0, 0.7 - float(d["thickness"]) / 2.0, 0.0)
	body.add_child(cs)
	level_root.add_child(body)
	body.global_position = Vector3(d["center"][0], d["top"], d["center"][2])  # slab bottom, parked at the top
	var trig: Area3D = null
	if d.get("trigger") != null:
		var T: Dictionary = d["trigger"]
		trig = Area3D.new()
		var ts := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(float(T["max"][0]) - float(T["min"][0]), 4.0, float(T["max"][1]) - float(T["min"][1]))
		ts.shape = bx
		trig.add_child(ts)
		level_root.add_child(trig)
		trig.global_position = Vector3((float(T["min"][0]) + float(T["max"][0])) / 2.0, float(T["y"]) + 2.0, (float(T["min"][1]) + float(T["max"][1])) / 2.0)
	var nodes := _group_nodes(String(d["group"]))
	var lamps: Array = []
	for nd in nodes:
		var mi := nd as MeshInstance3D
		if mi and mi.get_active_material(0) and mi.get_active_material(0).resource_name.begins_with(String(d["lamps"])):
			lamps.append(mi)
	_boss_lifts.append({"d": d, "nodes": nodes, "lamps": lamps, "body": body, "trig": trig, "phase": "top", "t0": 0.0})


func start_boss_lift(id: String) -> void:  # Stage 173: the game may start it itself (e.g. on a cutscene cue)
	for B in _boss_lifts:
		if String(B["d"]["id"]) == id and String(B["phase"]) == "top":
			B["phase"] = "going"
			B["t0"] = _t


func _update_boss_lifts() -> void:
	for B in _boss_lifts:  # Stage 173 (same as viewer.html): wait 'delay', flash 'warn', descend over 'duration', stay down
		var d: Dictionary = B["d"]
		if String(B["phase"]) == "top" and B["trig"] != null and _has_rider(B["trig"]):
			B["phase"] = "going"
			B["t0"] = _t
		var off := 0.0
		var flash := false
		if String(B["phase"]) != "top":
			var e := _t - float(B["t0"]) - float(d["delay"])
			if e >= 0.0 and e < float(d["warn"]):
				flash = true
			elif e >= float(d["warn"]):
				var u := minf(1.0, (e - float(d["warn"])) / float(d["duration"]))
				off = -float(d["travel"]) * u * u * (3.0 - 2.0 * u)
				flash = u < 1.0
				if u >= 1.0 and String(B["phase"]) != "landed":
					B["phase"] = "landed"
					var cam := get_viewport().get_camera_3d()
					if cam != null:
						var dd := Vector2(cam.global_position.x - float(d["center"][0]), cam.global_position.z - float(d["center"][2])).length()
						if dd < float(d["shake"]):
							_shake = maxf(_shake, 0.6 * (1.0 - dd / float(d["shake"])))
					boss_lift_landed.emit(String(d["id"]), Vector3(d["boss_spawn"][0], d["boss_spawn"][1], d["boss_spawn"][2]))
		for nd in B["nodes"]:
			(nd as Node3D).position = Vector3(0.0, off, 0.0)
		for lm in B["lamps"]:
			(lm as Node3D).visible = not flash or int(_t * 6.0) % 2 == 0
		(B["body"] as AnimatableBody3D).global_position = Vector3(d["center"][0], float(d["top"]) + off, d["center"][2])
		if flash and off < 0.0:  # anyone under the car as it comes down is shoved out past its rim
			var bot := float(d["top"]) + off - 0.45
			for cb in get_tree().get_nodes_in_group(&"players"):
				var c3 := cb as Node3D
				if c3 == null:
					continue
				var v := Vector2(c3.global_position.x - float(d["center"][0]), c3.global_position.z - float(d["center"][2]))
				if v.length() < float(d["radius"]) + 0.4 and c3.global_position.y < bot and c3.global_position.y + 1.8 > bot - 0.6:
					var dir := v.normalized() if v.length() > 0.01 else Vector2(1.0, 0.0)
					var p := Vector2(float(d["center"][0]), float(d["center"][2])) + dir * (float(d["radius"]) + 0.7)
					c3.global_position = Vector3(p.x, c3.global_position.y, p.y)


static func _has_rider(a: Area3D) -> bool:
	for b in a.get_overlapping_bodies():
		if b is CharacterBody3D:
			return true
	return false


func _update_lifts(delta: float) -> void:
	for L in _lifts:  # Stage 108 (same as viewer.html): board -> travel to the other end; a call zone brings it when empty
		var d: Dictionary = L["d"]
		if int(L["dir"]) == 0:
			if _has_rider(L["ride"]):
				L["board"] = float(L["board"]) + delta
				if float(L["board"]) >= float(d["wait"]):
					L["dir"] = 1 if float(L["s"]) < 0.5 else -1
					L["p"] = 0.0
					L["board"] = 0.0
			else:
				L["board"] = 0.0
				for ca in L["calls"]:
					var up: bool = String(ca[0]["at"]) == "top"
					if up == (float(L["s"]) > 0.5):
						continue
					if _has_rider(ca[1]):
						L["dir"] = 1 if up else -1
						L["p"] = 0.0
		else:
			L["p"] = minf(1.0, float(L["p"]) + delta / float(d["duration"]))
			L["s"] = float(L["p"]) if int(L["dir"]) > 0 else 1.0 - float(L["p"])
			if float(L["p"]) >= 1.0:
				L["dir"] = 0
		var s := float(L["s"])
		var off := float(d["travel"]) * s * s * (3.0 - 2.0 * s)
		if d.has("bob"):  # Stage 123: the lift pad floats too
			var M := float_xform(d, _t, off)
			for nd in L["nodes"]:
				(nd as Node3D).transform = M
			var X := flame_xform(d, _t, M)
			for nd in _group_nodes(String(d["flame"])):
				(nd as Node3D).transform = X
			(L["body"] as AnimatableBody3D).global_transform = M * Transform3D(Basis.IDENTITY, Vector3(d["center"][0], d["center"][1], d["center"][2]))
			continue
		for nd in L["nodes"]:
			(nd as Node3D).position = Vector3(0.0, off, 0.0)
		(L["body"] as AnimatableBody3D).global_position = Vector3(d["center"][0], float(d["center"][1]) + off, d["center"][2])


func _belt(b: Dictionary) -> void:
	var ch: Array = []
	for nd in _group_nodes(String(b["chevrons"])):
		ch.append([nd, (nd as Node3D).position])
	var u := Vector3(b["axis"][0], b["axis"][1], b["axis"][2]).normalized()
	var side := Vector3(u.z, 0.0, -u.x).normalized()
	var nrm := u.cross(side)
	if nrm.y < 0.0:
		nrm = -nrm
	var area := Area3D.new()
	area.name = String(b["id"]) + "_Riders"
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(float(b["width"]), 1.2, float(b["length"]))
	cs.shape = bx
	area.add_child(cs)
	level_root.add_child(area)
	area.global_transform = Transform3D(Basis(side, nrm, u), Vector3(b["center"][0], b["center"][1], b["center"][2]) + nrm * 0.6)
	var rl: Array = []  # Stage 190: the drum sprockets the belt turns (rest transform kept)
	for r in b.get("rollers", []):
		var nd := level_root.find_child(String(r["node"]), true, false) as Node3D
		if nd != null:
			rl.append([nd, nd.transform, r])
	var sfm: Array = []  # the link belt's material (its UVs run with the cleats)
	if b.has("surface"):
		var bn := String(b["surface"])
		for node in level_root.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			for si in mi.get_surface_override_material_count():
				var bm := mi.get_active_material(si) as BaseMaterial3D
				if bm and (bm.resource_name == bn or bm.resource_name.begins_with(bn + "__")) and not sfm.has(bm):
					sfm.append(bm)
	_belts.append([b, ch, area, rl, {"p": 0.0, "k": 1.0}, sfm])


## Stage 190: the game calls this when the mini boss dies - every belt with stops_on {"type": "boss_defeated"} spins down
## (over its stop_time) and stays stationary, so the players can climb it.
func boss_defeated(_id: String = "") -> void:
	_boss_dead = true


func _update_belts(delta: float) -> void:  # (same as viewer.html: travel p += speed * k * dt; cleats at fmod(p, spacing); sprockets sign * p / radius)
	for br in _belts:
		var b: Dictionary = br[0]
		var st: Dictionary = br[4]
		var stt := float(b.get("stop_time", 1.8))
		var stopped := _boss_dead and b.has("stops_on") and String(b["stops_on"].get("type", "")) == "boss_defeated"
		st["k"] = maxf(0.0, float(st["k"]) - delta / stt) if stopped else minf(1.0, float(st["k"]) + delta / stt)
		st["p"] = float(st["p"]) + float(b["speed"]) * float(st["k"]) * delta
		var u := Vector3(b["axis"][0], b["axis"][1], b["axis"][2]).normalized()
		var d := fposmod(float(st["p"]), float(b["spacing"])) - float(b["spacing"])
		for nr in br[1]:
			(nr[0] as Node3D).position = (nr[1] as Vector3) + u * d
		for r in br[3]:
			var rr: Dictionary = r[2]
			(r[0] as Node3D).transform = (r[1] as Transform3D) * Transform3D(Basis(Vector3.UP, float(rr["sign"]) * float(st["p"]) / float(rr["radius"])), Vector3.ZERO)
		for bm in br[5]:
			(bm as BaseMaterial3D).uv1_offset = Vector3(0.0, fposmod(-float(st["p"]) / float(b["spacing"]), 1.0), 0.0)


## Construct Error: the saws' arms swung each joint by its own amplitude
## about pivots off to the side, flinging the blades up past the ceiling
## beams and across each other ("spinning around the room", owner), only
## low at the far ends. Now each blade sweeps flat across its walkway at
## its rest height (the wrist follows a side-to-side path; shoulder and
## elbow angles solved for it, the saw head kept level), far enough each
## side to clear the bridge for a moment - the two alternate.
## `saw_speed` slows them (the game's button: owner asked "just to slow down
## the saws so the player can jump across in time").
const SAW_SWEEPS := {"Saw_West": [-34.9, 4.6], "Saw_East": [-28.8, 4.8]}  # blade centre x: middle, half-width
var saw_speed := 1.0
var _saw_t := 0.0


func _update_saws() -> void:
	_saw_t += get_process_delta_time() * saw_speed
	for sr in _saws:
		var w: Dictionary = sr[0]
		var A := Vector3(w["axis"][0], w["axis"][1], w["axis"][2]).normalized()
		var C := Vector3(w["center"][0], w["center"][1], w["center"][2])
		var ph := TAU * (_saw_t + float(w["phase"])) / float(w["period"])
		var links: Array = sr[1]
		var angles: Array = []
		for k in links.size():
			angles.append(deg_to_rad(float(links[k][0]["amp"])) * sin(ph - float(links[k][0]["lag"])))
		if SAW_SWEEPS.has(String(w["id"])) and links.size() == 3 and A.is_equal_approx(Vector3(0, 0, 1)):
			var sw: Array = SAW_SWEEPS[String(w["id"])]
			angles = _saw_ik(links, Vector2(float(sw[0]) + float(sw[1]) * sin(ph), C.y))
		var M := Transform3D.IDENTITY
		for k in links.size():
			var j: Dictionary = links[k][0]
			var P := Vector3(j["pivot"][0], j["pivot"][1], j["pivot"][2])
			var q := Basis(A, float(angles[k]))
			M = M * Transform3D(q, P - q * P)  # each joint turns about its own (already moved) hinge
			var T := M
			if k == links.size() - 1 and (sr[3] as Array).is_empty():  # the blade also spins about its axis through its centre
				var qs := Basis(A, float(w["rpm"]) * TAU / 60.0 * _t)
				T = M * Transform3D(qs, C - qs * C)
			for nr in links[k][1]:
				(nr[0] as Node3D).transform = T * (nr[1] as Transform3D)
		if not (sr[3] as Array).is_empty():  # Stage 102: the blade spins on the wrist (motor + guard stay put)
			var qb := Basis(A, float(w["rpm"]) * TAU / 60.0 * _t)
			var Tb := M * Transform3D(qb, C - qb * C)
			for nr in sr[3]:
				(nr[0] as Node3D).transform = Tb * (nr[1] as Transform3D)
		(sr[2] as Area3D).global_transform = Transform3D(Basis(Quaternion(Vector3.UP, A)), M * C)  # the kill cylinder's axis = the blade's


## Construct Error: shoulder / elbow / wrist angles (about +Z, in the XY
## plane) putting the wrist joint at `target`, the elbow on the side it
## rests on, the wrist turned back so the saw head stays level.
func _saw_ik(links: Array, target: Vector2) -> Array:
	var p: Array[Vector2] = []
	for k in 3:
		var pv: Array = links[k][0]["pivot"]
		p.append(Vector2(float(pv[0]), float(pv[1])))
	var S := p[0]
	var E0 := p[1]
	var W0 := p[2]
	var L1 := S.distance_to(E0)
	var L2 := E0.distance_to(W0)
	var v := target - S
	var d := clampf(v.length(), absf(L1 - L2) + 0.01, L1 + L2 - 0.01)
	var a := acos(clampf((L1 * L1 + d * d - L2 * L2) / (2.0 * L1 * d), -1.0, 1.0))
	var side := signf((W0 - S).angle_to(E0 - S))
	var E := S + v.normalized().rotated(side * a) * L1
	var a1 := (E0 - S).angle_to(E - S)
	var a2 := (W0 - E0).rotated(a1).angle_to(target - E)
	return [a1, a2, -(a1 + a2)]


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


static func goofy_pose(pd: Dictionary, tk: float, D: float, liq: float) -> Array:
	# Stage 110 (same as assembly.goofy_pose / viewer.html): [y offset, yaw deg, tilt deg, xz scale, colliders live]
	var g: Dictionary = pd["goof"]
	var rise := float(pd["rise"])
	var a := 0.45
	var b := float(g["peek"])
	var c := 0.22
	var offp := liq + 0.9 - float(pd["center"][1])
	if tk < 0.0:
		return [-rise, 0.0, 0.0, 1.0, false]
	if tk < a:  # emerge until the top peeks out
		var u := tk / a
		return [-rise + (offp + rise) * (1.0 - pow(1.0 - u, 3.0)), 0.0, 0.0, 1.0, false]
	var tb := tk - a
	if tb < b:  # look around
		return [offp + 0.12 * sin(TAU * 1.5 * tb), float(g["wig"]) * sin(TAU * float(g["hz"]) * tb) * sin(PI * tb / b), 0.0, 1.0, false]
	var tc := tb - b
	if tc < c:  # duck
		return [offp - 0.6 * sin(PI * 0.5 * tc / c), 0.0, 0.0, 1.0, false]
	var td := tc - c
	if td < D:  # pop up past the rest height
		var u := td / D
		var e := 1.0 + 2.9 * pow(u - 1.0, 3.0) + 1.9 * pow(u - 1.0, 2.0)
		return [(offp - 0.6) * (1.0 - e), 0.0, 0.0, 1.0 - 0.12 * sin(PI * u), u >= 0.8]
	var te := td - D
	if te > 4.0:
		return [0.0, 0.0, 0.0, 1.0, true]
	return [0.3 * sin(9.0 * te) * exp(-3.5 * te), 0.0, float(g["tilt"]) * exp(-2.6 * te) * sin(7.5 * te), 1.0 + 0.16 * exp(-4.0 * te) * cos(13.0 * te), true]


func _pose_goofy(sk: Skeleton3D, bones: Dictionary, pd: Dictionary, tk: float, D: float, liq: float, cols: Array) -> void:
	var G := goofy_pose(pd, tk, D, liq)
	var bi: int = bones.get(String(pd["joint"]), -1)
	if bi >= 0:
		var dr := deg_to_rad(float(pd["goof"]["dir"]))
		var q := Quaternion(Vector3(cos(dr), 0.0, sin(dr)), deg_to_rad(float(G[2]))) * Quaternion(Vector3.UP, deg_to_rad(float(G[1])))
		sk.set_bone_pose_position(bi, sk.get_bone_rest(bi).origin + Vector3(0.0, float(G[0]), 0.0))
		sk.set_bone_pose_rotation(bi, q)
		sk.set_bone_pose_scale(bi, Vector3(float(G[3]), 1.0, float(G[3])))
	if pd.has("rust"):  # Stage 112: green rust creeps up the column once it has settled (same as assembly.rust_grow)
		var ru: Dictionary = pd["rust"]
		var f := 0.0
		if tk >= 0.0:
			f = clampf((tk - (0.45 + float(pd["goof"]["peek"]) + 0.22 + D) - float(ru["delay"])) / float(ru["grow"]), 0.0, 1.0)
			f = f * f * (3.0 - 2.0 * f)
		var ui: int = bones.get(String(ru["bone"]), -1)
		if ui >= 0:
			sk.set_bone_pose_scale(ui, Vector3(1.0, maxf(f, 0.001), 1.0))
	var rs := 0.4
	var ry := -3.0
	if tk >= 0.3:  # the surge ring bursts out where it breaks the surface
		var f := clampf((tk - 0.3) / 1.6, 0.0, 1.0)
		rs = 0.4 + 2.6 * (1.0 - pow(1.0 - f, 2.0))
		ry = -0.9 * f * f if f < 1.0 else -3.0
	var ri: int = bones.get(String(pd["ring"]), -1)
	if ri >= 0:
		sk.set_bone_pose_position(ri, sk.get_bone_rest(ri).origin + Vector3(0.0, ry, 0.0))
		sk.set_bone_pose_scale(ri, Vector3(rs, 1.0, rs))
	for cl in cols:
		(cl as CollisionShape3D).disabled = not bool(G[4])


func _pose_riser(rec: Array, t: float) -> void:  # t: seconds since the trigger (< 0: still waiting)
	var r: Dictionary = rec[0]
	var sk: Skeleton3D = rec[1]
	var bones: Dictionary = rec[2]
	var D := float(r["rise_s"])
	for k in r["pads"].size():
		var pd: Dictionary = r["pads"][k]
		var tk := t - float(pd.get("delay", k * float(r["stagger"]))) if t >= 0.0 else -1.0  # Stage 111: per-pad delay
		if pd.has("goof"):  # Stage 110: goofy rise (peek, look around, duck, pop, squash + sway)
			_pose_goofy(sk, bones, pd, tk, D, float(r.get("liquid", 1.0)), rec[3][k])
			continue
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
			_riser_splash(rec[0], _t - rec[4])


var _splash_fx: Dictionary = {}  # Stage 180: riser id -> {"last": t, "pads": [[splash CPUParticles3D, drip CPUParticles3D]...]}


func _slime_drops(amount: int, one_shot: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.4
	p.one_shot = one_shot
	p.explosiveness = 1.0 if one_shot else 0.0
	p.emitting = false
	p.gravity = Vector3(0.0, -9.8, 0.0)
	var qm := QuadMesh.new()
	qm.size = Vector2(0.4, 0.4)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0.72, 1.0, 0.5)
	p.scale_amount_min = 0.5  # droplets of all sizes
	p.scale_amount_max = 1.3
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = sm
	p.mesh = qm
	level_root.add_child(p)
	return p


func _riser_splash(R: Dictionary, t: float) -> void:  # Stage 180 (same as viewer.html): a splash ring as each pad surfaces / launches, drips off its rim
	if not R.has("splash"):
		return
	var S: Dictionary = R["splash"]
	if not _splash_fx.has(R["id"]):
		var pads: Array = []
		for pd in R["pads"]:
			var h := float(pd["size"]) / 2.0
			var sp := _slime_drops(int(S["burst"]), true)  # a ring burst from the liquid round the pad
			sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			sp.emission_ring_axis = Vector3.UP
			sp.emission_ring_radius = h * 1.15
			sp.emission_ring_inner_radius = h * 0.95
			sp.emission_ring_height = 0.1
			sp.direction = Vector3.UP
			sp.spread = 35.0
			sp.initial_velocity_min = float(S["speed"][0])
			sp.initial_velocity_max = float(S["speed"][1])
			sp.position = Vector3(pd["center"][0], float(R["liquid"]) + 0.05, pd["center"][2])
			var dp := _slime_drops(60, false)  # drips falling off its rim as it climbs
			dp.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			dp.emission_ring_axis = Vector3.UP
			dp.emission_ring_radius = h
			dp.emission_ring_inner_radius = h * 0.9
			dp.emission_ring_height = 0.05
			dp.direction = Vector3.DOWN
			dp.initial_velocity_max = 0.4
			pads.append([sp, dp])
		_splash_fx[R["id"]] = {"last": -1.0, "pads": pads}
	var F: Dictionary = _splash_fx[R["id"]]
	for k in R["pads"].size():
		var pd: Dictionary = R["pads"][k]
		if not pd.has("splash"):
			continue
		var d0: float = float(pd["delay"]) if pd.has("delay") else k * float(R["stagger"])  # (Construct Error: typed)
		var tk: float = t - d0
		var tl: float = float(F["last"]) - d0
		for te in pd["splash"]:
			if tl < float(te) and tk >= float(te):
				(F["pads"][k][0] as CPUParticles3D).restart()
		var dk: float = tk - float(pd["splash"][1])
		var dp := F["pads"][k][1] as CPUParticles3D
		dp.emitting = dk >= 0.0 and dk < float(S["drips"])
		if dp.emitting:
			var G := goofy_pose(pd, tk, float(R["rise_s"]), float(R["liquid"]))
			dp.position = Vector3(pd["center"][0], float(pd["center"][1]) + float(G[0]) - 0.1, pd["center"][2])
	F["last"] = t


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


var _characters: Array = []


func _character(d: Dictionary) -> void:
	## Stage 152: the character's own GLB, packaged at <level>/characters/<file> (scene import: keep its animations)
	var path := _base_dir.path_join("characters").path_join(String(d["asset"]).get_file())
	var res = load(path)
	if res == null or not (res is PackedScene):
		push_warning("character GLB missing: " + path)
		return
	var inst: Node3D = (res as PackedScene).instantiate()
	level_root.add_child(inst)
	inst.position = Vector3(d["position"][0], d["position"][1], d["position"][2])
	inst.rotation.y = deg_to_rad(float(d.get("yaw", 0.0)))
	var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	var clips: Dictionary = d["clips"]
	if ap != null:
		for c in [String(clips["idle"]), String(clips["alert"])]:
			if ap.has_animation(c):
				ap.get_animation(c).loop_mode = Animation.LOOP_LINEAR
		ap.play(String(clips["idle"]))
	var fl: Dictionary = d.get("float", {})
	var bob: Node3D = inst.find_child(String(fl.get("node", "FloatRoot")), true, false)
	var sk: Skeleton3D = inst.find_child("Skeleton3D", true, false) as Skeleton3D
	var bone := sk.find_bone(String(fl.get("node", "FloatRoot"))) if sk != null else -1  # glTF import may turn the node into a bone
	_characters.append({"d": d, "ap": ap, "bob": bob, "sk": sk, "bone": bone, "alert": false,
		"rest": (sk.get_bone_rest(bone).origin if bone >= 0 else (bob.position if bob != null else Vector3.ZERO))})


func _update_characters() -> void:
	for c in _characters:
		var d: Dictionary = c["d"]
		var fl: Dictionary = d.get("float", {})
		var y := float(fl.get("amp", 0.08)) * sin(TAU * _t / float(fl.get("period", 4.0)))
		if c["bone"] >= 0:
			(c["sk"] as Skeleton3D).set_bone_pose_position(c["bone"], c["rest"] + Vector3(0.0, y, 0.0))
		elif c["bob"] != null:
			(c["bob"] as Node3D).position = c["rest"] + Vector3(0.0, y, 0.0)
		var tr: Dictionary = d["trigger"]
		var ctr := Vector3(tr["center"][0], tr["center"][1], tr["center"][2])
		var near := false
		for pl in get_tree().get_nodes_in_group(&"players"):
			if pl is Node3D and (pl as Node3D).global_position.distance_to(ctr) < float(tr["radius"]):
				near = true
		if near != c["alert"] and c["ap"] != null:
			c["alert"] = near
			var clip := String(d["clips"]["alert" if near else "idle"])
			(c["ap"] as AnimationPlayer).play(clip, float(d.get("fade", 0.3)))


func _physics_process(delta: float) -> void:
	_update_lifts(delta)
	_update_boss_lifts()
	_update_floaters()
	_update_pod_paths()
	_update_characters()
	for br in _belts:  # Stage 97: carry whoever stands on a conveyor ramp
		var b: Dictionary = br[0]
		var u := Vector3(b["axis"][0], b["axis"][1], b["axis"][2]).normalized()
		for body in (br[2] as Area3D).get_overlapping_bodies():
			var cb := body as CharacterBody3D
			if cb != null and cb.is_on_floor():
				cb.move_and_collide(u * float(b["speed"]) * float(br[4]["k"]) * delta)  # (Stage 190: k - stopped once the mini boss is down)
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
		var nrm := PackedVector3Array()  # Stage 105: jets (steam_jet) - one direction per point
		for e in spots:
			pts.append(Vector3(e["pos"][0], e["pos"][1], e["pos"][2]))
			if e.has("dir"):
				nrm.append(Vector3(e["dir"][0], e["dir"][1], e["dir"][2]).normalized())
		spots = [{"points": pts, "normals": nrm}] if nrm.size() == pts.size() else [{"points": pts}]
	for e in spots:
		var cp := CPUParticles3D.new()
		cp.mesh = quad
		cp.lifetime = float(p["lifetime"])
		if p.has("count"):
			cp.amount = int(p["count"])
			cp.preprocess = cp.lifetime
		elif p.has("burst"):
			cp.amount = int(p["burst"]) * (e["points"].size() if e.has("points") else 1)
			cp.one_shot = true
			cp.explosiveness = 1.0
			cp.emitting = false
			if fx.has("sync"):  # Stage 104: fired when the cycle time crosses each sync "at"
				_bursts.append([cp, 0.0, 0.0, 0.0, fx["sync"], [-1.0]])
			else:
				_bursts.append([cp, randf_range(p["interval"][0], p["interval"][1]), p["interval"][0], p["interval"][1]])
		else:
			cp.amount = max(1, int(ceil(float(p["rate"]) * cp.lifetime))) * (e["points"].size() if e.has("points") else 1)
		if e.has("points") and e.has("normals"):  # Stage 105: each particle leaves along its nozzle (local +z -> the point's normal)
			cp.emission_shape = CPUParticles3D.EMISSION_SHAPE_DIRECTED_POINTS
			cp.emission_points = e["points"]
			cp.emission_normals = e["normals"]
		elif e.has("points"):
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
		cp.direction = Vector3(0, 0, 1) if e.has("normals") else Vector3(0, 1, 0)
		cp.spread = float(p.get("spread", 15))
		if p.has("damping"):  # Stage 105: jets slow down and billow
			cp.damping_min = float(p["damping"])
			cp.damping_max = float(p["damping"])
		if p.has("emit_time") and p.has("burst"):  # emitted over emit_time s, not all at once
			cp.explosiveness = clampf(1.0 - float(p["emit_time"]) / float(p["lifetime"]), 0.0, 1.0)
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
	_update_saws()
	_update_jets()
	var scam := get_viewport().get_camera_3d()
	if scam != null and (_shake > 0.005 or scam.h_offset != 0.0 or scam.v_offset != 0.0):  # Stage 103: press impact shake
		scam.h_offset = randf_range(-0.5, 0.5) * _shake
		scam.v_offset = randf_range(-0.5, 0.5) * _shake
		_shake *= exp(-delta * 7.0)
		if _shake <= 0.005:
			scam.h_offset = 0.0
			scam.v_offset = 0.0
			_shake = 0.0
	for sr in _sweepers:  # Stage 98: turn the rotor and its kill areas about the tower's axis
		var sw: Dictionary = sr[0]
		var th := deg_to_rad(float(sw["rpm"]) * 6.0 * (_t + float(sw["phase"])))
		if sw.has("drive"):  # Stage 103: the ceiling press slams, the rotor spins up, then coasts to a stop
			var D: Dictionary = sw["drive"]
			var pf := press_profile(D, _t)
			th = deg_to_rad(float(pf[1]))
			for ns in sr[3]:
				(ns[0] as Node3D).position = Vector3(0.0, float(pf[0]) * float(ns[1]), 0.0)
			for ln in sr[4]:
				(ln as Node3D).visible = not (float(pf[2]) > float(D["period"]) - float(D["warn"])) or int(_t * 8.0) % 2 == 0
			if not sr[6].is_empty():  # Stage 155: the plasma turns with the rotor, rises, and surges with the ram (same as viewer.html)
				var pr := -float(pf[0]) / float(D["travel"])
				var ds := float(pf[2]) - float(D["slam"])
				var en := plasma_energy(D, float(pf[2]))  # Stage 158: on at the impact, held while pressed, fading as the ram lifts and the maces coast
				var fl := exp(-3.0 * ds) if ds >= 0.0 else 0.0
				var surge := 0.25 + en * (0.5 + 0.6 * pr + 0.12 * sin(_t * 41.0) * sin(_t * 17.0)) + 1.2 * fl
				for pm in sr[6]:
					var pmat := pm[0] as BaseMaterial3D
					pmat.uv1_offset = Vector3(float(pf[1]) / 360.0 * float(D["plasma_tiles"]), -_t * float(D["plasma_rise"]) - pr * 0.5, 0.0)
					pmat.emission_energy_multiplier = float(pm[1]) * surge
					if pmat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:  # the plasma fades in / out (the opaque electrode only dims)
						pmat.albedo_color.a = en
				var kk := floorf(_t * 24.0)  # Stage 157/158: arcs crackle hard on impact, then on and off while charged (same as viewer.html)
				var hh := sin(kk * 12.9898) * 43758.5453
				var ck := 1.0 if hh - floorf(hh) > 0.35 else 0.15
				var hit := minf(1.0, 1.6 * exp(-1.8 * ds)) if ds >= 0.0 else 0.0
				var fa := maxf(hit, 0.55 * en) * ck if en > 0.0 else 0.0
				for am in sr[7]:
					var amat := am[0] as BaseMaterial3D
					amat.albedo_color.a = fa
					amat.emission_energy_multiplier = float(am[1]) * (1.0 + 0.8 * fa) * fa
					amat.uv1_offset = Vector3(fposmod(kk * 0.618, 1.0), fposmod(kk * 0.382, 1.0), 0.0)
				if sr[8] != null:
					(sr[8] as OmniLight3D).light_energy = float(D["light"]["energy"]) * 2.0 * (hit * ck if en > 0.0 else 0.0)  # the impact flash only (lit at rest it washed the chambers out)
			if float(pf[2]) >= float(D["slam"]) and sr[5][0] != int(pf[3]):  # impact: shake a nearby camera
				sr[5][0] = int(pf[3])
				var cam := get_viewport().get_camera_3d()
				if cam != null:
					var dd := Vector2(cam.global_position.x - float(sw["center"][0]), cam.global_position.z - float(sw["center"][2])).length()
					if dd < float(D["shake"]):
						_shake = maxf(_shake, 0.45 * (1.0 - dd / float(D["shake"])))
		var C := Vector3(sw["center"][0], sw["center"][1], sw["center"][2])
		var q := Basis(Vector3.UP, th)
		var tr := Transform3D(q, C - q * C)
		for nr in sr[1]:
			(nr[0] as Node3D).transform = tr * (nr[1] as Transform3D)
		(sr[2] as Node3D).rotation.y = th
	_update_belts(get_process_delta_time())  # Stage 97 / 190: cleats slide, sprockets turn, spin down once the mini boss is defeated
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
		if b.size() > 4:  # Stage 104: synced vents
			var Y: Dictionary = b[4]
			var u := fposmod(_t + float(Y["phase"]), float(Y["period"]))
			var lu: float = b[5][0]
			if lu >= 0.0:
				for at in Y["at"]:
					var a_ := float(at)
					if (lu <= u and lu < a_ and a_ <= u) or (lu > u and (a_ > lu or a_ <= u)):
						(b[0] as CPUParticles3D).restart()
			b[5][0] = u
			continue
		b[1] -= delta
		if b[1] <= 0.0:
			(b[0] as CPUParticles3D).restart()
			b[1] = randf_range(b[2], b[3])
	if _sky_speed != 0.0 and environment and environment.environment:
		environment.environment.sky_rotation.y += _sky_speed * delta
