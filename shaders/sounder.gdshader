shader_type spatial;
render_mode unshaded, depth_draw_opaque;

// The echo sounder's screen.
//
// The one piece of electronics aboard, and it looks it: a monochrome phosphor
// panel from a decade when that was the only kind, running off a boat's wiring,
// which is to say badly. The trace is REAL — boat.gd feeds it the last sixty-odd
// seconds of actual seabed under the keel, so what crawls across the glass is
// the ground you have just passed over. Steer onto a shoal and you watch it come
// up at you before you feel it.
//
// Everything here is drawn: the waterfall, the scale, the digits. There is no
// texture and no viewport, because a 7-segment readout is seven rectangles and
// a lookup table, and doing it in the shader means it costs nothing and never
// goes out of sync with the depth it is supposed to be showing.

uniform float depth_hist[64];
uniform int head = 0;                 // ring-buffer write cursor
uniform float depth_now = 0.0;        // metres under the keel, for the digits
uniform float range_m = 40.0;         // full scale of the waterfall
uniform float power = 1.0;            // supply health, 0..1 — this boat's is poor
uniform float lit = 1.0;              // set to 0 when the ship's power is off
uniform vec3 phosphor : source_color = vec3(0.45, 1.0, 0.62);
uniform vec3 screen_bg : source_color = vec3(0.020, 0.045, 0.032);

float shash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float box2(vec2 p, vec2 c, vec2 h) {
	vec2 d = abs(p - c) - h;
	return (max(d.x, d.y) < 0.0) ? 1.0 : 0.0;
}

// Seven-segment cell. `p` runs 0..1 across one digit.
float sevenseg(vec2 p, int m) {
	if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) {
		return 0.0;
	}
	float v = 0.0;
	if ((m & 1) != 0) { v = max(v, box2(p, vec2(0.50, 0.06), vec2(0.30, 0.045))); }   // a
	if ((m & 2) != 0) { v = max(v, box2(p, vec2(0.84, 0.28), vec2(0.045, 0.20))); }   // b
	if ((m & 4) != 0) { v = max(v, box2(p, vec2(0.84, 0.72), vec2(0.045, 0.20))); }   // c
	if ((m & 8) != 0) { v = max(v, box2(p, vec2(0.50, 0.94), vec2(0.30, 0.045))); }   // d
	if ((m & 16) != 0) { v = max(v, box2(p, vec2(0.16, 0.72), vec2(0.045, 0.20))); }  // e
	if ((m & 32) != 0) { v = max(v, box2(p, vec2(0.16, 0.28), vec2(0.045, 0.20))); }  // f
	if ((m & 64) != 0) { v = max(v, box2(p, vec2(0.50, 0.50), vec2(0.30, 0.042))); }  // g
	return v;
}

int mask_for(int d) {
	if (d == 0) { return 63; }
	if (d == 1) { return 6; }
	if (d == 2) { return 91; }
	if (d == 3) { return 79; }
	if (d == 4) { return 102; }
	if (d == 5) { return 109; }
	if (d == 6) { return 125; }
	if (d == 7) { return 7; }
	if (d == 8) { return 127; }
	return 111;
}

