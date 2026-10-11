shader_type spatial;
// Burning toxic slime a toxic barrel leaves where it bursts (cartoon): a
// lumpy glossy puddle with drips and flung droplets, a glowing bright-green
// core, darker green body and an ink-dark rim; bubbles swell and pop on it,
// slime ripples and a wet glint drifts across. `burn` 1 -> 0 dies it down
// (the glow goes, it darkens to a sticky residue), `fade` fades it, `grow`
// 0 -> 1 splashes it out. Lies flat on the surface (quad in its plane).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 core_color : source_color = vec4(0.82, 1.0, 0.25, 1.0);
uniform vec4 body_color : source_color = vec4(0.25, 0.9, 0.08, 1.0);
uniform vec4 deep_color : source_color = vec4(0.04, 0.32, 0.05, 1.0);
uniform vec4 rim_color : source_color = vec4(0.03, 0.09, 0.03, 1.0);
uniform float burn = 1.0;
uniform float fade = 1.0;
uniform float grow = 1.0;
uniform float seed = 0.0;
uniform float droplets = 1.0;

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
	// Lumpy puddle with splash spikes / drips that wobble slowly.
	float wob = TIME * 0.6;
	float e = 0.58 + 0.12 * noise(vec2(a * 1.4 + seed, seed + wob * 0.3)) + 0.05 * sin(a * 4.0 + seed * 3.0 + wob);
	float sp = pow(max(cos(a * 3.0 + seed * 2.1), 0.0), 16.0) * 0.28 + pow(max(cos(a * 5.0 - seed * 1.3), 0.0), 24.0) * 0.2;
	float shape = d / (e + sp);
	float drops = -1.0;
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		float ang = seed * 4.0 + fi * 0.97 + hash(vec2(fi, seed)) * 0.7;
		float dist = 0.7 + 0.24 * hash(vec2(seed, fi));
		vec2 c = vec2(cos(ang), sin(ang)) * dist;
		float r = 0.04 + 0.05 * hash(vec2(fi + 3.0, seed));
		drops = max(drops, 1.0 - length(p - c) / r);
	}
	drops *= droplets;
	float aa = max(fwidth(shape), 0.004);
	float inside = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, shape);
	float body = max(inside, step(0.0, drops));
	if (body <= 0.0) {
		discard;
	}
	float x = inside > 0.0 ? shape : 0.9;
	// Slime: deep green body, glowing core, bright ripples, dark rim.
	float t = TIME;
	float rip = noise(p * 3.0 + vec2(t * 0.35, -t * 0.27) + seed) * 0.6 + noise(p * 7.0 - vec2(t * 0.5, t * 0.2)) * 0.4;
	vec3 slime = mix(deep_color.rgb, body_color.rgb, smoothstep(0.25, 0.75, rip));
	float glow = (1.0 - smoothstep(0.0, 0.62, x)) * burn;
	slime = mix(slime, core_color.rgb, glow * (0.55 + 0.45 * rip));
	// Bubbles: cells that swell, pop (bright ring) and come back.
	vec2 g = p * 4.2 + seed;
	vec2 cell = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = hash(cell);
	float life = fract(t * (0.35 + 0.5 * h) + h * 7.0);
	vec2 off = (vec2(hash(cell + 1.7), hash(cell + 5.3)) - 0.5) * 0.4;
	float br = (0.12 + 0.2 * h) * life;
	float bd = length(f - off);
	float bubble = (1.0 - smoothstep(br - 0.04, br, bd)) * step(0.35, h) * (1.0 - smoothstep(0.85, 1.0, life));
	float bring = (1.0 - smoothstep(0.0, 0.035, abs(bd - br))) * step(0.35, h);
	slime = mix(slime, core_color.rgb, bubble * 0.45 * (0.4 + 0.6 * burn));
	slime = mix(slime, vec3(0.95, 1.0, 0.7), bring * 0.6 * (0.3 + 0.7 * burn) * (1.0 - smoothstep(0.7, 1.0, x)));
	// Wet glint drifting over it.
	float gl = pow(max(noise(p * 2.0 + vec2(t * 0.15, 0.0) + seed * 2.0), 0.0), 6.0) * 2.0;
	slime += vec3(0.8, 1.0, 0.6) * gl * 0.35;
	slime = mix(slime, rim_color.rgb, smoothstep(0.84 - aa, 0.84 + aa, x));
	// Burnt out: a darker, duller residue.
	vec3 residue = mix(rim_color.rgb, deep_color.rgb, 0.6 + 0.4 * rip);
	ALBEDO = mix(residue, slime, smoothstep(0.0, 0.5, burn));
	ALPHA = body * fade * mix(0.8, 0.97, burn) * (1.0 - 0.3 * smoothstep(0.78, 1.0, x));
}
