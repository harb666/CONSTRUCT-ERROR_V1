shader_type spatial;
// Molten splat a shotgun stream leaves on the surface it hits (Magma Cannon
// style, cartoon): a blobby splash with drips and flung droplets, white-hot
// centre, orange fire and a dark red ink rim; it cools to a charred scorch
// with glowing cracks, then fades. Lies flat on the surface (quad in its
// plane). `heat` 1 -> 0 cools it, `fade` fades it, `grow` 0 -> 1 splashes out.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.45, 0.06, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.96, 0.78, 1.0);
uniform vec4 rim : source_color = vec4(0.6, 0.1, 0.02, 1.0);
uniform vec4 char_color : source_color = vec4(0.13, 0.06, 0.05, 1.0);
uniform float heat = 1.0;
uniform float fade = 1.0;
uniform float grow = 1.0;
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) / max(grow, 0.05);
	float d = length(p);
	float a = atan(p.y, p.x);
	// Lumpy blob + a few drips / splash spikes.
	float e = 0.52 + 0.12 * noise(vec2(a * 1.6 + seed, seed)) + 0.06 * sin(a * 5.0 + seed * 3.0);
	float sp = pow(max(cos(a * 3.0 + seed * 2.1), 0.0), 18.0) * 0.32 + pow(max(cos(a * 5.0 - seed * 1.3), 0.0), 26.0) * 0.22;
	float edge = e + sp;
	float shape = d / edge;
	// Flung droplets around it.
	float drops = -1.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		float ang = seed * 4.0 + fi * 1.13 + hash(vec2(fi, seed)) * 0.6;
		float dist = 0.68 + 0.22 * hash(vec2(seed, fi));
		vec2 c = vec2(cos(ang), sin(ang)) * dist;
		float r = 0.05 + 0.05 * hash(vec2(fi + 3.0, seed));
		drops = max(drops, 1.0 - length(p - c) / r);
	}
	float aa = max(fwidth(shape), 0.004);
	float inside = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, shape);
	float body = max(inside, step(0.0, drops));
	if (body <= 0.0) {
		discard;
	}
	float x = inside > 0.0 ? shape : 0.9;
	// Hot: white-hot centre -> fire -> ink rim. Shrinks as it cools.
	float core_w = 0.45 * heat;
	float n = noise(p * 4.0 + seed);
	vec3 fire = mix(color.rgb, hot.rgb, 0.35 * n);
	vec3 molten = mix(hot.rgb, fire, smoothstep(core_w - aa, core_w + aa, x));
	molten = mix(molten, rim.rgb, smoothstep(0.82 - aa, 0.82 + aa, x));
	// Cooled: char with glowing cracks that die out last.
	float crack = 1.0 - smoothstep(0.0, 0.07, abs(noise(p * 5.0 + seed * 1.7) - 0.5));
	vec3 scorch = mix(char_color.rgb, mix(rim.rgb, color.rgb, 0.5), crack * smoothstep(0.0, 0.6, heat) * (1.0 - x * 0.6));
	vec3 c = mix(scorch, molten, smoothstep(0.35, 0.85, heat));
	ALBEDO = c;
	// Soft outer edge so it sits on the surface (no hard paper cut-out).
	ALPHA = body * fade * mix(0.85, 1.0, heat) * (1.0 - 0.35 * smoothstep(0.75, 1.0, x) * (1.0 - heat));
}
