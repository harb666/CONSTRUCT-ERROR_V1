extends Node3D
## Spawns players. Today: one local player. Later the network layer will call
## spawn_player() per peer, giving remote players a network-fed PlayerInput
## and only creating a camera/touch UI for the local one.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const CAMERA_RIG_SCENE := preload("res://scenes/camera_rig.tscn")

@onready var players_root: Node3D = $Players
@onready var spawn_points: Node3D = $SpawnPoints
@onready var touch_controls: TouchControls = $UI/TouchControls
@onready var debug_hud: Label = $UI/DebugHud

var players := {}  # player_id -> PlayerController
## Owner's testing setting: players can't die (hits still land and count).
## Set back to true to restore dying / respawning.
@export var players_can_die := false
## Title "TAP TO START" + character select before the match: 1 = always,
## 0 = never, -1 = only when this level is the running game (not in tests).
@export var front_end_mode := -1

## The open front end (title / character select), if any.
var front_end: FrontEnd
var _menu_camera: Camera3D


func _ready() -> void:
	Vfx.configure_for_device()
	Sfx.preload_all()
	# ?level=toxic (or -- --level=toxic) plays Toxic Arena instead of the
	# default battle arena.
	if StressTest._param("level") == "toxic" and get_node_or_null("ToxicArena") == null and get_tree().current_scene == self:
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
		return
	var stress := StressTest.robot_count()
	if stress > 0:
		StressTest.populate(self, stress)
		print("stress test: %d robots" % stress)
	debug_hud.set("show_perf", StressTest.perf_enabled())
	if front_end_mode == 1 or (front_end_mode == -1 and get_tree().current_scene == self):
		open_front_end()
	else:
		spawn_player(1, true)


## Title + character select over the paused arena (a camera slowly circles
## it behind the menus, so the phone prepares its graphics meanwhile).
## DEPLOY spawns the local player as the picked character and un-pauses.
func open_front_end() -> void:
	get_tree().paused = true
	touch_controls.visible = false
	debug_hud.visible = false
	_menu_camera = Camera3D.new()
	_menu_camera.name = "MenuCamera"
	_menu_camera.fov = 60.0
	add_child(_menu_camera)
	_menu_camera.make_current()
	var layer := CanvasLayer.new()
	layer.name = "FrontEndLayer"
	layer.layer = 20
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	front_end = FrontEnd.new()
	front_end.name = "FrontEnd"
	front_end.orbit_camera = _menu_camera
	var c := Vector3.ZERO
	for sp: Node3D in spawn_points.get_children():
		c += sp.global_position
	front_end.orbit_center = c / maxf(spawn_points.get_child_count(), 1)
	layer.add_child(front_end)
	front_end.deployed.connect(_on_deployed)
	front_end.tree_exited.connect(layer.queue_free)


func _on_deployed(character: CharacterDefinition) -> void:
	get_tree().paused = false
	debug_hud.visible = true
	touch_controls.visible = DisplayServer.is_touchscreen_available()
	spawn_player(1, true, character)
	if _menu_camera:
		_menu_camera.queue_free()
		_menu_camera = null