void fragment() {
	vec2 uv = UV;
	vec3 col = screen_bg;

	// --- the waterfall -------------------------------------------------------
	// Oldest on the left, newest on the right, exactly as the paper recorders
	// these things replaced used to run.
	float glow = 0.0;
	if (uv.y > 0.30) {
		float wy = (uv.y - 0.30) / 0.70;            // 0 at the surface line
		int col_i = int(clamp(uv.x, 0.0, 0.999) * 64.0);
		int idx = (head + col_i) % 64;
		float d = depth_hist[idx];
		float t = clamp(d / max(range_m, 1.0), 0.0, 1.2);
		// The bottom return: a hard leading edge and a soft tail under it, the
		// tail thicker over mud and thinner over rock. Here it just follows the
		// slope, which is close enough to read.
		float edge = 1.0 - smoothstep(0.0, 0.030, abs(wy - t));
		float tail = smoothstep(t, t + 0.16, wy) * (1.0 - smoothstep(t + 0.16, t + 0.34, wy));
		glow = max(edge, tail * 0.42);
		// Second echo, the ghost a hard bottom throws at twice the range.
		glow = max(glow, (1.0 - smoothstep(0.0, 0.014, abs(wy - t * 2.0))) * 0.22);

		// Fish: arches, because a fish crossing the cone gets nearer then
		// further and the trace draws that as a hump.
		float fcell = floor(uv.x * 16.0);
		float fseed = shash(vec2(fcell, floor(float(head) / 7.0)));
		if (fseed > 0.72) {
			float fx = fract(uv.x * 16.0);
			float fy = 0.18 + fseed * 0.55 * t;
			float arch = fy - 0.05 * sin(fx * 3.14159);
			glow = max(glow, (1.0 - smoothstep(0.0, 0.022, abs(wy - arch)))
					* smoothstep(0.0, 0.15, fx) * smoothstep(1.0, 0.85, fx));
		}
		// Surface clutter along the top, always there in any sea.
		glow = max(glow, (1.0 - smoothstep(0.0, 0.03, wy)) * (0.25 + 0.35 * shash(vec2(uv.x * 90.0, floor(TIME * 8.0)))));
	}

	// --- the scale -----------------------------------------------------------
	// Ticks down the right-hand edge, longer every fifth.
	if (uv.x > 0.93 && uv.y > 0.30) {
		float wy = (uv.y - 0.30) / 0.70;
		float ticks = wy * range_m / 5.0;
		float f = abs(fract(ticks) - 0.5);
		float major = step(0.5, fract(ticks * 0.5 + 0.25));
		if (f > 0.46 && uv.x > (major > 0.5 ? 0.93 : 0.955)) {
			glow = max(glow, 0.55);
		}
	}

	// --- the readout ---------------------------------------------------------
	// Three digits and a tenth: 18.4 metres. Blanked with dashes if the sounder
	// has lost the bottom.
	float dg = 0.0;
	float dv = clamp(depth_now, 0.0, 99.9);
	int i100 = int(dv / 10.0);
	int i10 = int(dv) - i100 * 10;
	int i1 = int(dv * 10.0) - int(dv) * 10;
	vec2 dp = (uv - vec2(0.055, 0.045)) / vec2(0.155, 0.205);
	if (depth_now <= 0.0) {
		// no bottom: three bars
		for (int k = 0; k < 3; k++) {
			vec2 q = dp - vec2(float(k) * 1.22, 0.0);
			dg = max(dg, sevenseg(q, 64));
		}
	} else {
		if (i100 > 0) {
			dg = max(dg, sevenseg(dp, mask_for(i100)));
		}
		dg = max(dg, sevenseg(dp - vec2(1.22, 0.0), mask_for(i10)));
		dg = max(dg, sevenseg(dp - vec2(2.62, 0.0), mask_for(i1)));
		// decimal point
		dg = max(dg, box2(dp, vec2(2.40, 0.94), vec2(0.055, 0.045)));
	}
	// A small "m" struck through the corner, drawn as three bars.
	vec2 mp = (uv - vec2(0.60, 0.075)) / vec2(0.055, 0.13);
	dg = max(dg, box2(mp, vec2(0.10, 0.60), vec2(0.10, 0.40)));
	dg = max(dg, box2(mp, vec2(0.50, 0.60), vec2(0.10, 0.40)));
	dg = max(dg, box2(mp, vec2(0.90, 0.60), vec2(0.10, 0.40)));
	dg = max(dg, box2(mp, vec2(0.50, 0.24), vec2(0.50, 0.09)));

	// --- the glass -----------------------------------------------------------
	float sig = max(glow, dg);
	// Phosphor bloom: the pixel next to a lit one glows a little too.
	col += phosphor * sig * 1.15;
	col += phosphor * sig * 0.35;

	// Scan lines, and the faint horizontal banding of a panel driven off a
	// supply that is not quite steady.
	float scan = 0.88 + 0.12 * sin(uv.y * 420.0);
	float roll = 1.0 + 0.05 * sin(uv.y * 12.0 - TIME * 1.7);
	col *= scan * roll;

	// Bad wiring. The boat's supply sags when anything else draws on it, so the
	// tube dims and brightens, and now and then it stutters outright.
	float flick = 0.90 + 0.10 * sin(TIME * 47.0) + 0.06 * sin(TIME * 13.3);
	float drop = step(0.985, shash(vec2(floor(TIME * 22.0), 3.0)));
	float sag = clamp(1.0 - power, 0.0, 1.0);
	col *= mix(1.0, flick * (1.0 - drop * 0.75), sag * 0.85 + 0.20);
	// A hard stutter that gets common as the supply gets worse.
	col *= 1.0 - step(0.990 - sag * 0.07, shash(vec2(floor(TIME * 19.0), 11.0))) * 0.9;

	// Curved glass: darken the corners and put a bezel shadow round the edge.
	vec2 e = abs(uv - 0.5) * 2.0;
	float vig = 1.0 - smoothstep(0.75, 1.25, length(e)) * 0.75;
	col *= vig;

	col *= lit;
	// Even dead, the glass is not black — it reflects the room a little.
	col += screen_bg * 0.5;

	// `unshaded` outputs ALBEDO and ignores EMISSION entirely — writing the
	// picture to EMISSION here gave a dead black panel. Over-drive the albedo
	// instead so the glow pass still picks the phosphor up.
	ALBEDO = col * 2.4;
}
