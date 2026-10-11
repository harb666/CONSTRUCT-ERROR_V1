shader_type spatial;
// Top of the hub elevator lift (ElevatorLift), in the level's style: dark
// purple metal plates with black grooves (rings and spokes), a band of
// hot-pink / black hazard chevrons round the edge, glowing pink light
// strips and a lit target emblem in the middle. `power` 0 -> 1 lights it
// up as it arrives; `alert` flashes the strips (counting down to go).
// Lies flat (a quad in its XZ plane, UV 0..1 across the disc).

uniform vec4 metal : source_color = vec4(0.17, 0.12, 0.18, 1.0);
uniform vec4 metal_dark : source_color = vec4(0.1, 0.07, 0.11, 1.0);
uniform vec4 groove : source_color = vec4(0.02, 0.015, 0.03, 1.0);
uniform vec4 neon : source_color = vec4(1.0, 0.2, 0.5, 1.0);
uniform float power = 0.0;
uniform float alert = 0.0;

float band(float x, float c, float w, float aa) {
	return 1.0 - smoothstep(w - aa, w + aa, abs(x - c));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x);
	float aa = fwidth(r) * 1.2;
	vec3 col = metal.rgb;
	// Plates: alternate shades by ring and sector.
	float ring = floor(r * 4.0);
	float sector = floor((a / 6.2831853 + 0.5) * 12.0);
	col = mix(col, metal_dark.rgb, 0.5 * mod(ring + sector, 2.0) * step(0.25, r) * step(r, 0.86));
	// Grooves: rings and spokes.
	float g = band(r, 0.25, 0.008, aa) + band(r, 0.5, 0.008, aa) + band(r, 0.68, 0.008, aa) + band(r, 0.86, 0.01, aa);
	float spoke = abs(fract((a / 6.2831853 + 0.5) * 12.0) - 0.5) / 12.0 * 6.2831853 * r;
	g += (1.0 - smoothstep(0.006, 0.006 + aa, spoke)) * step(0.25, r) * step(r, 0.86);
	col = mix(col, groove.rgb, clamp(g, 0.0, 1.0));
	// Hazard chevrons round the edge.
	float edge = step(0.88, r) * step(r, 0.97);
	float chev = step(0.5, fract((a / 6.2831853) * 36.0 + (r - 0.88) * 9.0));
	col = mix(col, mix(vec3(0.02), neon.rgb * 0.75, chev), edge);
	// Light strips (glow once powered) and the centre arrow.
	float strip = band(r, 0.68, 0.012, aa) + band(r, 0.975, 0.012, aa);
	// Centre emblem: a lit disc in a ring, three ticks pointing in.
	float arrow = 1.0 - smoothstep(0.09 - aa, 0.09 + aa, r);
	arrow += band(r, 0.17, 0.014, aa);
	float tick = abs(fract((a / 6.2831853) * 3.0 + 0.25) - 0.5);
	arrow += step(tick, 0.035) * step(0.2, r) * step(r, 0.24);
	arrow = clamp(arrow, 0.0, 1.0);
	float blink = 0.55 + 0.45 * sin(TIME * 18.0);
	float lit = power * mix(1.0, blink, alert);
	vec3 glow = neon.rgb * (clamp(strip, 0.0, 1.0) * (0.25 + 1.6 * lit) + arrow * (0.15 + 1.4 * lit));
	col = mix(col, neon.rgb * 0.4, clamp(arrow, 0.0, 1.0) * 0.6);
	ALBEDO = col;
	METALLIC = 0.6 * (1.0 - edge);
	ROUGHNESS = 0.45;
	EMISSION = glow;
}
