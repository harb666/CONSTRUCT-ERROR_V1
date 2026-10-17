// The character preview's textured <-> wire dissolve (shared by
// wire_line / wire_hide): 0 at the feet, 1 at the top, with blocky noise
// (screen-pixel cells, a new pattern every 4 8th notes) for a ragged edge.
uniform float wire = 0.0;
uniform float seed = 0.0;
uniform float front_w = 0.08;
uniform float y0 = 0.0;
uniform float y1 = 2.0;
uniform float cell_px = 14.0;

float dhash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float dissolve_key(float y, vec2 frag) {
	float h = clamp((y - y0) / max(y1 - y0, 0.001), 0.0, 1.0);
	return h * 0.65 + dhash(floor(frag / cell_px) + floor(seed * 0.25)) * 0.35;
}
