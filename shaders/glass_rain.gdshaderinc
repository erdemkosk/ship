// Shared rain-on-pane field. The expensive bead walk lives here so a small
// off-screen pass can bake it; the spatial glass shader only samples.
// Godot only includes .gdshaderinc — a .gdinc is not a ShaderInclude, so
// the preprocessor leaves the '#' for the tokenizer and the version is null.

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
	float rad = (0.09 + rad_span * (1.0 - roll)) * mix(0.32, 1.0, age);
	vec2 center = o + jit;
	float d = length(f - center);
	float body = smoothstep(rad, rad * 0.22, d) * age;
	float rim = smoothstep(rad * 1.14, rad * 0.86, d)
			* smoothstep(rad * 0.38, rad * 0.68, d) * age;
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
	return bead_cell(f, vec2(0.0), q, cover, chance, grow, 0.16);
}

// wet, rim, glint. Alpha stays 1 so a transparent bake does not eat the field.
// Wiper stays on the pane — it has to stay sharp.
vec4 rain_cover(vec2 pane, float rain, float t) {
	if (rain <= 0.004) {
		return vec4(0.0);
	}
	vec2 q = vec2(pane.x * 5.5, pane.y * 2.4);
	float sheet = gnoise(q);
	float rill_n = gnoise(vec2(pane.x * 17.0, pane.y * 5.0 - t * 0.010 * rain));
	float rill = smoothstep(0.52, 0.86, rill_n);
	float raw = sheet * 0.34 + rill * 0.42;
	float lo = mix(0.92, 0.18, rain);
	float wet = smoothstep(lo, lo + 0.38, raw);
	float grow = mix(0.18, 0.06, rain);
	vec4 fat = bead_layer(pane * 14.5 + vec2(4.7, 2.3), rain, 0.05 + rain * 0.20, grow + 0.03);
	vec4 fine = bead_fine(pane * 36.0, rain, 0.10 + rain * 0.38, grow);
	wet = max(wet, max(fine.x * 0.60, fat.x * 0.86));
	wet = max(wet, max(fine.w * 0.45, fat.w * 0.70));
	float rim = max(fine.y * 0.70, fat.y);
	float glint = max(fine.z * 0.55, fat.z);
	glint = max(glint, rill * rain * 0.14);
	glint = max(glint, fat.w * 0.12);
	return vec4(wet, rim, glint, 1.0);
}
