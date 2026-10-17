shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;
// The turbine fan's wind streaks (ToxicWorks; the package's CPUParticles3D,
// align_y on: each particle's Y axis is its velocity). Drawn as lines along
// the way they travel, turned round that line to face the camera, so the
// gusts read as blowing out of the fan (the package's billboards stood every
// streak upright, like falling rain). Bright head, fading tail, faded in and
// out over each streak's life.

uniform vec4 color : source_color = vec4(0.85, 1.0, 0.8, 0.28);

varying float fade;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 ax = MODEL_MATRIX[1].xyz;
	float al = length(ax);
	ax = al > 1e-5 ? ax / al : vec3(0.0, 1.0, 0.0);
	vec3 side = cross(ax, INV_VIEW_MATRIX[3].xyz - c);
	float sl = length(side);
	side = sl > 1e-4 ? side / sl : INV_VIEW_MATRIX[0].xyz;
	VERTEX = (VIEW_MATRIX * vec4(c + ax * VERTEX.y + side * VERTEX.x, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
	fade = sin(clamp(INSTANCE_CUSTOM.y, 0.0, 1.0) * PI);
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	ALBEDO = color.rgb;
	ALPHA = color.a * fade * (1.0 - UV.y) * smoothstep(0.0, 0.7, across);
}
