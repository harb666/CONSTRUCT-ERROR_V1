shader_type spatial;
// Cartoon cel muzzle flash (techniques from VFEZ-godot, MIT, Alexander
// Nikopoulos 2025: posterize, hand-drawn boil, dissolve + burn). Procedural,
// no textures.
// shape 0 = star burst (camera-facing), 1 = flame cone along +Y.
// - posterized colour bands (white / hot / mid / ink rim) - cel look
// - hand-drawn boil: the outline re-jitters `boil_fps` times a second
// - noise dissolve with a burning edge as `progress` -> 1 (breaks into blobs)
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 hot : source_color = vec4(1.0, 1.0, 0.92, 1.0);
uniform vec4 mid : source_color = vec4(1.0, 0.85, 0.2, 1.0);
uniform vec4 outer : source_color = vec4(1.0, 0.45, 0.05, 1.0);
uniform vec4 ink : source_color = vec4(0.45, 0.08, 0.02, 1.0);
uniform vec4 burn : source_color = vec4(1.0, 0.95, 0.6, 1.0);
uniform int shape = 0;
uniform float spikes = 9.0;
uniform float seed = 0.0;
uniform float progress = 0.0;
uniform float boil_fps = 12.0;

float h1(float n) { return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453); }
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float frame = floor(TIME * boil_fps);
	vec2 p = UV * 2.0 - 1.0;
	// hand-drawn boil: tiny stepped offsets
	p += (vec2(h1(frame), h1(frame + 7.0)) - 0.5) * 0.04;
	float x;
	vec2 nuv;
	if (shape == 0) {
		float ang = atan(p.y, p.x) / 6.2831853 + 0.5;
		float k = ang * spikes;
		float i = floor(k);
		float f = fract(k);
		float tip = (mod(i, 2.0) < 0.5 ? 1.0 : 0.6) * mix(0.75, 1.0, h1(i + frame * 3.1));
		float lim = mix(0.32, tip, pow(1.0 - abs(f * 2.0 - 1.0), 2.4));
		x = length(p) / lim;
		nuv = vec2(ang * 6.0, length(p) * 3.0);
	} else {
		float t = 1.0 - UV.y;
		float wob = 0.85 + 0.15 * sin(t * 19.0 + seed * 9.0 + frame * 1.7);
		float w = (1.0 - pow(t, 1.3)) * mix(0.55, 1.0, smoothstep(0.0, 0.2, t)) * wob;
		x = max(abs(p.x) / max(w, 0.001), smoothstep(0.9, 1.0, t) * 1.2);
		nuv = vec2(p.x * 2.0, t * 4.0 - TIME * 6.0);
	}
	// Dissolve into blobs (outer parts first), burning edge.
	float n = vnoise(nuv * 2.5 + seed) * 0.7 + vnoise(nuv * 6.0 - seed) * 0.3;
	float d = n + (1.0 - x) * 0.6 - progress * 1.25;
	float aa = max(fwidth(x), 0.002);
	// Posterized bands.
	vec3 c = hot.rgb;
	c = mix(c, mid.rgb, step(0.32, x));
	c = mix(c, outer.rgb, step(0.62, x));
	c = mix(c, ink.rgb, step(0.86, x));
	c = mix(c, burn.rgb, step(d, 0.06) * step(0.0, d) * step(x, 0.86) * step(0.3, progress));
	ALBEDO = c;
	ALPHA = (1.0 - smoothstep(1.0 - aa, 1.0 + aa, x)) * step(0.0, d);
}
