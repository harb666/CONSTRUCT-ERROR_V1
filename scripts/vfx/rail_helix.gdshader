shader_type spatial;
// Shotgun rail trail spiral: a helical ribbon mesh along the stream's path.
// Alpha-blended (not additive) so it stays orange over bright surfaces.
// UV.x = position along the path (0 = barrel, 1 = impact), UV.y = across
// the ribbon. `head` reveals it as the stream travels; afterwards it slowly
// widens (`expand`, along NORMAL = outward from the axis) and fades.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.4, 0.05, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform float head = 0.0;
uniform float fade = 1.0;
uniform float expand = 0.0;

varying float u;
varying float v;

void vertex() {
	u = UV.x;
	v = UV.y;
	VERTEX += NORMAL * expand;
}

void fragment() {
	float edge = 1.0 - abs(v * 2.0 - 1.0);
	edge = edge * edge * (3.0 - 2.0 * edge);
	float shown = 1.0 - smoothstep(head - 0.01, head, u);
	float near_head = smoothstep(head - 0.12, head, u) * shown;
	vec3 c = mix(color.rgb, hot.rgb, clamp(near_head + edge * 0.35, 0.0, 1.0));
	ALBEDO = c;
	ALPHA = clamp(color.a * edge * shown * fade * (1.0 + near_head), 0.0, 1.0);
}
