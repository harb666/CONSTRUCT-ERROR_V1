shader_type spatial;
// Shotgun stream as a cartoon MAGMA jet (Ratchet: Gladiator's Magma Cannon):
// a fat flame body with ragged, licking edges that race along it, a
// white-hot core, orange-yellow fire and a dark red rim, plus hot pulses.
// Solid (alpha-blended), so it reads over the bright arena. UV.x = metres
// along the stream, UV.y = 0..1 across; vertex alpha fades it.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.45, 0.05, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform vec4 rim : source_color = vec4(0.6, 0.08, 0.02, 1.0);
// 0..1: the core thins out as the trail fades.
uniform float core = 1.0;
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float side = UV.y * 2.0 - 1.0;
	float a = abs(side);
	// Ragged flame edge: licks racing along the jet, different per side.
	float t = TIME * 9.0;
	float n = noise(vec2(UV.x * 3.2 - t, side > 0.0 ? seed : seed + 17.0)) * 0.6
		+ noise(vec2(UV.x * 8.0 - t * 1.7, seed + 5.0 + step(0.0, side) * 9.0)) * 0.4;
	float edge = 0.62 + 0.38 * n;
	float x = a / edge;
	float pulse = smoothstep(0.55, 1.0, 0.5 + 0.5 * sin(UV.x * 4.0 - TIME * 50.0));
	float aa = max(fwidth(x), 0.003);
	float core_w = (0.34 + 0.14 * pulse) * core;
	vec3 fire = mix(color.rgb, mix(color.rgb, hot.rgb, 0.55), 0.5 + 0.5 * n);
	vec3 c = mix(hot.rgb, fire, smoothstep(core_w - aa, core_w + aa, x));
	c = mix(c, rim.rgb, smoothstep(0.8 - aa, 0.8 + aa, x));
	ALBEDO = c;
	ALPHA = (1.0 - smoothstep(1.0 - aa * 1.5, 1.0, x)) * COLOR.a;
}
