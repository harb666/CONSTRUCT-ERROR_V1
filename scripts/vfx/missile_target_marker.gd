class_name MissileTargetMarker
extends Node3D
## Ground warning where a boss missile is going to land: a red ring the size
## of the blast, a fill that grows as the missile closes in (countdown) and
## a pulsing crosshair. Stays where it was placed (it never follows the
## player), and fades out the moment the missile lands. Three additive,
## unshaded quads: cheap on mobile.

const COLOR := Color(1.0, 0.12, 0.05)
const FADE_TIME := 0.15

var radius := 2.5
## 0 at launch .. 1 at the expected impact (set by the missile).
var progress := 0.0

var _ring: MeshInstance3D
var _fill: MeshInstance3D
var _cross: MeshInstance3D
var _t := 0.0
var _fading := -1.0


## Place a marker on the ground at `at` (world), sized to `blast_radius`.
static func spawn(parent: Node, at: Vector3, blast_radius: float) -> MissileTargetMarker:
	var m := MissileTargetMarker.new()
	m.radius = blast_radius
	parent.add_child(m)
	m.global_position = at + Vector3.UP * 0.04
	return m


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_ring = _flat("ring", Vector2.ONE * radius * 2.0)
	_fill = _flat("glow", Vector2.ONE * radius * 2.0)
	_cross = _flat("star", Vector2.ONE * radius * 0.9)
	_update()


func _flat(tex: String, size: Vector2) -> MeshInstance3D:
	var q := Vfx.quad(tex, COLOR, size)
	q.rotation.x = -PI / 2.0  # lie on the ground
	(q.material_override as StandardMaterial3D).render_priority = 1
	add_child(q)
	return q


## The missile has landed (or blown up early): fade out now.
func finish() -> void:
	if _fading < 0.0:
		_fading = 0.0


func _process(delta: float) -> void:
	_t += delta
	if _fading >= 0.0:
		_fading += delta
		if _fading >= FADE_TIME:
			queue_free()
			return
	_update()


func _update() -> void:
	var fade := 1.0 - clampf(_fading / FADE_TIME, 0.0, 1.0) if _fading >= 0.0 else 1.0
	var p := clampf(progress, 0.0, 1.0)
	# Pulses faster as the impact gets closer.
	var pulse := 0.5 + 0.5 * sin(_t * lerpf(8.0, 22.0, p))
	Vfx.set_alpha(_ring, (0.75 + 0.25 * pulse) * fade)
	_fill.scale = Vector3.ONE * maxf(p, 0.05)
	Vfx.set_alpha(_fill, (0.35 + 0.3 * p) * fade)
	_cross.rotation.y = _t * 1.5
	Vfx.set_alpha(_cross, (0.4 + 0.5 * pulse) * fade)
