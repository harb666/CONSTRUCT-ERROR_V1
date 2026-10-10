shader_type spatial;
// The owner's purple portal (Purple_Portal.mp4), baked by tools/bake_portal.py
// into an 8 x 8 atlas of grey (brightness) + alpha (matte / glow) cells;
// colour comes back from the ramp measured from the video. Two cells are
// blended (frame blending / cross-fades).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2D ramp : source_color, filter_linear, repeat_disable;
uniform float cell_a = 0.0;
uniform float cell_b = 0.0;
uniform float mix_b = 0.0;
uniform float alpha = 1.0;

vec4 cell(float c, vec2 uv) {
	vec2 o = vec2(mod(c, 8.0), floor(c / 8.0));
	// Stay half a texel inside the cell so neighbours don't bleed in.
	uv = clamp(uv, vec2(0.5 / 128.0), vec2(1.0 - 0.5 / 128.0));
	return texture(atlas, (o + uv) / 8.0);
}

void fragment() {
	vec4 s = mix(cell(cell_a, UV), cell(cell_b, UV), mix_b);
	ALBEDO = texture(ramp, vec2(s.r, 0.5)).rgb;
	// Round off the cell's corners (no square haze).
	float r = length(UV * 2.0 - 1.0);
	ALPHA = s.a * alpha * (1.0 - smoothstep(0.88, 1.0, r));
}
