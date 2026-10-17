shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// The faint force field between a laser gate's beams (LaserGateFX):
// hexagon cells, scan lines sweeping up, brighter at the frame's edges.
// `intensity` 0 = gone (the gate opening wipes it away from the bottom).

uniform vec3 color : source_color = vec3(1.0, 0.08, 0.2);
uniform vec2 size = vec2(12.0, 6.0);
uniform float intensity = 1.0;
uniform float wipe = 0.0;

float hex(vec2 p) {
	p.x *= 1.1547;
	p.y += mod(floor(p.x), 2.0) * 0.5;
	p = abs(fract(p) - 0.5);
	return abs(max(p.x * 1.5 + p.y, p.y * 2.0) - 1.0);
}

void fragment() {
	vec2 p = UV * size;
	float cells = 1.0 - smoothstep(0.0, 0.08, hex(p * 1.6));
	float scan = pow(fract(UV.y * 1.0 - TIME * 0.35), 18.0);
	float lines = 0.5 + 0.5 * sin(UV.y * size.y * 40.0 + TIME * 6.0);
	vec2 e = min(UV, 1.0 - UV) * size;
	float edge = exp(-min(e.x, e.y) * 3.0);
	float shimmer = 0.7 + 0.3 * sin(TIME * 3.0 + p.x * 0.7 + p.y * 0.4);
	float a = (cells * 0.18 * shimmer + scan * 0.35 + lines * 0.03 + edge * 0.5);
	float gone = step(1.0 - UV.y, wipe);
	ALBEDO = color * a * intensity * (1.0 - gone);
}
