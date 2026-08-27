shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx, depth_draw_opaque;

// The paper chart on the wheelhouse table.
//
// It is drawn FROM THE SEABED HEIGHTMAP — the same RF texture the seafloor mesh
// and the shore foam read. So the coast on the paper is the coast in the water,
// to the metre, and it stays that way if the terrain is ever regenerated. No
// hand-drawn map to fall out of step with the world.
//
// Everything else is what a chart is made of: contours at the depths that
// matter, a wash over the shallows, soundings, a graticule, a compass rose, and
// enough foxing and coffee that it looks like it has been aboard a while. It is
// lit by the wheelhouse lamp like any other surface, because half of what makes
// a thing feel real is that the light in the room lands on it.

uniform sampler2D height_tex : filter_linear, repeat_enable;
uniform float base_depth = -28.0;
// Where the boat is, in chart UV, and which way her head is.
uniform vec2 boat_uv = vec2(0.5, 0.5);
uniform float boat_head = 0.0;
uniform vec3 paper : source_color = vec3(0.815, 0.752, 0.605);
uniform vec3 ink : source_color = vec3(0.140, 0.115, 0.095);
uniform vec3 land_col : source_color = vec3(0.795, 0.700, 0.470);
uniform vec3 mark_col : source_color = vec3(0.520, 0.110, 0.075);

