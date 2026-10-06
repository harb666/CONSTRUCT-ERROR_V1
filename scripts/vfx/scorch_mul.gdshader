shader_type spatial;
// Ground scorch: darkens what's under it where the greyscale mark is
// (multiply blend; no dark square around it). `strength` fades it out.
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D tex : hint_default_black;
uniform float strength = 0.8;

void fragment() {
	float m = texture(tex, UV).r * strength;
	ALBEDO = mix(vec3(1.0), vec3(0.12, 0.09, 0.08), m);
}
