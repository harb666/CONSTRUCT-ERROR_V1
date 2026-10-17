shader_type canvas_item;
// The character select preview during the glitchy menu (MenuGlitch): bands
// slide sideways and the colour splits on the beat. (Its textured <-> wire
// dissolve happens in 3D: WireMesh.)

uniform float glitch : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;
uniform float alpha = 1.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;
	float band = floor(uv.y * 18.0 + hash(vec2(seed, 1.7)) * 2.0);
	if (hash(vec2(band, seed)) < glitch * 0.35) {
		uv.x += (hash(vec2(band, seed + 3.0)) - 0.5) * 0.12 * glitch;
	}
	vec2 split = vec2(0.006 * glitch, 0.0);
	vec4 c = texture(TEXTURE, uv);
	c.r = texture(TEXTURE, uv + split).r;
	c.b = texture(TEXTURE, uv - split).b;
	c.a = max(c.a, max(texture(TEXTURE, uv + split).a, texture(TEXTURE, uv - split).a));
	COLOR = vec4(c.rgb, c.a * alpha);
}
