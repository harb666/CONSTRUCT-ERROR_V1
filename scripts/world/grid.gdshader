shader_type spatial;
// World-space 1m checker so speed and distance are readable without textures.

uniform vec3 color_a : source_color = vec3(0.55, 0.57, 0.6);
uniform vec3 color_b : source_color = vec3(0.47, 0.49, 0.52);
uniform float cell = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 g = floor(world_pos / cell + 0.001);
	float c = mod(g.x + g.y + g.z, 2.0);
	ALBEDO = mix(color_a, color_b, c);
	ROUGHNESS = 0.9;
}
