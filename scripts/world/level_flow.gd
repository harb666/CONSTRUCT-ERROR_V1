class_name LevelFlow
extends Node
## A level part's flow (owner asked, Skyforge): fight the waves
## (WaveDirector), then the lift rises out of the hub's elevator shaft
## (ElevatorLift); the squad rides it down and the next part of the level
## loads (LevelTransfer: this part is unloaded, the next one spawns its own
## enemies). Shows it all on the LevelFlowHud (banners, status, a marker on
## the lift).

@export var director_path: NodePath = ^"../WaveDirector"
@export var lift_path: NodePath = ^"../ElevatorLift"
## The next part of the level. A stand-in until the owner's next part is
## made: Battle Arena.
@export_file("*.tscn") var next_level := "res://scenes/battle_arena.tscn"

var director: WaveDirector
var lift: ElevatorLift
var hud: LevelFlowHud
## Set once the ride has ended and the next part is loading.
var leaving := false


func _ready() -> void:
	director = get_node_or_null(director_path) as WaveDirector
	lift = get_node_or_null(lift_path) as ElevatorLift
	var ui := get_node_or_null(^"../UI")
	if ui:
		hud = LevelFlowHud.new()
		hud.name = "LevelFlowHud"
		ui.add_child(hud)
		# Under the touch controls / menus, over the 3D.
		ui.move_child(hud, 0)
	if director:
		director.wave_started.connect(_on_wave_started)
		director.wave_cleared.connect(_on_wave_cleared)
		director.all_cleared.connect(_on_all_cleared)
	if lift:
		lift.arrived.connect(_on_lift_arrived)
		lift.departed.connect(_on_lift_departed)
		lift.ride_finished.connect(_on_ride_finished)


## The host's flow events, shown here too (online).
func net_event(kind: StringName, args: Array) -> void:
	match kind:
		&"wave_started":
			_on_wave_started(int(args[0]), int(args[1]))
		&"wave_cleared":
			_on_wave_cleared(int(args[0]), int(args[1]))
		&"all_cleared":
			_on_all_cleared()


func _on_wave_started(index: int, total: int) -> void:
	Net.world_event(self, &"wave_started", [index, total])
	if hud:
		hud.banner("WAVE %d / %d" % [index, total], "ENEMIES INBOUND" if index > 1 else "CLEAR THE SKYFORGE")


func _on_wave_cleared(index: int, total: int) -> void:
	Net.world_event(self, &"wave_cleared", [index, total])
	if hud and index < total:
		hud.banner("WAVE CLEARED", "NEXT WAVE INCOMING")


func _on_all_cleared() -> void:
	Net.world_event(self, &"all_cleared")
	if hud:
		hud.banner("AREA SECURED", "LIFT ARRIVING")
	if lift and Net.is_authority():
		lift.rise()


func _on_lift_arrived() -> void:
	if hud:
		hud.banner("LIFT READY", "GET THE SQUAD ON IT" if _player_count() > 1 else "GET ON IT")


func _on_lift_departed() -> void:
	if hud:
		hud.banner("GOING DOWN", "")


func _on_ride_finished() -> void:
	if leaving or not Net.is_authority():
		return
	go_next()


## Load the next part (the owner of the world decides; online, everyone
## follows).
func go_next() -> void:
	leaving = true
	Net.go_to_level(get_tree(), next_level)


func _player_count() -> int:
	return get_tree().get_nodes_in_group(&"players").size()


func _process(_delta: float) -> void:
	if hud == null:
		return
	hud.marker = Vector3.INF
	hud.status_color = HudStyle.CYAN
	var st := ""
	if lift and lift.state != ElevatorLift.State.DOWN:
		match lift.state:
			ElevatorLift.State.RISING:
				st = "LIFT ARRIVING"
			ElevatorLift.State.READY:
				var n := lift.riders
				st = "GET TO THE LIFT" if n <= 1 else "SQUAD ON THE LIFT  %d / %d" % [lift.aboard, n]
				hud.marker = lift.global_position + Vector3.UP * 0.5
				hud.marker_label = "LIFT"
				hud.status_color = LevelFlowHud.MARKER_COL
			ElevatorLift.State.COUNTDOWN:
				st = "GOING DOWN  %d" % ceili(maxf(lift.countdown_left, 0.0))
				hud.status_color = LevelFlowHud.MARKER_COL
	elif director and director.wave > 0:
		match director.state:
			WaveDirector.State.FIGHTING:
				st = "WAVE %d / %d   -   %d LEFT" % [director.wave, director.total_waves(), director.remaining()]
			WaveDirector.State.BREAK:
				st = "NEXT WAVE"
			WaveDirector.State.DONE:
				st = "AREA SECURED"
	hud.status = st
