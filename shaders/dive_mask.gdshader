shader_type canvas_item;
render_mode unshaded, blend_mix;

// Inside of a dive mask, worn. Metro-style glass: a thick tempered lens you
// look THROUGH, not a vignette stamped on the picture. Dirt and salt live in
// the corners and never fully leave. Drops sit on both faces of the glass and
// bend what is behind them. Fog is still a threshold field that creeps from
// the cold skirt inward. The frame is silicone two centimetres from the eye,
// so it has no edge — only falloff, a metal lip, and light leaking through
// thin rubber.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float wear : hint_range(0.0, 1.0) = 0.0;
uniform float fog : hint_range(0.0, 1.0) = 0.0;
uniform float wipe : hint_range(0.0, 1.0) = 0.0;
uniform float wipe_x = 9.0;
uniform float wipe_dir = -1.0;
uniform float aspect = 1.78;
uniform float wave_time = 0.0;
uniform float underwater : hint_range(0.0, 1.0) = 0.0;
uniform float rain : hint_range(0.0, 1.0) = 0.0;
uniform float breath : hint_range(0.0, 1.0) = 0.0;
uniform float drops : hint_range(0.0, 1.0) = 0.0;
uniform float drop_wipe : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 34.56);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	float a = hash21(p);
	return vec2(a, hash21(p + vec2(19.19, 7.31)));
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
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, -0.9);
		a *= 0.51;
	}
	return v;
}

// Rounded mask opening: wide glass, wider on top, nose pocket lifting the
// bottom. Returns signed distance — negative inside the lens.
float mask_sd(vec2 p) {
	vec2 q = vec2(p.x / (1.0 + 0.118 * p.y), p.y);
	float d = length(max(abs(q) - vec2(0.705, 0.318), vec2(0.0))) - 0.138;
	float nose = length((q - vec2(0.0, -0.648)) * vec2(1.10, 0.76)) - 0.248;
	d = max(d, -nose);
	return d;
}

float finger_clear(vec2 p, float w) {
	if (w < 0.001) {
		return 1.0;
	}
	float front = wipe_x + sin(p.y * 7.3 + 1.1) * 0.038
			+ sin(p.y * 19.4) * 0.014;
	float cleared = smoothstep(front + 0.05 * wipe_dir, front - 0.17 * wipe_dir, p.x);
	float streak = 0.5 + 0.5 * sin(p.y * 61.0 + 1.7)
			* (0.55 + 0.45 * sin(p.y * 17.0 + 0.4));
	return mix(1.0, 0.08 + 0.16 * streak, cleared);
}

// One generation of beads. `layer` seeds a different population; `amount`
// is how many cells are occupied. Returns uv offset, rim highlight, and
// coverage so dirt/fog can sit under a drop.
void beads(vec2 uv, float time, float amount, float layer, float drip,
		out vec2 distort, out float highlight, out float cover) {
	distort = vec2(0.0);
	highlight = 0.0;
	cover = 0.0;
	if (amount < 0.01) {
		return;
	}
	vec2 grid_n = vec2(7.0, 5.0);
	vec2 cell = uv * grid_n;
	vec2 id0 = floor(cell);
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			vec2 id = id0 + vec2(float(ox), float(oy));
			vec2 rnd = hash22(id + layer * 17.3);
			float alive = step(rnd.x, amount * 0.72 + 0.08);
			vec2 f = rnd;
			f.y = fract(f.y + time * drip * (0.04 + rnd.x * 0.10) * alive);
			vec2 c = (id + f) / grid_n;
			vec2 dlt = (uv - c) * vec2(1.0, 1.22);
			float rad = mix(0.007, 0.020, hash21(id + 4.1 + layer));
			float dist = length(dlt);
			float inner = smoothstep(rad, rad * 0.22, dist);
			float rim = smoothstep(rad * 1.18, rad * 0.70, dist) * (1.0 - inner);
			vec2 dir = dlt / max(dist, 1e-4);
			distort += dir * inner * 0.018 * alive;
			highlight += rim * 0.55 * alive;
			cover = max(cover, inner * alive);
			float tail = smoothstep(0.004, 0.0, abs(uv.x - c.x))
					* smoothstep(0.0, 0.045, c.y - uv.y)
					* smoothstep(0.09, 0.015, c.y - uv.y);
			distort.y += tail * 0.007 * drip * alive;
			highlight += tail * 0.12 * alive;
		}
	}
}

