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
	spawn_player(1, true)


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

	if is_local:
		var rig: CameraRig = CAMERA_RIG_SCENE.instantiate()
		rig.target = player
		add_child(rig)
		var local_input := input as LocalPlayerInput
		local_input.camera_rig = rig
		touch_controls.look_dragged.connect(local_input.add_touch_look)
		debug_hud.player = player
	return player
