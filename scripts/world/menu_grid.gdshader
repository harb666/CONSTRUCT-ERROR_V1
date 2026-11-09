shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
// The menu backdrop's floor (owner asked for a light title: the full test
// arena behind the menus cost a phone too much memory): a dark floor with
// glowing cyan grid lines, brighter every 4th, fading into the distance,
// a slow pulse running out from the middle.
uniform vec4 line_color : source_color = vec4(0.27, 0.86, 0.96, 1.0);
uniform vec4 floor_color : source_color = vec4(0.02, 0.05, 0.08, 1.0);
uniform float cell = 2.0;
uniform float fade_from = 18.0;
uniform float fade_to = 70.0;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid(vec2 p, float size, float width) {
	vec2 g = abs(fract(p / size - 0.5) - 0.5) / fwidth(p / size);
	return 1.0 - clamp(min(g.x, g.y) - width, 0.0, 1.0);
}

void fragment() {
	vec2 p = world.xz;
	float fine = grid(p, cell, 0.2);
	float major = grid(p, cell * 4.0, 0.6);
	float d = length(p);
	float fade = 1.0 - smoothstep(fade_from, fade_to, d);
	float pulse = 0.5 + 0.5 * sin(d * 0.35 - TIME * 1.6);
	float l = max(fine * 0.35, major * (0.75 + 0.25 * pulse)) * fade;
	ALBEDO = mix(floor_color.rgb, line_color.rgb, l);
}
