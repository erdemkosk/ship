shader_type canvas_item;
render_mode unshaded, blend_mix;

// The inside of a diving mask.
//
// Four things, and they are the four things you actually notice wearing one:
//
//   the frame   you are looking through a hole and your peripheral vision is
//               gone. The skirt is black silicone a centimetre from your eye,
//               so it is not a sharp edge — it is a soft, dark falloff with
//               one hairline of light along the inside of the rim.
//   the glass   underwater a mask magnifies about a third and bends the light
//               at the edges, which is why everything looks close and why the
//               corners fringe.
//   the fog     and this is the one worth doing properly. It is not a white
//               filter fading up, and it is not a field of round dots either:
//               it CREEPS. The glass is coldest where the skirt touches it, so
//               the haze starts as a soft bloom round the rim and grows inward
//               in an irregular front, thinning to nothing over the middle of
//               the lens until finally that goes too.
//   the wipe    a finger drags across the inside, clears a band, and leaves
//               streaks where it smeared what it did not take.
//
// The fog is a THRESHOLD field, not a texture drawn on top. Every point of the
// glass has its own moment of going over — earlier at the rim, later in the
// middle, jittered by a slow noise — and `fog` is simply how far that moment
// has arrived. That is why the front is organic and why it spreads instead of
// appearing. The haze itself blurs what is behind it, takes its contrast and
// bleeds its highlights, because that is what looking through water vapour
// actually does to a picture.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
// 0 in the locker, 1 on your face. The middle of the range is the mask coming
// down over your eyes, which is why the screen is allowed to go dark there.
uniform float wear : hint_range(0.0, 1.0) = 0.0;
uniform float fog : hint_range(0.0, 1.0) = 0.0;
// Runs 1 -> 0 while the hand crosses the glass. Off at 0.
uniform float wipe : hint_range(0.0, 1.0) = 0.0;
// Where the finger is on the glass and which way it is going, handed over by
// the hand rig itself. The glass clears UNDER the hand or the two disagree and
// the whole thing falls apart.
uniform float wipe_x = 9.0;
uniform float wipe_dir = -1.0;
uniform float aspect = 1.78;
uniform float wave_time = 0.0;
uniform float underwater : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 34.56);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	float a = hash21(p);
	float b = hash21(p + vec2(19.19, 7.31));
	return vec2(a, b);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.52;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, -0.9);
		a *= 0.51;
	}
	return v;
}


