class_name LevelTransfer
extends RefCounted
## Moving the squad from one part of a level to the next (the hub lift):
## remembers the local player's character, weapons on each arm and the
## weapons unlocked so far, fades the screen to black, swaps the whole
## level scene (the old part is unloaded, the next part loads with its own
## enemies) and fades back in once the player stands in the new part.
## main.gd calls `take()` when a level starts: if a transfer is pending, it
## skips the title / character select and spawns the player straight in.

const FADE_OUT := 0.9
const FADE_IN := 0.8

static var pending := false
static var character_id := &""
static var weapons := {}  # "Right" / "Left" -> weapon id
static var unlocked: Array[StringName] = []
static var ammo := {}  # weapon id -> rounds left
static var bitcoins := 0
static var transfers := 0
static var _fade: CanvasLayer


## Remember what the local player carries.
static func capture(player: PlayerController) -> void:
	character_id = player.character.id if player and player.character else &""
	weapons.clear()
	unlocked.clear()
	ammo.clear()
	bitcoins = player.bitcoins if player else 0
	if player == null:
		return
	var holder := player.get_node_or_null("WeaponHolder") as WeaponHolder
	if holder:
		for side in ["Right", "Left"]:
			var w := holder.weapon(side)
			if w and w.definition:
				weapons[side] = w.definition.id
	var loadout := player.get_node_or_null("WeaponLoadout") as WeaponLoadout
	if loadout:
		for d in loadout.unlocked_weapons():
			unlocked.append(d.id)
			if not d.unlimited():
				ammo[d.id] = loadout.ammo_of(d)


## A level picked on the level select: the player starts there as
## `character`, with nothing carried over (Net.go_to_level / go then load it).
static func start_as(character: CharacterDefinition) -> void:
	character_id = character.id if character else &""
	weapons.clear()
	unlocked.clear()
	ammo.clear()
	bitcoins = 0


## Fade out, then load `scene_path` (the next part).
static func go(tree: SceneTree, scene_path: String, player: PlayerController = null) -> void:
	if player:
		capture(player)
	pending = true
	transfers += 1
	var rect := _fade_rect(tree)
	var tw := rect.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(rect, "color:a", 1.0, FADE_OUT * (1.0 - rect.color.a))
	tw.tween_callback(func() -> void: swap(tree, scene_path))


## Load another level scene with the old one fully gone first (a plain
## scene change keeps both in memory for a moment - too much for iPhone
## Safari, which then kills the page).
static func swap(tree: SceneTree, scene_path: String) -> void:
	DebugHud.note("loading " + scene_path.get_file().get_basename())
	tree.unload_current_scene()
	var t := tree.create_timer(0.1, true, false, true)
	t.timeout.connect(func() -> void: tree.change_scene_to_file(scene_path))


## A level starting: the pending transfer, if any (and it's no longer
## pending). Empty if the level starts normally.
static func take() -> Dictionary:
	if not pending:
		return {}
	pending = false
	return {"character": character_id, "weapons": weapons.duplicate(), "unlocked": unlocked.duplicate(), "ammo": ammo.duplicate(), "bitcoins": bitcoins}


## Give `player` what it carried over.
static func apply(player: PlayerController, data: Dictionary) -> void:
	var reg := load("res://resources/weapons/weapon_registry.tres") as WeaponRegistry
	if reg == null or player == null:
		return
	player.add_bitcoins(int(data.get("bitcoins", 0)))
	var loadout := player.get_node_or_null("WeaponLoadout") as WeaponLoadout
	if loadout:
		for id in data.get("unlocked", []):
			loadout.unlock(reg.find(id))
		var am: Dictionary = data.get("ammo", {})
		for id in am:
			loadout.set_ammo(reg.find(id), int(am[id]))
	var holder := player.get_node_or_null("WeaponHolder") as WeaponHolder
	if holder:
		var ws: Dictionary = data.get("weapons", {})
		for side in ws:
			var def := reg.find(ws[side])
			if def:
				holder.equip(def, side)


## Fade back in (the new part is ready).
static func fade_in(tree: SceneTree) -> void:
	if _fade == null or not is_instance_valid(_fade):
		return
	var rect := _fade.get_child(0) as ColorRect
	var layer := _fade
	var tw := rect.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(0.25)
	tw.tween_property(rect, "color:a", 0.0, FADE_IN)
	tw.tween_callback(layer.queue_free)
	_fade = null


## Black full-screen cover on the root (it outlives the scene swap).
static func _fade_rect(tree: SceneTree) -> ColorRect:
	if _fade == null or not is_instance_valid(_fade):
		_fade = CanvasLayer.new()
		_fade.name = "LevelFade"
		_fade.layer = 40
		_fade.process_mode = Node.PROCESS_MODE_ALWAYS
		var rect := ColorRect.new()
		rect.color = Color(0, 0, 0, 0)
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade.add_child(rect)
		tree.root.add_child(_fade)
	return _fade.get_child(0) as ColorRect
