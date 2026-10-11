shader_type spatial;
// The Frost Byte blizzard's body: a widening cone of swirling snow and ice
// (a tube mesh built once; UV.x = share of the length, UV.y = round the
// cone 0..1). Streaks twist round the cone and stream outwards; white and
// ice blue; revealed up to `front`, faded by `fade`.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float front = 1.0;
uniform float fade = 1.0;
uniform float twist = 2.5;
uniform float spin_speed = 2.2;
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	// Swirl coordinates: round the cone, wound along it, turning in time.
	float ang = UV.y + UV.x * twist - TIME * spin_speed;
	// Wrap the noise round seamlessly (period 1 round the cone).
	float a1 = fract(ang) * 8.0;
	float s1 = mix(noise(vec2(a1, UV.x * 6.0 - TIME * 4.0 + seed)), noise(vec2(a1 - 8.0, UV.x * 6.0 - TIME * 4.0 + seed)), smoothstep(7.0, 8.0, a1));
	float s2 = noise(vec2(fract(ang * 2.0) * 16.0, UV.x * 14.0 - TIME * 7.0 + seed * 2.0));
	float streak = smoothstep(0.45, 0.85, s1 * 0.7 + s2 * 0.3);
	float reveal = 1.0 - smoothstep(front - 0.08, front, UV.x);
	vec3 col = mix(vec3(0.42, 0.78, 1.0), vec3(1.0), streak * 0.85 + smoothstep(front - 0.15, front, UV.x) * 0.5);
	// Rim facing the camera reads as volume: denser at the silhouette.
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	ALBEDO = col;
	ALPHA = (0.18 + 0.72 * streak) * (0.45 + 0.55 * rim) * reveal * fade * smoothstep(0.0, 0.06, UV.x) * (1.0 - 0.4 * UV.x);
}
