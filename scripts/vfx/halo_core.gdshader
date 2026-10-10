shader_type spatial;
// Harbinger's halo core: a bright electric-blue ring with white-hot current
// running round it.
render_mode unshaded, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(0.15, 0.55, 1.0, 1.0);

float hash(float n) { return fract(sin(n) * 43758.5453); }
float noise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), f);
}

void fragment() {
	float run = smoothstep(0.55, 0.95, noise(UV.x * 26.0 - TIME * 10.0));
	float pulse = 0.85 + 0.15 * noise(TIME * 15.0);
	ALBEDO = mix(color.rgb * 1.3, vec3(0.9, 0.97, 1.0), 0.25 + 0.6 * run) * pulse;
}
