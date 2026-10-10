shader_type spatial;
// Shotgun energy stream, cartoon style: a solid white-hot core, a solid
// orange body and a darker rim with hard (anti-aliased) edges, and bright
// pulses racing along it. Alpha-blended, so it stays vivid over the bright
// arena. UV.x = metres along the stream, UV.y = 0..1 across; vertex alpha
// fades it.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.45, 0.05, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform vec4 rim : source_color = vec4(0.6, 0.1, 0.02, 1.0);
// 0..1: the core thins out as the trail fades.
uniform float core = 1.0;

void fragment() {
	float a = abs(UV.y * 2.0 - 1.0);  // 0 centre, 1 edge
	float pulse = smoothstep(0.55, 1.0, 0.5 + 0.5 * sin(UV.x * 5.0 - TIME * 55.0));
	float aa = max(fwidth(a), 0.002);
	float core_w = (0.3 + 0.12 * pulse) * core;
	vec3 c = mix(hot.rgb, mix(color.rgb, hot.rgb, 0.3 * pulse), smoothstep(core_w - aa, core_w + aa, a));
	c = mix(c, rim.rgb, smoothstep(0.74 - aa, 0.74 + aa, a));
	ALBEDO = c;
	ALPHA = (1.0 - smoothstep(1.0 - aa * 1.5, 1.0, a)) * COLOR.a;
}
