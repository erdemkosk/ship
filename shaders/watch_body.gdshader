shader_type spatial;

// The case, bezel, lugs and strap of a watch that has been worn for years.
//
// One shader for all four, because they are all the same story told with
// different numbers: a moulded surface that is dull in the middle and worn
// through at every edge it has ever been knocked against. Nothing here is
// painted on by hand — the wear is derived from where the geometry IS.
//
//   edges     For a box, the two smaller of the three normalised local
//             coordinates sum to nearly zero in the middle of a face and to
//             nearly two at a corner. That number is the whole wear map: the
//             corners of a steel bezel go bright and bare, the corners of a
//             rubber strap go pale and chalky.
//   scuffs    Low-frequency blotches that lift the roughness in patches —
//             the difference between a moulding and a surface.
//   ribs      Strap only: the moulded ridges across the band, which are what
//             make a black rubber strap read as rubber at all rather than as
//             a black box.

uniform vec3 base_color : source_color = vec3(0.09, 0.095, 0.10);
uniform vec3 worn_color : source_color = vec3(0.42, 0.44, 0.46);
uniform vec3 half_size = vec3(0.018, 0.0155, 0.0058);
uniform float rough_base : hint_range(0.0, 1.0) = 0.62;
uniform float metal_base : hint_range(0.0, 1.0) = 0.0;
uniform float wear : hint_range(0.0, 2.0) = 1.0;
uniform float rib : hint_range(0.0, 1.0) = 0.0;
uniform float rib_freq = 420.0;
// How much the wear turns a surface metallic. Steel goes bright where it is
// rubbed bare; rubber does not, and letting it flared the strap into a band of
// zebra stripes wherever the light hit it edge-on.
uniform float metal_gain : hint_range(0.0, 1.0) = 0.65;

varying vec3 v_local;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 34.56);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x),
			mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec3 t = abs(v_local) / max(half_size, vec3(1e-5));
	// Sum of the two smaller ratios: 0 in the middle of a face, ~2 at a corner.
	float mx = max(t.x, max(t.y, t.z));
	float e = clamp(t.x + t.y + t.z - mx, 0.0, 2.0);
	float edge = smoothstep(0.70, 1.45, e);

	// Blotchy use across the faces, and a finer grain over the top of it.
	vec2 uv2 = v_local.xy * 620.0 + v_local.z * 210.0;
	float blot = vnoise(uv2 * 0.18);
	float grain = vnoise(uv2 * 1.4);
	float used = clamp(edge * wear + (blot - 0.55) * 0.55 * wear, 0.0, 1.0);

	vec3 col = mix(base_color, worn_color, used * 0.85);
	float rg = mix(rough_base, rough_base * 0.42, used);
	float mt = mix(metal_base, min(metal_base + metal_gain, 1.0), used);

	// Moulded ribs across the strap. They run along the band's short axis, so
	// the ridge line is the local X of a link — the arm's own direction.
	if (rib > 0.001) {
		float r = sin(v_local.y * rib_freq) * 0.5 + 0.5;
		r = pow(r, 1.6);
		// Subtle. Moulded rubber ribs are a texture you notice, not a pattern
		// you read; at high contrast they turn the band into a tank track.
		col *= 0.93 + 0.12 * r;
		// The ridges hold no more shine than the valleys — moulded rubber is
		// matte all over, and letting the peaks go glossy is what turned the
		// band into stripes of highlight at grazing angles.
		NORMAL_MAP = vec3(0.5, 0.5 + cos(v_local.y * rib_freq) * 0.14 * rib, 1.0);
		NORMAL_MAP_DEPTH = 0.32;
	}

	col *= 0.92 + 0.16 * grain;

	ALBEDO = col;
	ROUGHNESS = clamp(rg, 0.04, 1.0);
	METALLIC = mt;
	SPECULAR = 0.5;
}
