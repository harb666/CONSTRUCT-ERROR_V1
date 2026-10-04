class_name WeaponSpawnPad
extends StaticBody3D
## Root of the weapon spawn pad prefab. Set `weapon` on each placed pad;
## it is handed to the pad's WeaponSpawner.

@export var weapon: WeaponDefinition


func _enter_tree() -> void:
	var spawner := get_node_or_null("WeaponSpawner") as WeaponSpawner
	if spawner and weapon:
		spawner.weapon = weapon


func _ready() -> void:
	# The pad is flat and sunk into the floor: its shadow is invisible but its
	# ~90k triangles would still be drawn again in the shadow pass.
	for gi: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
