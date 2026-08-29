shader_type spatial;
// cull_back, not cull_disabled: a thin box already has an inward face and an
// outward face. Drawing both sides of each meant the windscreen shaded twice
// — the whole view, every pixel — the moment you looked out in the rain.
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Wheelhouse glass.
//
// Real clear glass is ALMOST NOT THERE: it passes ~92% of the light straight
// through. So this pane is plain low-alpha geometry — no screen-texture trick,
// no refraction offset, nothing that could blur or tint the view. What sells it
// as glass is the little that remains: a hard Fresnel sheen when the light
// rakes across it, a tight specular highlight, and a faint film of salt that
// thickens toward the pane's corners.
//
// Rain is water, not dirt. A drop is a meniscus and a glint; a rivulet is a
// thin bright thread. The pane stays a window. Coverage is driven by `rain`,
// which boat.gd eases in at a rate that follows the rain: a drizzle takes
// its time, a downpour sheets the pane in seconds. Bead, then trail, then
// a sheet you still see through.

uniform vec4 tint : source_color = vec4(0.13, 0.16, 0.17, 1.0);
uniform float grime : hint_range(0.0, 1.0) = 0.10;
uniform float clarity : hint_range(0.0, 1.0) = 0.95;
// How long the pane has been taking rain, eased in from weather via boat.gd.
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

float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(ghash(i), ghash(i + vec2(1.0, 0.0)), f.x),
			mix(ghash(i + vec2(0.0, 1.0)), ghash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// One cell of a jittered drop field. Fat beads walk the 3x3 neighbourhood
// because a big drop can sit on a seam. Fine beads stay inside their cell
// (smaller radius) so one tap is enough — same meniscus and glint, not a
// noise speckle, and not eighteen extra cells per pixel.
vec4 bead_cell(vec2 f, vec2 o, vec2 c, float cover, float chance, float grow, float rad_span) {
	float roll = ghash(c + vec2(11.3, 91.7));
	if (roll > chance) {
		return vec4(0.0);
	}
	float land = roll / max(chance, 1e-3);
	float age = clamp((cover - land * 0.90) / grow, 0.0, 1.0);
	if (age <= 0.001) {
		return vec4(0.0);
	}
	vec2 jit = vec2(ghash(c), ghash(c + vec2(37.1, 17.9)));
	// Bigger drops are rarer, and they sit lower — they have run.
	float rad = (0.09 + rad_span * (1.0 - roll)) * mix(0.32, 1.0, age);
	vec2 center = o + jit;
	float d = length(f - center);
	float body = smoothstep(rad, rad * 0.22, d) * age;
	// Meniscus: the thin dark ring that makes a drop a drop, not a stain.
	float rim = smoothstep(rad * 1.14, rad * 0.86, d)
			* smoothstep(rad * 0.38, rad * 0.68, d) * age;
	// Sky-side glint. Emission, not a reflection probe — a probe would
	// put a second ocean on the pane, which is physically right and
	// genuinely sickening at the helm.
	vec2 hl = center + vec2(-0.15, 0.24) * rad;
	float glint = smoothstep(rad * 0.30, 0.0, length(f - hl)) * age;
	float runner = step(0.58, ghash(c + vec2(5.5, 2.2)));
	float below = center.y - f.y;
	float trail = runner * smoothstep(0.28, 0.80, age)
			* smoothstep(0.038, 0.0, abs(f.x - center.x))
			* smoothstep(0.0, 0.03, below)
			* smoothstep(0.42 + 0.55 * roll, 0.06, below);
	return vec4(body, rim, glint, trail);
}

vec4 bead_layer(vec2 p, float cover, float chance, float grow) {
	vec2 q = floor(p);
	vec2 f = p - q;
	vec4 acc = vec4(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			acc = max(acc, bead_cell(f, o, q + o, cover, chance, grow, 0.23));
		}
	}
	return acc;
}

