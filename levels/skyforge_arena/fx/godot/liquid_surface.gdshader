// image-to-level Stage 4: animated toxic/glowing liquid surface (UNTESTED in Godot here).
// Applied by apply_effects.gd as a material_override; albedo_tex = the GLB's base colour texture.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 scroll = vec2(0.03, 0.015);  // UV units per second
uniform float swirl = 0.025;               // UV distortion amplitude
uniform float pulse_speed = 0.25;          // Hz
uniform float pulse_amount = 0.15;
uniform float glow_energy = 1.0;
uniform vec3 glow_tint : source_color = vec3(1.0);

void fragment() {
	vec2 uv = UV;
	vec2 w = vec2(sin(uv.y * 6.2831 + TIME * 0.7), cos(uv.x * 6.2831 + TIME * 0.5)) * swirl;
	vec3 a = texture(albedo_tex, uv + scroll * TIME + w).rgb;
	vec3 b = texture(albedo_tex, uv * 1.37 - scroll * 0.6 * TIME - w).rgb;
	vec3 col = mix(a, b, 0.4);
	ALBEDO = col;
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	EMISSION = col * glow_tint * glow_energy * (1.0 + pulse_amount * sin(TIME * pulse_speed * 6.2831));
}
