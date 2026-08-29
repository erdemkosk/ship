shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float wave_time = 0.0;
uniform vec4 tint : source_color = vec4(0.02, 0.08, 0.10, 1.0);
uniform float depth_m : hint_range(0.0, 50.0) = 4.0;
uniform vec2 sun_screen = vec2(0.5, -0.2);  // where the sun is, in screen space
uniform float shaft_energy : hint_range(0.0, 2.0) = 0.6;
uniform float look_down : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = wave_time;
	vec2 distort = vec2(
		sin(uv.y * 28.0 + t * 1.4) * 0.0018,
		cos(uv.x * 22.0 - t * 1.1) * 0.0014);
	vec3 scene = texture(screen_texture, uv + distort * amount).rgb;
	float cau = sin((uv.x * 18.0 + uv.y * 6.0) + t * 0.7)
			* sin((uv.x * 7.0 - uv.y * 16.0) - t * 0.9);
	cau = pow(abs(cau), 3.0) * 0.11 * amount;
	float murk = clamp(depth_m / 22.0, 0.0, 1.0);
	float lum = dot(scene, vec3(0.299, 0.587, 0.114));
	float from_above = smoothstep(0.08, 0.36, lum);
	float absorb = mix(0.16, 0.48, murk) * amount * (1.0 - from_above * 0.92);
	vec3 beer = vec3(exp(-1.85 * absorb), exp(-0.32 * absorb), exp(-0.18 * absorb));
	vec3 col = scene * beer;
	col = mix(col, col * vec3(0.62, 0.95, 0.90) + tint.rgb * 0.55,
			absorb * 0.38 * (1.0 - from_above));
	col += vec3(0.07, 0.16, 0.13) * cau;
	// Light shafts: sunlight broken by the surface into blades that all point
	// back at the sun. Cheap radial streaks, faded out with depth because the
	// water swallows them.
	if (shaft_energy > 0.001) {
		vec2 d = uv - sun_screen;
		float ang = atan(d.y, d.x);
		float rad = length(d);
		float blades = sin(ang * 9.0 + t * 0.35) * 0.5 + 0.5;
		blades *= sin(ang * 23.0 - t * 0.22) * 0.5 + 0.5;
		float sh = pow(blades, 2.2) * exp(-rad * 1.35) * exp(-murk * 1.6)
				* shaft_energy * amount;
		col += vec3(0.40, 0.68, 0.66) * sh * 0.42;
	}

	float vig = smoothstep(0.55, 1.18, distance(uv, vec2(0.5)));
	col *= 1.0 - vig * (0.10 + 0.18 * murk) * amount * (1.0 - from_above);
	// The void is below you. Looking down, the picture dies; looking up at
	// the window it does not.
	col *= 1.0 - look_down * mix(0.18, 0.78, murk) * amount * (1.0 - from_above);
	COLOR = mix(vec4(0.0), vec4(col, 1.0), step(0.001, amount));
}
