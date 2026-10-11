class_name Net
extends Node
## Online co-op. The autoload "NetSession" is this node (Net.instance); the
## game asks through the static helpers below, which work (offline) even
## without it. Offline (the normal single-player game) this peer is the
## authority for everything.

static var instance: Net

## Connected to a co-op session (hosting or joined).
var online := false


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


## Does this peer run the world (robots, barrels, waves, the lift)? The
## host does; offline, always.
static func is_authority() -> bool:
	return instance == null or not instance.online or instance.multiplayer.is_server()


static func is_online() -> bool:
	return instance != null and instance.online


## This device's player (null before DEPLOY).
static func local_player(tree: SceneTree) -> PlayerController:
	return tree.get_first_node_in_group(&"local_player") as PlayerController


## Move the squad on to the next part of the level.
static func go_to_level(tree: SceneTree, scene_path: String) -> void:
	LevelTransfer.go(tree, scene_path, local_player(tree))
