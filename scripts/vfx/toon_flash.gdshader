shader_type spatial;
// Cartoon muzzle flash shapes, drawn (no textures) with a white-hot centre,
// the weapon's colour and a darker rim, hard anti-aliased edges and alpha
// blending - so they read over the bright arena as well as dark backdrops.
// shape 0: star burst (camera-facing), uneven spikes picked by `seed`.
// shape 1: flame tongue along the quad's +Y (base at the bottom, tip at top)
//          with ragged sides.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.55, 0.1, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.97, 0.8, 1.0);
uniform vec4 rim : source_color = vec4(0.8, 0.2, 0.02, 1.0);
uniform int shape = 0;
uniform float spikes = 8.0;
uniform float seed = 0.0;
uniform float fade = 1.0;
// How much of the shape is white-hot (0..1).
uniform float core = 0.45;

float hash(float n) { return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453); }

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float x;
	if (shape == 0) {
		float ang = atan(p.y, p.x) / 6.2831853 + 0.5;
		float k = ang * spikes;
		float i = floor(k);
		float f = fract(k);
		// Alternate long and short spikes, each a little random.
		float tip = (mod(i, 2.0) < 0.5 ? 0.95 : 0.62) * mix(0.8, 1.0, hash(i));
		float lim = mix(0.38, tip, pow(1.0 - abs(f * 2.0 - 1.0), 2.2));
		x = length(p) / lim;
	} else {
		float t = 1.0 - UV.y;  // 0 at the base, 1 at the tip
		float wobble = 0.82 + 0.18 * sin(t * 23.0 + seed * 9.0) * sin(t * 7.0 + seed * 3.0);
		float w = (1.0 - pow(t, 1.4)) * mix(0.65, 1.0, smoothstep(0.0, 0.25, t)) * wobble;
		x = max(abs(p.x) / max(w, 0.001), smoothstep(0.92, 1.0, t) * 1.2);
	}
	vec3 c = mix(hot.rgb, color.rgb, smoothstep(core * 0.8, core + 0.1, x));
	c = mix(c, rim.rgb, smoothstep(0.82, 0.9, x));
	float aa = max(fwidth(x), 0.001);
	ALBEDO = c;
	ALPHA = (1.0 - smoothstep(1.0 - aa, 1.0 + aa, x)) * fade;
}
