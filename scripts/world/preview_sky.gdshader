// Skyforge Arena: the sky panorama mapped exactly as the image-to-level
// preview (three.js equirectUv: u = atan2(z, x) / 2pi + 0.5, v up), so the
// sun, planet and skyline sit where they do in the map maker.
shader_type sky;

uniform sampler2D panorama : source_color, filter_linear, repeat_enable;

void sky() {
	vec3 d = normalize(EYEDIR);
	float u = atan(d.z, d.x) * 0.15915494 + 0.5;
	float v = asin(clamp(d.y, -1.0, 1.0)) * 0.31830989 + 0.5;
	COLOR = texture(panorama, vec2(u, 1.0 - v)).rgb;
}
