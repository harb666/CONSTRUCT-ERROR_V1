// image-to-level Stage 4: liquid flowing down a fall / along a pipe (UNTESTED in Godot here).
// uv_speed = flow speed (m/s) / material tile size (m); flow_dir = effects.json "flow_uv" (measured flow direction in
// the mesh's UV space - the texture moves along it, so falls and pipes flow the right way whatever their UV layout).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;  // open liquid sheets (terrain waterfalls) show both sides

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float uv_speed = 0.25;
uniform vec2 flow_dir = vec2(0.0, 1.0);
uniform float wobble = 0.02;
uniform float glow_energy = 1.2;
uniform vec3 glow_tint : source_color = vec3(1.0);

void fragment() {
	vec2 uv = UV;
	vec2 side = vec2(-flow_dir.y, flow_dir.x);
	uv += side * sin(dot(uv, flow_dir) * 9.0 + TIME * 3.0) * wobble;
	uv -= flow_dir * TIME * uv_speed;
	vec3 col = texture(albedo_tex, uv).rgb;
	ALBEDO = col;
	ROUGHNESS = 0.1;
	EMISSION = col * glow_tint * glow_energy;
}
