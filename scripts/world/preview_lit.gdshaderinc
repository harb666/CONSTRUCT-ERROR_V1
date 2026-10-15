// Skyforge Arena: image-to-level's PREVIEW lighting (three.js r160
// MeshStandardMaterial, physically correct lights, the preview's toon
// patch), so the level looks exactly as it does in the map maker. Built at
// runtime by SkyforgePreviewLook: each variant is "shader_type spatial;",
// its #defines (cull / blend mode, feature switches) and this include.
//  - sun: DirectionalLight colour x 1.25 x energy, its N.L in toon bands
//    (0 / floor / 1 at 0.08 / 0.45), no sun highlights;
//  - hemisphere light: sky colour (half-way to white) / ground colour,
//    1.2 x ambient energy;
//  - sky image lighting (the preview's PMREM of the panorama): diffuse from
//    the roughness-1 blur, reflections by roughness (sky/ibl_atlas.png,
//    tools/bake_skyforge_ibl.py) x envMapIntensity (toon ambient 0.85),
//    with three.js's DFG approximation and multi-scattering;
//  - the glTF material: base colour x map, ORM (AO r, roughness g, metal b),
//    normal map, emissive x map;
//  - fog: smoothstep(start, end, depth) and the height fog
//    1 - exp(min(0, (y - h) x d)), whichever is stronger.
// Compatibility renderer: textures / colour uniforms arrive sRGB-encoded,
// ALBEDO and EMISSION are taken as sRGB, light and FOG are linear - so the
// maths runs in linear and is encoded back on the way out.
#if defined(CULL_DISABLED) && defined(PREVIEW_ALPHA)
render_mode cull_disabled, blend_mix, depth_draw_opaque, ambient_light_disabled, specular_disabled;
#elif defined(CULL_DISABLED)
render_mode cull_disabled, ambient_light_disabled, specular_disabled;
#elif defined(CULL_FRONT)
render_mode cull_front, ambient_light_disabled, specular_disabled;
#elif defined(PREVIEW_ALPHA)
render_mode cull_back, blend_mix, depth_draw_opaque, ambient_light_disabled, specular_disabled;
#else
render_mode cull_back, ambient_light_disabled, specular_disabled;
#endif

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D emission_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 1.0;
uniform float roughness = 1.0;
uniform float metallic = 1.0;
uniform float normal_scale = 1.0;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
// Scrolling liquid (the preview moves the material's UVs along the flow).
uniform vec2 flow_dir = vec2(0.0, 1.0);
uniform float flow_speed = 0.0;
uniform float flow_wobble = 0.0;

// Scene (shared by every material).
uniform sampler2D ibl_atlas : source_color, filter_linear, repeat_enable;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);      // towards the sun, world
uniform vec3 sun_color = vec3(1.0);              // linear, x intensity
uniform float toon_floor = 0.55;
uniform vec3 hemi_sky = vec3(1.0);               // linear, x intensity
uniform vec3 hemi_ground = vec3(0.3);
uniform float env_intensity = 0.85;
uniform vec3 fog_color = vec3(0.5);              // linear
uniform float fog_start = 380.0;
uniform float fog_end = 1400.0;
uniform float fog_height = 24.0;
uniform float fog_height_density = 0.05;

varying vec3 world_pos;

vec3 to_lin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c)); }
vec3 to_srgb(vec3 c) { c = max(c, vec3(0.0)); return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c)); }

