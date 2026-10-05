class_name WeaponRegistry
extends Resource
## Every weapon in the game, in wheel order. The weapon wheel, loadout and
## pickups only read this list and each WeaponDefinition (id, name, icon,
## scene, unlocked-at-start, allowed arms), so adding a weapon = a new
## definition + adding it here; no UI changes.

@export var weapons: Array[WeaponDefinition] = []


func find(id: StringName) -> WeaponDefinition:
	for w in weapons:
		if w.id == id:
			return w
	return null
