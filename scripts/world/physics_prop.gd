class_name PhysicsProp
extends RigidBody3D
## Simple movable prop (crate/barrel/block) built in code. Gravity wells pull,
## shrink, capture and throw these; heavier ones resist more.

enum Shape { BOX, CYLINDER }

@export var shape := Shape.BOX
@export var size := Vector3(0.6, 0.6, 0.6)
@export var color := Color(0.75, 0.55, 0.3)


func _ready() -> void:
	collision_layer |= GravityWell.MOVABLE_LAYER
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var col := CollisionShape3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	if shape == Shape.BOX:
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		mi.mesh = bm
		var bs := BoxShape3D.new()
		bs.size = size
		col.shape = bs
	else:
		var cm := CylinderMesh.new()
		cm.top_radius = size.x * 0.5
		cm.bottom_radius = size.x * 0.5
		cm.height = size.y
		cm.material = mat
		mi.mesh = cm
		var cs := CylinderShape3D.new()
		cs.radius = size.x * 0.5
		cs.height = size.y
		col.shape = cs
	add_child(mi)
	add_child(col)
