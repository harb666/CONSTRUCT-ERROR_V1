shader_type spatial;
// Ice over a model (material_overlay on its meshes, so skinned / posed
// bodies work as they are): the surface grown out along its normals by
// `thickness` (an ice shell in the body's own shape - a frozen sculpture),
// glassy pale blue with a white fresnel rim, faceted shading, white
// cracks and sparkling glints. `frost` 0 = clear thick ice, 1 = a white
// powdery frost layer (the boss); `amount` grows it in / out; `melt`
// turns it wet and see-through as it melts.
render_mode blend_mix, depth_draw_never, cull_back, specular_schlick_ggx;

uniform float thickness = 0.04;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float frost : hint_range(0.0, 1.0) = 0.0;
uniform float melt : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ice_color : source_color = vec4(0.62, 0.86, 1.0, 1.0);
uniform vec4 deep_color : source_color = vec4(0.25, 0.55, 0.9, 1.0);
uniform float scale = 6.0;
uniform float seed = 0.0;

varying vec3 obj_pos;

float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
void vertex() {
	// Lumpy growth (thicker in places, like ice built up) - a shell in the
	// body's shape.
	float lump = 0.75 + 0.5 * noise3(VERTEX * scale * 0.6 + seed);
	VERTEX += NORMAL * thickness * amount * lump * (1.0 - 0.6 * melt);
	obj_pos = VERTEX;
}

void fragment() {
	vec3 p = obj_pos * scale;
	float n = noise3(p * 1.7);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	// Faceted look: the normal bent by blocky noise.
	vec3 facet = vec3(noise3(floor(p * 1.3)) - 0.5, noise3(floor(p * 1.3) + 9.0) - 0.5, noise3(floor(p * 1.3) + 21.0) - 0.5);
	NORMAL = normalize(NORMAL + facet * 0.55 * (1.0 - frost));
	// Cracks: thin bright lines where the noise crosses its middle.
	float crack = 1.0 - smoothstep(0.0, 0.035, abs(noise3(p * 0.8 + seed) - 0.5));
	float glint = step(0.985, hash3(floor(p * 9.0))) * (0.6 + 0.4 * sin(TIME * 6.0 + hash3(floor(p * 9.0)) * 30.0));
	vec3 ice = mix(deep_color.rgb, ice_color.rgb, 0.45 + 0.55 * n);
	ice = mix(ice, vec3(1.0), fres * 0.85 + crack * 0.7);
	// Frost: white crystalline powder, settling thickest on surfaces that
	// face up (world up in view space).
	float up = dot(NORMAL, normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz));
	float powder = smoothstep(0.3, 0.6, noise3(p * 2.3 + 4.0) * 0.6 + noise3(p * 7.0) * 0.25 + up * 0.35);
	vec3 frosted = mix(vec3(0.84, 0.93, 1.0), vec3(1.0), powder);
	vec3 col = mix(ice, frosted, frost);
	ALBEDO = col;
	ROUGHNESS = mix(0.08, 0.7, frost) + melt * 0.0;
	METALLIC = 0.0;
	SPECULAR = 0.9;
	EMISSION = (vec3(0.55, 0.85, 1.0) * fres * 0.6 + vec3(1.0) * glint * 2.0 + frosted * 0.3 * frost) * (1.0 - melt * 0.7);
	float a_ice = 0.5 + 0.35 * fres + crack * 0.3;
	float a_frost = mix(0.55, 0.95, powder) + fres * 0.1;
	ALPHA = clamp(mix(a_ice, a_frost, frost), 0.0, 1.0) * smoothstep(0.0, 0.25, amount) * (1.0 - melt);
}