vec4 bead_fine(vec2 p, float cover, float chance, float grow) {
	vec2 q = floor(p);
	vec2 f = p - q;
	// Radius stays under ~0.27 so the drop never needs a neighbour cell.
	return bead_cell(f, vec2(0.0), q, cover, chance, grow, 0.16);
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

	// Salt film, streaked by rain that dried. Pane coordinates, so it stays
	// on the glass where it dried.
	vec2 gp = v_pane * 4.5;
	float dirt = gnoise(gp) * 0.55 + gnoise(gp * 3.7) * 0.45;
	float streak = gnoise(vec2(v_pane.x * 18.0, v_pane.y * 1.2));
	float film = clamp(mix(dirt, streak, 0.35) * grime, 0.0, 1.0);

	float wet = 0.0;
	float rim = 0.0;
	float glint = 0.0;
	if (rain > 0.004) {
		// Coverage first. Isolated beads on an otherwise dry pane read as a
		// wiped window — the wiper's job. A threshold walks across the sheet
		// field as rain rises, so a drizzle is open glass with a few drops
		// and a downpour is water you cannot see through.
		vec2 q = vec2(v_pane.x * 5.5, v_pane.y * 2.4);
		float sheet = gnoise(q);
		float rill_n = gnoise(vec2(v_pane.x * 17.0, v_pane.y * 5.0 - TIME * 0.010 * rain));
		float rill = smoothstep(0.52, 0.86, rill_n);
		float raw = sheet * 0.34 + rill * 0.42;
		float lo = mix(0.92, 0.18, rain);
		wet = smoothstep(lo, lo + 0.38, raw);

		// Fat beads walk neighbours. Fine beads are one cell: still a
		// meniscus and a glint, not the noise speckle that read as dirt.
		float grow = mix(0.18, 0.06, rain);
		vec4 fat = bead_layer(v_pane * 14.5 + vec2(4.7, 2.3), rain, 0.05 + rain * 0.20, grow + 0.03);
		vec4 fine = bead_fine(v_pane * 36.0, rain, 0.10 + rain * 0.38, grow);
		wet = max(wet, max(fine.x * 0.60, fat.x * 0.86));
		wet = max(wet, max(fine.w * 0.45, fat.w * 0.70));
		rim = max(fine.y * 0.70, fat.y);
		glint = max(fine.z * 0.55, fat.z);
		glint = max(glint, rill * rain * 0.14);
		glint = max(glint, fat.w * 0.12);

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
				rim *= mix(0.04, 1.0, back);
				glint *= mix(0.02, 1.0, back);
				// The blade pushes a bow wave ahead of itself.
				float bow = smoothstep(0.16, 0.02, abs(ang - wiper_ang));
				wet = max(wet, bow * 0.40 * rain);
				glint = max(glint, bow * 0.22 * rain);
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
		n = normalize(n + (TANGENT * gx + BINORMAL * gy) * wet * 0.22);
	}

	NORMAL = n;
	// Water is its own surface. Cool, a little pale — not the grey-brown
	// that read as mud, and not the empty pane that read as already wiped.
	ALBEDO = mix(tint.rgb, vec3(0.28, 0.33, 0.36), wet);
	// Reflection is kept DELIBERATELY LOW. A pane that mirrors properly also
	// mirrors the sea, and the sea never stops moving: standing at the helm you
	// got a second, swimming, upside-down ocean sliding across the glass in
	// front of the real one. Physically right, and genuinely sickening. So the
	// Fresnel barely reaches the alpha, the specular is a fraction of glass's
	// true value, and the surface is left rough enough that whatever it does
	// catch arrives as a soft glow rather than a picture.
	// Water carries the opacity. In a storm the pane is a veil until the
	// blade has been past. The pane does NOT swim about as she rolls,
	// because nothing here depends on the view angle.
	ALPHA = clamp((1.0 - clarity) + fres * 0.08 + film * 0.16
			+ wet * 0.64 + rim * 0.10, 0.02, 0.80);
	METALLIC = 0.0;
	SPECULAR = mix(0.22, 0.42, wet);
	// Wet glass is glossier than dry, not duller. Salt film is the matte part.
	ROUGHNESS = mix(0.26, 0.16, wet);
	ROUGHNESS = mix(ROUGHNESS, 0.58, film * 0.55);
	// The glint is emission so a drop still catches the cabin lamp at night
	// without borrowing a reflection of the sea.
	EMISSION = vec3(0.34, 0.39, 0.44) * glint * (0.28 + 0.55 * rain);
}
