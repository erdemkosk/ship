shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

// Wheelhouse glass.
//
// Real clear glass is ALMOST NOT THERE: it passes ~92% of the light straight
// through. So this pane is plain low-alpha geometry — no screen-texture trick,
// no refraction offset, nothing that could blur or tint the view. What sells it
// as glass is the little that remains: a hard Fresnel sheen when the light
// rakes across it, a tight specular highlight, and a faint film of salt that
// thickens toward the pane's corners.

uniform vec4 tint : source_color = vec4(0.13, 0.16, 0.17, 1.0);
uniform float grime : hint_range(0.0, 1.0) = 0.10;
uniform float clarity : hint_range(0.0, 1.0) = 0.95;
// Rain running down the pane, pushed from weather via boat.gd.
uniform float rain : hint_range(0.0, 1.0) = 0.0;
// The front pane only: a wiper sweeping about a pivot at the bottom centre.
uniform int has_wiper = 0;
uniform int wiper_on = 0;
uniform float wiper_ang = 0.0;
// The sweep's PHASE, monotonically increasing. From it the shader works out how
// long ago the arm passed any given point on the pane, which is what lets the
// water grow back behind it instead of the fan being on or off.
uniform float wiper_phase = 0.0;
uniform float wiper_rate = 2.6;

varying vec3 v_world;
varying vec2 v_pane;

float ghash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Beads: a jittered grid, one droplet per cell, round and of varying size.
// Value noise thresholded gives blobs with soft shoulders — this gives DROPS,
// with an edge, which is the whole difference between "wet-looking" and "water".
float beads(vec2 p, float density) {
	vec2 q = floor(p);
	vec2 f = p - q;
	float best = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 c = q + o;
			float roll = ghash(c + vec2(11.3, 91.7));
			if (roll > density) { continue; }
			vec2 jit = vec2(ghash(c), ghash(c + vec2(37.1, 17.9)));
			// Bigger drops are rarer, and they sit lower — they have run.
			float rad = 0.13 + 0.24 * (1.0 - roll / max(density, 1e-3));
			float d = length(f - o - jit);
			best = max(best, smoothstep(rad, rad * 0.30, d));
		}
	}
	return best;
}

