class_name WeaponSpawner
extends Node3D
## Attach to a spawn pad (or any node). Floats a weapon above it, slowly
## spinning and bobbing, and gives it to the first player with a WeaponHolder
## that walks into the pickup zone. Works with any WeaponDefinition.

signal weapon_taken(player: Node, definition: WeaponDefinition)

@export var weapon: WeaponDefinition
@export var spin_speed := 0.6        # rad/s
@export var bob_height := 0.08       # m
@export var bob_speed := 1.6         # rad/s
@export var pickup_radius := 1.0
@export var pickup_height := 2.2
## Seconds until it reappears after pickup (0 = never).
@export var respawn_time := 0.0

var display: Weapon
var _pivot: Node3D
var _area: Area3D
var _time := 0.0


func _ready() -> void:
	_pivot = Node3D.new()
	_pivot.name = "DisplayPivot"
	add_child(_pivot)

	_area = Area3D.new()
	_area.name = "PickupZone"
	_area.monitorable = false
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = pickup_radius
	cyl.height = pickup_height
	shape.shape = cyl
	shape.position.y = pickup_height * 0.5
	_area.add_child(shape)
	add_child(_area)
	_area.body_entered.connect(_on_body_entered)
	spawn_display()


func spawn_display() -> void:
	if weapon == null or weapon.weapon_scene == null or display:
		return
	display = weapon.weapon_scene.instantiate()
	display.definition = weapon
	_pivot.add_child(display)
	display.scale = Vector3.ONE * weapon.display_scale
	# Centre the model over the pad so it spins in place.
	display.position = -display.get_visual_center() * weapon.display_scale
	display.on_displayed()
	_update_pivot()
	# A player may already be standing in the zone.
	for body in _area.get_overlapping_bodies():
		_on_body_entered(body)


func _process(delta: float) -> void:
	_time += delta
	_update_pivot()


func _update_pivot() -> void:
	if weapon == null:
		return
	_pivot.position = Vector3(0, weapon.display_height + sin(_time * bob_speed) * bob_height, 0)
	_pivot.rotation.y = fmod(_time * spin_speed, TAU)


func _on_body_entered(body: Node) -> void:
	if display == null:
		return
	var holder := body.get_node_or_null("WeaponHolder") as WeaponHolder
	if holder == null or not holder.can_equip(weapon):
		return
	display.queue_free()
	display = null
	holder.equip(weapon)
	weapon_taken.emit(body, weapon)
	if respawn_time > 0.0:
		get_tree().create_timer(respawn_time).timeout.connect(spawn_display)
