class_name PlayerHitFeedback
extends Node
## Cartoon damage feedback on a player character (child of the player; for
## every player, so co-op partners see it too). Nothing here changes damage
## or movement. Per hit (`PlayerController.damaged`):
##  - a cartoon flinch: the upper body snaps back away from the shot,
##    squashes down and springs back up with a wobble, plus a mechanical
##    shake (BossHitReact with squash, before the arm aim so weapons stay on
##    target),
##  - a cartoon hit flash over the body: white-hot, then red,
##  - a "POW" star burst where it was hit (HitStar).
## Strength grows with the damage; rapid hits (the boss's chaingun) are
## throttled so they twitch rather than stack.

const HURT := Color(1.0, 0.25, 0.18)

## Flinch per hit: lean (deg per kick), shake (deg), squash per kick.
@export var lean_deg := 14.0
@export var shake_deg := 2.5
@export var squash := 0.2
## Kick strength from the damage (share of max health): base + per share.
@export var kick_base := 0.45
@export var kick_per_share := 6.0
## Body flash: brightness, time (s), share of it that is white-hot.
@export var flash_strength := 1.6
@export var flash_time := 0.16
@export var white_share := 0.35
## Star size range (m) and min seconds between stars / flinches.
@export var star_size := Vector2(0.5, 1.0)
@export var min_gap := 0.07

var player: PlayerController
var react: BossHitReact
var flinches := 0
var stars := 0
var flashes := 0
var _meshes: Array[GeometryInstance3D] = []
var _clock := 0.0
var _last := -10.0
var _flash_left := 0.0
var _flash_k := 1.0


func _ready() -> void:
	player = get_parent() as PlayerController
	if player:
		player.damaged.connect(_on_damaged)


func _process(delta: float) -> void:
	_clock += delta
	if _flash_left > 0.0:
		var was := _flash_left
		_flash_left -= delta
		var turn := flash_time * (1.0 - white_share)
		if was > turn and _flash_left <= turn and _flash_left > 0.0:
			_set_overlay(HitFeedback._overlay(HURT, flash_strength * _flash_k))
		if _flash_left <= 0.0:
			_set_overlay(null)


func flash_active() -> bool:
	return _flash_left > 0.0


func _on_damaged(info: DamageInfo) -> void:
	# The player's own black hole never hurts them: no reaction either.
	if info.damage_type == DamageInfo.Type.SUPERNOVA or info.source == player:
		return
	if _clock - _last < min_gap:
		return
	_last = _clock
	_ensure_setup()
	var share := info.damage_amount * player.incoming_damage_scale / maxf(player.max_health, 1.0)
	var k := clampf(kick_base + share * kick_per_share, kick_base, 1.3)
	if react:
		react.kick(k, info.impact_direction)
		flinches += 1
	# Hit flash over the body: white-hot first, then red.
	_flash_k = clampf(k, 0.7, 1.2)
	_set_overlay(HitFeedback._overlay(Color(1, 1, 0.92), flash_strength * _flash_k * 0.8))
	_flash_left = flash_time
	flashes += 1
	var at := info.impact_position
	var body := player.global_position + Vector3.UP * 1.1
	if at == Vector3.ZERO or at.distance_to(body) > 2.0:
		at = body
	stars += 1
	HitStar.spawn(get_tree(), at, HURT, lerpf(star_size.x, star_size.y, clampf((k - kick_base) / (1.3 - kick_base), 0.0, 1.0)))


## Finds the character's skeleton and body meshes (the model is chosen at
## spawn) and adds the flinch modifier once.
func _ensure_setup() -> void:
	if react and is_instance_valid(react):
		return
	var visual := player.get_node_or_null("Visual")
	if visual == null:
		return
	var skels := visual.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var skel := skels[0] as Skeleton3D
	react = BossHitReact.new()
	react.name = "HitFlinch"
	react.max_lean_deg = lean_deg
	react.shake_deg = shake_deg
	react.squash = squash
	skel.add_child(react)
	# Before the arm aim so the weapons stay on target while the body jerks.
	for c in skel.get_children():
		if c is ArmAimModifier:
			skel.move_child(react, c.get_index())
			break
	react.setup(skel)
	_meshes.clear()
	for mi: MeshInstance3D in skel.find_children("*", "MeshInstance3D", true, false):
		if mi.skin != null or mi.skeleton != NodePath(""):
			_meshes.append(mi)


## Our tint over the body (`null` = off); leaves other overlays (the
## hologram teleport) alone.
func _set_overlay(mat: Material) -> void:
	for m in _meshes:
		if not is_instance_valid(m):
			continue
		var cur := m.material_overlay
		if cur != null and not HitFeedback._overlays.values().has(cur):
			continue
		m.material_overlay = mat
