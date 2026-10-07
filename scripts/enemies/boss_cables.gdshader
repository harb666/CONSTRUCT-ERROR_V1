shader_type spatial;
// Boss core cables / hoses: vertex colours (rubber, metal connectors, red
// power stripe in alpha), the stripe glowing and pulsing while powered.
render_mode cull_disabled;

uniform float power = 1.0;

void fragment() {
	ALBEDO = COLOR.rgb;
	float metal = smoothstep(0.3, 0.4, COLOR.g);
	METALLIC = metal * 0.8;
	ROUGHNESS = mix(0.6, 0.35, metal);
	float pulse = 0.65 + 0.35 * sin(TIME * 7.0);
	EMISSION = vec3(1.0, 0.06, 0.03) * COLOR.a * power * pulse * 1.8;
}
