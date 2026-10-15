// image-to-level Stage 26: TV static on screens (UNTESTED in Godot here).
// Applied by apply_effects.gd as a material_override on every mesh whose material is the effect's target_material;
// albedo_tex = the GLB's base colour texture (the screen picture). Snow cells change fps times a second, a dark bar
// rolls down, and every signal_every seconds the picture breaks through for signal_len seconds.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float amount = 0.85;        // share of static over the picture (0 = clean picture, 1 = only snow)
uniform float grain = 120.0;        // snow cells per UV unit (vertical); x gets 3x (atlas halves are half as wide)
uniform float fps = 18.0;
uniform float signal_every = 6.0;   // seconds
uniform float signal_len = 1.4;     // seconds the picture comes through
uniform float roll_speed = 0.25;    // rolling bar, screens per second
uniform float glow = 1.0;
uniform float seed = 0.0;
// Stage 52: screens carry an id as a whole-number u shift of their UVs (same texels - the texture repeats). id > 0:
// own signal timing, roll speed, tint and quick brightness flickers. egg_id: that screen now and then shows the
// atlas cell egg_rect (x, y, w, h in UV) - the easter egg - for egg_len seconds every egg_every seconds.
uniform float egg_id = -1.0;
uniform vec4 egg_rect = vec4(0.5, 0.5, 0.5, 0.5);
uniform float egg_every = 45.0;
uniform float egg_len = 3.5;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	float id = floor(UV.x);
	float on = step(0.5, id);
	float hid = hash(vec2(id, 3.7)) * on;
	vec2 luv = vec2(UV.x - id, UV.y);
	float sd = seed + id * 7.31;
	float ev = signal_every * mix(1.0, 0.55 + 0.9 * hash(vec2(id, 1.3)), on);
	float sl = signal_len * mix(1.0, 0.7 + 0.6 * hash(vec2(id, 5.1)), on);
	float egg = 0.0;
	if (abs(id - egg_id) < 0.5) {
		float e = mod(TIME + 11.0, egg_every);
		egg = smoothstep(0.0, 0.3, e) * (1.0 - smoothstep(egg_len - 0.3, egg_len, e));
	}
	vec3 tint = mix(vec3(1.0), vec3(0.8 + 0.4 * hash(vec2(id, 9.0)), 0.8 + 0.4 * hash(vec2(id, 11.0)), 0.8 + 0.4 * hash(vec2(id, 13.0))), 0.5 * on);
	vec3 pic = texture(albedo_tex, UV).rgb * mix(tint, vec3(1.0), egg);
	if (egg > 0.0) pic = mix(pic, texture(albedo_tex, egg_rect.xy + fract(luv * 2.0) * egg_rect.zw).rgb, egg);
	float f = mod(floor(TIME * fps), 997.0);  // bounded: sin() hash stays precise on mobile GPUs
	vec2 cell = floor(UV * vec2(grain * 3.0, grain));
	float n = hash(cell + vec2(f * 13.1, f * 7.7) + sd);
	float line = 0.75 + 0.25 * hash(vec2(cell.y, f + sd));  // horizontal line jitter
	float ph = mod(TIME + sd * 1.7, ev);
	float sig = max(smoothstep(0.0, 0.25, ph) * (1.0 - smoothstep(sl - 0.25, sl, ph)), egg * 1.1);
	float m = amount * (1.0 - 0.8 * min(sig, 1.0));
	float bar = smoothstep(0.0, 0.08, abs(fract(luv.y + TIME * roll_speed * mix(1.0, 0.6 + 0.8 * hid, on)) - 0.5));
	float fk = on * step(0.965, hash(vec2(floor(TIME * (6.0 + 6.0 * hid)), id)));  // quick dips, each screen at its own moments
	vec3 col = mix(pic, vec3(n * line), m) * mix(0.65, 1.0, bar) * (1.0 - 0.45 * fk);
	ALBEDO = col * glow;
}
