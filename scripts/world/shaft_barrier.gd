class_name ShaftBarrier
extends StaticBody3D
## Invisible wall round the hub's elevator shaft (owner asked: "players /
## enemies can't fall down, a perfect invisible barrier around it"): a tall
## ring just outside the pit's edge. Only players and robots collide with it
## (its own physics layer, in their masks); shots, rockets, debris and the
## camera pass straight through. Off while the lift is up, so the squad can
## step onto it.

## Its physics layer (layer 4, "barrier").
const LAYER := 8

## The pit's edge is at most 5.55 m from the shaft's centre: the ring's
## inside face stands just outside it.
@export var inner_radius := 5.6
@export var thickness := 0.5
## From a little below the floor to far above it (nothing gets over).
@export var height := 60.0
@export var segments := 40

var _shapes: Array[CollisionShape3D] = []


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 0
	var r := inner_radius + thickness * 0.5
	# Boxes round the ring, overlapping so there's no gap between them.
	var w := TAU * (inner_radius + thickness) / segments * 1.2
	for i in segments:
		var a := TAU * i / segments
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(w, height, thickness)
		cs.shape = box
		cs.transform = Transform3D(Basis(Vector3.UP, -a + PI * 0.5), Vector3(cos(a) * r, height * 0.5 - 0.4, sin(a) * r))
		add_child(cs)
		_shapes.append(cs)


func set_active(on: bool) -> void:
	for cs in _shapes:
		cs.set_deferred(&"disabled", not on)


func is_active() -> bool:
	return not _shapes.is_empty() and not _shapes[0].disabled
