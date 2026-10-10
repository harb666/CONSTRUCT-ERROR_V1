shader_type spatial;
// SmokeTrail ribbon, shaped on the GPU: one fixed mesh (built once, shared by
// every trail) whose vertices carry (point index, column -1 / 0 / +1) in UV;
// the trail's points come in as uniforms each frame (pts = position + age,
// seeds), so no graphics buffers are rebuilt per frame. Three columns
// across - soft edges, solid centre - camera-facing, older smoke billows
// wider, drifts up and fades; the newest stretch is warm while emitting.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 pts[72];
uniform float seeds[72];
uniform int count = 0;
uniform float lifetime = 2.6;
uniform float start_width = 0.35;
uniform float end_width = 2.2;
uniform bool emitting = false;
uniform vec4 smoke_color : source_color = vec4(0.62, 0.6, 0.58, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.62, 0.25, 1.0);

varying vec4 col;

void vertex() {
	int i = int(UV.x + 0.5);
	float c = UV.y;
	if (count < 2 || i >= count) {
		VERTEX = vec3(0.0);
		col = vec4(0.0);
	} else {
		vec3 p = pts[i].xyz;
		float age = pts[i].w;
		float seed = seeds[i];
		vec3 tang = pts[min(i + 1, count - 1)].xyz - pts[max(i - 1, 0)].xyz;
		if (dot(tang, tang) < 1e-6) {
			tang = vec3(0.0, 1.0, 0.0);
		}
		vec3 side = normalize(cross(tang, CAMERA_POSITION_WORLD - p));
		float k = clamp(age / lifetime, 0.0, 1.0);
		float w = mix(start_width, end_width, sqrt(k)) * (0.8 + 0.4 * seed);
		vec3 drift = vec3(0.0, 0.9 * k * k, 0.0) + side * sin(seed * 12.0 + age * 1.7) * 0.3 * k;
		float heat = emitting ? clamp(1.0 - age / 0.2, 0.0, 1.0) : 0.0;
		vec3 rgb = mix(smoke_color.rgb, hot_color.rgb, heat);
		float a = (1.0 - k) * (1.0 - k) * 0.85 * (0.75 + 0.25 * seed);
		if (i == count - 1 && emitting) {
			a = 0.0;
		}
		if (abs(c) > 0.5) {
			a = 0.0;  // soft edges
		}
		VERTEX = p + drift + side * w * 0.5 * c;
		col = vec4(rgb, a);
	}
}

void fragment() {
	ALBEDO = col.rgb;
	ALPHA = col.a;
}
