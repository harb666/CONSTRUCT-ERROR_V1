shader_type spatial;
// The robot boss's body armour: its own atlas as imported (colour, normal,
// metal / roughness), drawn on both sides (owner asked to fix the "open
// meshes" at the neck and hips). The body is thousands of single-sided
// armour sheets; from below or behind you looked past their edges at their
// backs, which weren't drawn, so the gaps showed through as jagged holes.
// Now the backs are drawn too, as the shadowed inside of the plates - the
// same metal, darker and duller - so the armour reads as solid.
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform float inner_shade = 0.42;

void fragment() {
	vec3 orm = texture(orm_tex, UV).rgb;
	ALBEDO = texture(albedo_tex, UV).rgb;
	METALLIC = orm.b;
	ROUGHNESS = orm.g;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	if (!FRONT_FACING) {
		ALBEDO *= inner_shade;
		ROUGHNESS = max(orm.g, 0.65);
	}
}
