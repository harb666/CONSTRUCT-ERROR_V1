shader_type spatial;
// Worn combat-robot armour for the boss's added/plain parts (missile silo,
// chest flap): samples the robot's own atlas (its colours stay) and wears it
// procedurally in object space - red paint chipped back to bare metal, grey
// paint scuffed lighter, scratches, grime - with metal/roughness to match.
// `restyle` turns plain flat faces facing away from the flap's front (+Z)
// into dark armour plate with a chipped red trim and panel seams.
// No extra textures.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform float wear = 1.0;
uniform float noise_scale = 42.0;
uniform float restyle = 0.0;
uniform vec3 box_min = vec3(-0.1);
uniform vec3 box_size = vec3(0.2);

varying vec3 op;
varying vec3 on;

void vertex() {
	op = VERTEX;
	on = NORMAL;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return 0.55 * noise3(p) + 0.3 * noise3(p * 2.13 + 7.1) + 0.15 * noise3(p * 4.37 + 3.3);
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	vec3 p = op * noise_scale;
	// Flap back / edges: dark armour plate, red trim round the border.
	if (restyle > 0.5 && on.z < 0.5) {
		vec3 q = clamp((op - box_min) / max(box_size, vec3(1e-4)), 0.0, 1.0);
		float border = min(min(q.x, 1.0 - q.x), min(q.y, 1.0 - q.y));
		float trim = 1.0 - smoothstep(0.1, 0.115, border);
		float seam = 1.0 - smoothstep(0.004, 0.012, min(abs(q.x - 0.5), abs(q.y - 0.42)));
		base = mix(vec3(0.075, 0.075, 0.08), vec3(0.6, 0.03, 0.03), trim);
		base *= 1.0 - 0.6 * seam * (1.0 - trim);
	}
	float redness = clamp((base.r - max(base.g, base.b)) * 3.0, 0.0, 1.0);
	// Industrial grey: plain grey paint reads as worn gunmetal.
	float grey = 1.0 - clamp(redness * 4.0, 0.0, 1.0);
	base = mix(base, base * 0.5 + vec3(0.13, 0.13, 0.14), grey * 0.6);
	float chip = smoothstep(0.64, 0.67, fbm(p + vec3(3.1)));
	float edge_wear = smoothstep(0.6, 0.66, fbm(p * 0.45 + vec3(9.0))) * 0.35;
	float scratch = smoothstep(0.9, 0.95, noise3(vec3(p.x * 7.0, p.y * 0.5, p.z * 7.0)));
	float grime = fbm(p * 0.12);
	vec3 metal = vec3(0.38, 0.38, 0.4) * (0.8 + 0.45 * noise3(p * 3.0));
	vec3 col = base;
	float bare = clamp((chip * (0.55 + 0.45 * redness) + edge_wear * redness) * wear, 0.0, 1.0);
	col = mix(col, metal, bare);
	col = mix(col, metal * 1.15, scratch * 0.45 * wear);
	col *= 0.72 + 0.36 * grime;
	ALBEDO = col;
	METALLIC = mix(0.3, 0.85, max(bare, scratch * 0.6));
	ROUGHNESS = mix(0.75, 0.38, bare) - 0.1 * scratch;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
}