float chash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float cnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(chash(i), chash(i + vec2(1.0, 0.0)), f.x),
			mix(chash(i + vec2(0.0, 1.0)), chash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float cfbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += cnoise(p) * a;
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// A line of constant screen width wherever `v` crosses `target`. Using fwidth
// keeps a contour the same thickness whether the bottom there is a cliff or a
// plain — draw it in metres instead and the flats turn into solid ink.
float iso(float v, float target, float w) {
	float aa = fwidth(v) + 1e-5;
	return 1.0 - smoothstep(w * aa, (w + 1.0) * aa, abs(v - target));
}

// Distance to a line of given angle through the rose centre, for the rays.
float ray(vec2 d, float ang, float len, float wide) {
	vec2 u = vec2(sin(ang), cos(ang));
	float along = dot(d, u);
	float off = abs(dot(d, vec2(u.y, -u.x)));
	if (along < 0.0 || along > len) {
		return 0.0;
	}
	return 1.0 - smoothstep(wide * 0.4, wide, off);
}

void fragment() {
	vec2 uv = UV;
	float h = texture(height_tex, uv).r;

	// --- the paper -----------------------------------------------------------
	float fib = cfbm(uv * 340.0) * 0.10 + cfbm(uv * 90.0) * 0.14;
	float stain = cfbm(uv * 5.0 + vec2(3.1, 7.7));
	vec3 col = paper * (0.90 + fib * 0.55);
	col = mix(col, paper * vec3(0.86, 0.76, 0.60), smoothstep(0.55, 0.95, stain) * 0.55);
	// Foxing: the little rust-coloured spots old paper gets.
	float fox = smoothstep(0.74, 0.93, cfbm(uv * 26.0 + vec2(11.0, 2.0)));
	col = mix(col, vec3(0.60, 0.45, 0.30), fox * 0.30);

	// --- the water -----------------------------------------------------------
	// Two washes: the drying-height line and the ten-metre line, the two a
	// coaster's skipper actually cares about.
	float shoal = 1.0 - smoothstep(-11.0, -3.0, h);
	col = mix(col, vec3(0.660, 0.720, 0.700), shoal * 0.26);
	float veryshoal = 1.0 - smoothstep(-4.0, -0.4, h);
	col = mix(col, vec3(0.700, 0.760, 0.690), veryshoal * 0.30);

	// Soundings: a stipple that thickens where it shoals, standing in for the
	// printed depth figures at this scale.
	vec2 sg = uv * 190.0;
	vec2 sc = floor(sg);
	vec2 sf = fract(sg) - vec2(chash(sc), chash(sc + vec2(5.0, 9.0)));
	float dot_r = 0.10 + 0.13 * clamp((h - base_depth) / 24.0, 0.0, 1.0);
	float sounding = (1.0 - smoothstep(dot_r * 0.6, dot_r, length(sf)))
			* step(chash(sc + vec2(31.0, 17.0)), 0.34)
			* step(h, -0.4);
	col = mix(col, ink, sounding * 0.30);

	// --- contours ------------------------------------------------------------
	float c = 0.0;
	c = max(c, iso(h, -22.0, 0.5) * 0.55);
	c = max(c, iso(h, -12.0, 0.7) * 0.75);
	c = max(c, iso(h, -5.0, 0.7) * 0.85);
	col = mix(col, ink, c * 0.62);

	// --- the land ------------------------------------------------------------
	float land = smoothstep(-0.35, 0.55, h);
	// Hachure-ish tint that darkens as the ground rises, so a headland reads as
	// high and a drying rock reads as flat.
	vec3 lc = mix(land_col, land_col * 0.72, clamp(h / 22.0, 0.0, 1.0));
	// Stipple over the land, the way land is filled on a paper chart.
	float hatch = smoothstep(0.52, 0.72, cnoise(uv * 620.0));
	lc = mix(lc, lc * 0.80, hatch * 0.5);
	col = mix(col, lc, land);
	// Coastline: the heaviest line on the sheet.
	col = mix(col, ink, iso(h, 0.0, 1.1) * 0.92);

	// --- graticule -----------------------------------------------------------
	vec2 g = abs(fract(uv * 8.0) - 0.5);
	vec2 gw = fwidth(uv * 8.0);
	float grid = max(1.0 - smoothstep(gw.x * 0.5, gw.x * 1.5, g.x),
			1.0 - smoothstep(gw.y * 0.5, gw.y * 1.5, g.y));
	col = mix(col, ink, grid * 0.13);

	// --- compass rose --------------------------------------------------------
	vec2 rc = uv - vec2(0.155, 0.815);
	float rr = length(rc);
	float rose = 0.0;
	float rw = fwidth(rr) * 1.4 + 1e-5;
	rose = max(rose, 1.0 - smoothstep(rw, rw * 2.4, abs(rr - 0.088)));
	rose = max(rose, 1.0 - smoothstep(rw, rw * 2.4, abs(rr - 0.070)));
	rose = max(rose, 1.0 - smoothstep(rw, rw * 2.4, abs(rr - 0.020)));
	if (rr < 0.095) {
		float rline = fwidth(rc.x) * 2.2;
		for (int i = 0; i < 8; i++) {
			float a = float(i) * 0.7853981634;
			float len = (i % 2 == 0) ? 0.088 : 0.070;
			rose = max(rose, ray(rc, a, len, rline * 2.2));
			rose = max(rose, ray(-rc, a, len, rline * 2.2));
		}
	}
	col = mix(col, ink, clamp(rose, 0.0, 1.0) * 0.80);
	// North arrow. It points toward v = 0, which is world -Z: the chart is laid
	// out in the world's frame, not the boat's, so the arrow stays put and the
	// boat turns under it. (It pointed south first time round — v grows aft.)
	if (rc.y < 0.0 && rc.y > -0.115 && abs(rc.x) < 0.010 * (1.0 + rc.y / 0.115)) {
		col = mix(col, mark_col, 0.88);
	}

	// --- where you are -------------------------------------------------------
	// A pencilled fix, drawn small: the brass pin standing on the paper is the
	// thing you actually read. This is what is under it.
	vec2 bd = uv - boat_uv;
	float br = length(bd);
	float bw = fwidth(br) * 1.5 + 1e-5;
	float fix = 1.0 - smoothstep(bw, bw * 2.6, abs(br - 0.0125));
	// Course line ahead of her, the way a fix is laid off.
	vec2 hd = vec2(sin(boat_head), -cos(boat_head));
	float ahead = dot(bd, hd);
	float side = abs(dot(bd, vec2(hd.y, -hd.x)));
	if (ahead > 0.012 && ahead < 0.095) {
		fix = max(fix, 1.0 - smoothstep(bw, bw * 2.2, side));
	}
	col = mix(col, mark_col, clamp(fix, 0.0, 1.0) * 0.90);

	// --- age ----------------------------------------------------------------
	// A coffee ring, and the corners darkened by every hand that ever held it.
	vec2 cf = uv - vec2(0.79, 0.24);
	float cr = length(cf * vec2(1.0, 1.08));
	col = mix(col, vec3(0.52, 0.40, 0.26),
			(1.0 - smoothstep(0.004, 0.012, abs(cr - 0.062))) * 0.22);
	vec2 e = abs(uv - 0.5) * 2.0;
	float edge = max(e.x, e.y);
	col *= 1.0 - smoothstep(0.72, 1.0, edge) * 0.34;

	ALBEDO = col;
	ROUGHNESS = 0.88;
	SPECULAR = 0.16;
	METALLIC = 0.0;
}
