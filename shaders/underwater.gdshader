shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float wave_time = 0.0;
uniform vec4 tint : source_color = vec4(0.02, 0.08, 0.10, 1.0);
uniform float depth_m : hint_range(0.0, 50.0) = 4.0;
uniform vec2 sun_screen = vec2(0.5, -0.2);
uniform float shaft_energy : hint_range(0.0, 2.0) = 0.6;
uniform float look_down : hint_range(0.0, 1.0) = 0.0;
uniform vec4 shaft_color : source_color = vec4(0.72, 0.82, 0.88, 1.0);
uniform float lamp_tight : hint_range(0.25, 2.5) = 1.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = wave_time;
	float look_up = 1.0 - look_down;
	float murk = clamp(depth_m / 22.0, 0.0, 1.0);
	vec2 distort = vec2(
		sin(uv.y * 28.0 + t * 1.4) * 0.0018,
		cos(uv.x * 22.0 - t * 1.1) * 0.0014);
	// Looking up, the far ceiling sits behind more water — a slightly
	// longer warp, not a second picture.
	distort *= 1.0 + look_up * murk * 1.4;
	vec3 scene = texture(screen_texture, uv + distort * amount).rgb;
	float cau = sin((uv.x * 18.0 + uv.y * 6.0) + t * 0.7)
			* sin((uv.x * 7.0 - uv.y * 16.0) - t * 0.9);
	cau = pow(abs(cau), 3.0) * 0.11 * amount;
	float lum = dot(scene, vec3(0.299, 0.587, 0.114));
	float from_above = smoothstep(0.10, 0.42, lum) * look_down;
	float absorb = mix(0.16, 0.48, murk) * amount * (1.0 - from_above * 0.70);
	vec3 beer = vec3(exp(-1.85 * absorb), exp(-0.32 * absorb), exp(-0.18 * absorb));
	vec3 col = scene * beer;
	// Do not re-teal the torn window when you are looking at it.
	col = mix(col, col * vec3(0.62, 0.95, 0.90) + tint.rgb * 0.55,
			absorb * 0.38 * (1.0 - from_above) * (1.0 - look_up * 0.70));
	col += vec3(0.07, 0.16, 0.13) * cau * 0.45 * (1.0 - look_up * 0.5);
	float depth_fade = exp(-murk * 0.85);
	// Soft bloom of the already-shredded window, not a mesh disc.
	if (shaft_energy > 0.001) {
		float aspect = SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 1e-5);
		vec2 dlt = uv - sun_screen;
		dlt.x *= aspect;
		float w1 = sin(dlt.x * 16.0 + dlt.y * 11.0 + t * 1.15);
		float w2 = sin(dlt.x * 8.5 - dlt.y * 13.0 - t * 0.72);
		dlt += vec2(w1, w2) * 0.016 * (0.65 + murk);
		float rad = length(dlt);
		float tight = max(lamp_tight, 0.25);
		float glow = exp(-rad * rad * (11.0 * tight));
		float bloom = exp(-rad * rad * (2.6 * tight));
		float wash = exp(-rad * (1.15 * sqrt(tight)));
		float shim = 0.82 + 0.18 * sin(uv.x * 7.5 + t * 0.55)
				* sin(uv.y * 6.2 - t * 0.40);
		vec3 lamp = shaft_color.rgb * (glow * 0.35 + bloom * 0.28 + wash * 0.10);
		col += lamp * shim * shaft_energy * amount * look_up * depth_fade * 0.55;
		// Shafts: walk toward the sun through the torn window already in
		// the colour buffer, so they follow the shards instead of drawing
		// a second circle.
		vec2 to_sun = sun_screen - uv;
		float shaft = 0.0;
		for (int i = 1; i <= 5; i++) {
			float k = float(i) / 5.0;
			vec2 s = clamp(uv + to_sun * k * 0.42, vec2(0.001), vec2(0.999));
			vec3 sm = texture(screen_texture, s).rgb;
			shaft += dot(sm, vec3(0.30, 0.52, 0.18)) * (1.0 - k);
		}
		col += shaft_color.rgb * shaft * 0.055 * shaft_energy * amount
				* look_up * depth_fade;
	}

	// Volume between the eye and the ceiling: looking up, distant water
	// hazes; looking down, the basin dies.
	col = mix(col, tint.rgb * 0.12, murk * 0.20 * look_up * amount);
	float vig = smoothstep(0.55, 1.18, distance(uv, vec2(0.5)));
	col *= 1.0 - vig * (0.10 + 0.18 * murk) * amount * (1.0 - from_above);
	col *= 1.0 - look_down * mix(0.18, 0.78, murk) * amount * (1.0 - from_above);
	COLOR = mix(vec4(0.0), vec4(col, 1.0), step(0.001, amount));
}
