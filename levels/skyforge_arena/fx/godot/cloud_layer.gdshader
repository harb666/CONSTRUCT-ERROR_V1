// image-to-level: soft layered cloud deck (UNTESTED in Godot here - starting point).
// One transparent disc per layer: fbm coverage, radial edge fade (no visible plane edge), forward-scattering glow
// towards the sun, soft intersections with geometry (depth fade) and a fade when the camera is inside the layer.
// Mobile-safe: no raymarching, 4 noise octaves, one draw call per layer. Godot's own fog is applied on top.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.86, 0.76);
uniform vec3 shade : source_color = vec3(0.62, 0.5, 0.56);
uniform vec3 glow : source_color = vec3(1.0, 0.62, 0.35);
uniform float opacity = 0.6;
uniform float coverage = 0.45;
uniform float scale = 0.012;        // noise cells per metre
uniform vec2 scroll = vec2(0.004, 0.0015);
uniform vec2 center = vec2(0.0);    // world xz of the disc centre
uniform float radius = 600.0;
uniform float inner = 0.55;         // fraction of the radius where the edge fade starts
uniform float seed = 0.0;
uniform vec3 sun_dir = vec3(0.0, 0.2, -1.0);   // direction TO the sun
uniform float soft_distance = 6.0;  // depth fade where the layer cuts through columns / rocks
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1.0, 0.0)), f.x), mix(h(i + vec2(0.0, 1.0)), h(i + vec2(1.0, 1.0)), f.x), f.y); }
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++) { v += a * n(p); p = p * 2.03 + vec2(17.1, 9.2); a *= 0.5; } return v; }

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 q = wp.xz * scale + seed;
	float n1 = fbm(q + scroll * TIME); float n2 = fbm(q * 2.6 - scroll * TIME * 1.6 + 3.1);
	float cov = smoothstep(coverage - 0.16, coverage + 0.2, n1 * 0.72 + n2 * 0.28);
	float edge = 1.0 - smoothstep(inner, 1.0, length(wp.xz - center) / radius);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float fw = pow(max(dot(normalize(wp - cam), normalize(sun_dir)), 0.0), 6.0);
	ALBEDO = mix(shade, color, smoothstep(0.25, 0.85, n2 * 0.6 + n1 * 0.4)) + glow * fw * 0.55;
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0); vp.xyz /= vp.w;
	float soft = clamp((VERTEX.z - vp.z) / soft_distance, 0.0, 1.0);
	ALPHA = opacity * cov * edge * soft * smoothstep(2.0, 14.0, abs(cam.y - wp.y));
}
