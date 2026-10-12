class_name ToxicBarrel
extends StaticBody3D
## The owner's toxic barrel (assets/props/toxic_barrel; the supplied
## Toxic_barrel_1.glb simplified 117k -> 20k triangles with gltfpack, kept
## in source/). Solid scenery (cover) that can be locked onto and shot:
## any hit makes it explode (ToxicBlast) and leave burning green slime
## (ToxicSlime) - a big puddle where it stood and smaller ones where the
## flung slime lands. The blast blows nearby grunts / skirmishers apart,
## dents the boss, hurts players close by and sets off other barrels near
## it (a chain). While it waits its slime glows and bubbles out of the top.

## Loaded with the first barrel, not preloaded (the script stays cached
## after the level is gone; a preload would keep the model in memory).
const MODEL := "res://assets/props/toxic_barrel/toxic_barrel.glb"
## The model's base sits this far below its origin (m).
const MODEL_BASE := 0.952

## Blast reach (m); robots within `kill_radius` die at once, blown apart.
@export var blast_radius := 4.0
@export var kill_radius := 2.6
@export var robot_damage := 1.2
@export var explosive_force := 34.0
## The boss's armour only takes a dent.
@export var boss_damage := 2.0
## Players: most damage right next to it, least at the edge of the blast
## (before the player's `incoming_damage_scale` x5: 22 to 5 health).
@export var player_damage_max := 4.4
@export var player_damage_min := 1.0
## Barrels within this of the blast go off too, a moment later.
@export var chain_radius := 5.0
@export var chain_delay := 0.18
## Slime: the big puddle where it stood and the splashes flung round it.
@export var slime_radius := 1.7
@export var splashes := 5

static var exploded_count := 0

var exploded := false
var targetable: Targetable
var model: Node3D
var _glow_mat: StandardMaterial3D
var _bubbles: CPUParticles3D
var _t := randf() * 10.0


func _ready() -> void:
	add_to_group(&"toxic_barrels")
	model = (load(MODEL) as PackedScene).instantiate()
	model.name = "Model"
	add_child(model)
	model.position = Vector3.UP * MODEL_BASE
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.62
	cyl.height = 1.9
	cs.shape = cyl
	cs.position = Vector3.UP * 0.95
	add_child(cs)
	targetable = Targetable.new()
	targetable.name = "Targetable"
	targetable.select_radius = 0.9
	targetable.select_half_height = 1.0
	add_child(targetable)
	targetable.position = Vector3.UP * 1.0
	# The toxic tank glows and pulses (its own copy of the material).
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if m and m.resource_name.contains("Toxic_Green"):
				_glow_mat = m.duplicate() as StandardMaterial3D
				_glow_mat.emission_enabled = true
				_glow_mat.emission = Color(0.35, 1.0, 0.12)
				_glow_mat.emission_texture = m.albedo_texture
				mi.set_surface_override_material(s, _glow_mat)
	# Slime bubbling up out of the top.
	_bubbles = Vfx.particles("glow", 0.1, 6, 1.4)
	_bubbles.local_coords = false
	_bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_bubbles.emission_sphere_radius = 0.35
	_bubbles.direction = Vector3.UP
	_bubbles.spread = 15.0
	_bubbles.initial_velocity_min = 0.3
	_bubbles.initial_velocity_max = 0.8
	_bubbles.gravity = Vector3(0, 0.2, 0)
	_bubbles.color_ramp = Vfx.ramp([Color(0.8, 1.0, 0.5, 0.0), Color(0.5, 1.0, 0.2, 0.9), Color(0.2, 0.7, 0.1, 0.0)], [0.0, 0.3, 1.0])
	add_child(_bubbles)
	_bubbles.position = Vector3.UP * 1.95


func _process(delta: float) -> void:
	_t += delta
	if _glow_mat:
		_glow_mat.emission_energy_multiplier = 0.75 + 0.25 * sin(_t * 2.3) + 0.08 * sin(_t * 7.1)


## Any hit sets it off (online: on the host's device; the others' go off
## when it says - net_event).
func apply_damage(info: DamageInfo) -> void:
	if Net.is_authority():
		explode(info.source if info else null)


