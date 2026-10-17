shader_type spatial;
// The glow of the Neon Sentinel's energy ball through the glass: a
// camera-facing halo round the core with flickering plasma tendrils
// licking out of it; it sits inside the eye, so the pupil slit and the
// socket rim cut it. Brighter / bigger with `energy`.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, world_vertex_coords;

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 0.82, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.82, 0.08, 1.0);
uniform float size = 0.4;
uniform float energy = 1.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }
float noise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), f);
}

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	float s = size * (0.8 + 0.25 * energy);
	VERTEX = c + (right * (UV.x - 0.5) + up * (0.5 - UV.y)) * s;
}

void fragment() {
	vec2 d = UV - 0.5;
	float r = length(d) * 2.0;
	float a = atan(d.y, d.x);
	// Tendrils: an angular noise that crawls round and flickers.
	float k = a * 1.909859 + 6.0;  // 12 lobes round the circle
	float lick = noise(k + TIME * 2.5) * noise(k * 1.7 - TIME * 4.0 + 13.0);
	float tendrils = smoothstep(0.25, 0.7, lick) * exp(-r * (3.2 - lick * 1.4));
	float hot = exp(-r * r * 30.0);
	float halo = exp(-r * r * 6.0);
	float throb = 0.88 + 0.12 * sin(TIME * 11.0) * sin(TIME * 4.3);
	vec3 col = core_color.rgb * hot * 2.2 + glow_color.rgb * (halo * 0.75 + tendrils * 1.3);
	ALBEDO = col * throb * energy * smoothstep(1.0, 0.7, r);
}
