class_name ElevatorLift
extends AnimatableBody3D
## The lift in the hub's elevator shaft (owner asked: "a lift come from the
## centre elevator shaft which would take the players to the next part of
## the level"). It waits at the bottom of the shaft; `rise()` brings it up
## until its deck is flush with the hub floor (pink lights powering up), and
## a column of pink light marks it across the level. Once every player is
## standing on it a short countdown runs (anyone stepping off stops it),
## then it sinks back down the shaft with the squad aboard (controls held)
## and `ride_finished` fires: the level flow fades out and loads the next
## part. Placed with its origin where the deck's top sits when it's up.
## The peer that owns the world drives it; others mirror its state.

signal arrived
signal departed
signal ride_finished
signal state_changed(state: int)

enum State { DOWN, RISING, READY, COUNTDOWN, DESCENDING, GONE }

const DECK_SHADER := preload("res://scripts/world/lift_deck.gdshader")
const BEAM_SHADER := preload("res://scripts/world/lift_beam.gdshader")
const NEON := Color(1.0, 0.2, 0.5)

## Deck size: clear of the 8 pilasters down the shaft (they stand out to
## 5.03 m from its centre).
@export var radius := 4.95
## What can be stood on: out to the shaft wall, so nobody slips down the
## gap round the deck.
@export var collision_radius := 5.45
@export var thickness := 0.6
## How far below the floor it waits (m).
@export var depth := 10.0
@export var rise_time := 6.0
## A player within this of the centre (on the deck) is aboard.
@export var board_radius := 4.6
@export var countdown_time := 3.0
## The ride down: this far, in this long (speeding up gently: riders stay
## on the deck).
@export var ride_depth := 13.0
@export var ride_time := 4.5
@export var beam_height := 34.0

var state := State.DOWN
var aboard := 0
var riders := 0
var countdown_left := 0.0
var _t := 0.0
var _top := Vector3.ZERO
var _deck_mat: ShaderMaterial
var _rim_mat: StandardMaterial3D
var _beam: MeshInstance3D
var _beam_mat: ShaderMaterial
var _light: OmniLight3D


## One of each of its shaders, for Vfx.warm_up (built behind the title
## screen, not as the lift rises).
static func warm_up_items() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for sh: Shader in [DECK_SHADER, BEAM_SHADER]:
		var mi := MeshInstance3D.new()
		mi.mesh = QuadMesh.new()
		var m := ShaderMaterial.new()
		m.shader = sh
		mi.material_override = m
		out.append(mi)
	return out


func _ready() -> void:
	add_to_group(&"elevator_lift")
	sync_to_physics = true
	_top = global_position
	_build()
	_place(_top.y - depth)
	_apply_look()


func _build() -> void:
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = collision_radius
	cyl.height = thickness
	cs.shape = cyl
	cs.position = Vector3.DOWN * thickness * 0.5
	add_child(cs)
	# Drum (sides + underside): dark metal.
	var drum := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = radius
	dm.bottom_radius = radius * 0.94
	dm.height = thickness
	dm.radial_segments = 48
	dm.rings = 1
	drum.mesh = dm
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.13, 0.09, 0.14)
	metal.metallic = 0.7
	metal.roughness = 0.42
	drum.material_override = metal
	drum.position = Vector3.DOWN * thickness * 0.5
	add_child(drum)
	# Deck top (procedural plates, chevrons, lights).
	var deck := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2.ONE * radius * 2.0
	deck.mesh = q
	_deck_mat = ShaderMaterial.new()
	_deck_mat.shader = DECK_SHADER
	deck.material_override = _deck_mat
	deck.position = Vector3.UP * 0.004
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(deck)
	# Glowing rim round the edge.
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.16
	tm.outer_radius = radius + 0.02
	tm.rings = 48
	tm.ring_segments = 6
	rim.mesh = tm
	rim.scale = Vector3(1.0, 0.6, 1.0)
	_rim_mat = StandardMaterial3D.new()
	_rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rim_mat.albedo_color = NEON.darkened(0.6)
	rim.material_override = _rim_mat
	rim.position = Vector3.DOWN * 0.06
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rim)
	# The piston it rides on, down into the dark below the shaft.
	for i in 3:
		var col := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.7 - i * 0.35
		cm.bottom_radius = cm.top_radius
		cm.height = 6.0
		cm.radial_segments = 20
		col.mesh = cm
		col.material_override = metal
		col.position = Vector3.DOWN * (thickness + 3.0 + i * 5.5)
		add_child(col)
		var band := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = cm.top_radius + 0.05
		bm.bottom_radius = bm.top_radius
		bm.height = 0.18
		bm.radial_segments = 20
		band.mesh = bm
		band.material_override = _rim_mat
		band.position = col.position + Vector3.UP * 2.8
		add_child(band)
	# Light column marking it once it's up.
	_beam = MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = radius * 0.8
	beam_mesh.bottom_radius = radius * 0.92
	beam_mesh.height = beam_height
	beam_mesh.radial_segments = 32
	beam_mesh.rings = 1
	beam_mesh.cap_top = false
	beam_mesh.cap_bottom = false
	_beam.mesh = beam_mesh
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = BEAM_SHADER
	_beam_mat.set_shader_parameter("height", beam_height)
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.position = Vector3.UP * beam_height * 0.5
	_beam.visible = false
	add_child(_beam)
	_light = OmniLight3D.new()
	_light.light_color = NEON.lightened(0.2)
	_light.omni_range = 11.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = Vector3.UP * 2.5
	add_child(_light)
	Vfx.tame_light(_light)


