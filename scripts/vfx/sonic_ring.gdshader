// Sonic boom pieces (SonicBoom): a shock ring (a flat quad drawing a bright
// ring with a white-hot core and a cyan / magenta edge), or the vapor cone
// (`cone` = 1: a cone mesh, bright at its rim edge-on, fading down its
// length).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 core : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 edge : source_color = vec4(0.0, 0.95, 1.0, 1.0);
uniform vec4 edge2 : source_color = vec4(1.0, 0.15, 0.85, 1.0);
// 0..1 how bright (fades out as it spreads).
uniform float amount = 1.0;
// Ring width (fraction of its radius).
uniform float width = 0.18;
uniform float cone = 0.0;

void fragment() {
	if (cone > 0.5) {
		float rim = 1.0 - abs(dot(NORMAL, VIEW));
		float along = mix(0.3, 1.0, UV.y);
		float k = pow(rim, 2.0) * along * amount;
		ALBEDO = mix(edge.rgb, core.rgb, rim) * k;
	} else {
		float r = length(UV - 0.5) * 2.0;
		float d = abs(r - (1.0 - width));
		float ring = 1.0 - smoothstep(0.0, width, d);
		float hot = 1.0 - smoothstep(0.0, width * 0.35, d);
		// Torn into segments, glitch style.
		float a = atan(UV.y - 0.5, UV.x - 0.5);
		float seg = step(0.25, fract(sin(floor(a * 6.0 + TIME * 30.0) * 91.7) * 437.5));
		vec3 c = mix(mix(edge2.rgb, edge.rgb, seg), core.rgb, hot);
		ALBEDO = c * ring * amount * (0.55 + 0.45 * seg);
	}
}
