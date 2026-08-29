shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float wet : hint_range(0.0, 1.0) = 0.0;
uniform float spray : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float amount = clamp(wet + spray, 0.0, 1.0);
	vec2 uv = SCREEN_UV;
	vec2 distort = vec2(0.0);
	float highlight = 0.0;

	// Persistent rain beads that slowly drip down the glass.
	float drops_f = mix(4.0, 14.0, wet);
	for (int i = 0; i < 16; i++) {
		float fi = float(i);
		float active = step(fi, drops_f - 0.01);
		vec2 seed = vec2(fi, 0.37);
		vec2 c = vec2(hash(seed), hash(seed + 1.7));
		float speed = 0.012 + hash(seed + 2.4) * 0.035;
		c.y = fract(c.y + TIME * speed * wet);
		vec2 aspect = vec2(1.0, 1.28);
		float d = length((uv - c) * aspect);
		// Small. A bead the size of a coin on the lens reads as a drawn circle,
		// not as water.
		float rad = mix(0.006, 0.017, hash(seed + 4.1));
		float inner = smoothstep(rad, rad * 0.28, d);
		float rim = smoothstep(rad * 1.15, rad * 0.72, d) * (1.0 - inner);
		vec2 dir = (uv - c) / max(d, 0.0008);
		distort += dir * inner * 0.016 * wet * active;
		highlight += rim * 0.20 * active;
		float tail = smoothstep(0.005, 0.0, abs(uv.x - c.x))
				* smoothstep(0.0, 0.06, c.y - uv.y)
				* smoothstep(0.11, 0.02, c.y - uv.y);
		distort.y += tail * 0.006 * wet * active;
		highlight += tail * 0.07 * active;
	}

	// Splash sheet: a brief water curtain across the lens.
	float sheet = spray * (0.65 + 0.35 * sin(uv.y * 42.0 - TIME * 11.0));
	distort.y += sheet * 0.022;
	distort.x += spray * 0.006 * sin(uv.y * 28.0 + TIME * 7.0);
	float streak = spray * smoothstep(0.18, 0.0, abs(uv.x - 0.5 - 0.08 * sin(TIME * 3.0)))
			* (0.4 + 0.6 * sin(uv.y * 55.0 - TIME * 14.0));
	highlight += streak * 0.25;

	vec3 col = texture(screen_texture, uv + distort).rgb;
	col += vec3(0.22, 0.25, 0.27) * highlight * amount;
	col = mix(col, col * vec3(0.92, 0.95, 0.97), spray * 0.18);
	float vig = smoothstep(0.52, 1.12, distance(uv, vec2(0.5)));
	col *= 1.0 - vig * 0.28 * amount;
	COLOR = mix(vec4(0.0), vec4(col, 1.0), step(0.008, amount));
}
