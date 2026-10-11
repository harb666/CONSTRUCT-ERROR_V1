shader_type spatial;
// The light column over the hub lift once it has arrived (ElevatorLift):
// an open cylinder of hot-pink light, brightest at the base and fading up,
// with bands of light rising up it, so the lift can be seen from anywhere
// on the level. `height` = the cylinder's height (centred on its origin).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.25, 0.55, 1.0);
uniform float strength = 1.0;
uniform float height = 34.0;

varying float up;

void vertex() {
	up = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);  // 0 at the base
}

void fragment() {
	float fade = pow(1.0 - up, 1.6);
	float bands = 0.6 + 0.4 * smoothstep(0.55, 1.0, fract(up * 9.0 - TIME * 0.8));
	// Soft edges seen side-on (the cylinder's silhouette fades out).
	float rim = clamp(abs(dot(NORMAL, VIEW)) * 1.4, 0.0, 1.0);
	ALBEDO = color.rgb * fade * bands * rim * strength * 0.7;
}
