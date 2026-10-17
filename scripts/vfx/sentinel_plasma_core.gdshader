shader_type spatial;
// The Neon Sentinel's energy ball (owner asked to make it better): a ball of
// plasma - white-hot where it faces you, burning yellow to amber at its
// rim - with hot currents crawling over it, throbbing; brighter with
// `energy`.
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

uniform float energy = 1.0;

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
	p = VERTEX;
}

void fragment() {
	float f = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float n = noise(p * 60.0 + vec3(0.0, TIME * 3.0, TIME * 1.7));
	float veins = smoothstep(0.55, 0.8, noise(p * 110.0 - vec3(TIME * 4.0, 0.0, 0.0)));
	vec3 col = mix(vec3(1.0, 0.45, 0.0), vec3(1.0, 0.88, 0.15), smoothstep(0.0, 0.6, f));
	col = mix(col, vec3(1.0, 1.0, 0.85), pow(f, 2.5) * (0.7 + 0.3 * n) + veins * 0.5);
	float throb = 0.92 + 0.08 * sin(TIME * 9.0) + 0.05 * sin(TIME * 31.0);
	ALBEDO = col * throb * (0.9 + 0.35 * energy);
}
