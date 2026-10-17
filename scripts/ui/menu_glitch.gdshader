shader_type canvas_item;
// The glitchy main menu (owner asked; ideas from the owner's glitch-video
// repo): everything already on screen - the arena behind the menu, the
// panels, buttons and cards - merges in and out of neon vector line art.
// `wire` is how much of the screen is lines (a ragged dissolve front rising
// from the bottom with a glowing edge, quantised in blocks like the video's
// face dissolve); `glitch` drives the video's line glitches (band shifts,
// drop-outs, segments thrown loose) and an RGB split with magenta / green
// ghosts. The menu text is drawn crisp on top of this (MenuGlitch), so it
// stays readable. Lines: an edge pass on the picture, tinted with each
// source's own hue brightened to neon (like the video's `neon()`).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float wire : hint_range(0.0, 1.0) = 0.0;
uniform float glitch : hint_range(0.0, 1.0) = 0.0;
// Changes on every 8th note: a new pattern of bands / drop-outs.
uniform float seed = 0.0;
uniform float front_w = 0.07;
// A screen-UV rect left out of the line pass (the character preview, which
// dissolves into its own real wire mesh).
uniform vec4 keep_rect = vec4(0.0);
// Line thickness in screen pixels (the phone draws at 2x).
uniform float line_px = 1.5;
uniform float gain = 5.0;
uniform vec3 bg = vec3(0.03, 0.008, 0.06);
uniform vec3 front_a : source_color = vec3(1.0, 0.25, 0.85);
uniform vec3 front_b : source_color = vec3(0.3, 0.95, 1.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Edge strength (Sobel on brightness) at `uv`, and the brightest colour
// round it (the line's hue).
float edges(vec2 uv, vec2 px, out vec3 hue) {
	vec3 c00 = texture(screen_tex, uv + px * vec2(-1.0, -1.0)).rgb;
	vec3 c10 = texture(screen_tex, uv + px * vec2(0.0, -1.0)).rgb;
	vec3 c20 = texture(screen_tex, uv + px * vec2(1.0, -1.0)).rgb;
	vec3 c01 = texture(screen_tex, uv + px * vec2(-1.0, 0.0)).rgb;
	vec3 c21 = texture(screen_tex, uv + px * vec2(1.0, 0.0)).rgb;
	vec3 c02 = texture(screen_tex, uv + px * vec2(-1.0, 1.0)).rgb;
	vec3 c12 = texture(screen_tex, uv + px * vec2(0.0, 1.0)).rgb;
	vec3 c22 = texture(screen_tex, uv + px * vec2(1.0, 1.0)).rgb;
	float l00 = lum(c00), l10 = lum(c10), l20 = lum(c20), l01 = lum(c01);
	float l21 = lum(c21), l02 = lum(c02), l12 = lum(c12), l22 = lum(c22);
	float gx = (l20 + 2.0 * l21 + l22) - (l00 + 2.0 * l01 + l02);
	float gy = (l02 + 2.0 * l12 + l22) - (l00 + 2.0 * l10 + l20);
	hue = max(max(max(c00, c20), max(c02, c22)), max(max(c10, c12), max(c01, c21)));
	return sqrt(gx * gx + gy * gy);
}

// A dark colour brightened to a neon line colour, keeping its hue; greys
// become pale lilac / white (the video's `neon()`).
vec3 neon(vec3 c) {
	float mx = max(max(c.r, c.g), max(c.b, 0.001));
	float sat = mx - min(min(c.r, c.g), c.b);
	if (sat < 0.06) {
		float v = 0.6 + 0.4 * min(1.0, mx * 2.0);
		return vec3(0.82, 0.78, 1.0) * v;
	}
	return clamp(0.24 + 0.85 * pow(c / mx, vec3(1.4)), 0.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	// Band shifts: horizontal slices of the screen slide sideways.
	float bands = 26.0;
	float band = floor(uv.y * bands + hash(vec2(seed, 3.1)) * 3.0);
	float bh = hash(vec2(band, seed));
	if (bh < glitch * 0.3) {
		uv.x += (hash(vec2(band, seed + 7.0)) - 0.5) * 0.09 * glitch;
	}
	bool keep = uv.x > keep_rect.x && uv.y > keep_rect.y && uv.x < keep_rect.z && uv.y < keep_rect.w;
	// RGB split on the picture.
	vec2 split = vec2(0.004 * glitch, 0.0);
	vec3 col = vec3(texture(screen_tex, uv + split).r, texture(screen_tex, uv).g, texture(screen_tex, uv - split).b);
	// Dissolve key: rising from the bottom with a ragged, blocky edge.
	vec2 cell = floor(uv * res / 22.0);
	float key = (1.0 - uv.y) * 0.62 + hash(cell + floor(seed * 0.125)) * 0.38;
	// wire 0: no lines; 1: all lines; the front band runs just ahead.
	float w2 = wire * (1.0 + front_w);
	float lines_on = keep ? 0.0 : step(key, w2 - front_w);
	float front = keep ? 0.0 : (step(key, w2) - lines_on) * step(0.001, wire);
	vec3 outc = col;
	if (lines_on > 0.0 || front > 0.0) {
		vec2 px = SCREEN_PIXEL_SIZE * line_px;
		vec3 hue;
		float e = edges(uv, px, hue);
		float l = smoothstep(0.03, 0.16, e * gain / 5.0);
		// Drop-outs: whole blocks of line art blink out, and some
		// segments are thrown loose (shifted a little).
		vec2 blk = floor(uv * res / 48.0);
		float drop = step(hash(blk + seed * 1.7), 0.14 * glitch);
		l *= 1.0 - drop;
		vec3 lines = bg + neon(hue) * l * 1.35;
		if (glitch > 0.35) {
			// Magenta / green ghost copies of the line art.
			vec3 h2;
			float off = 0.006 + 0.01 * glitch;
			float em = edges(uv + vec2(off, 0.0), px, h2);
			float eg = edges(uv - vec2(off, 0.0), px, h2);
			lines += vec3(1.0, 0.2, 0.85) * smoothstep(0.03, 0.16, em * gain / 5.0) * 0.45 * glitch;
			lines += vec3(0.2, 1.0, 0.45) * smoothstep(0.03, 0.16, eg * gain / 5.0) * 0.35 * glitch;
		}
		outc = mix(outc, lines, lines_on);
		// The glowing front where the picture turns into lines.
		vec3 fc = mix(front_a, front_b, hash(cell * 1.3 + seed));
		outc = mix(outc, outc * 0.35 + fc * (0.7 + 0.6 * l), front * 0.85);
	}
	COLOR = vec4(outc, 1.0);
}
