// image-to-level Stage 4: animated toxic/glowing liquid surface (UNTESTED in Godot here).
// Applied by apply_effects.gd as a material_override; albedo_tex = the GLB's base colour texture.
// Stage 49: procedural ripples (no textures, no extra meshes): rings running out from pour impacts and from everything
// standing in the liquid (ripple_points: x, z, amplitude, radius), plus random drop ripples popping up across the surface.
// Same maths as the browser preview (pipeline/viewer.html, liquid_surface).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 scroll = vec2(0.03, 0.015);  // UV units per second
uniform float swirl = 0.025;               // UV distortion amplitude
uniform float pulse_speed = 0.25;          // Hz
uniform float pulse_amount = 0.15;
uniform float glow_energy = 1.0;
uniform vec3 glow_tint : source_color = vec3(1.0);
uniform vec4 ripple_points[24];
uniform int ripple_count = 0;
uniform float ripple = 1.0;                // ring brightness
uniform float drops = 1.0;                 // random drop ripples (0 = off)
uniform vec3 ripple_color : source_color = vec3(0.92, 1.0, 0.7);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 hash3(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yxz + 33.33);
	return fract((q.xxy + q.yzz) * q.zyx);
}

vec2 ripples(vec2 p, float t) {  // x = bright crests, y = dark troughs (the pair reads on a bright liquid)
	vec2 s = vec2(0.0);
	for (int i = 0; i < ripple_count; i++) {
		vec4 q = ripple_points[i];
		float d = length(p - q.xy) - q.w;      // from the pour's splash / the object's edge
		if (d < 0.0 || d > 26.0) continue;
		float wv = sin(d * 2.3 - t * (2.2 + 1.6 * q.z));
		float k = q.z * exp(-d * 0.14) * smoothstep(0.0, 0.8, d);
		s += vec2(pow(max(wv, 0.0), 6.0), pow(max(-wv, 0.0), 4.0)) * k;
	}
	if (drops > 0.0) {
		vec2 c = floor(p / 7.0);
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec2 id = c + vec2(float(x), float(y));
				vec3 h = hash3(id);
				vec2 ctr = (id + 0.2 + 0.6 * h.xy) * 7.0;
				float a = fract(t / (2.4 + 3.0 * h.z) + h.x * 7.1);  // 0..1 through this drop's life
				float d = length(p - ctr);
				float r = a * 3.6;
				float f = (1.0 - a) * (1.0 - a) * drops;
				s.x += (smoothstep(0.18, 0.0, abs(d - r)) + 0.6 * smoothstep(0.13, 0.0, abs(d - r * 0.55))) * f;
				s.y += smoothstep(0.22, 0.0, abs(d - r + 0.3)) * f * 0.8;
			}
		}
	}
	return clamp(s, vec2(0.0), vec2(1.5));
}

void fragment() {
	vec2 uv = UV;
	vec2 rr = ripples(wpos.xz, TIME) * ripple;
	float rp = rr.x;
	vec2 w = vec2(sin(uv.y * 6.2831 + TIME * 0.7), cos(uv.x * 6.2831 + TIME * 0.5)) * swirl;
	w += vec2((rr.x - rr.y) * 0.008);           // rings bend the texture a little (refraction-ish)
	vec3 a = texture(albedo_tex, uv + scroll * TIME + w).rgb;
	vec3 b = texture(albedo_tex, uv * 1.37 - scroll * 0.6 * TIME - w).rgb;
	vec3 col = mix(a, b, 0.4) * (1.0 - 0.45 * clamp(rr.y, 0.0, 1.0));
	ALBEDO = col + ripple_color * rp * 0.35;
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	EMISSION = col * glow_tint * glow_energy * (1.0 + pulse_amount * sin(TIME * pulse_speed * 6.2831)) + ripple_color * rp * 0.9;
}
