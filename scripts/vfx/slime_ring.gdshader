// Slime splash (SlimeSplash): a ripple ring racing out over the slime
// (`disc` = 0), or the foam patch where the body went in (`disc` = 1: a
// soft bright blob). Toxic green with a pale crest, alpha-faded by `amount`.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.45, 1.0, 0.15, 1.0);
uniform float amount = 1.0;
// Ring width (fraction of its radius).
uniform float width = 0.16;
uniform float disc = 0.0;

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	if (disc > 0.5) {
		float k = 1.0 - smoothstep(0.2, 1.0, r);
		// Lumpy foam: broken up round its edge.
		float a = atan(UV.y - 0.5, UV.x - 0.5);
		k *= 0.75 + 0.25 * sin(a * 7.0 + r * 9.0);
		ALBEDO = mix(color.rgb, vec3(0.92, 1.0, 0.75), k * 0.6);
		ALPHA = clamp(k * 1.3, 0.0, 1.0) * amount;
	} else {
		float d = abs(r - (1.0 - width));
		float ring = 1.0 - smoothstep(0.0, width, d);
		float crest = 1.0 - smoothstep(0.0, width * 0.35, d);
		float inside = (1.0 - smoothstep(0.0, 1.0 - width, r)) * 0.18;
		ALBEDO = mix(color.rgb, vec3(0.9, 1.0, 0.7), crest * 0.7);
		ALPHA = clamp(ring * 0.9 + inside, 0.0, 1.0) * amount;
	}
}