void fragment() {
	vec2 uv = SCREEN_UV;
	if (wear < 0.001) {
		COLOR = vec4(texture(screen_texture, uv).rgb, 1.0);
		discard;
	}

	vec2 p = (uv - vec2(0.5)) * vec2(aspect, -1.0);
	float br = sin(wave_time * 1.15) * 0.5 + sin(wave_time * 0.41) * 0.5;
	p.y -= br * 0.0035;
	p *= 1.0 + breath * 0.004;

	float d = mask_sd(p);
	d += (fbm(p * 7.5 + vec2(1.2, 4.0)) - 0.5) * 0.016;
	float don = clamp(wear * 1.35, 0.0, 1.0);
	d -= (1.0 - don) * 0.55;
	float edge = smoothstep(-0.42, 0.02, d);
	float in_lens = 1.0 - smoothstep(-0.04, 0.05, d);

	vec2 r2 = uv - vec2(0.5);
	float rr = dot(r2, r2);
	// Thick tempered pane: barrel plus extra bend at the frame, where the
	// glass is seen on edge and the picture shears.
	float mag = 0.034 + underwater * 0.04 + edge * 0.085;
	vec2 luv = vec2(0.5) + r2 * (1.0 - mag);
	vec2 guv = vec2(0.5) + r2 * (1.0 - mag + 0.028 + edge * 0.04);

	float wet = drops * finger_clear(p, drop_wipe);
	wet = max(wet, drops * 0.16 * edge);
	vec2 d_out = vec2(0.0);
	float h_out = 0.0;
	float c_out = 0.0;
	beads(uv, wave_time, wet, 1.0, 0.55 + 0.45 * underwater, d_out, h_out, c_out);

	float bead_amt = clamp(fog * 0.90 + breath * 0.35, 0.0, 1.0) * (0.28 + 0.72 * edge);
	bead_amt *= finger_clear(p, wipe);
	vec2 d_in = vec2(0.0);
	float h_in = 0.0;
	float c_in = 0.0;
	beads(uv, wave_time * 0.15, bead_amt, 3.0, 0.12, d_in, h_in, c_in);

	luv += (d_out * 0.85 + d_in * 0.55) * in_lens;

	float f = 0.0;
	float sheet = 0.0;
	float amt = fog;
	if (fog > 0.002 || wipe > 0.001) {
		vec2 fp = p * 2.6 + vec2(0.0, wave_time * 0.008);
		float n = fbm(fp);
		float grain = fbm(p * 11.0 + vec2(4.3, 1.1));
		float thr = clamp(mix(0.92, 0.14, edge) - 0.20 * (n - 0.5)
				- 0.07 * (grain - 0.5), 0.02, 1.12);
		amt *= finger_clear(p, wipe);
		f = smoothstep(thr - 0.22, thr, amt + breath * 0.05);
		f *= 0.86 + 0.28 * (fbm(p * 6.0 + vec2(2.0, 8.0)) - 0.5);
		sheet = smoothstep(0.84, 1.02, amt);
		f = clamp(max(f, sheet), 0.0, 1.0);
	}

	// Wipe leaves a greasy film even after the fog is gone.
	float smear = 0.0;
	if (wipe > 0.001) {
		float front = wipe_x + sin(p.y * 8.0) * 0.03;
		float band = smoothstep(0.22, 0.0, abs(p.x - front));
		smear = band * wipe * (0.35 + 0.65 * vnoise(p * vec2(18.0, 90.0)));
	}

	float lod = f * (3.4 + 2.8 * sheet) + smear * 0.8;
	float ca = 0.0014 + 0.012 * rr + edge * 0.010;
	vec3 col;
	col.r = texture(screen_texture, vec2(0.5) + (luv - vec2(0.5)) * (1.0 + ca), lod).r;
	col.g = texture(screen_texture, luv, lod).g;
	col.b = texture(screen_texture, vec2(0.5) + (luv - vec2(0.5)) * (1.0 - ca), lod).b;
	vec3 ghost = texture(screen_texture, clamp(guv, vec2(0.001), vec2(0.999)), lod + 0.4).rgb;

	if (f > 0.002) {
		vec3 wide = texture(screen_texture, luv, 5.0 + 2.4 * sheet).rgb;
		col = mix(col, wide, f * 0.58);
		vec3 flat_grey = vec3(dot(col, vec3(0.299, 0.587, 0.114)));
		col = mix(col, flat_grey, f * 0.58);
		col = mix(col, vec3(0.70, 0.74, 0.76), f * (0.28 + 0.48 * sheet));
		float lum = dot(wide, vec3(0.299, 0.587, 0.114));
		col += vec3(0.58, 0.62, 0.64) * smoothstep(0.22, 1.0, lum) * f * 0.34;
	}

	// Old tempered glass is not colourless.
	col *= vec3(0.96, 0.98, 0.97);
	col = mix(col, col * vec3(0.93, 0.96, 0.94), edge * 0.35);

	float scene_lum = dot(col, vec3(0.299, 0.587, 0.114));

	// Salt film and fingerprints — they live in the corners and survive a wipe.
	float dirt = fbm(p * 4.2 + vec2(2.2, 8.0));
	float prints = vnoise(p * vec2(7.0, 11.0) + 3.7);
	float corner = smoothstep(0.12, 0.55, edge);
	float film = clamp(dirt * 0.45 + prints * 0.25, 0.0, 1.0) * corner * 0.55;
	film *= 1.0 - c_in * 0.4;
	col = mix(col, col * vec3(0.72, 0.74, 0.70) + vec3(0.03, 0.03, 0.02), film);

	// Scratches catch only what is already bright.
	float scr = vnoise(p * vec2(1.8, 52.0) + vec2(4.0, 0.0));
	scr = smoothstep(0.91, 1.0, scr) * smoothstep(0.32, 0.0, abs(d + 0.14));
	float chip = vnoise(p * 18.0 + 9.0);
	chip = smoothstep(0.97, 1.0, chip) * smoothstep(0.20, 0.0, abs(d + 0.08));
	col += vec3(0.07, 0.075, 0.08) * (scr * 0.9 + chip) * scene_lum;

	col += vec3(0.22, 0.26, 0.28) * (h_out * 0.55 + h_in * 0.40) * in_lens
			* (0.25 + 0.75 * scene_lum);

	// Standing water in the skirt. Surface lifts with the breath.
	float pool_y = -0.355 + br * 0.014;
	float pool = smoothstep(-0.055, -0.002, d) * smoothstep(-0.08, pool_y, p.y);
	float meniscus = smoothstep(0.018, 0.0, abs(p.y - pool_y)) * pool;
	col = mix(col, col * vec3(0.58, 0.80, 0.92) + vec3(0.012, 0.04, 0.055),
			pool * (0.42 + 0.38 * underwater));
	col += vec3(0.18, 0.22, 0.24) * meniscus * 0.35 * scene_lum;

	// Thick-glass Fresnel and the inner face ghost — this is how you know
	// there is a pane, not a hole cut in a HUD.
	float fres = pow(clamp(edge, 0.0, 1.0), 1.35);
	col = mix(col, col * 0.82 + ghost * 0.22, fres * 0.55);
	col *= vec3(0.96, 0.985, 0.97);
	float pane = smoothstep(0.038, 0.0, abs(d + 0.012));
	col += vec3(0.18, 0.22, 0.20) * pane * (0.12 + 0.65 * scene_lum);

	// --- skirt: silicone two centimetres from the eye, no hard edge ----------
	float metal = smoothstep(0.022, 0.0, abs(d + 0.004));
	float metal_spec = pow(max(0.12 + 0.88 * scene_lum, 0.0), 1.8);
	col += vec3(0.38, 0.37, 0.34) * metal * metal_spec * 0.55;

	float pen = smoothstep(-0.40, 0.10, d);
	float core = smoothstep(-0.10, 0.16, d);
	col *= 1.0 - pen * 0.70;
	vec3 rubber = vec3(0.018, 0.016, 0.017);
	float leak = smoothstep(0.12, -0.04, d) * smoothstep(-0.28, -0.02, d);
	rubber += vec3(0.09, 0.04, 0.025) * leak * (0.20 + 0.80 * scene_lum);
	col = mix(col, rubber, core * core);

	float lip = smoothstep(0.040, 0.0, abs(d + 0.008));
	col += vec3(0.22, 0.26, 0.27) * lip * (0.04 + 0.50 * scene_lum);

	float crease = smoothstep(0.06, 0.0, abs(d + 0.03));
	col = mix(col, col * vec3(0.58, 0.55, 0.50), crease * 0.22 * (1.0 - core));

	float dark = smoothstep(0.06, 0.42, wear) * smoothstep(0.94, 0.52, wear);
	col *= 1.0 - dark * 0.94;

	COLOR = vec4(col, 1.0);
}
