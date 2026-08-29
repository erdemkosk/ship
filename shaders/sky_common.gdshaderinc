// Procedural sky, shared between the sky shader and the water shader.
//
// The whole point of putting it here: the sea reflects THIS sky. Before, the
// water faked it with a single flat `horizon_color`, which is why it read as a
// painted plastic sheet. Everything is driven from scripts/weather.gd, which
// pushes the same uniform set to the sky material and to every ocean material.
#ifndef SKY_COMMON_INC
#define SKY_COMMON_INC

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.8);
uniform float sun_energy = 1.0;
uniform float sun_size = 0.0015;

uniform vec3 top_color : source_color = vec3(0.10, 0.15, 0.25);
uniform vec3 horizon_color : source_color = vec3(0.30, 0.30, 0.30);
uniform vec3 ground_color : source_color = vec3(0.008, 0.010, 0.014);

uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.6;
uniform float cloud_density : hint_range(0.5, 2.0) = 1.0;
uniform vec2 cloud_offset = vec2(0.0);
uniform float cloud_time = 0.0;
uniform vec3 cloud_lit_color : source_color = vec3(0.50, 0.50, 0.52);
uniform vec3 cloud_dark_color : source_color = vec3(0.12, 0.13, 0.14);

uniform float star_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float flash_energy = 0.0;
uniform vec3 flash_dir = vec3(0.0, 1.0, 0.0);
uniform float flash_lobe = 0.0;

vec3 sky_flash_add(vec3 dir, float shade) {
	float lobe = pow(max(dot(normalize(dir), normalize(flash_dir)), 0.0), 7.0);
	lobe *= smoothstep(-0.02, 0.20, dir.y);
	return vec3(0.78, 0.84, 1.0)
			* (flash_energy * (0.28 + 0.22 * shade) + flash_lobe * lobe * 1.2);
}

float sky_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float sky_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = sky_hash12(i);
	float b = sky_hash12(i + vec2(1.0, 0.0));
	float c = sky_hash12(i + vec2(0.0, 1.0));
	float d = sky_hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float sky_fbm(vec2 p, int octaves) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < octaves; i++) {
		v += amp * sky_vnoise(p);
		p = p * 2.13 + vec2(11.3);
		amp *= 0.5;
	}
	return v;
}

// Coverage 0 is a clear sky. The old thresholds still spawned a deck at 0
// because FBM sits around 0.5 and the floor was 0.52.
float sky_cloud_mask(float n, float coverage, float lo0, float hi0, float lo1, float hi1) {
	float c = clamp(coverage, 0.0, 1.0);
	float lo = mix(lo0, lo1, c);
	float hi = mix(hi0, hi1, c);
	return smoothstep(lo, hi, n) * smoothstep(0.0, 0.06, c);
}

