shader_type spatial;
// Hologram overlay (material_overlay on a model's meshes): a glowing
// see-through cyan coat with moving scan lines and a bright rim.
// Teleport-in: everything above `line_y` (world height) is covered by the
// hologram, a bright band marks the line, and below it the real model shows
// - so as the line sweeps up the model materialises from the feet.
// `line_y` far below the model = whole model holographic (idle look).
// Inspired by GDQuest's 3D hologram (godot-4-vfx-assets, MIT).
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(0.3, 0.85, 1.0, 1.0);
uniform float line_y = -1000.0;
uniform float band = 0.12;
// Hologram coat opacity above the line (0 = only rim + scan lines).
uniform float coat = 0.75;
uniform float strength = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float above = smoothstep(line_y - 0.015, line_y + 0.015, wpos.y);
	float rim = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.0);
	float scan = step(0.5, fract(wpos.y * 26.0 - TIME * 2.5));
	float edge = 1.0 - smoothstep(0.0, band, abs(wpos.y - line_y));
	float a = above * (coat * (0.65 + 0.35 * scan) + rim * 0.8) + edge;
	ALBEDO = mix(color.rgb * (0.85 + 0.3 * scan), vec3(1.0), clamp(edge * 0.8 + rim * 0.3, 0.0, 1.0));
	ALPHA = clamp(a * strength, 0.0, 1.0);
}
