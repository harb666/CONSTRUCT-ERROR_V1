shader_type spatial;
// Machine gun's translucent conduits (orb -> barrel): the supplied yellow
// glass look plus plasma flowing towards the barrel (+X in model space).
// Driven by the gun's one shared `energy` (0..1); `flow_phase` is advanced on
// the CPU so the speed can change smoothly.
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D emission_tex : source_color, hint_default_black, filter_linear_mipmap;
uniform float base_alpha = 0.58;
uniform float base_emission = 0.66;
uniform float energy = 0.0;
uniform float strength = 1.0;
uniform float flow_phase = 0.0;
uniform float overload = 0.0;
uniform vec3 plasma_yellow : source_color = vec3(1.0, 0.84, 0.1);
uniform vec3 plasma_hot : source_color = vec3(1.0, 0.22, 0.04);
uniform float start_x = 0.31;
uniform float end_x = 0.77;

varying vec3 p;

void vertex() {
	p = VERTEX;
}

float hash(vec2 v) {
	return fract(sin(dot(v, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 v) {
	vec2 i = floor(v);
	vec2 f = fract(v);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	// Dimmer glass than supplied, so the plasma inside reads against it.
	ALBEDO = a.rgb * 0.45;
	ROUGHNESS = 0.3;
	float u = clamp((p.x - start_x) / (end_x - start_x), 0.0, 1.0);
	// Plasma packets travelling from the orb end towards the barrel.
	float x = p.x * 26.0 - flow_phase;
	float packet = pow(0.5 + 0.5 * sin(x), 5.0);
	float fine = pow(0.5 + 0.5 * sin(x * 2.7 + 1.3), 8.0);
	float turb = noise(vec2(p.x * 70.0 - flow_phase * 2.6, (p.y + p.z) * 90.0 + flow_phase * 0.4));
	float flow = packet + 0.6 * fine * energy;
	flow *= mix(1.0, 0.35 + 1.4 * turb, 0.2 + 0.6 * energy);
	// Overloaded: unstable dropouts and surges.
	float drop = step(0.68, noise(vec2(flow_phase * 3.0, p.x * 9.0)));
	flow *= 1.0 - overload * 0.7 * drop;
	flow += overload * 0.9 * step(0.8, noise(vec2(flow_phase * 5.0 + 3.0, p.x * 14.0)));
	float level = (1.0 + 1.1 * energy) * strength;
	// Packet centres yellow-white, edges and the stream between them hot
	// orange/red; hotter towards the barrel and with energy.
	vec3 core = mix(plasma_yellow, vec3(1.0, 0.97, 0.75), clamp(packet * energy, 0.0, 1.0));
	vec3 edge = mix(plasma_yellow, vec3(1.0, 0.5, 0.06), clamp(0.15 + 0.8 * energy + 0.2 * u, 0.0, 1.0));
	edge = mix(edge, plasma_hot, clamp((energy - 0.45) * 1.2 + 0.25 * u * energy + overload * 0.5, 0.0, 1.0));
	vec3 col = mix(edge, core, smoothstep(0.35, 0.9, packet));
	float stream = 0.12 + 0.25 * energy;
	EMISSION = texture(emission_tex, UV).rgb * base_emission * 0.3 + col * (flow * 1.1 + stream) * level;
	ALPHA = clamp(base_alpha + 0.25 * flow * (0.4 + energy), 0.0, 0.88);
}
