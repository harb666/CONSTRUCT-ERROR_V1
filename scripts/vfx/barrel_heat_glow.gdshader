shader_type spatial;
// Machine gun heat: an additive overlay on the gun body that makes the
// front/barrel glow, creeping back from the muzzle as `heat` (0..1) rises:
// yellow -> orange -> red, the yellow light panels brightest.
render_mode unshaded, blend_add, depth_draw_never, cull_back;

uniform float heat = 0.0;
uniform float strength = 1.0;
uniform float flicker = 0.0;
// Model-space X of the muzzle and how far back the glow reaches at full heat.
uniform float front_x = 0.97;
uniform float reach = 0.62;
uniform sampler2D emission_tex : source_color, hint_default_black;

varying float vx;

void vertex() {
	vx = VERTEX.x;
}

vec3 heat_color(float h) {
	vec3 c = mix(vec3(1.0, 0.8, 0.12), vec3(1.0, 0.42, 0.04), smoothstep(0.35, 0.7, h));
	return mix(c, vec3(1.0, 0.12, 0.03), smoothstep(0.78, 1.0, h));
}

void fragment() {
	float edge = front_x - reach * heat;
	float m = smoothstep(edge - 0.06, edge + 0.14, vx);
	vec3 e = texture(emission_tex, UV).rgb;
	float lights = (e.r + e.g) * 0.5;
	float k = m * heat * strength * (0.22 + 1.3 * lights) * (1.0 + flicker);
	ALBEDO = heat_color(heat) * k;
}
