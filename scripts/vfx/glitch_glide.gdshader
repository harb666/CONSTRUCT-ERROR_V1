// The player glitching as they power-glide (GlitchGlide): drawn over the
// character as its material_overlay (two passes: cyan one way, magenta the
// other). Blocky horizontal bands of the body are thrown sideways for a
// few frames at a time (like the menu glitch's band shifts), coloured and
// scan-lined, a faint coat on the rest - an RGB-split, torn signal.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, world_vertex_coords;

uniform vec4 tint : source_color = vec4(0.0, 0.95, 1.0, 1.0);
// 0..1: how hard it's glitching.
uniform float amount = 1.0;
// Sideways throw of a torn band (m); the second pass uses a negative one.
uniform float shift = 0.16;
uniform float seed = 0.0;
// Bands per metre, and how many of them are torn at once.
uniform float bands = 7.0;
uniform float torn = 0.42;

varying float v_band;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void vertex() {
	// Changes 20 times a second, in steps (a glitch, not a wobble).
	float step_t = floor(TIME * 20.0);
	float band = floor(VERTEX.y * bands);
	float h = hash(band * 12.9898 + step_t * 78.233 + seed);
	float on = step(1.0 - torn, h);
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	VERTEX += right * (h - 0.5) * 2.0 * shift * amount * on;
	// A whole-body skip now and then.
	float skip = step(0.86, hash(step_t * 3.17 + seed * 1.3));
	VERTEX += right * shift * 0.6 * amount * skip * sign(shift);
	v_band = on;
}

void fragment() {
	float scan = 0.55 + 0.45 * step(0.5, fract(FRAGCOORD.y * 0.25));
	float k = mix(0.12, 0.85, v_band) * amount * scan;
	ALBEDO = tint.rgb * k;
}