// three.js equirectUv (u = atan2(z, x) / 2pi + 0.5, v up), into band `b`
// (0..3 = roughness 0.25, 0.5, 0.75, 1.0) of the atlas.
vec3 ibl_band(vec3 d, float b) {
	d = normalize(d);
	float u = atan(d.z, d.x) * 0.15915494 + 0.5;
	float v = asin(clamp(d.y, -1.0, 1.0)) * 0.31830989 + 0.5;
	float row = clamp(1.0 - v, 0.5 / 64.0, 1.0 - 0.5 / 64.0);
	return to_lin(texture(ibl_atlas, vec2(u, (b + row) * 0.25)).rgb);
}
vec3 ibl(vec3 d, float r) {
	float b = clamp(r * 4.0 - 1.0, 0.0, 3.0);
	float b0 = floor(b);
	return mix(ibl_band(d, b0), ibl_band(d, min(b0 + 1.0, 3.0)), b - b0);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

varying vec3 v_diffuse;
varying vec3 v_sun;

void fragment() {
	vec2 uv = UV * uv_scale + uv_offset;
	if (flow_speed != 0.0) {
		float k = TIME * flow_speed;
		float w = sin(TIME * 3.0) * flow_wobble;
		uv += vec2(-flow_dir.x * k - flow_dir.y * w, -flow_dir.y * k + flow_dir.x * w);
	}
	vec4 base = texture(albedo_tex, uv);
	vec3 albedo = to_lin(albedo_color.rgb) * to_lin(base.rgb);
#ifdef VCOL
	albedo *= to_lin(COLOR.rgb);
#endif
	float alpha = albedo_color.a * base.a;
	vec3 orm = texture(orm_tex, uv).rgb;
	float ao = orm.r;
	float rough = clamp(roughness * orm.g, 0.0525, 1.0);
	float metal = clamp(metallic * orm.b, 0.0, 1.0);
	// Normals as three.js builds them: flat faces from screen derivatives
	// (the level's meshes carry no normals), else the vertex normal; normal
	// maps through a derivative tangent frame (getTangentFrame). `sgn` keeps
	// the frame the same way round whichever way the screen y runs.
	vec3 fdx = dFdx(VERTEX);
	vec3 fdy = dFdy(VERTEX);
	vec3 nraw = cross(fdx, fdy);
	float sgn = dot(nraw, VIEW) < 0.0 ? -1.0 : 1.0;
#ifdef FLAT
	vec3 n = normalize(nraw) * sgn;
#else
	vec3 n = normalize(NORMAL);
#endif
#ifdef NMAP
	vec2 st0 = dFdx(uv);
	vec2 st1 = dFdy(uv);
	vec3 q1perp = cross(fdy, n);
	vec3 q0perp = cross(n, fdx);
	vec3 T = (q1perp * st0.x + q0perp * st1.x) * sgn;
	vec3 B = (q1perp * st0.y + q0perp * st1.y) * sgn;
	float det = max(dot(T, T), dot(B, B));
	float sc = det == 0.0 ? 0.0 : inversesqrt(det);
	vec3 tn = texture(normal_tex, uv).rgb * 2.0 - 1.0;
	tn.xy *= normal_scale;
	n = normalize(T * sc * tn.x + B * sc * tn.y + n * tn.z);
#endif
	NORMAL = n;
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 wv = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 diffuse_color = albedo * (1.0 - metal);
	vec3 col = vec3(0.0);
	v_diffuse = vec3(0.0);
	v_sun = vec3(0.0);
#ifdef UNLIT
	col = to_lin(albedo_color.rgb);
#else
	// Sun (direct): toon-banded N.L, no highlights (Lambert: smooth).
	float dnl = clamp(dot(wn, normalize(sun_dir)), 0.0, 1.0);
#ifndef LAMBERT
	dnl = dnl < 0.08 ? 0.0 : (dnl < 0.45 ? toon_floor : 1.0);
#endif
	v_sun = sun_color * dnl * 0.31830989;
	v_diffuse = diffuse_color;
	// Hemisphere light.
	vec3 hemi = mix(hemi_ground, hemi_sky, 0.5 * wn.y + 0.5);
	vec3 indirect_diffuse = hemi * diffuse_color * 0.31830989;
	vec3 indirect_specular = vec3(0.0);
#ifndef LAMBERT
	// Sky image lighting + reflections.
	vec3 spec_color = mix(vec3(0.04), albedo, metal);
	float dnv = clamp(dot(wn, wv), 0.0, 1.0);
	vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
	vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
	vec4 rr = rough * c0 + c1;
	float a004 = min(rr.x * rr.x, exp2(-9.28 * dnv)) * rr.x + rr.y;
	vec2 fab = vec2(-1.04, 1.04) * a004 + rr.zw;
	vec3 fss_ess = spec_color * fab.x + fab.y;
	float ess = fab.x + fab.y;
	float ems = 1.0 - ess;
	vec3 favg = spec_color + (1.0 - spec_color) * 0.047619;
	vec3 fms = fss_ess * favg / (1.0 - ems * favg);
	vec3 single_s = fss_ess;
	vec3 multi_s = fms * ems;
	vec3 total_s = single_s + multi_s;
	vec3 diffuse2 = diffuse_color * (1.0 - max(max(total_s.r, total_s.g), total_s.b));
	vec3 env_irr = ibl(wn, 1.0) * env_intensity;          // = iblIrradiance / pi
	vec3 refl = reflect(-wv, wn);
	refl = normalize(mix(refl, wn, rough * rough));
	vec3 radiance = ibl(refl, rough) * env_intensity;
	float spec_occ = clamp(pow(dnv + ao, exp2(-16.0 * rough - 1.0)) - 1.0 + ao, 0.0, 1.0);
	indirect_specular = (radiance * single_s + multi_s * env_irr) * spec_occ;
	indirect_diffuse += diffuse2 * env_irr;
#endif
	indirect_diffuse *= ao;
	col = v_sun * diffuse_color + indirect_diffuse + indirect_specular;
#endif
	col += to_lin(emission_color.rgb) * to_lin(texture(emission_tex, uv).rgb) * emission_energy;
	// Out like three.js: to sRGB, THEN the fog (view depth; height fog).
	vec3 outc = to_srgb(col);
	float f = smoothstep(fog_start, fog_end, -VERTEX.z);
	if (fog_height_density > 0.0001) {
		f = max(f, 1.0 - exp(min(0.0, (world_pos.y - fog_height) * fog_height_density)));
	}
	outc = mix(outc, fog_color, f);
	// Everything goes out as emission (taken as sRGB); ALBEDO only carries
	// the surface for light(), which takes the sun off where a player or
	// robot shadows it.
	ALBEDO = to_srgb(v_diffuse);
	EMISSION = outc;
#ifdef PREVIEW_ALPHA
	ALPHA = alpha;
#endif
}

void light() {
#ifndef UNLIT
	if (LIGHT_IS_DIRECTIONAL) {
		// The sun is already in (fragment): only take it off in shadow.
		DIFFUSE_LIGHT -= v_sun * (1.0 - ATTENUATION);
	}
#endif
}
