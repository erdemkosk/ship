shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// The radar. A PPI — plan position indicator — which is the round one with the
// line going round it.
//
// Like the sounder and the chart, the picture is not decoration: for every
// pixel it works out what bearing and range that point stands for, converts
// that into a world position, and asks the seabed heightmap whether there is
// land there. So the coast on the screen is the coast outside, and a headland
// you can barely see in the murk paints exactly where it is.
//
// Head-up, the way a small set is: the top of the screen is the ship's head, so
// the land wheels round the screen as she turns rather than the other way.
//
// The sweep is slow and the afterglow is long, which is the giveaway that this
// is an old set. A modern one refreshes faster than the phosphor decays and the
// picture just sits there; on this one you watch the paint come round.

uniform sampler2D height_tex : filter_linear, repeat_enable;
uniform vec2 boat_uv = vec2(0.5, 0.5);
uniform float boat_head = 0.0;
uniform float range_m = 900.0;         // radius of the outer ring
uniform float terrain_size = 2048.0;
uniform float rpm = 7.5;               // deliberately slow
uniform float lit = 1.0;
uniform float power = 1.0;          // supply health; this boat's is not good
uniform vec3 phosphor : source_color = vec3(0.40, 1.0, 0.55);

float rhash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	// Screen-space coordinates with +y UP: the quad's V runs downward, so it is
	// negated here. Orientation was checked by pinning the boat at the origin
	// head north and reading the picture against known ground — the lighthouse
	// rock paints fine on the starboard bow at a fifth of the range, and the
	// southern headland astern at half of it, which is where they are.
	vec2 c = (UV - 0.5) * 2.0;
	c.y = -c.y;
	float r = length(c);
	vec3 col = vec3(0.012, 0.030, 0.020);

	if (r <= 1.0) {
		// Screen bearing: 0 dead ahead, growing to starboard.
		float br = atan(c.x, c.y);
		// Out into the world. Head-up, so the ship's heading is added on.
		float wb = br + boat_head;
		vec2 off = vec2(sin(wb), -cos(wb)) * r * range_m;
		float h = texture(height_tex, boat_uv + off / terrain_size).r;

		// What comes back. Land is a hard return; anything drying or nearly so
		// gives a weak one, which is how a rock in the fairway announces itself.
		float echo = smoothstep(-0.6, 1.2, h);
		echo = max(echo, smoothstep(-3.0, -0.8, h) * 0.30);
		// Sea clutter: the first fifth of the range is always a mess of returns
		// off the waves, worse the closer in you look.
		float clutter = (1.0 - smoothstep(0.0, 0.22, r))
				* step(0.55, rhash(vec2(floor(br * 90.0), floor(r * 160.0) + floor(TIME * 3.0))))
				* 0.45;
		echo = max(echo, clutter);

		// The sweep, and the phosphor decaying behind it.
		float sweep = mod(TIME * rpm * 0.10471976, 6.2831853);
		float since = mod(sweep - br, 6.2831853);
		float after = exp(-since * 0.62);
		float line = smoothstep(0.10, 0.0, since) * 0.55;

		float sig = echo * (0.10 + 0.95 * after);
		// The trace itself is visible even where nothing paints.
		sig = max(sig, line * (0.16 + 0.84 * echo));
		// Own-ship origin blob.
		sig = max(sig, (1.0 - smoothstep(0.0, 0.020, r)) * 0.9);

		col += phosphor * sig * 1.25;

		// Range rings and the heading marker, drawn faint and always on.
		float rw = fwidth(r) * 1.5 + 1e-5;
		float rings = 0.0;
		for (int i = 1; i <= 4; i++) {
			float rr = float(i) * 0.25;
			rings = max(rings, 1.0 - smoothstep(rw, rw * 2.5, abs(r - rr)));
		}
		float bw = fwidth(c.x) * 1.6 + 1e-5;
		float head_line = (c.y > 0.0) ? (1.0 - smoothstep(bw, bw * 2.5, abs(c.x))) : 0.0;
		// Bearing ticks every ten degrees round the edge.
		float ticks = step(0.955, r) * step(0.62, abs(fract(br * 28.6478898) - 0.5) * 2.0);
		col += phosphor * (rings * 0.16 + head_line * 0.26 + ticks * 0.35);
	} else {
		// Outside the tube: the mask round the screen.
		col = vec3(0.020, 0.021, 0.020);
	}

	// Scan lines and a supply that is not quite steady, same as the sounder —
	// they are wired to the same battery and it shows.
	col *= 0.90 + 0.10 * sin(UV.y * 380.0);
	// Bad wiring, and worse the harder it blows. In a gale the set browns out,
	// stutters, and now and then loses the picture altogether.
	float sag = clamp(1.0 - power, 0.0, 1.0);
	col *= 1.0 - sag * (0.30 + 0.34 * sin(TIME * 27.0) + 0.20 * sin(TIME * 7.3));
	col *= 1.0 - step(0.988 - sag * 0.06, rhash(vec2(floor(TIME * 17.0), 7.0))) * 0.85;
	col *= 0.93 + 0.07 * sin(TIME * 31.0) + 0.04 * sin(TIME * 9.7);
	col *= 1.0 - smoothstep(0.72, 1.15, r) * 0.55;
	col *= lit;
	col += vec3(0.012, 0.024, 0.017) * 0.6;

	ALBEDO = col * 2.4;
}