// blur: 0 = mirror (sky dome / calm water), 1 = fully diffuse (rough water).
// Rough reflections lose cloud detail and the sun disk long before they lose
// the overall luminance — that's what the blur term models.
// disk_mul: scales the hard sun disk. The water passes 0 here, because Godot's
// own GGX specular already paints the sun glitter; drawing it twice blows out.
// layers: 2 draws a second, lower cloud deck that slides against the first as
// you turn — the parallax that stops a planar FBM reading as a painted ceiling.
// The water passes 1: its reflection is blurred anyway, and sky_color is the
// most expensive thing the sea shader does.
vec3 sky_color_n(vec3 dir, float blur, float disk_mul, int layers) {
	float sharp = 1.0 - blur;
	int oct = blur > 0.55 ? 3 : 5;

	float t = pow(clamp(dir.y, 0.0, 1.0), 0.5);
	vec3 col = mix(horizon_color, top_color, t);

	float sd = dot(dir, sun_dir);

	// --- clouds (planar projection of warped FBM) ---
	vec2 uv = dir.xz / max(dir.y, 0.06) * 0.32 + cloud_offset;
	float warp = sky_fbm(uv * 2.3 + vec2(cloud_time * 0.015, 0.0), oct);
	float n = sky_fbm(uv * 1.15 + warp * 0.4, oct);
	float m = sky_cloud_mask(n, cloud_coverage, 1.08, 1.18, 0.06, 0.52);
	m *= smoothstep(0.015, 0.14, dir.y);
	m = mix(m, cloud_coverage * 0.8 * smoothstep(0.015, 0.22, dir.y), blur * 0.75);

	float m_low = 0.0;
	vec3 low_col = vec3(0.0);
	if (layers > 1) {
		vec2 uvl = dir.xz / max(dir.y, 0.06) * 0.72 + cloud_offset * 2.1;
		float wl = sky_fbm(uvl * 1.9 + vec2(cloud_time * 0.026, 0.0), 3);
		float nl = sky_fbm(uvl * 0.85 + wl * 0.5, 4);
		m_low = sky_cloud_mask(nl, cloud_coverage, 1.06, 1.16, 0.18, 0.68);
		m_low *= smoothstep(0.02, 0.22, dir.y) * 0.75;
		low_col = mix(cloud_lit_color, cloud_dark_color, clamp(nl * cloud_density, 0.0, 1.0)) * 0.85;
		low_col += sky_flash_add(dir, clamp(nl * cloud_density, 0.0, 1.0));
	}

	// --- stars (fade behind clouds / daylight) ---
	if (star_intensity > 0.001 && dir.y > 0.02 && sharp > 0.35) {
		vec2 sp = dir.xz / (dir.y + 0.35) * 26.0;
		vec2 cell = floor(sp);
		float h = sky_hash12(cell);
		// Off-centre in the cell and unevenly bright, or the sky is graph paper.
		vec2 off = vec2(sky_hash12(cell + 1.3), sky_hash12(cell + 7.7)) - 0.5;
		vec2 cp = fract(sp) - 0.5 - off * 0.85;
		float mag = pow(sky_hash12(cell + 3.1), 5.0);
		float star = step(0.955, h) * smoothstep(0.11, 0.012, length(cp))
				* (0.18 + mag * 3.2);
		col += vec3(0.7, 0.75, 0.85) * star * star_intensity * (1.0 - m) * sharp;
	}

	// --- sun / moon disk + glow, occluded by clouds ---
	float occl = 1.0 - m * 0.92;
	float disk = smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.4, sd);
	float glow = pow(max(sd, 0.0), mix(32.0, 8.0, blur)) * 0.6 + pow(max(sd, 0.0), 7.0) * 0.10;
	col += sun_color * (disk * 1.6 * disk_mul + glow) * sun_energy * occl;

	// --- cloud shading ---
	float shade = clamp(sky_fbm(uv * 2.6 - warp * 0.3, oct), 0.0, 1.0);
	shade = mix(shade, 0.5, blur * 0.7);
	vec3 cloud_col = mix(cloud_lit_color, cloud_dark_color, clamp(shade * cloud_density, 0.0, 1.0));
	float rim = pow(max(sd, 0.0), 5.0) * 0.4 * (1.0 - shade);
	cloud_col += sun_color * rim * sun_energy * 0.8;
	cloud_col += sky_flash_add(dir, shade);

	if (layers > 1) {
		col = mix(col, low_col, m_low * 0.9);
	}
	col = mix(col, cloud_col, m * 0.96);
	col += vec3(0.62, 0.68, 0.95) * flash_energy * 0.08;
	return col;
}

// What the sea reflects. The dome version runs three 5-octave FBMs per pixel;
// the sea covers most of the screen and its reflection is blurred by the wave
// slope anyway, so it gets one 3-octave FBM, no domain warp, and reuses that
// same noise for the cloud shading. Measured as the single most expensive thing
// in the water shader.
vec3 sky_color(vec3 dir, float blur, float disk_mul) {
	float t = pow(clamp(dir.y, 0.0, 1.0), 0.5);
	vec3 col = mix(horizon_color, top_color, t);
	float sd = dot(dir, sun_dir);

	vec2 uv = dir.xz / max(dir.y, 0.06) * 0.32 + cloud_offset;
	float n = sky_fbm(uv * 1.15, 3);
	float m = sky_cloud_mask(n, cloud_coverage, 1.08, 1.18, 0.06, 0.52);
	m *= smoothstep(0.015, 0.14, dir.y);
	m = mix(m, cloud_coverage * 0.8 * smoothstep(0.015, 0.22, dir.y), blur * 0.75);

	float occl = 1.0 - m * 0.92;
	float glow = pow(max(sd, 0.0), mix(32.0, 8.0, blur)) * 0.6 + pow(max(sd, 0.0), 7.0) * 0.10;
	float disk = smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.4, sd);
	col += sun_color * (disk * 1.6 * disk_mul + glow) * sun_energy * occl;

	float shade = mix(clamp(n, 0.0, 1.0), 0.5, blur * 0.7);
	vec3 cloud_col = mix(cloud_lit_color, cloud_dark_color, clamp(shade * cloud_density, 0.0, 1.0));
	cloud_col += sun_color * pow(max(sd, 0.0), 5.0) * 0.4 * (1.0 - shade) * sun_energy * 0.8;
	cloud_col += sky_flash_add(dir, shade);

	col = mix(col, cloud_col, m * 0.96);
	col += vec3(0.62, 0.68, 0.95) * flash_energy * 0.08;
	return col;
}

#endif
