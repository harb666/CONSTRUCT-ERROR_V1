class_name BlackHoleCore
extends Node3D
## The animated black hole. Separate reusable scene: today it sits in the
## Black Hole Generator's chamber; later it detaches and becomes the projectile.
## Normalised so a scale of 1.0 = ~1 m across. The source GLB is untouched;
## its stray far-away "Planet" node is just hidden here.

const ANIM := "Accretion_Disk_Rotation"

## The owner's animated portal around it (replaces the look of the big
## gravity-lens disc; see BlackHolePortal).
var portal: BlackHolePortal


func _ready() -> void:
	var planet := find_child("Planet", true, false) as Node3D
	if planet:
		planet.visible = false
	var ap := find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap and ap.has_animation(ANIM):
		ap.play(ANIM)
	for gi: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	portal = BlackHolePortal.new()
	add_child(portal)
