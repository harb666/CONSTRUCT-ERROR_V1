shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords;
// A laser gate's emitter flares (LaserGateFX; all of a gate's flares in one
// mesh, one draw: each quad's centre in CUSTOM0.xyz, a seed in .w): camera-
// facing hot spots with four turning spikes, pulsing.

uniform vec3 color : source_color = vec3(1.0, 0.1, 0.18);
uniform float intensity = 1.0;
uniform float size = 1.4;

varying float seed;

void vertex() {
	seed = CUSTOM0.w;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	VERTEX = CUSTOM0.xyz + (right * (UV.x - 0.5) + up * (0.5 - UV.y)) * size;
}

void fragment() {
	vec2 d = UV - 0.5;
	float r = length(d) * 2.0;
	float a = atan(d.y, d.x) + TIME * 1.3 + seed;
	float spikes = pow(abs(cos(a * 2.0)), 40.0) * exp(-r * 2.2);
	float hot = exp(-r * r * 30.0);
	float halo = exp(-r * r * 4.0);
	float pulse = 0.8 + 0.2 * sin(TIME * 9.0 + seed * 5.0);
	vec3 c = vec3(1.0, 0.93, 0.9) * hot * 3.5 + color * (halo * 1.6 + spikes * 2.4);
	ALBEDO = c * intensity * pulse * smoothstep(1.0, 0.8, r);
}