## Deck top at height `y`.
func _place(y: float) -> void:
	global_position = Vector3(_top.x, y, _top.z)


func deck_height() -> float:
	return global_position.y


## Bring it up (the level's last wave is cleared).
func rise() -> void:
	if state != State.DOWN:
		return
	_set_state(State.RISING)


func _set_state(s: int) -> void:
	if s == state:
		return
	state = s as State
	_t = 0.0
	if state == State.COUNTDOWN:
		countdown_left = countdown_time
	if state == State.DESCENDING:
		departed.emit()
	if state == State.READY:
		arrived.emit()
	_lock_riders(state == State.DESCENDING)
	state_changed.emit(state)
	Net.world_event(self, &"lift", [int(state), _t])


func net_event(kind: StringName, args: Array) -> void:
	if kind == &"lift" and args.size() == 2:
		set_state_from_net(int(args[0]), float(args[1]))


## Mirror the owner's state (online: everyone sees the same lift).
func set_state_from_net(s: int, t: float) -> void:
	if s != state:
		_set_state(s)
	_t = t


func _physics_process(delta: float) -> void:
	_t += delta
	var auth := Net.is_authority()
	match state:
		State.DOWN:
			_place(_top.y - depth)
		State.RISING:
			var k := clampf(_t / rise_time, 0.0, 1.0)
			_place(_top.y - depth * (1.0 - smoothstep(0.0, 1.0, k)))
			if k >= 1.0 and auth:
				_set_state(State.READY)
		State.READY, State.COUNTDOWN:
			_place(_top.y)
			_count_aboard()
			if state == State.COUNTDOWN:
				countdown_left -= delta
			if auth:
				var all := aboard > 0 and aboard >= riders
				if state == State.READY and all:
					_set_state(State.COUNTDOWN)
				elif state == State.COUNTDOWN:
					if not all:
						_set_state(State.READY)
					elif countdown_left <= 0.0:
						_set_state(State.DESCENDING)
		State.DESCENDING:
			var k := clampf(_t / ride_time, 0.0, 1.0)
			_place(_top.y - ride_depth * k * k)
			if k >= 1.0 and auth:
				_set_state(State.GONE)
				ride_finished.emit()
		State.GONE:
			pass
	_apply_look()


## Players standing on the deck (and how many there are in all).
func _count_aboard() -> void:
	aboard = 0
	riders = 0
	for p in get_tree().get_nodes_in_group(&"players"):
		var pc := p as Node3D
		if pc == null:
			continue
		riders += 1
		if is_aboard(pc):
			aboard += 1


func is_aboard(body: Node3D) -> bool:
	var off := body.global_position - global_position
	return Vector2(off.x, off.z).length() < board_radius and off.y > -0.5 and off.y < 2.5


## Riders can't walk / jump off on the way down.
func _lock_riders(on: bool) -> void:
	for p in get_tree().get_nodes_in_group(&"players"):
		var pc := p as PlayerController
		if pc:
			pc.controls_locked = on and is_aboard(pc)


func _apply_look() -> void:
	var power := 0.0
	match state:
		State.RISING:
			power = smoothstep(0.6, 1.0, _t / rise_time)
		State.READY, State.COUNTDOWN, State.DESCENDING:
			power = 1.0
	_deck_mat.set_shader_parameter("power", power)
	_deck_mat.set_shader_parameter("alert", 1.0 if state == State.COUNTDOWN or state == State.DESCENDING else 0.0)
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.004)
	_rim_mat.albedo_color = NEON.darkened(0.6).lerp(NEON.lightened(0.15), power * pulse)
	_beam.visible = state == State.READY or state == State.COUNTDOWN
	_beam_mat.set_shader_parameter("strength", 1.0 if state == State.READY else 0.6)
	if Vfx.effect_lights:
		_light.light_energy = 3.0 * power
	else:
		_light.light_energy = 0.0
