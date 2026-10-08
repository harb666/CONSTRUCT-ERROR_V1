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


func _ready() -> void:
	Vfx.configure_for_device()
	# ?level=toxic (or -- --level=toxic) plays Toxic Arena instead of the
	# default battle arena.
	if StressTest._param("level") == "toxic" and get_node_or_null("ToxicArena") == null and get_tree().current_scene == self:
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
		return
	spawn_player(1, true)
	var stress := StressTest.robot_count()
	if stress > 0:
		StressTest.populate(self, stress)
		print("stress test: %d robots" % stress)
	debug_hud.set("show_perf", StressTest.perf_enabled())


func spawn_player(player_id: int, is_local: bool) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
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
	return player


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
