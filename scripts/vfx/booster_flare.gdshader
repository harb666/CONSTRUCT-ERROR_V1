shader_type spatial;
// The Neon Sentinel's booster mouth (PlasmaTrail): a camera-facing plasma
// flare - white-hot centre, neon halo and four flickering spikes - that
// throbs and swells with the throttle.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, world_vertex_coords;

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 0.86, 1.0);
uniform vec4 glow_color : source_color = vec4(0.62, 1.0, 0.12, 1.0);
uniform float size = 0.6;
uniform float throttle = 0.5;
uniform float intensity = 1.0;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	float s = size * (0.75 + 0.5 * throttle);
	VERTEX = c + (right * (UV.x - 0.5) + up * (0.5 - UV.y)) * s;
}

void fragment() {
	vec2 d = UV - 0.5;
	float r = length(d) * 2.0;
	float a = atan(d.y, d.x) + TIME * 2.3;
	float spikes = pow(abs(cos(a * 2.0)), 26.0) * exp(-r * 2.4) * (0.6 + 0.4 * sin(TIME * 47.0));
	float hot = exp(-r * r * 26.0);
	float halo = exp(-r * r * 4.5);
	float throb = 0.85 + 0.15 * sin(TIME * 33.0);
	vec3 col = core_color.rgb * hot * 3.0 + glow_color.rgb * (halo * (0.9 + throttle) + spikes * 1.6);
	ALBEDO = col * throb * intensity * smoothstep(1.0, 0.75, r);
}
