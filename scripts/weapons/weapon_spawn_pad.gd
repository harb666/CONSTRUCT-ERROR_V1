class_name WeaponSpawnPad
extends StaticBody3D
## Root of the weapon spawn pad prefab. Set `weapon` on each placed pad;
## it is handed to the pad's WeaponSpawner.

@export var weapon: WeaponDefinition


func _enter_tree() -> void:
	var spawner := get_node_or_null("WeaponSpawner") as WeaponSpawner
	if spawner and weapon:
		spawner.weapon = weapon