void fragment() {
	vec2 uv = SCREEN_UV;
	if (wear < 0.001) {
		COLOR = vec4(texture(screen_texture, uv).rgb, 1.0);
		discard;
	}

	// Centred and aspect-corrected: x runs +-aspect/2, y runs +-0.5. SCREEN_UV
	// counts DOWN the screen, so y is flipped here — otherwise the nose pocket
	// ends up in your forehead, which is exactly what it did.
	vec2 p = (uv - vec2(0.5)) * vec2(aspect, -1.0);
	// The mask breathes with you — a couple of millimetres, slow. Static, it
	// reads as a decal printed on the screen.
	float br = sin(wave_time * 1.15) * 0.5 + sin(wave_time * 0.41) * 0.5;
	p.y -= br * 0.0035;

	// The opening. A mask is not a porthole: the glass is wide, it is wider at
	// the top than at the bottom, and the bottom edge lifts in the middle where
	// the nose pocket is moulded into it. All three of those are here, because
	// with any of them missing it reads as a circle cut in a wall.
	vec2 q = vec2(p.x / (1.0 + 0.115 * p.y), p.y);
	vec2 b = vec2(0.720, 0.330);
	float d = length(max(abs(q) - b, vec2(0.0))) - 0.130;
	float nose = length((q - vec2(0.0, -0.655)) * vec2(1.12, 0.78)) - 0.245;
	d = max(d, -nose);

	// While it is going on, the frame is coming DOWN over your eyes and the
	// hole is wider than it ends up — so the transition is the hole closing to
	// its final size, not a picture fading in.
	float don = clamp(wear * 1.35, 0.0, 1.0);
	d -= (1.0 - don) * 0.55;
	float edge = smoothstep(-0.34, 0.005, d);   // 0 at the centre, 1 at the rim

	// --- looking through the glass ------------------------------------------
	// A flat lens against water magnifies by the ratio of the two refractive
	// indices, and bends more the further off-axis you are. Both of those are
	// here, small, and both die away in air.
	vec2 luv = uv;
	vec2 r2 = (uv - vec2(0.5));
	float rr = dot(r2, r2);
	luv = vec2(0.5) + r2 * (1.0 - underwater * (0.055 + 0.14 * rr));

	// --- fog ----------------------------------------------------------------
	float f = 0.0;
	float sheet = 0.0;
	if (fog > 0.002) {
		// Where the glass goes over first. Rim before middle, jittered by a
		// large soft noise that drifts very slowly — so it is never the same
		// shape twice and it never looks stamped on.
		vec2 fp = p * 2.6 + vec2(0.0, wave_time * 0.008);
		float n = fbm(fp);
		float grain = fbm(p * 11.0 + vec2(4.3, 1.1));
		// Calibrated so it takes its time: a bloom round the skirt at a quarter
		// of the way, half the lens gone at two thirds, and the middle — the
		// part you are actually looking through — only at the very end.
		float thr = clamp(1.08 - 0.46 * edge - 0.28 * (n - 0.5)
				- 0.08 * (grain - 0.5), 0.03, 1.25);
		float amt = fog;
		// The wipe: a finger across the inside. It wanders with the knuckles,
		// it is soft on the leading side and hard behind, and it never takes
		// everything — what is left is the streaks the next breath grows from.
		if (wipe > 0.001) {
			// The front sits AT the fingertip and everything the finger has
			// already passed is clear. A finger is not a straight edge either:
			// it drags with the knuckles and it skips.
			float front = wipe_x + sin(p.y * 7.3 + 1.1) * 0.038
					+ sin(p.y * 19.4) * 0.014;
			float cleared = smoothstep(front + 0.05 * wipe_dir,
					front - 0.17 * wipe_dir, p.x);
			float streak = 0.5 + 0.5 * sin(p.y * 61.0 + 1.7)
					* (0.55 + 0.45 * sin(p.y * 17.0 + 0.4));
			amt *= mix(1.0, 0.07 + 0.17 * streak, cleared);
		}
		// Each point goes over in its own time, softly. This is the spread: the
		// low thresholds (the rim) are crossed first and the front works inward
		// as `amt` rises. Written the other way round it CLEARS as the fog
		// rises, which is precisely as wrong as it sounds.
		f = smoothstep(thr - 0.40, thr, amt);
		// Texture within the haze: it is never even, it is thicker in patches.
		f *= 0.86 + 0.28 * (fbm(p * 6.0 + vec2(2.0, 8.0)) - 0.5);
		// And at the end it stops being patchy at all: the whole lens goes and
		// you are blind, which is the moment your hand comes up on its own.
		sheet = smoothstep(0.84, 1.02, amt);
		f = clamp(max(f, sheet), 0.0, 1.0);
	}

	// The haze does three things to what is behind it and all three matter:
	// it BLURS, it takes the colour out, and it bleeds the bright parts.
	//
	// The three channels are sampled at slightly different scales: four
	// millimetres of tempered glass at an angle splits the colours, and the
	// split grows toward the corners. It is a fraction of a pixel in the middle
	// and two or three at the edge, which is exactly where you notice it.
	float lod = f * (3.6 + 3.0 * sheet);
	float ca = (0.0010 + 0.0040 * rr) * (0.45 + 0.55 * underwater);
	vec3 col;
	col.r = texture(screen_texture, vec2(0.5) + (luv - vec2(0.5)) * (1.0 + ca), lod).r;
	col.g = texture(screen_texture, luv, lod).g;
	col.b = texture(screen_texture, vec2(0.5) + (luv - vec2(0.5)) * (1.0 - ca), lod).b;
	if (f > 0.002) {
		vec3 wide = texture(screen_texture, luv, 5.0 + 2.5 * sheet).rgb;
		col = mix(col, wide, f * 0.55);
		vec3 flat_grey = vec3(dot(col, vec3(0.299, 0.587, 0.114)));
		col = mix(col, flat_grey, f * 0.62);
		col = mix(col, vec3(0.68, 0.735, 0.755), f * (0.30 + 0.46 * sheet));
		// Light does not stop at fog, it spreads through it. This is the halo
		// round every lamp and every patch of surface when the glass is over.
		float lum = dot(wide, vec3(0.299, 0.587, 0.114));
		col += vec3(0.55, 0.60, 0.62) * smoothstep(0.25, 1.0, lum) * f * 0.30;
	}

	// Fine scratches, only visible against something bright behind them.
	float scr = vnoise(p * vec2(2.0, 46.0) + vec2(4.0, 0.0));
	scr = smoothstep(0.93, 1.0, scr) * smoothstep(0.28, 0.0, abs(d + 0.16));
	col += vec3(0.05, 0.055, 0.06) * scr * dot(col, vec3(0.4));

	// --- the frame ----------------------------------------------------------
	// The skirt is two centimetres from your eye. At that distance nothing has
	// an edge — it is far inside the near plane and hopelessly out of focus. So
	// it is three zones, not a cut: a wide penumbra that eats the light long
	// before anything black arrives, the black itself, and one line of light
	// where the inside of the rim catches whatever is in front of you.
	float pen = smoothstep(-0.215, 0.020, d);
	float core = smoothstep(-0.022, 0.058, d);
	col *= 1.0 - pen * 0.74;
	vec3 rubber = vec3(0.011, 0.012, 0.015);
	col = mix(col, rubber, core);
	// The rim line only exists where there is light to catch, so it disappears
	// in the dark instead of glowing on its own.
	float lip = smoothstep(0.028, 0.003, abs(d + 0.002));
	col += vec3(0.26, 0.31, 0.33) * lip
			* (0.04 + 0.50 * dot(col, vec3(0.34, 0.45, 0.21)))
			* (0.35 + 0.65 * underwater);

	// A little water standing in the bottom of the skirt, and a few beads in
	// the corners that never quite clear.
	// A little water standing in the bottom of the skirt. It has a surface, and
	// that surface moves with your breathing — the one part of a mask that is
	// never still.
	float pool_y = -0.36 + br * 0.012;
	float pool = smoothstep(-0.052, -0.004, d) * smoothstep(-0.10, pool_y, p.y);
	col = mix(col, col * vec3(0.62, 0.82, 0.93) + vec3(0.01, 0.035, 0.05),
			pool * (0.38 + 0.34 * underwater));

	// --- putting it on ------------------------------------------------------
	// Your own hands cross your eyes and for a moment you cannot see. Peaks in
	// the middle of the movement and is gone at both ends.
	float dark = smoothstep(0.06, 0.42, wear) * smoothstep(0.94, 0.52, wear);
	col *= 1.0 - dark * 0.94;

	COLOR = vec4(col, 1.0);
}
