shader_type spatial;
// Gravitational-lens style distortion: a camera-facing disc that re-samples
// the screen behind it, twisted and pulled around its centre.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float strength = 0.55;   // radial pull
uniform float swirl = 2.2;       // twist (radians) at the centre
uniform float spin_speed = 1.3;  // twist animation
uniform vec4 tint : source_color = vec4(0.55, 0.2, 0.85, 1.0);
uniform float tint_amount = 0.12;

void vertex() {
	// Billboard, keeping the node's scale.
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sc.x, INV_VIEW_MATRIX[1] * sc.y, INV_VIEW_MATRIX[2] * sc.z, MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	// Map quad space -> screen UV (handles aspect and axis flips).
	mat2 js = mat2(dFdx(SCREEN_UV), dFdy(SCREEN_UV));
	mat2 jp = mat2(dFdx(p), dFdy(p));
	mat2 a = js * inverse(jp);
	vec2 center = SCREEN_UV - a * p;

	float fall = 1.0 - smoothstep(0.0, 1.0, r);
	fall *= fall;
	float ang = (swirl + TIME * spin_speed) * fall;
	float c = cos(ang);
	float s = sin(ang);
	vec2 q = mat2(vec2(c, s), vec2(-s, c)) * p * (1.0 + strength * fall);
	vec3 col = texture(screen_tex, center + a * q).rgb;
	ALBEDO = mix(col, tint.rgb, tint_amount * fall);
	ALPHA = 1.0 - smoothstep(0.8, 1.0, r);
}
