shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float wave_time = 0.0;
uniform vec4 tint : source_color = vec4(0.02, 0.08, 0.10, 1.0);
uniform float depth_m : hint_range(0.0, 50.0) = 4.0;
uniform vec2 sun_screen = vec2(0.5, -0.2);  // where the sun is, in screen space
uniform float shaft_energy : hint_range(0.0, 2.0) = 0.6;

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = wave_time;
	vec2 distort = vec2(
		sin(uv.y * 28.0 + t * 1.4) * 0.0018,
		cos(uv.x * 22.0 - t * 1.1) * 0.0014);
	vec3 scene = texture(screen_texture, uv + distort * amount).rgb;
	float cau = sin((uv.x * 18.0 + uv.y * 6.0) + t * 0.7)
			* sin((uv.x * 7.0 - uv.y * 16.0) - t * 0.9);
	cau = pow(abs(cau), 3.0) * 0.08 * amount;
	float murk = clamp(depth_m / 18.0, 0.0, 1.0);
	// Even a metre down the water has taken most of the red out of everything.
	// The old floor of 0.35 left the first few metres nearly untinted, which is
	// exactly where you spend most of your time — and it looked like air.
	vec3 col = mix(scene, scene * tint.rgb * 2.4, mix(0.47, 0.80, murk) * amount);
	col += vec3(0.05, 0.12, 0.10) * cau;
	// Light shafts: sunlight broken by the surface into blades that all point
	// back at the sun. Cheap radial streaks, faded out with depth because the
	// water swallows them.
	if (shaft_energy > 0.001) {
		vec2 d = uv - sun_screen;
		float ang = atan(d.y, d.x);
		float rad = length(d);
		float blades = sin(ang * 9.0 + t * 0.35) * 0.5 + 0.5;
		blades *= sin(ang * 23.0 - t * 0.22) * 0.5 + 0.5;
		float sh = pow(blades, 2.2) * exp(-rad * 1.6) * exp(-murk * 2.4)
				* shaft_energy * amount;
		col += vec3(0.35, 0.60, 0.62) * sh * 0.28;
	}

	float vig = smoothstep(0.35, 1.05, distance(uv, vec2(0.5)));
	col *= 1.0 - vig * (0.28 + 0.35 * murk) * amount;
	COLOR = mix(vec4(0.0), vec4(col, 1.0), step(0.001, amount));
}
