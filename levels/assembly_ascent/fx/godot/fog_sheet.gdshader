// image-to-level Stage 4: low drifting mist sheet (UNTESTED in Godot here).
// Mobile-safe stand-in for volumetric fog (FogVolume needs the Forward+ renderer). Procedural noise, no texture.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(0.55, 0.9, 0.3);
uniform float opacity = 0.35;
uniform vec2 scroll = vec2(0.02, 0.01);
uniform float scale = 0.08;   // noise cells per metre

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = wp.xz * scale;
	float n = vnoise(p + scroll * TIME * 10.0) * 0.6 + vnoise(p * 2.3 - scroll * 17.0 * TIME) * 0.4;
	ALBEDO = color;
	float e = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));  // soft border: no visible rectangle edge
	ALPHA = opacity * smoothstep(0.25, 0.85, n) * smoothstep(0.0, 0.15, e);
}
