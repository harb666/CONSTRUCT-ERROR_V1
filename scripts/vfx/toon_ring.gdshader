shader_type spatial;
// Cartoon shockwave ring on a quad: a solid cream band with a dark ink rim
// and a slightly wobbly edge (matching the puffy toon clouds). `progress`
// 0 -> 1 thins the band; `fade` fades it out. Unshaded, no textures.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 fill_color : source_color = vec4(1.0, 0.93, 0.74, 1.0);
uniform vec4 rim_color : source_color = vec4(0.42, 0.2, 0.08, 1.0);
uniform float width = 0.32;
uniform float progress = 0.0;
uniform float fade = 1.0;
uniform float seed = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float a = atan(p.y, p.x);
	// Lumpy cartoon edge.
	float wob = 0.025 * sin(a * 7.0 + seed) + 0.015 * sin(a * 13.0 - seed * 1.7);
	float outer = 0.96 + wob;
	float w = width * (1.0 - 0.75 * progress);
	float inner = outer - w;
	float aa = fwidth(d) * 1.5;
	float band = smoothstep(inner - aa, inner + aa, d) * (1.0 - smoothstep(outer - aa, outer + aa, d));
	if (band <= 0.0) {
		discard;
	}
	// Ink rim on both edges, thicker outside.
	float rim_w = max(w * 0.22, aa * 2.0);
	float rim = 1.0 - smoothstep(rim_w * 0.6, rim_w, min(d - inner, (outer - d) * 0.7));
	vec3 col = mix(fill_color.rgb, rim_color.rgb, rim);
	ALBEDO = col;
	ALPHA = band * fade;
}
