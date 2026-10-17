shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_never;
// Overlay on the preview character's textured meshes (WireMesh): where the
// dissolve has reached, the body is painted out in the panel's dark colour
// (leaving its wire copy), with a glowing front band where it's crossing.
#include "res://scripts/ui/wire_dissolve.gdshaderinc"

uniform vec3 hide_color : source_color = vec3(0.03, 0.09, 0.11);
uniform vec3 front_a : source_color = vec3(1.0, 0.25, 0.85);
uniform vec3 front_b : source_color = vec3(0.3, 0.95, 1.0);

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float k = dissolve_key(world_y, FRAGCOORD.xy);
	float w2 = wire * (1.0 + front_w);
	if (k >= w2 || wire <= 0.0) {
		discard;
	}
	if (k >= w2 - front_w) {
		vec2 cell = floor(FRAGCOORD.xy / cell_px);
		ALBEDO = mix(front_a, front_b, dhash(cell * 1.7 + seed));
	} else {
		ALBEDO = hide_color;
	}
}
