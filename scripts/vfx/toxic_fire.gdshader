shader_type spatial;
// Green cartoon fire burning on toxic slime (ToxicSlime): a flame quad
// (turned to the camera about the vertical by its script) with licking
// tongues that rise and flicker, cel bands - white-green hot core, toxic
// green body, dark green rim - and the odd blob breaking off the top.
// `burn` 1 -> 0 dies it down, `fade` fades it.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 hot_color : source_color = vec4(0.93, 1.0, 0.72, 1.0);
uniform vec4 mid_color : source_color = vec4(0.62, 1.0, 0.2, 1.0);
uniform vec4 body_color : source_color = vec4(0.24, 0.88, 0.06, 1.0);
uniform vec4 rim_color : source_color = vec4(0.03, 0.26, 0.04, 1.0);
uniform float burn = 1.0;
uniform float fade = 1.0;
uniform float seed = 0.0;
uniform float speed = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float y = 1.0 - UV.y;            // 0 at the base, 1 at the top
	float x = UV.x * 2.0 - 1.0;
	float t = TIME * speed + seed;
	// Teardrop body that narrows to licking tips.
	float grad = 1.0 - y;
	float w = 0.12 + 0.88 * pow(max(grad, 0.0), 0.65);
	float n = noise(vec2(x * 2.6 + seed, y * 3.2 - t * 2.4)) * 0.62 + noise(vec2(x * 6.5 - seed, y * 7.0 - t * 4.1)) * 0.38;
	float sway = (noise(vec2(y * 1.5 - t * 0.9, seed)) - 0.5) * 0.35 * y;
	float shape = 1.0 - abs(x - sway) / w;
	float field = shape * 0.95 + grad * 0.55 - 0.5 + (n - 0.5) * (0.55 + 0.5 * y);
	field -= (1.0 - burn) * 0.45;
	// Blobs breaking off the top.
	vec2 bp = vec2(x * 2.0, y * 3.0 - t * 1.6);
	float blob = (noise(bp * 2.2) - 0.72) * 2.5 * smoothstep(0.45, 0.9, y) * smoothstep(1.0, 0.75, abs(x));
	field = max(field, blob);
	float aa = max(fwidth(field), 0.01);
	float mask = smoothstep(-aa, aa, field);
	if (mask <= 0.0) {
		discard;
	}
	// Cel bands from the rim in to the hot core.
	vec3 c = rim_color.rgb;
	c = mix(c, body_color.rgb, smoothstep(0.07 - aa, 0.07 + aa, field));
	c = mix(c, mid_color.rgb, smoothstep(0.24 - aa, 0.24 + aa, field));
	// Hot core: a soft, flickering blob low in the flame.
	float core = field - 0.5 + 0.18 * (1.0 - y) + (noise(vec2(x * 4.0, y * 5.0 - t * 5.0)) - 0.5) * 0.25;
	c = mix(c, hot_color.rgb, smoothstep(-aa, aa, core) * burn);
	ALBEDO = c;
	ALPHA = mask * fade * (1.0 - smoothstep(0.92, 1.0, y));
}
