class_name SupernovaFinish
extends Node3D
## The supernova's expanding plasma burst (from supernova_finish.glb, baked
## to a light layer set by tools/bake_supernova_finish.gd). Its layers appear
## in their original order, compressed so the whole thing plays in
## `duration` seconds, swelling to just past the blast's damage radius.
## Translucent (alpha-blended, no depth writes) so players can see through.

const BAKED := preload("res://assets/vfx/supernova/supernova_finish_baked.scn")
const PLASMA_TEX := preload("res://assets/vfx/supernova/supernova_finish_Turbulent_Plasma_512.png")

@export var duration := 0.8
## Share of the duration spent building up (the rest fades out).
@export var build_fraction := 0.72
## Layer opacity (low = see-through).
@export var plasma_alpha := 0.24
@export var core_alpha := 0.28
@export var plasma_tint := Color(1.0, 0.55, 0.95)
## Each layer pops from this fraction of its size to full as it appears.
@export var pop_from := 0.35
@export var pop_time := 0.06

var radius := 12.0
var _t := 0.0
var _burst: Node3D
var _layers: Array = []  # [MeshInstance3D, appear_time_in_seconds]
var _mats: Array[StandardMaterial3D] = []
var _src_length := 8.82


## Burst at `at`, reaching `reach` metres radius.
static func spawn(parent: Node, at: Vector3, reach: float) -> SupernovaFinish:
	var f := SupernovaFinish.new()
	f.radius = reach
	parent.add_child(f)
	f.global_position = at
	return f


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_burst = BAKED.instantiate()
	add_child(_burst)
	_src_length = float(_burst.get_meta("source_length", 8.82))
	var extent := float(_burst.get_meta("extent", 0.75))
	var center: Vector3 = _burst.get_meta("center", Vector3.ZERO)
	var k := radius * 2.0 / maxf(extent, 0.001)
	_burst.scale = Vector3.ONE * k
	_burst.position = -center * k
	# Materials: translucent plasma, see-through hot core. Shared per burst.
	var plasma := _material(PLASMA_TEX, Color(plasma_tint, plasma_alpha))
	var core := _material(null, Color(1.0, 0.85, 1.0, core_alpha))
	_mats = [plasma, core]
	var build := duration * build_fraction
	for c in _burst.get_children():
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		var is_core := mi.mesh.surface_get_material(0) != null and mi.mesh.surface_get_material(0).resource_name.begins_with("White")
		mi.material_override = core if is_core else plasma
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 4.0
		mi.visible = false
		mi.set_meta("full", mi.scale)
		_layers.append([mi, float(mi.get_meta("appear", 0.0)) / _src_length * build])


func _material(tex: Texture2D, col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.albedo_color = col
	if tex:
		m.albedo_texture = tex
	return m


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	var build := duration * build_fraction
	for l in _layers:
		var mi: MeshInstance3D = l[0]
		var since: float = _t - float(l[1])
		mi.visible = since >= 0.0
		if mi.visible:
			var p := clampf(since / pop_time, 0.0, 1.0)
			mi.scale = (mi.get_meta("full") as Vector3) * lerpf(pop_from, 1.0, p)
	# Fade the whole burst out after it has built up.
	var fade := 1.0 - clampf((_t - build) / maxf(duration - build, 0.01), 0.0, 1.0)
	_mats[0].albedo_color.a = plasma_alpha * fade
	_mats[1].albedo_color.a = core_alpha * fade


func is_finished() -> bool:
	return _t >= duration
