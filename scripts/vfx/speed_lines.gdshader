// Anime speed lines over the screen while the player power-glides
// (CameraRig): thin streaks radiating from the middle, white with cyan /
// magenta ones (the game's glitch colours), flickering in steps, clear
// round the centre so the action stays readable.
shader_type canvas_item;

// 0..1: how hard (the glide's blend).
uniform float amount = 0.0;
uniform vec4 white : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 cyan : source_color = vec4(0.2, 0.95, 1.0, 1.0);
uniform vec4 magenta : source_color = vec4(1.0, 0.2, 0.85, 1.0);
uniform float lines = 150.0;
uniform vec2 aspect = vec2(1.78, 1.0);

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - 0.5) * aspect;
	float r = length(p);
	float a = atan(p.y, p.x) / 6.2831853 + 0.5;
	float seg = floor(a * lines);
	float step_t = floor(TIME * 22.0);
	float h = hash(seg * 7.13 + step_t * 3.17);
	float on = step(0.7, h);
	float w = fract(a * lines);
	float thin = 1.0 - smoothstep(0.08, 0.3, abs(w - 0.5));
	// Each streak starts at its own distance out, so they read as lines.
	float inner = mix(0.42, 0.7, hash(seg * 1.7 + step_t));
	float mask = smoothstep(inner, inner + 0.22, r);
	float pick = hash(seg * 3.3 + 1.0);
	vec3 c = pick < 0.6 ? white.rgb : (pick < 0.82 ? cyan.rgb : magenta.rgb);
	COLOR = vec4(c, on * thin * mask * amount * 0.8);
}
