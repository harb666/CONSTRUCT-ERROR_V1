// The player glitching as they power-glide (GlitchGlide): drawn over the
// character as its material_overlay, in one pass (a second pass redrew the
// whole character once more - too much for a phone mid-glide). Blocky
// horizontal bands of the body are thrown sideways for a few frames at a
// time (like the menu glitch's band shifts), each torn band cyan or
// magenta (thrown opposite ways: an RGB split), scan-lined, a faint coat
// on the rest.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, world_vertex_coords;

uniform vec4 tint : source_color = vec4(0.0, 0.95, 1.0, 1.0);
uniform vec4 tint2 : source_color = vec4(1.0, 0.1, 0.85, 1.0);
// 0..1: how hard it's glitching.
uniform float amount = 1.0;
// Sideways throw of a torn band (m).
uniform float shift = 0.16;
uniform float seed = 0.0;
// Bands per metre, and how many of them are torn at once.
uniform float bands = 7.0;
uniform float torn = 0.42;

varying float v_band;
varying vec3 v_col;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void vertex() {
	// Changes 20 times a second, in steps (a glitch, not a wobble).
	float step_t = floor(TIME * 20.0);
	float band = floor(VERTEX.y * bands);
	float h = hash(band * 12.9898 + step_t * 78.233 + seed);
	float on = step(1.0 - torn, h);
	float which = step(0.5, fract(h * 7.31));
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	float dir = which > 0.5 ? 1.0 : -0.8;
	VERTEX += right * (0.35 + 0.65 * fract(h * 3.7)) * dir * shift * amount * on;
	// A whole-body skip now and then.
	float skip = step(0.86, hash(step_t * 3.17 + seed * 1.3));
	VERTEX += right * shift * 0.6 * amount * skip;
	v_band = on;
	v_col = mix(tint.rgb, tint2.rgb, which);
}

void fragment() {
	float scan = 0.55 + 0.45 * step(0.5, fract(FRAGCOORD.y * 0.25));
	float k = mix(0.12, 0.85, v_band) * amount * scan;
	ALBEDO = mix(tint.rgb, v_col, v_band) * k;
}
