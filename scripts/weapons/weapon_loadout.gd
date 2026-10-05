class_name WeaponLoadout
extends Node
## Lives on a player. Which weapons are unlocked this session and requests
## to put one on an arm. Reads only the WeaponRegistry and definitions, so new
## weapons need no changes here. Weapons marked unlocked_at_start are always
## available; pickups unlock the rest (and the first pickup of a weapon is
## put straight on the RIGHT arm to try it). Nothing is ever taken away:
## every unlocked weapon stays in the weapon wheel.

signal unlocked(definition: WeaponDefinition)
signal loadout_changed(side: String, definition: WeaponDefinition)

@export var registry: WeaponRegistry
@export var holder_path: NodePath = ^"../WeaponHolder"
## Arm a newly collected weapon goes on.
@export var pickup_side := "Right"

var _unlocked := {}
var _extra: Array[WeaponDefinition] = []


func _ready() -> void:
	reset()


## Back to a fresh session (only the start weapons unlocked).
func reset() -> void:
	_unlocked.clear()
	_extra.clear()
	if registry:
		for w in registry.weapons:
			if w.unlocked_at_start:
				_unlocked[w.id] = true


func holder() -> WeaponHolder:
	return get_node_or_null(holder_path) as WeaponHolder


func is_unlocked(def: WeaponDefinition) -> bool:
	return def != null and _unlocked.has(def.id)


## Lock a weapon again (tests; a new session uses reset()).
func relock(def: WeaponDefinition) -> void:
	if def and not def.unlocked_at_start:
		_unlocked.erase(def.id)


## Unlocked weapons in wheel (registry) order.
func unlocked_weapons() -> Array[WeaponDefinition]:
	var out: Array[WeaponDefinition] = []
	if registry:
		for w in registry.weapons:
			if _unlocked.has(w.id):
				out.append(w)
	for w in _extra:
		if _unlocked.has(w.id) and not out.has(w):
			out.append(w)
	return out


## Unlocked weapons that can go on `side`.
func available_for(side: String) -> Array[WeaponDefinition]:
	return unlocked_weapons().filter(func(w: WeaponDefinition) -> bool: return side in w.allowed_sides)


## Unlock a weapon. Returns true the first time.
func unlock(def: WeaponDefinition) -> bool:
	if def == null or _unlocked.has(def.id):
		return false
	_unlocked[def.id] = true
	if registry == null or registry.find(def.id) == null:
		_extra.append(def)
	unlocked.emit(def)
	return true


## A pickup was collected: unlock it and, the first time, equip it on the
## pickup arm. Returns true if it was new.
func collect(def: WeaponDefinition) -> bool:
	var first := unlock(def)
	if first:
		equip(pickup_side if pickup_side in def.allowed_sides else def.allowed_sides[0], def)
	return first


## Put an unlocked weapon on an arm (with the switch sequence).
func equip(side: String, def: WeaponDefinition) -> bool:
	var h := holder()
	if h == null or not is_unlocked(def) or not (side in def.allowed_sides):
		return false
	h.switch_weapon(def, side)
	loadout_changed.emit(side, def)
	return true


## What an arm holds (or is switching to).
func equipped(side: String) -> WeaponDefinition:
	var h := holder()
	return h.slot(side).target_definition() if h and h.slot(side) else null
