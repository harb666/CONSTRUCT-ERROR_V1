class_name DamageInfo
extends RefCounted
## Everything an attack tells its target, so targets can react to HOW they
## were hit (e.g. how violently an enemy dies). Weapons build one of these
## and pass it to `DamageInfo.apply(target, info)`.

enum Type { GENERIC, BULLET, ENERGY, IMPACT, EXPLOSION, SUPERNOVA }

var damage_amount := 0.0
var damage_type := Type.GENERIC
## World point where the hit landed (or the explosion centre).
var impact_position := Vector3.ZERO
## Direction the force travels (away from the attacker / explosion).
var impact_direction := Vector3.FORWARD
## Kinetic punch of a direct hit (rough scale: 1 = light bullet,
## 10 = heavy projectile, 30+ = huge impact).
var impact_force := 0.0
## Blast force from an explosion at the target (already distance-scaled;
## ~10 = grenade edge, 40 = point-blank supernova).
var explosive_force := 0.0
var source: Node
## Which player weapon made the hit (&"plasma", &"machine_gun", &"shotgun",
## &"black_hole"; empty = unknown). Only changes how targets react.
var weapon := &""
## Scales how hard broken-off parts are thrown (e.g. < 1 when a black hole
## tears an enemy apart and should keep the pieces).
var launch_scale := 1.0


static func make(amount: float, type: Type, position: Vector3, direction: Vector3,
		impact := 0.0, explosive := 0.0, from: Node = null) -> DamageInfo:
	var d := DamageInfo.new()
	d.damage_amount = amount
	d.damage_type = type
	d.impact_position = position
	d.impact_direction = direction.normalized() if direction.length_squared() > 1e-6 else Vector3.FORWARD
	d.impact_force = impact
	d.explosive_force = explosive
	d.source = from
	return d


## Total violence of the hit (impact + blast).
func total_force() -> float:
	return impact_force + explosive_force


func is_explosive() -> bool:
	return damage_type == Type.EXPLOSION or damage_type == Type.SUPERNOVA or explosive_force > impact_force


## Deliver to any target: rich `apply_damage(info)` if it has one, else the
## simple `take_damage(amount, from)` (older/simple targets).
static func apply(target: Object, info: DamageInfo) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.has_method("apply_damage"):
		target.apply_damage(info)
		return true
	if target.has_method("take_damage"):
		target.take_damage(info.damage_amount, info.impact_position)
		return true
	return false
