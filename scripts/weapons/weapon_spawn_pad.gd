class_name WeaponSpawnPad
extends StaticBody3D
## Root of the weapon spawn pad prefab. Set `weapon` on each placed pad;
## it is handed to the pad's WeaponSpawner.

@export var weapon: WeaponDefinition
## Pad glow colour. Alpha 0 (default) keeps the model's own purple; any other
## colour recolours the pad's purple glow (model colour + emissive textures,
## the ring and the halo) to it, e.g. orange for the shotgun pad.
@export var glow_color := Color(0, 0, 0, 0)

const RECOLOR_SHADER := preload("res://scripts/world/glow_recolor.gdshader")


func _enter_tree() -> void:
	var spawner := get_node_or_null("WeaponSpawner") as WeaponSpawner
	if spawner and weapon:
		spawner.weapon = weapon


func _ready() -> void:
	# The pad is flat and sunk into the floor: its shadow is invisible but its
	# ~90k triangles would still be drawn again in the shadow pass.
	for gi: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if glow_color.a > 0.0:
		_recolor(glow_color)


func _recolor(col: Color) -> void:
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i) as StandardMaterial3D
			if m == null:
				continue
			if m.albedo_texture is GradientTexture2D:
				# Glow ring / halo sprites: same look, new tint.
				var d := m.duplicate() as StandardMaterial3D
				d.albedo_color = Color(col.r, col.g, col.b, m.albedo_color.a)
				mi.set_surface_override_material(i, d)
			elif m.albedo_texture:
				var sm := ShaderMaterial.new()
				sm.shader = RECOLOR_SHADER
				sm.set_shader_parameter("albedo_tex", m.albedo_texture)
				sm.set_shader_parameter("orm_tex", m.roughness_texture)
				sm.set_shader_parameter("normal_tex", m.normal_texture)
				sm.set_shader_parameter("emission_tex", m.emission_texture)
				sm.set_shader_parameter("use_emission", m.emission_enabled)
				sm.set_shader_parameter("emission_energy", m.emission_energy_multiplier)
				sm.set_shader_parameter("glow_color", Color(col.r, col.g, col.b))
				mi.set_surface_override_material(i, sm)
