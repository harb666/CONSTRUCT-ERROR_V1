shader_type spatial;
// Harbinger's halo arcs: thin electric arcs crackling across a flat band
// around the ring, over a soft blue haze. Blended (not added) so it still
// shows over the bright arena. No textures.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.15, 0.55, 1.0, 1.0);
uniform float intensity = 1.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }
float noise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), f);
}

void fragment() {
	float a = UV.x;              // 0..1 around the ring
	float r = UV.y * 2.0 - 1.0;  // -1..1 across the band, 0 on the ring
	float t = TIME;
	float haze = exp(-abs(r) * 5.0) * (0.35 + 0.1 * noise(t * 18.0));
	float arc = 0.0;
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		// A jagged line wandering across the band...
		float off = (noise(a * 52.0 + t * (8.0 + fk * 4.0) + fk * 17.0) - 0.5) * 1.5;
		float line = smoothstep(0.12, 0.0, abs(r - off));
		// ...shown only along some stretches of the ring, which move.
		float gate = smoothstep(0.5, 0.8, noise(a * 10.0 - t * (3.0 + fk) + fk * 31.0));
		arc = max(arc, line * gate);
	}
	ALBEDO = mix(color.rgb, vec3(0.85, 0.95, 1.0), arc);
	ALPHA = clamp((haze + arc) * intensity, 0.0, 1.0);
}
