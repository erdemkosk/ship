shader_type spatial;
render_mode cull_back;

// The face of an old digital dive watch.
//
// Everything on it is drawn procedurally — no font, no texture. Digits are
// real seven-segment geometry with the classic LCD slant, because that is the
// whole period look: a quartz movement from the eighties has exactly seven
// strokes per numeral and no more.
//
// It is a NEGATIVE display now: luminous green strokes on near-black glass,
// the layout of a first-generation dive computer — the kind of instrument
// that was sold on being readable at forty metres in silt, which is also
// exactly what a game needs from a watch the size of a thumbnail on screen.
// The digits carry their own light; the `glow` uniform only turns them up
// (underwater, after dark) and washes the panel faintly behind them.
//
// Age is in the details, all cheap: ghost traces where the off segments sit,
// contrast that wanders in patches, a slow whole-display sag, and hairline
// scratches across the glass that only catch against the light.

uniform float hours = 14.0;
uniform float minutes = 32.0;
uniform float tsec = 0.0;        // free-running clock: colon blink, sag
uniform float depth_m = 0.0;
uniform float press_bar = 1.01;
uniform float glow : hint_range(0.0, 1.0) = 0.0;   // night / underwater boost

const float ASPECT = 1.6;        // the quad is 0.032 x 0.020
const vec3 LCD_BG = vec3(0.024, 0.032, 0.028);
const vec3 GREEN = vec3(0.20, 1.00, 0.42);

// A(1) top, B(2) tr, C(4) br, D(8) bottom, E(16) bl, F(32) tl, G(64) middle.
const int MASKS[10] = {63, 6, 91, 79, 102, 109, 125, 7, 127, 111};

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 34.56);
	return fract(p.x * p.y);
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

float bar(vec2 p, vec2 c, vec2 h) {
	vec2 d = abs(p - c) - h;
	return smoothstep(0.065, -0.05, max(d.x, d.y));
}

// One cell, arbitrary segment mask — digits and the few letters 7-seg can do.
float seg7(vec2 p, int m) {
	p.x += (p.y - 0.5) * 0.10;   // the slant
	float a = 0.0;
	if ((m & 1) != 0) { a = max(a, bar(p, vec2(0.50, 0.94), vec2(0.31, 0.074))); }
	if ((m & 2) != 0) { a = max(a, bar(p, vec2(0.88, 0.71), vec2(0.074, 0.21))); }
	if ((m & 4) != 0) { a = max(a, bar(p, vec2(0.88, 0.25), vec2(0.074, 0.21))); }
	if ((m & 8) != 0) { a = max(a, bar(p, vec2(0.50, 0.02), vec2(0.31, 0.074))); }
	if ((m & 16) != 0) { a = max(a, bar(p, vec2(0.12, 0.25), vec2(0.074, 0.21))); }
	if ((m & 32) != 0) { a = max(a, bar(p, vec2(0.12, 0.71), vec2(0.074, 0.21))); }
	if ((m & 64) != 0) { a = max(a, bar(p, vec2(0.50, 0.48), vec2(0.31, 0.074))); }
	return a;
}

float slotm(vec2 uv, vec2 org, vec2 dsz, int m) {
	vec2 p = (uv - org) / dsz;
	if (p.x < -0.2 || p.x > 1.2 || p.y < -0.2 || p.y > 1.2) {
		return 0.0;
	}
	return seg7(p, m);
}

float slot(vec2 uv, vec2 org, vec2 dsz, int n) {
	return slotm(uv, org, dsz, MASKS[clamp(n, 0, 9)]);
}

float dotp(vec2 uv, vec2 c, float r) {
	vec2 d = (uv - c) * vec2(ASPECT, 1.0);
	return smoothstep(r, r * 0.4, length(d));
}

// Depth marker: a little arrow pointing down. Pressure: a gauge ring.
//
// The half-plane test this used to be had NO LOWER BOUND — every point below
// the apex satisfied it, so the "arrow" was an infinite wedge that filled the
// bottom-left of the display and swallowed the pressure row. Three planes, all
// of them closed.
float tri_down(vec2 uv, vec2 c, float s) {
	vec2 p = (uv - c) * vec2(ASPECT, 1.0) / s;
	float d = max(max(p.y - 0.42, -0.58 - p.y),
			abs(p.x) - (p.y + 0.58) * 0.52);
	return smoothstep(0.14, -0.14, d);
}

