shader_type spatial;
// Puffy cartoon smoke / fireball ball: a sphere pushed out into a cloud by
// 3D Voronoi cells, then eaten away by the same cells as `progress` goes
// 0 -> 1 (alpha scissor: opaque pass, no sorting, cheap on phones).
// `heat` 1 = white-hot fire, 0 = smoke (lit by the scene).
// Based on GDQuest's "3D smoke explosion" (godot-4-vfx-assets, MIT,
// Copyright (c) 2023-present GDQuest); Voronoi by Inigo Quilez (MIT, 2013,
// https://www.shadertoy.com/view/ldl3Dl).
render_mode shadows_disabled, cull_back;

uniform vec3 smoke_color : source_color = vec3(0.42, 0.4, 0.38);
uniform vec3 fire_hot : source_color = vec3(1.0, 0.95, 0.7);
uniform vec3 fire_mid : source_color = vec3(1.0, 0.55, 0.1);
uniform vec3 fire_cool : source_color = vec3(0.45, 0.08, 0.02);
uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float smoothness = 0.08;
uniform float deformation = 0.35;
uniform float cell_scale = 2.2;
uniform float seed = 0.0;
uniform float alpha = 1.0;

varying float cell;

vec3 hash3(vec3 x) {
	x = vec3(dot(x, vec3(127.1, 311.7, 74.7)),
			dot(x, vec3(269.5, 183.3, 246.1)),
			dot(x, vec3(113.5, 271.9, 124.6)));
	return fract(sin(x) * 43758.5453123);
}

float voronoi(vec3 x) {
	vec3 p = floor(x);
	vec3 f = fract(x);
	float d1 = 100.0;
	for (int k = -1; k <= 1; k++)
	for (int j = -1; j <= 1; j++)
	for (int i = -1; i <= 1; i++) {
		vec3 b = vec3(float(i), float(j), float(k));
		vec3 r = b - f + hash3(p + b);
		d1 = min(d1, dot(r, r));
	}
	return sqrt(d1);
}

void vertex() {
	cell = voronoi(VERTEX * cell_scale + vec3(seed));
	VERTEX += NORMAL * (1.0 - cell * cell) * deformation;
}

void fragment() {
	// Fire: hottest where the cloud bulges out (low cell value), cooler in
	// the creases and as `heat` drops.
	float h = clamp(heat * (1.25 - cell * 0.6), 0.0, 1.0);
	vec3 fire = h > 0.5 ? mix(fire_mid, fire_hot, (h - 0.5) * 2.0) : mix(fire_cool, fire_mid, h * 2.0);
	float burn = smoothstep(0.0, 0.25, heat);
	ALBEDO = mix(smoke_color, fire, burn);
	// Smoke keeps some of its own colour in shadow (never goes black).
	EMISSION = fire * burn * 1.6 + smoke_color * (1.0 - burn) * 0.45;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	ALPHA = alpha * smoothstep(progress - smoothness, progress + smoothness, cell);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