func take_damage(_amount: float, _from := Vector3.ZERO) -> void:
	if Net.is_authority():
		explode()


func net_event(kind: StringName, _args: Array) -> void:
	if kind == &"explode":
		explode()


func explode(by: Node = null) -> void:
	if exploded or not is_inside_tree():
		return
	exploded = true
	exploded_count += 1
	Net.world_event(self, &"explode")
	var at := global_position
	var centre := at + Vector3.UP * 0.9
	var host: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	if targetable:
		targetable.kill()
		targetable.queue_free()
		targetable = null
	collision_layer = 0
	collision_mask = 0
	model.visible = false
	_bubbles.emitting = false
	set_process(false)
	ToxicBlast.spawn(host, at, blast_radius)
	_sound(host, centre)
	_damage(centre, by)
	_place_slime(host, at)
	# Other barrels near it go off too, a moment later.
	for b in get_tree().get_nodes_in_group(&"toxic_barrels"):
		var other := b as ToxicBarrel
		if other and other != self and not other.exploded and other.global_position.distance_to(at) < chain_radius:
			get_tree().create_timer(chain_delay, false).timeout.connect(func() -> void:
				if is_instance_valid(other):
					other.explode(self))
	get_tree().create_timer(1.0, false).timeout.connect(queue_free)


func _sound(host: Node, at: Vector3) -> void:
	var sounds: Array[AudioStream] = [Sfx.ROCKET_EXPLODE_0, Sfx.ROCKET_EXPLODE_1, Sfx.ROCKET_EXPLODE_2]
	Sfx.play_at(host, sounds[randi() % sounds.size()], at, 0.0, 6.0, 80.0)


func _damage(centre: Vector3, by: Node) -> void:
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var r := e as Node3D
		if r == null or not r.get(&"alive"):
			continue
		var mid := r.global_position + Vector3.UP * 0.9
		var d := mid.distance_to(centre)
		if d > blast_radius:
			continue
		var k := 1.0 - d / blast_radius
		var dir := (mid - centre).normalized() if d > 0.05 else Vector3.UP
		var amount: float
		if r is RobotBoss:
			amount = boss_damage
		elif d <= kill_radius:
			amount = 1.0e4  # blown apart
		else:
			amount = robot_damage * k
		var info := DamageInfo.make(amount, DamageInfo.Type.EXPLOSION, centre, dir, 0.0, explosive_force * (0.5 + 0.5 * k), self)
		info.weapon = &"toxic_barrel"
		r.call(&"apply_damage", info)
	for p in get_tree().get_nodes_in_group(&"players"):
		var pc := p as Node3D
		if pc == null:
			continue
		var d := (pc.global_position + Vector3.UP).distance_to(centre)
		if d > blast_radius or not pc.has_method("apply_damage"):
			continue
		var k := 1.0 - d / blast_radius
		var info := DamageInfo.make(lerpf(player_damage_min, player_damage_max, k), DamageInfo.Type.EXPLOSION, centre, (pc.global_position - centre).normalized(), 0.0, 0.0, self)
		info.weapon = &"toxic_barrel"
		pc.apply_damage(info)


## The big puddle where it stood, and splashes where the slime lands.
func _place_slime(host: Node, at: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var floor := _floor_hit(space, at + Vector3.UP * 1.0)
	if not floor.is_empty():
		ToxicSlime.spawn(host, floor.position, floor.normal, slime_radius, 0.05, self)
	var a0 := randf() * TAU
	for i in splashes:
		var a := a0 + TAU * (i + randf_range(-0.3, 0.3)) / splashes
		var dist := randf_range(1.7, blast_radius * 0.95)
		var p := at + Vector3(cos(a), 0.0, sin(a)) * dist + Vector3.UP * 1.5
		var hit := _floor_hit(space, p)
		if hit.is_empty() or absf(hit.position.y - at.y) > 2.5:
			continue  # off the edge / far below: no puddle
		ToxicSlime.spawn(host, hit.position, hit.normal, randf_range(0.55, 0.95), 0.25 + dist * 0.07, self)


func _floor_hit(space: PhysicsDirectSpaceState3D, from: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4.0)
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty() or not (hit.collider is StaticBody3D) or hit.collider is ToxicBarrel:
		return {}
	return hit