func spawn_player(player_id: int, is_local: bool, character: CharacterDefinition = null) -> PlayerController:
	if character == null:
		var roster := CharacterRoster.load_default()
		character = roster.characters[0] if roster and not roster.characters.is_empty() else null
	var player: PlayerController = character.instantiate_player() if character and character.player_scene else PLAYER_SCENE.instantiate()
	player.player_id = player_id
	player.name = "Player%d" % player_id
	var spawn: Node3D = spawn_points.get_child((player_id - 1) % spawn_points.get_child_count())
	player.transform = spawn.transform

	var input: PlayerInput
	if is_local:
		input = LocalPlayerInput.new()
	else:
		input = PlayerInput.new()  # placeholder until a network input source exists
	input.name = "Input"
	player.add_child(input)
	player.input = input
	players_root.add_child(player)
	players[player_id] = player
	player.add_to_group(&"players")  # enemies look for these
	player.can_die = players_can_die

	if is_local:
		player.add_to_group(Sfx.LISTENER_GROUP)  # sounds get louder as it gets closer
		var rig: CameraRig = CAMERA_RIG_SCENE.instantiate()
		rig.target = player
		add_child(rig)
		var local_input := input as LocalPlayerInput
		local_input.camera_rig = rig
		touch_controls.look_dragged.connect(local_input.add_touch_look)
		_add_hit_flash(player)
		# Tap-to-target: selector (what is selected) -> command target_id ->
		# player's TargetLock (validates) -> WeaponHolder auto-fires.
		var selector := TargetSelector.new()
		selector.name = "TargetSelector"
		selector.camera = rig.camera
		selector.origin_node = player
		local_input.add_child(selector)
		local_input.target_selector = selector
		touch_controls.tapped.connect(selector.handle_tap)
		# One lock per weapon slot; losing a target clears only that slot.
		var lock := player.get_node("TargetLock") as TargetLock
		var lock_left := player.get_node("TargetLockLeft") as TargetLock
		selector.max_range = lock.max_range
		for l: TargetLock in [lock, lock_left]:
			l.view_camera = rig.camera
			var side := l.side
			l.target_lost.connect(func(_reason: String) -> void: selector.clear_side(side))
		var marker := $UI/TargetMarker
		marker.lock = lock
		marker.lock_left = lock_left
		marker.camera = rig.camera
		debug_hud.player = player
		var vitals := VitalsHud.new()
		vitals.name = "VitalsHud"
		vitals.player = player
		$UI.add_child(vitals)
		var holder_hud := player.get_node_or_null("WeaponHolder") as WeaponHolder
		if holder_hud:
			var weapons := WeaponHud.new()
			weapons.name = "WeaponHud"
			weapons.holder = holder_hud
			$UI.add_child(weapons)
		# Weapon wheel (hold the weapon button, drag to an arm's weapon).
		var loadout := player.get_node_or_null("WeaponLoadout") as WeaponLoadout
		if loadout:
			var wheel := WeaponWheel.new()
			wheel.name = "WeaponWheel"
			wheel.loadout = loadout
			wheel.touch = touch_controls
			$UI.add_child(wheel)
		var holder := player.get_node_or_null("WeaponHolder") as WeaponHolder
		if holder:
			rig.aiming = holder.current != null
			holder.weapon_equipped.connect(func(_d: WeaponDefinition) -> void:
				rig.aiming = true)
		_test_hooks(player, selector)
	return player


## Browser testing switches: ?weapon=<id> starts with that weapon in the
## right hand; ?autolock=1 keeps the nearest on-screen enemy locked.
func _test_hooks(player: PlayerController, selector: TargetSelector) -> void:
	var wid := StressTest._param("weapon")
	var holder := player.get_node_or_null("WeaponHolder") as WeaponHolder
	if wid != "" and holder:
		var reg := load("res://resources/weapons/weapon_registry.tres") as WeaponRegistry
		var def := reg.find(StringName(wid)) if reg else null
		if def:
			holder.equip.call_deferred(def, "Right")
	if StressTest._param("autolock") == "1":
		var t := Timer.new()
		t.wait_time = 1.0
		t.autostart = true
		add_child(t)
		t.timeout.connect(func() -> void:
			if selector.get_selected("Right") != null:
				return
			var best: Node3D = null
			for e in get_tree().get_nodes_in_group(&"enemies"):
				var n := e as Node3D
				var tg := n.get_node_or_null("Targetable") as Targetable if n else null
				var lk := player.get_node("TargetLock") as TargetLock
				if tg and tg.is_valid_target() and lk.in_view(tg.get_aim_point()) and (best == null or n.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
					best = n
			if best:
				selector.tap_target(best.get_node("Targetable")))


## Brief green flash at the screen edges when the local player is hit.
func _add_hit_flash(player: PlayerController) -> void:
	var rect := TextureRect.new()
	rect.name = "HitFlash"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.05, 0.5)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.3, 1.0, 0.25, 0.0))
	grad.set_color(1, Color(0.3, 1.0, 0.25, 0.75))
	grad.add_point(0.6, Color(0.3, 1.0, 0.25, 0.0))
	g.gradient = grad
	rect.texture = g
	rect.modulate.a = 0.0
	$UI.add_child(rect)
	$UI.move_child(rect, 0)
	player.damaged.connect(func(_info: DamageInfo) -> void:
		rect.modulate.a = 0.8
		var tw := rect.create_tween()
		tw.tween_property(rect, "modulate:a", 0.0, 0.3))
