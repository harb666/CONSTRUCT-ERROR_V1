shader_type spatial;
// Harbinger's halo glow: a soft tube of blue light round the core, brightest
// through its middle and fading to its edges from any viewing angle.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(0.15, 0.55, 1.0, 1.0);
uniform float strength = 0.75;

float hash(float n) { return fract(sin(n) * 43758.5453); }
float noise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), f);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float flicker = 0.8 + 0.2 * noise(TIME * 16.0 + UV.x * 6.0);
	ALBEDO = color.rgb;
	ALPHA = pow(facing, 2.0) * strength * flicker;
}
