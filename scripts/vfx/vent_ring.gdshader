// Pistol cannon vent (PlasmaVent): a segmented ring of light round the
// barrel. `progress` = the lit share of it, clockwise from the top (the
// cooldown's countdown filling up); the rest shows faintly. `heat` turns it
// from the plasma's cyan to overheated orange.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.2, 0.85, 1.0, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.5, 0.15, 1.0);
uniform float amount = 1.0;
uniform float progress = 1.0;
uniform float heat = 0.0;
uniform float segments = 12.0;
// Turn (fraction of a revolution).
uniform float spin = 0.0;
uniform float width = 0.14;

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float d = abs(r - (1.0 - width));
	float ring = 1.0 - smoothstep(0.0, width, d);
	float core = 1.0 - smoothstep(0.0, width * 0.35, d);
	float a = fract(atan(p.x, -p.y) / 6.2831853 + 1.0);
	float seg = step(0.2, fract((a + spin) * segments));
	float lit = step(a, progress);
	vec3 c = mix(color.rgb, hot.rgb, heat);
	c = mix(c, vec3(1.0), core * 0.65);
	ALBEDO = c * ring * seg * mix(0.15, 1.0, lit) * amount;
}