float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(ghash(i), ghash(i + vec2(1.0, 0.0)), f.x),
			mix(ghash(i + vec2(0.0, 1.0)), ghash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Pane-local coordinates: the pane is a thin box, so drop the thin axis and
	// keep the two that span the glass. Everything drawn ON the glass — salt,
	// rain, the wiper's arc — is anchored to these and NOT to world space.
	// Anchored to the world, the whole pattern slid across the pane as she made
	// way: water that stayed put while the boat went out from under it.
	vec3 an = abs(NORMAL);
	if (an.x > an.y && an.x > an.z) {
		v_pane = VERTEX.zy;
	} else if (an.z >= an.x && an.z > an.y) {
		v_pane = VERTEX.xy;
	} else {
		v_pane = VERTEX.xz;
	}
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float ndv = clamp(abs(dot(n, normalize(VIEW))), 1e-3, 1.0);
	// Schlick for glass (n = 1.5 -> F0 = 0.04).
	float fres = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);

	// Salt film, streaked by rain running down the pane. Pane coordinates, so
	// it stays on the glass where it dried.
	vec2 gp = v_pane * 4.5;
	float dirt = gnoise(gp) * 0.55 + gnoise(gp * 3.7) * 0.45;
	float streak = gnoise(vec2(v_pane.x * 18.0, v_pane.y * 1.2));
	float film = clamp(mix(dirt, streak, 0.35) * grime, 0.0, 1.0);

	// --- rain on the glass ---------------------------------------------------
	// Columns of water crawling downward: the same streak noise, but marching
	// with time. Heavy rain sheets the whole pane.
	float wet = 0.0;
	if (rain > 0.005) {
		// Water on glass is three things at once, and all of it is STILL:
		// broad sheets that have already run, fine rivulets inside them, and
		// beads that cling exactly where they landed. Scrolling any of it with
		// TIME turns the pane into a texture sliding past — the one thing water
		// on glass never does. A bead stays put until something jars it loose,
		// and the wiper is the something.
		vec2 q = vec2(v_pane.x * 5.5, v_pane.y * 2.4);
		float sheet = gnoise(q);
		float rill = gnoise(vec2(v_pane.x * 17.0, v_pane.y * 5.0));
		rill = smoothstep(0.52, 0.86, rill);
		// Two populations: a scatter of small drops everywhere, and a sparser
		// set of fat ones. Density grows with the rain, so a shower is beads on
		// clear glass and a storm is beads inside running water.
		float fine = beads(v_pane * 34.0, 0.07 + rain * 0.33);
		float fat = beads(v_pane * 15.0 + vec2(4.7, 2.3), 0.04 + rain * 0.19);
		float raw = sheet * 0.34 + rill * 0.42;
		// Threshold, not brightness: scaling the field just dims the pane,
		// moving a threshold across it puts more water on it, and keeps the
		// wet/dry edge hard.
		float lo = mix(0.92, 0.20, rain);
		wet = smoothstep(lo, lo + 0.40, raw);
		wet = max(wet, max(fine * 0.60, fat * 0.86));

		// The wiper clears a fan below its arm; everything it sweeps stays
		// almost dry while it runs. Which is the point of the whole exercise:
		// without the wiper the pane is barely worth looking through.
		if (has_wiper == 1 && wiper_on == 1) {
			vec2 rel = vec2(v_pane.x, v_pane.y + 0.72);
			float r = length(rel);
			float ang = atan(rel.x, rel.y);
			if (r < 1.12 && abs(ang) < 1.15) {
				// HOW LONG AGO the blade passed here. The arm is at
				// 1.02*sin(phase), so it crosses a point at angle `ang` twice a
				// cycle; take whichever crossing was more recent. This is the
				// whole effect: the glass behind the blade is clear and fills
				// back in over a second or two, instead of a fan that is simply
				// on or off.
				float sN = clamp(ang / 1.02, -1.0, 1.0);
				float a1 = asin(sN);
				float pc = mod(wiper_phase, TAU);
				float d1 = mod(pc - mod(a1, TAU), TAU);
				float d2 = mod(pc - mod(PI - a1, TAU), TAU);
				float since = min(d1, d2) / max(wiper_rate, 1e-3);

				// Heavier rain refills faster — in a real squall the blade is
				// losing the argument before it reaches the other side.
				float refill = mix(5.0, 1.1, rain);
				float back = smoothstep(0.0, refill, since);
				// Never quite dry: a wiped pane keeps a smeared film.
				wet *= mix(0.05, 1.0, back);
				// The blade pushes a bow wave ahead of itself.
				float bow = smoothstep(0.16, 0.02, abs(ang - wiper_ang));
				wet = max(wet, bow * 0.55 * rain);
			}
		}

		// Wet glass is BUMPY, and that is what actually reads as water — far
		// more than tinting the pane. The bump only bends the highlight (there
		// is no refraction here by design), so every lamp aboard smears across
		// the running water instead of staying a clean point.
		// A whisper of surface relief, and no more. Cranked up it smeared every
		// lamp aboard across the running water, which looked spectacular for
		// about four seconds and then made the wheelhouse unbearable.
		float gx = gnoise(vec2(q.x + 0.30, q.y)) - sheet;
		float gy = gnoise(vec2(q.x, q.y + 0.30)) - sheet;
		n = normalize(n + (TANGENT * gx + BINORMAL * gy) * wet * 0.35);
	}

	NORMAL = n;
	// The water is its OWN surface, not a darkening of the glass. A film of
	// water scatters — it is pale and it catches the cabin lamp, which is
	// exactly why you cannot see out through a wet windscreen at night.
	ALBEDO = mix(tint.rgb, vec3(0.33, 0.37, 0.40), wet);
	// Reflection is kept DELIBERATELY LOW. A pane that mirrors properly also
	// mirrors the sea, and the sea never stops moving: standing at the helm you
	// got a second, swimming, upside-down ocean sliding across the glass in
	// front of the real one. Physically right, and genuinely sickening. So the
	// Fresnel barely reaches the alpha, the specular is a fraction of glass's
	// true value, and the surface is left rough enough that whatever it does
	// catch arrives as a soft glow rather than a picture.
	// Water carries the opacity; Fresnel barely contributes. That is the whole
	// trick: a pane you cannot see through in a storm, that does NOT swim
	// about as she rolls, because nothing here depends on the view angle.
	ALPHA = clamp((1.0 - clarity) + fres * 0.08 + film * 0.18 + wet * 0.64, 0.02, 0.80);
	METALLIC = 0.0;
	SPECULAR = 0.22;
	ROUGHNESS = mix(0.30, 0.62, max(film, wet * 0.85));
}
