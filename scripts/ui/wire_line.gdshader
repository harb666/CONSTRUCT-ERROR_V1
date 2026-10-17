shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled, blend_mix;
// The character preview's wire copies (WireMesh): its real mesh edges, in
// neon, where the dissolve has reached (rising from the feet with a blocky
// ragged edge - the same key as wire_hide.gdshader, which paints the
// textured body out there). Drawn through the body, like the glitch
// video's full wireframes.
#include "res://scripts/ui/wire_dissolve.gdshaderinc"

uniform vec4 color : source_color = vec4(0.4, 1.0, 0.5, 1.0);

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float k = dissolve_key(world_y, FRAGCOORD.xy);
	if (k >= wire * (1.0 + front_w) - front_w || wire <= 0.0) {
		discard;
	}
	ALBEDO = color.rgb * 1.3;
	ALPHA = 1.0;
}
