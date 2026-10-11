shader_type spatial;
// Frosted ice on the floor round a frozen robot: a ragged patch of white
// frost with spiky crystal fronds reaching out, glassy blue ice inside.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float a = atan(p.y, p.x);
	// Fronds: thin spikes of frost reaching out at random angles.
	float fr = pow(abs(sin(a * 9.0 + seed)), 30.0) * 0.35 + pow(abs(sin(a * 14.0 - seed * 1.7)), 50.0) * 0.25;
	float edge = 0.55 + 0.15 * noise(vec2(a * 2.0 + seed, seed)) + fr;
	if (d > edge) {
		discard;
	}
	float k = d / edge;
	float n = noise(p * 9.0 + seed) * 0.6 + noise(p * 23.0) * 0.4;
	vec3 ice = mix(vec3(0.55, 0.8, 1.0), vec3(0.85, 0.95, 1.0), n);
	vec3 col = mix(ice, vec3(1.0), smoothstep(0.45, 1.0, k) * 0.8 + step(0.8, n) * 0.4);
	ALBEDO = col;
	ALPHA = (0.85 - 0.35 * k) * (1.0 - smoothstep(0.9, 1.0, k));
}
