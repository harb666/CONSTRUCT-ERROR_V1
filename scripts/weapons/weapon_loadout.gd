class_name WeaponLoadout
extends Node
## Lives on a player. Which weapons are unlocked this session and requests
## to put one on an arm. Reads only the WeaponRegistry and definitions, so new
## weapons need no changes here. Weapons marked unlocked_at_start are always
## available; pickups unlock the rest (and the first pickup of a weapon is
## put straight on the RIGHT arm to try it). Nothing is ever taken away:
## every unlocked weapon stays in the weapon wheel.
## Ammo (owner asked: only the pistol cannon is unlimited): each other
## weapon has `max_ammo` rounds, full when unlocked (a pad), refilled by
## enemies' ammo drops (RecoveryDrops) and pads. Run dry, the arm switches
## to the pistol cannon by itself and back again when ammo for it is picked
## up; an empty weapon can't be picked in the wheel.

signal unlocked(definition: WeaponDefinition)
signal loadout_changed(side: String, definition: WeaponDefinition)
signal ammo_changed(definition: WeaponDefinition)

@export var registry: WeaponRegistry
@export var holder_path: NodePath = ^"../WeaponHolder"
## Arm a newly collected weapon goes on.
@export var pickup_side := "Right"

## No ammo used (tests of the weapons themselves).
static var unlimited_ammo := false

var _unlocked := {}
var _extra: Array[WeaponDefinition] = []
## Rounds left per weapon id (weapons with a max_ammo).
var _ammo := {}
## Arm -> the weapon that ran dry on it (it comes back on a refill).
var _dry := {}


func _ready() -> void:
	reset()


## Back to a fresh session (only the start weapons unlocked).
func reset() -> void:
	_unlocked.clear()
	_extra.clear()
	_ammo.clear()
	_dry.clear()
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


## Unlocked weapons that can go on `side` (heavy weapons: right arm only).
func available_for(side: String) -> Array[WeaponDefinition]:
	return unlocked_weapons().filter(func(w: WeaponDefinition) -> bool: return w.can_go_on(side))


## Unlock a weapon. Returns true the first time.
func unlock(def: WeaponDefinition) -> bool:
	if def == null or _unlocked.has(def.id):
		return false
	_unlocked[def.id] = true
	if not def.unlimited():
		_ammo[def.id] = def.max_ammo
	if registry == null or registry.find(def.id) == null:
		_extra.append(def)
	unlocked.emit(def)
	return true


## A pickup was collected: unlock it and, the first time, equip it on the
## pickup arm. Returns true if it was new.
func collect(def: WeaponDefinition) -> bool:
	var first := unlock(def)
	if first:
		equip(pickup_side if def.can_go_on(pickup_side) else def.allowed_sides[0], def)
	return first


## Put an unlocked weapon on an arm (with the switch sequence). A heavy
## weapon asked for on the left arm goes on the right arm instead.
func equip(side: String, def: WeaponDefinition) -> bool:
	var h := holder()
	if def:
		side = def.side_for(side)
	if h == null or not is_unlocked(def) or not def.can_go_on(side) or not has_ammo(def):
		return false
	_dry.erase(side)
	h.switch_weapon(def, side)
	loadout_changed.emit(side, def)
	return true


## What an arm holds (or is switching to).
func equipped(side: String) -> WeaponDefinition:
	var h := holder()
	return h.slot(side).target_definition() if h and h.slot(side) else null


# --- Ammo ---

## Rounds left (-1: unlimited; 0 for a weapon not unlocked).
func ammo_of(def: WeaponDefinition) -> int:
	if def == null or def.unlimited():
		return -1
	return int(_ammo.get(def.id, 0))


func has_ammo(def: WeaponDefinition) -> bool:
	return def != null and (def.unlimited() or ammo_of(def) > 0)


## Share of a full load (1 for unlimited).
func ammo_ratio(def: WeaponDefinition) -> float:
	if def == null or def.unlimited():
		return 1.0
	return clampf(float(ammo_of(def)) / def.max_ammo, 0.0, 1.0)


func ammo_full(def: WeaponDefinition) -> bool:
	return def == null or def.unlimited() or ammo_of(def) >= def.max_ammo


func set_ammo(def: WeaponDefinition, n: int) -> void:
	if def == null or def.unlimited():
		return
	_ammo[def.id] = clampi(n, 0, def.max_ammo)
	ammo_changed.emit(def)


## Rounds used (WeaponHolder, after each shot). Run dry: the arm(s) holding
## it switch to the pistol cannon.
func use_ammo(def: WeaponDefinition, n := 1) -> void:
	if def == null or def.unlimited() or unlimited_ammo:
		return
	set_ammo(def, ammo_of(def) - n)
	if ammo_of(def) > 0:
		return
	var h := holder()
	if h == null or h.default_weapon == null:
		return
	for side in ["Right", "Left"]:
		var s := h.slot(side)
		if s and s.target_definition() == def:
			_dry[side] = def
			h.switch_weapon(h.default_weapon, side)
			loadout_changed.emit(side, h.default_weapon)


## Ammo picked up (drops, pads). Returns how much was taken. A weapon that
## ran dry goes back on its arm if that arm still has the stand-in cannon.
func add_ammo(def: WeaponDefinition, n: int) -> int:
	if def == null or def.unlimited() or not is_unlocked(def):
		return 0
	var before := ammo_of(def)
	set_ammo(def, before + n)
	var got := ammo_of(def) - before
	var h := holder()
	if got > 0 and h:
		for side in _dry.keys():
			if _dry[side] == def:
				_dry.erase(side)
				var s := h.slot(side)
				if s and s.target_definition() == h.default_weapon:
					h.switch_weapon(def, side)
					loadout_changed.emit(side, def)
	return got


## Unlocked weapons with room for more ammo, emptiest first.
func ammo_wanted() -> Array[WeaponDefinition]:
	var out: Array[WeaponDefinition] = []
	for w in unlocked_weapons():
		if not w.unlimited() and w.ammo_pack > 0 and not ammo_full(w):
			out.append(w)
	out.sort_custom(func(a: WeaponDefinition, b: WeaponDefinition) -> bool: return ammo_ratio(a) < ammo_ratio(b))
	return out
