// Stage 61/62: parts added on a working assembly line (effect "assembly_line"). Every parcel carries the part; the part's
// UVs hold its parcel's number (u shifted by id_step per parcel, starting at id_step). The parcel's centre along the line
// is s0 + i * spacing + offset (offset = the line's current slide, set every frame by apply_effects.gd); the whole part
// shows once that reaches s_arm - the moment the arm lets go of it - and is discarded before. Emissive parts: unshaded.
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float s0 = 0.0;
uniform float spacing = 1.0;
uniform float s_arm = 0.0;
uniform float id_step = 10.0;
uniform float offset = 0.0;
uniform float glow = 1.0;

void fragment() {
	float i = floor((UV.x + id_step * 0.5) / id_step) - 1.0;
	if (s0 + i * spacing + offset < s_arm - 0.001) discard;
	ALBEDO = texture(albedo_tex, UV).rgb * tint.rgb * glow;
}
