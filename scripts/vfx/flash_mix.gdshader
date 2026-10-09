// Solid (alpha-blended, not additive) fire for flashes that must show up
// on bright backgrounds: a greyscale texture gives the shape (as alpha),
// `color` the colour; hotter (brighter) towards the texture's core.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D tex : filter_linear_mipmap, repeat_disable;
uniform vec4 color : source_color = vec4(1.0, 0.55, 0.12, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform float fade = 1.0;

void fragment() {
	float m = texture(tex, UV).r;
	ALBEDO = mix(color.rgb, hot_color.rgb, smoothstep(0.3, 0.75, m));
	// The textures are soft and dim: most of the shape is low values.
	ALPHA = smoothstep(0.02, 0.3, m) * color.a * fade;
}
