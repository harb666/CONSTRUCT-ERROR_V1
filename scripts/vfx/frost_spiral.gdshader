shader_type spatial;
// The Frost Byte's blizzard: spiral bands of white and ice blue wound round
// a widening cone (an ArrayMesh built once; UV.x = share of the length,
// UV.y = across the band, COLOR.r = the band's colour mix). The bands spin
// (`spin`), stream outwards (scrolling streaks), are revealed up to the
// blast's `front` and fade with `fade`.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float front = 1.0;
uniform float fade = 1.0;
uniform float spin = 0.0;
uniform float seed = 0.0;
uniform vec4 white : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 ice : source_color = vec4(0.45, 0.82, 1.0, 1.0);
uniform vec4 deep : source_color = vec4(0.2, 0.5, 0.95, 1.0);

varying float band_col;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	// Spin round the cone's axis (local +Z), a little faster near the gun.
	float a = spin * (1.3 - 0.5 * UV.x);
	float c = cos(a);
	float s = sin(a);
	VERTEX.xy = mat2(vec2(c, s), vec2(-s, c)) * VERTEX.xy;
	band_col = COLOR.r;
}

void fragment() {
	float across = abs(UV.y * 2.0 - 1.0);
	// Ragged, streaming streaks along each band.
	float streak = noise(vec2(UV.x * 26.0 - TIME * 7.0, UV.y * 3.0 + seed)) * 0.65 + noise(vec2(UV.x * 60.0 - TIME * 12.0, seed + 4.0)) * 0.35;
	float edge = 0.55 + 0.45 * streak;
	float body = 1.0 - smoothstep(edge - 0.25, edge, across);
	// Revealed up to the front, a soft bright leading edge.
	float reveal = 1.0 - smoothstep(front - 0.06, front, UV.x);
	float lead = smoothstep(front - 0.12, front - 0.02, UV.x) * reveal;
	vec3 col = mix(deep.rgb, ice.rgb, smoothstep(0.2, 0.9, 1.0 - across));
	col = mix(col, white.rgb, band_col * 0.6 + (1.0 - across) * 0.3 + lead * 0.6);
	// Darker ice-blue edges so the bands read against a bright arena.
	col = mix(col, deep.rgb, smoothstep(0.55, 0.95, across) * 0.6);
	ALBEDO = col;
	// Thins out towards the far end (the blizzard spreading wide).
	ALPHA = body * reveal * fade * (1.0 - 0.35 * UV.x) * smoothstep(0.0, 0.04, UV.x);
}
