shader_type spatial;
// Jagged crackling fire bolts round a shotgun stream (cartoon: solid
// white-hot core, fiery body, dark rim, pulses). Built once per shot along
// the path - VERTEX = kink point on the path, NORMAL = path direction,
// TANGENT = a sideways axis, UV2 = (share of the path, kink growth),
// COLOR.r = this bolt's seed - and jagged here: every `rejag` seconds each
// kink jumps to a new random offset (no per-frame mesh rebuilds). The part
// past the head collapses onto `head_pos`; the ribbon faces the camera.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.45, 0.05, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform vec4 rim : source_color = vec4(0.6, 0.1, 0.02, 1.0);
uniform float core = 1.0;
uniform float head = 1.0;
uniform vec3 head_pos;
uniform float width = 0.055;
uniform float jag = 0.15;
uniform float rejag = 0.035;
uniform float seed = 0.0;
uniform float fade = 1.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void vertex() {
	vec3 p = VERTEX;
	if (UV2.x >= head) {
		p = head_pos;
	} else {
		float step = floor(TIME / rejag);
		float k = UV2.x * 911.0 + COLOR.r * 97.0 + seed;
		vec2 r = vec2(hash(k + step * 13.37), hash(k * 1.731 + step * 7.13 + 3.1)) * 2.0 - 1.0;
		vec3 n1 = normalize(TANGENT);
		vec3 n2 = normalize(cross(normalize(NORMAL), n1));
		p += (n1 * r.x + n2 * r.y) * jag * UV2.y;
	}
	vec3 side = normalize(cross(normalize(NORMAL), normalize(CAMERA_POSITION_WORLD - p)));
	VERTEX = p + side * (UV.y * 2.0 - 1.0) * width * 0.5;
	COLOR = vec4(1.0, 1.0, 1.0, fade);
}

void fragment() {
	float a = abs(UV.y * 2.0 - 1.0);
	float pulse = smoothstep(0.55, 1.0, 0.5 + 0.5 * sin(UV.x * 5.0 - TIME * 55.0));
	float aa = max(fwidth(a), 0.002);
	float core_w = (0.3 + 0.12 * pulse) * core;
	vec3 c = mix(hot.rgb, mix(color.rgb, hot.rgb, 0.3 * pulse), smoothstep(core_w - aa, core_w + aa, a));
	c = mix(c, rim.rgb, smoothstep(0.74 - aa, 0.74 + aa, a));
	ALBEDO = c;
	ALPHA = (1.0 - smoothstep(1.0 - aa * 1.5, 1.0, a)) * COLOR.a;
}
