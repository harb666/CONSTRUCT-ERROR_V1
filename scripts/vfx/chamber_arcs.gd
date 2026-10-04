class_name ChamberArcs
extends Node3D
## Crackling electric arcs between the contained black hole and the chamber's
## containment ring. Each arc is a lightning-strip quad stretched between the
## centre and a random point on the ring, re-rolled every few frames.

@export var arc_count := 3
@export var ring_radius := 0.15
@export var ring_half_length := 0.11
@export var arc_width := 0.1
@export var reroll_time := Vector2(0.04, 0.1)

## 0..1: arcs are only shown while the chamber holds a charged core.
var intensity := 1.0

var _arcs: Array[MeshInstance3D] = []
var _ends: Array[Vector3] = []
var _timers: Array[float] = []


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for i in arc_count:
		var q := Vfx.quad("bolt", Vfx.HOT, Vector2.ONE)
		add_child(q)
		_arcs.append(q)
		_ends.append(Vector3.ZERO)
		_timers.append(0.0)
		_reroll(i)


func _reroll(i: int) -> void:
	var a := randf() * TAU
	_ends[i] = Vector3(randf_range(-ring_half_length, ring_half_length), cos(a) * ring_radius, sin(a) * ring_radius)
	_timers[i] = randf_range(reroll_time.x, reroll_time.y)
	_arcs[i].visible = randf() < 0.85
	Vfx.set_alpha(_arcs[i], randf_range(0.5, 1.0) * intensity)


func _process(delta: float) -> void:
	visible = intensity > 0.01
	if not visible:
		return
	var cam := get_viewport().get_camera_3d()
	for i in _arcs.size():
		_timers[i] -= delta
		if _timers[i] <= 0.0:
			_reroll(i)
		var a := global_position
		var b := global_transform * _ends[i]
		var axis := b - a
		var len := axis.length()
		if len < 1e-4 or cam == null:
			continue
		var y := axis / len
		var to_cam := (cam.global_position - (a + b) * 0.5).normalized()
		var x := y.cross(to_cam).normalized()
		var z := x.cross(y)
		var w := arc_width * (1.0 if randf() < 0.5 else -1.0)
		_arcs[i].global_transform = Transform3D(Basis(x * w, y * len, z), (a + b) * 0.5)
