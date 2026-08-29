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
uniform vec4 shaft_color : source_color = vec4(0.72, 0.82, 0.88, 1.0);
uniform float lamp_tight : hint_range(0.25, 2.5) = 1.0;

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
	float from_above = smoothstep(0.10, 0.42, lum) * look_down;
	float absorb = mix(0.16, 0.48, murk) * amount * (1.0 - from_above * 0.70);
	vec3 beer = vec3(exp(-1.85 * absorb), exp(-0.32 * absorb), exp(-0.18 * absorb));
	vec3 col = scene * beer;
	col = mix(col, col * vec3(0.62, 0.95, 0.90) + tint.rgb * 0.55,
			absorb * 0.38 * (1.0 - from_above));
	col += vec3(0.07, 0.16, 0.13) * cau * 0.65;
	// The lamp lives here, not on the sea mesh. A gaussian in screen space
	// stays round; painting it on clipmap quads is what looked square.
	if (shaft_energy > 0.001) {
		float aspect = SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 1e-5);
		vec2 dlt = uv - sun_screen;
		dlt.x *= aspect;
		// Waves smear the disc. Two slow sines, not a grid — that was the
		// other way it went square.
		float w1 = sin(dlt.x * 16.0 + dlt.y * 11.0 + t * 1.15);
		float w2 = sin(dlt.x * 8.5 - dlt.y * 13.0 - t * 0.72);
		dlt += vec2(w1, w2) * 0.016 * (0.65 + murk);
		float rad = length(dlt);
		float tight = max(lamp_tight, 0.25);
		float core = exp(-rad * rad * (70.0 * tight));
		float glow = exp(-rad * rad * (11.0 * tight));
		float bloom = exp(-rad * rad * (2.6 * tight));
		float wash = exp(-rad * (1.15 * sqrt(tight)));
		float shim = 0.82 + 0.18 * sin(uv.x * 7.5 + t * 0.55)
				* sin(uv.y * 6.2 - t * 0.40);
		float look_up = 1.0 - look_down;
		float depth_fade = exp(-murk * 0.85);
		vec3 lamp = shaft_color.rgb * (core * 1.9 + glow * 0.95)
				+ shaft_color.rgb * vec3(0.55, 0.85, 1.0) * (bloom * 0.42 + wash * 0.14);
		col += lamp * shim * shaft_energy * amount * look_up * depth_fade;
	}

	float vig = smoothstep(0.55, 1.18, distance(uv, vec2(0.5)));
	col *= 1.0 - vig * (0.10 + 0.18 * murk) * amount * (1.0 - from_above);
	// The void is below you. Looking down, the picture dies; looking up at
	// the window it does not.
	col *= 1.0 - look_down * mix(0.18, 0.78, murk) * amount * (1.0 - from_above);
	COLOR = mix(vec4(0.0), vec4(col, 1.0), step(0.001, amount));
}
