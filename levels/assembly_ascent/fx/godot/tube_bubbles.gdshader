// Stage 48: bubbles rising up the see-through vat / column tubes (effect "tube_bubbles").
// One mesh for every bubble of the level: 4 vertices per bubble, all at the tube's bottom centre (VERTEX),
// UV = quad corner (-1..1), COLOR = random seed, UV2 = (tube height, tube radius). The vertex shader moves
// each bubble up its tube and turns the quad to the camera; the fragment shader draws a glassy bubble.
// Same maths as the browser preview (pipeline/viewer.html, category "bubbles").
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec2 size_range = vec2(0.07, 0.34);
uniform vec2 speed_range = vec2(0.9, 2.4);
uniform float wobble = 0.14;
uniform float nozzles = 0.7; // share of bubbles that stream from the 7 nozzles (the rest start anywhere on the floor)
uniform vec4 tint : source_color = vec4(0.82, 1.0, 0.7, 1.0);
uniform float alpha = 0.85;

varying vec2 q;
varying float fade;

void vertex() {
	vec4 s = COLOR;
	float h = UV2.x;
	float r = UV2.y;
	float spd = mix(speed_range.x, speed_range.y, s.x);
	float k = fract(TIME * spd / h + s.y);           // 0 at the nozzle, 1 at the top
	float y = h * pow(k, 1.3);                        // speeds up as it rises
	float ang; float rad;
	if (s.w < nozzles) {
		float n = floor(s.z * 7.0);
		ang = n * 1.0472;
		rad = n > 5.5 ? 0.0 : 0.44 * r;
	} else {
		ang = s.z * 6.2832;
		rad = sqrt(fract(s.w * 7.13)) * 0.78 * r;
	}
	float wob = wobble * (0.25 + k) * min(1.0, r * 0.5);
	vec3 off = vec3(cos(ang) * rad + sin(TIME * (2.0 + 3.0 * s.x) + s.y * 40.0) * wob, y,
	                sin(ang) * rad + cos(TIME * (1.7 + 2.0 * s.z) + s.w * 30.0) * wob);
	float sz = mix(size_range.x, size_range.y, pow(fract(s.x * 13.7 + s.w), 2.0)) * (0.7 + 0.5 * k);
	fade = smoothstep(0.0, 0.05, k) * (1.0 - smoothstep(0.92, 1.0, k));
	q = UV;
	vec4 mv = MODELVIEW_MATRIX * vec4(VERTEX + off, 1.0);
	mv.xy += UV * sz;
	POSITION = PROJECTION_MATRIX * mv;
}

void fragment() {
	float d = length(q);
	if (d > 1.0) discard;
	float rim = smoothstep(0.6, 0.92, d) * (1.0 - smoothstep(0.92, 1.0, d));
	float hl = 1.0 - smoothstep(0.0, 0.3, length(q - vec2(-0.36, 0.38)));
	float hl2 = 1.0 - smoothstep(0.0, 0.13, length(q - vec2(0.38, -0.32)));
	ALBEDO = mix(tint.rgb, vec3(1.0), clamp(hl + 0.6 * hl2, 0.0, 1.0));
	ALPHA = clamp(0.08 + rim * 0.85 + hl * 0.9 + hl2 * 0.55, 0.0, 1.0) * fade * alpha;
}
