// Shared Gerstner wave field.
//
// Included by ocean.gdshader (surface) and seabed.gdshader (caustics) so both
// see exactly the same water. The CPU mirror lives in scripts/ocean.gd
// (_displace / jacobian) — if you change the maths here, change it there too,
// or the boat stops floating on the wave you can see.
#ifndef WAVE_COMMON_INC
#define WAVE_COMMON_INC

const int MAX_WAVES = 48;

uniform int num_waves = 0;
uniform vec4 waves[MAX_WAVES]; // xy: direction, z: amplitude, w: k (2*PI/wavelength)
uniform float omegas[MAX_WAVES];
uniform float wave_time = 0.0;
uniform float choppiness : hint_range(0.0, 1.5) = 1.0;

struct WaveSample {
	vec3 disp;     // xz horizontal pinch + y height
	vec3 normal;   // geometric surface normal
	float jacobian;// < 1 where the surface compresses; < 0 where it folds (whitecap)
};

WaveSample sample_waves(vec2 p, float t, int count) {
	WaveSample o;
	o.disp = vec3(0.0);
	vec2 nslope = vec2(0.0);
	float ny = 0.0;
	float jxx = 0.0;
	float jzz = 0.0;
	float jxz = 0.0;
	for (int i = 0; i < count; i++) {
		vec2 d = waves[i].xy;
		float a = waves[i].z;
		float k = waves[i].w;
		float f = k * dot(d, p) - omegas[i] * t;
		float s = sin(f);
		float c = cos(f);
		float wa = k * a;
		o.disp += vec3(choppiness * d.x * a * c, a * s, choppiness * d.y * a * c);
		nslope += d * wa * c;
		ny += choppiness * wa * s;
		// d(disp.xz)/d(xz) — the fold term that produces whitecaps.
		float q = choppiness * wa * s;
		jxx -= q * d.x * d.x;
		jzz -= q * d.y * d.y;
		jxz -= q * d.x * d.y;
	}
	o.normal = normalize(vec3(-nslope.x, max(1.0 - ny, 0.08), -nslope.y));
	o.jacobian = (1.0 + jxx) * (1.0 + jzz) - jxz * jxz;
	return o;
}

// Cheap variant: Jacobian only, for the lagged foam trail.
float wave_jacobian(vec2 p, float t, int count) {
	float jxx = 0.0;
	float jzz = 0.0;
	float jxz = 0.0;
	for (int i = 0; i < count; i++) {
		vec2 d = waves[i].xy;
		float k = waves[i].w;
		float q = choppiness * k * waves[i].z * sin(k * dot(d, p) - omegas[i] * t);
		jxx -= q * d.x * d.x;
		jzz -= q * d.y * d.y;
		jxz -= q * d.x * d.y;
	}
	return (1.0 + jxx) * (1.0 + jzz) - jxz * jxz;
}

// Caustic focusing on the seabed.
//
// Light refracting through a wavy surface converges where the surface is
// concave and diverges where it is convex. Project the surface curvature down
// through `depth` metres of water and the determinant of that mapping is
// exactly the intensity ratio — bright webs at the folds, dim between them.
// This is why real caustics scale and slow down as the water gets deeper.
float wave_focus(vec2 p, float t, float depth, int count) {
	float hxx = 0.0;
	float hzz = 0.0;
	float hxz = 0.0;
	for (int i = 0; i < count; i++) {
		vec2 d = waves[i].xy;
		float k = waves[i].w;
		// d2(a*sin(f))/dx2 = -a*k^2*dx^2*sin(f)
		float c = waves[i].z * k * k * sin(k * dot(d, p) - omegas[i] * t);
		hxx -= c * d.x * d.x;
		hzz -= c * d.y * d.y;
		hxz -= c * d.x * d.y;
	}
	// Water bends the ray by (n-1)/n of the slope; 0.75 is that factor folded in.
	float dd = depth * 0.75;
	float det = (1.0 + dd * hxx) * (1.0 + dd * hzz) - dd * dd * hxz * hxz;
	return 1.0 / max(abs(det), 0.06);
}

#endif
