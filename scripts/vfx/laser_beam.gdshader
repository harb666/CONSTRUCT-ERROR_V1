shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords;
// A laser gate's beams (LaserGateFX; all of a gate's beams in one mesh, one
// draw: each quad's beam centre in CUSTOM0.xyz, a seed in .w; `axis` is
// the gate's long side): ribbons along the beams that always turn to face
// the camera, with a white-hot core inside a red glow,
// energy pulses racing along it and a fast flicker. `intensity` / `thin`
// drive the opening overload and collapse.

uniform vec3 core_color : source_color = vec3(1.0, 0.92, 0.9);
uniform vec3 glow_color : source_color = vec3(1.0, 0.06, 0.16);
uniform float width = 0.55;
uniform float length = 12.0;
uniform float intensity = 1.0;
uniform float thin = 1.0;
uniform vec3 axis = vec3(1.0, 0.0, 0.0);

varying float seed;

void vertex() {
	vec3 center = CUSTOM0.xyz;
	seed = CUSTOM0.w;
	float along = dot(VERTEX - center, axis);
	vec3 p = center + axis * along;
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - p);
	vec3 side = normalize(cross(axis, to_cam));
	VERTEX = p + side * (UV.y - 0.5) * width * thin;
}

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	float y = abs(UV.y - 0.5) * 2.0;
	float core = exp(-y * y * 160.0);
	float glow = exp(-y * y * 7.0);
	float x = UV.x * length;
	// Energy pulses racing along the beam, and a finer shimmer.
	float pulse = pow(0.5 + 0.5 * sin(x * 1.6 - TIME * 16.0 + seed * 3.0), 6.0);
	float shimmer = 0.75 + 0.25 * sin(x * 9.0 + TIME * 37.0 + seed * 11.0);
	float flick = 0.86 + 0.14 * sin(TIME * 61.0 + seed * 7.0) * sin(TIME * 23.0 + seed);
	float ends = smoothstep(0.0, 0.015, UV.x) * smoothstep(1.0, 0.985, UV.x);
	vec3 c = core_color * core * (2.4 + 1.5 * pulse) + glow_color * glow * (0.55 + 0.35 * shimmer + 0.9 * pulse);
	ALBEDO = c * intensity * flick * ends;
}
