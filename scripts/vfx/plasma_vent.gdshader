// Pistol cannon venting (PlasmaVent): drawn over the cannon as its
// material_overlay while it cools. `heat` 1 = just overheated: white-hot
// orange, with bands of energy crawling back down the barrel and a bright
// rim; cools to the plasma's cyan and fades. `flash`: the cyan-white flare
// as it comes back ready.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 color : source_color = vec4(0.2, 0.85, 1.0, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.5, 0.15, 1.0);
uniform float heat = 0.0;
uniform float flash = 0.0;

varying float vx;

void vertex() {
	vx = VERTEX.x;
}

void fragment() {
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float bands = smoothstep(0.55, 1.0, sin(vx * 34.0 + TIME * 16.0) * 0.5 + 0.5);
	vec3 c = mix(color.rgb, hot.rgb, smoothstep(0.35, 0.9, heat));
	c = mix(c, vec3(1.0), heat * heat * 0.45);
	float k = heat * (0.3 + rim * 0.9 + bands * 0.55);
	ALBEDO = c * k + mix(color.rgb, vec3(1.0), 0.5) * flash * (0.5 + rim);
}
