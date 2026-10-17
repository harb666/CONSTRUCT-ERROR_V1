shader_type spatial;
// PlasmaTrail ribbon (the Neon Sentinel's booster; Halo-sentinel style),
// shaped on the GPU like SmokeTrail: one fixed mesh shared by every trail,
// vertices carry (point index, column -1 / 0 / +1) in UV and the trail's
// points come in as uniforms each frame (no graphics buffers rebuilt per
// frame). Additive: a white-hot core thread inside a neon glow that cools
// from lime-yellow to magenta down the trail, pinched at the booster,
// swelling then thinning out, with energy pulses racing back along it.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 pts[48];
uniform int count = 0;
uniform float lifetime = 0.85;
uniform float head_width = 0.1;
uniform float max_width = 0.42;
uniform float intensity = 1.0;
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 0.86, 1.0);
uniform vec4 glow_color : source_color = vec4(0.62, 1.0, 0.12, 1.0);
uniform vec4 tail_color : source_color = vec4(1.0, 0.1, 0.55, 1.0);

varying float across;
varying float k;
varying float along;

void vertex() {
	int i = int(UV.x + 0.5);
	float c = UV.y;
	across = c;
	if (count < 2) {
		VERTEX = vec3(0.0);
		k = 1.0;
		along = 0.0;
	} else if (i >= count) {
		// Unused: parked on the last point (a degenerate strip, never a
		// sliver stretched off to the world origin).
		VERTEX = pts[count - 1].xyz;
		k = 1.0;
		along = 0.0;
	} else {
		vec3 p = pts[i].xyz;
		float age = pts[i].w;
		vec3 tang = pts[min(i + 1, count - 1)].xyz - pts[max(i - 1, 0)].xyz;
		if (dot(tang, tang) < 1e-6) {
			tang = vec3(0.0, 0.0, 1.0);
		}
		vec3 side = normalize(cross(tang, CAMERA_POSITION_WORLD - p));
		k = clamp(age / lifetime, 0.0, 1.0);
		float swell = smoothstep(0.0, 0.18, k) * (1.0 - k * 0.55);
		float w = mix(head_width, max_width, swell);
		along = float(count - 1 - i);
		VERTEX = p + side * w * c;
	}
}

void fragment() {
	float x = abs(across);
	float core = exp(-x * x * 30.0);
	float glow = exp(-x * x * 3.2) * (1.0 - smoothstep(0.75, 1.0, x));
	float pulse = 0.75 + 0.25 * sin(along * 1.3 - TIME * 38.0);
	float flicker = 0.88 + 0.12 * sin(TIME * 61.0 + along * 0.7);
	float fade = pow(1.0 - k, 1.4);
	vec3 neon = mix(glow_color.rgb, tail_color.rgb, smoothstep(0.15, 0.85, k));
	vec3 col = core_color.rgb * core * 2.2 * (1.0 - k * 0.8) + neon * glow * 1.25 * pulse;
	ALBEDO = col * fade * flicker * intensity;
}
