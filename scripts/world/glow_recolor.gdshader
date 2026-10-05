shader_type spatial;
// Same PBR inputs as the weapon spawn pad's imported material (albedo,
// ORM: G roughness / B metallic, normal map, emission), but every purple
// texel (in both the colour and the emissive texture) becomes `glow_color`
// at the same brightness. Greys and darks are untouched. Lets one pad model
// and its textures glow in any colour without extra texture downloads.
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D emission_tex : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec3 glow_color : source_color = vec3(1.0, 0.42, 0.05);
uniform float emission_energy = 1.0;
uniform bool use_emission = true;

vec3 recolor(vec3 c) {
	float hi = max(c.r, c.b);
	if (hi < 0.0005) {
		return c;
	}
	// Purple = red and blue well above green, blue-leaning.
	float sat = (hi - c.g) / hi;
	float purple = smoothstep(0.12, 0.42, sat) * smoothstep(0.0, 0.15, (c.b - c.g) / hi);
	vec3 g = glow_color / max(max(glow_color.r, glow_color.g), max(glow_color.b, 0.001));
	return mix(c, g * hi, purple);
}

void fragment() {
	vec3 a = texture(albedo_tex, UV).rgb;
	ALBEDO = recolor(a);
	vec4 orm = texture(orm_tex, UV);
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	if (use_emission) {
		EMISSION = recolor(texture(emission_tex, UV).rgb) * emission_energy;
	}
}
