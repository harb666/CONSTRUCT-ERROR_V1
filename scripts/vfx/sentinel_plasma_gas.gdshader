shader_type spatial;
// The Neon Sentinel's eye gas (owner asked: "more yellowish plasma gas
// inside the glass"): glowing yellow plasma swirling round the core, thick
// through the middle of the eye and wispy at its edge, curling and
// flickering; brighter with `energy` (RobotSentinel's expressions: it
// flares when it's startled, winding up a volley or hit).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 centre = vec3(0.0, -0.035, 0.37);
uniform float energy = 1.0;
uniform vec4 deep : source_color = vec4(1.0, 0.5, 0.02, 1.0);
uniform vec4 bright : source_color = vec4(1.0, 0.9, 0.18, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 1.0, 0.78, 1.0);

varying vec3 p;

float hash(vec3 q) {
	q = fract(q * 0.3183099 + 0.1);
	q *= 17.0;
	return fract(q.x * q.y * q.z * (q.x + q.y + q.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	p = VERTEX - centre;
}

void fragment() {
	float t = TIME * (0.8 + 0.5 * energy);
	// Swirl round the eye's axis, faster near the core.
	float r = length(p.xy);
	float a = t * 1.4 + (0.25 - r) * 9.0;
	vec3 q = vec3(mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * p.xy, p.z) * 13.0;
	float n = noise(q + vec3(0.0, -t * 1.6, t * 0.7)) * 0.6 + noise(q * 2.3 + vec3(t * 2.1, 0.0, 0.0)) * 0.4;
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float dens = pow(facing, 1.3) * (0.3 + 1.1 * n * n);
	vec3 col = mix(deep.rgb, bright.rgb, smoothstep(0.25, 0.7, n));
	col = mix(col, hot.rgb, smoothstep(0.62, 0.9, n) * facing);
	float flicker = 0.9 + 0.1 * sin(TIME * 23.0 + n * 6.0);
	ALBEDO = col * dens * flicker * (0.55 + 0.45 * energy);
}