float ring(vec2 uv, vec2 c, float r) {
	vec2 d = (uv - c) * vec2(ASPECT, 1.0);
	return smoothstep(0.35, 0.0, abs(length(d) - r) / (r * 0.55));
}

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);   // y up

	float seg = 0.0;    // live strokes
	float gh = 0.0;     // every stroke, faint — where the off segments sleep

	// --- time, along the top -------------------------------------------------
	int hh = int(clamp(hours, 0.0, 23.0));
	int mm = int(clamp(minutes, 0.0, 59.0));
	vec2 tz = vec2(0.092, 0.190);
	float ty = 0.720;
	if (hh >= 10) {
		seg = max(seg, slot(uv, vec2(0.225, ty), tz, hh / 10));
	}
	gh = max(gh, slotm(uv, vec2(0.225, ty), tz, 127));
	seg = max(seg, slot(uv, vec2(0.343, ty), tz, hh % 10));
	gh = max(gh, slotm(uv, vec2(0.343, ty), tz, 127));
	// The colon carries the seconds: on for the first six tenths of each one.
	if (fract(tsec) < 0.6) {
		seg = max(seg, dotp(uv, vec2(0.487, ty + 0.050), 0.023));
		seg = max(seg, dotp(uv, vec2(0.487, ty + 0.135), 0.023));
	}
	seg = max(seg, slot(uv, vec2(0.532, ty), tz, mm / 10));
	gh = max(gh, slotm(uv, vec2(0.532, ty), tz, 127));
	seg = max(seg, slot(uv, vec2(0.650, ty), tz, mm % 10));
	gh = max(gh, slotm(uv, vec2(0.650, ty), tz, 127));

	// --- depth, big, the row this watch exists for --------------------------
	float dep = clamp(depth_m, 0.0, 99.9);
	vec2 dz = vec2(0.185, 0.360);
	float dy = 0.270;
	seg = max(seg, tri_down(uv, vec2(0.072, 0.460), 0.060));
	if (dep >= 9.95) {
		seg = max(seg, slot(uv, vec2(0.165, dy), dz, int(dep) / 10));
	}
	gh = max(gh, slotm(uv, vec2(0.165, dy), dz, 127));
	seg = max(seg, slot(uv, vec2(0.395, dy), dz, int(dep) % 10));
	gh = max(gh, slotm(uv, vec2(0.395, dy), dz, 127));
	seg = max(seg, dotp(uv, vec2(0.618, dy + 0.024), 0.027));
	seg = max(seg, slot(uv, vec2(0.655, dy + 0.030), vec2(0.150, 0.300), int(dep * 10.0) % 10));
	gh = max(gh, slotm(uv, vec2(0.655, dy + 0.030), vec2(0.150, 0.300), 127));

	// --- pressure, small, along the bottom, with "bAr" in the only letters a
	// --- seven-segment display has ever known how to make ------------------
	float pr = clamp(press_bar, 0.0, 9.99);
	vec2 pz = vec2(0.080, 0.165);
	float py = 0.042;
	seg = max(seg, ring(uv, vec2(0.078, 0.128), 0.032));
	seg = max(seg, slot(uv, vec2(0.150, py), pz, int(pr)));
	gh = max(gh, slotm(uv, vec2(0.150, py), pz, 127));
	seg = max(seg, dotp(uv, vec2(0.252, py + 0.016), 0.015));
	seg = max(seg, slot(uv, vec2(0.278, py), pz, int(pr * 10.0) % 10));
	gh = max(gh, slotm(uv, vec2(0.278, py), pz, 127));
	seg = max(seg, slot(uv, vec2(0.380, py), pz, int(pr * 100.0) % 10));
	gh = max(gh, slotm(uv, vec2(0.380, py), pz, 127));
	vec2 lz = vec2(0.062, 0.125);
	seg = max(seg, slotm(uv, vec2(0.560, py), lz, 124));   // b
	seg = max(seg, slotm(uv, vec2(0.640, py), lz, 119));   // A
	seg = max(seg, slotm(uv, vec2(0.720, py), lz, 80));    // r

	// --- the tired part -----------------------------------------------------
	// Contrast is patchy across the cell, and the whole display breathes a
	// few per cent on a slow cycle. Old crystals, old zebra strip.
	float tired = 0.86 + 0.14 * vnoise(uv * vec2(6.0, 4.0) + 2.7);
	float sag = 0.955 + 0.045 * sin(tsec * 0.31 + uv.x * 2.0);
	seg = clamp(seg * tired * sag, 0.0, 1.0);

	// Glass: corner shading, and two or three hairline scratches you only
	// catch against the light.
	float vig = 1.0 - 0.30 * smoothstep(0.35, 0.85,
			length((uv - 0.5) * vec2(1.15, 1.55)));
	float scr = vnoise(vec2(uv.x * 2.6 - uv.y * 1.8, uv.y * 42.0 + uv.x * 11.0));
	scr = smoothstep(0.955, 1.0, scr) * 0.30;

	vec3 col = LCD_BG * vig;
	col += GREEN * gh * 0.028;             // ghost traces, barely there
	col = mix(col, GREEN * 0.06, seg);     // the strokes' own body colour
	col += vec3(scr) * 0.35;

	// The crystal. A broad, soft reflection that slides across the glass as
	// you turn your wrist, riding the same scratches the display already has —
	// which is what tells the eye there is a sheet of glass in front of the
	// numbers rather than a screen printed on the case.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 vl = (vec3(0.0, 0.0, 1.0) * mat3(VIEW_MATRIX));
	float band = 1.0 - abs(uv.y - 0.5 - vl.y * 0.35 - vl.x * 0.10) * 3.2;
	band = clamp(band, 0.0, 1.0);
	col += vec3(0.13, 0.15, 0.16) * (0.20 + 0.80 * scr / 0.30) * band * band * 0.20;
	col += vec3(0.07, 0.085, 0.09) * fres * 0.7;

	ALBEDO = col;
	ROUGHNESS = mix(0.14, 0.34, scr / 0.30);
	SPECULAR = 0.6;
	METALLIC = 0.0;
	// The strokes carry their own light; glow only turns them up and lets a
	// faint wash bleed into the glass behind them.
	float lum = 0.55 + 0.65 * glow;
	EMISSION = GREEN * seg * lum + GREEN * 0.020 * glow * vig;
}
