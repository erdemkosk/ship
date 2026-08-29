// Shared FFT wave field.
//
// The field is produced on the GPU by scripts/wave/wave_generator.gd as two
// texture arrays, one layer per cascade:
//   wave_displacements  xyz = horizontal pinch + height
//   wave_normals        xy  = height gradient, z = dhx_dx, w = accumulated foam
//
// This replaced a 40-component analytic Gerstner sum. The reason the old sum
// existed at all was that scripts/ocean.gd had to evaluate the SAME waves on the
// CPU for buoyancy, and a texture is not a function. That contract did not die
// with the Gerstner set, it moved: cpu_sample.glsl downsamples these very texels
// into a buffer ocean.gd reads back, so the boat still floats on the wave you
// can see. Change the cascade set and both sides follow, because there is only
// one field now instead of two that had to be kept in step by hand.
//
// Foam is likewise no longer inferred from a lagged Jacobian. The FFT unpack
// pass accumulates it (grow where the surface folds, exponential decay
// everywhere) into the normal map's alpha, which is the persistent foam buffer
// the Gerstner version could only fake with a second time-shifted sample.
#ifndef WAVE_COMMON_INC
#define WAVE_COMMON_INC

const int MAX_CASCADES = 4;

uniform sampler2DArray wave_displacements : filter_linear, repeat_enable;
// Mipmapped: the far sea is many texels per pixel and point-sampling it turns
// wave slope into crawling noise. The chain is built by mip_reduce.glsl.
uniform sampler2DArray wave_normals : filter_linear_mipmap, repeat_enable;
uniform int num_cascades = 0;
// xy = 1/tile_length, z = displacement scale, w = normal scale
uniform vec4 map_scales[MAX_CASCADES];
// Distance at which each cascade stops displacing vertices, in metres.
//
// A mesh whose quads are 9 m across cannot carry a 4 m wave — feeding it into
// the vertex stream only buys crawling geometry, which is what the old "every
// ring draws all forty components" did. So each cascade fades out where the
// mesh gets too coarse for it.
//
// Crucially this is keyed on CAMERA DISTANCE, not on which clipmap ring the
// vertex belongs to. Per-ring cascade counts sound equivalent and are not: two
// rings meet along a boundary, and if they disagree about which cascades to
// displace with, the surface steps along that seam. Distance is continuous and
// both rings read the same value there, so the seam closes by construction.
uniform float cascade_fade[MAX_CASCADES];
// Scene clock. The wave field is animated on the GPU by the compute pass now,
// so this no longer drives the waves — but foam drift, rain rings, shore chop
// and the detail normal layers all still ride it.
uniform float wave_time = 0.0;
uniform float choppiness : hint_range(0.0, 2.0) = 1.0;

struct WaveSample {
	vec3 disp;     // xz horizontal pinch + y height
	vec3 normal;   // geometric surface normal
	float foam;    // accumulated whitecap coverage, 0..1
};

// Displacement only. Vertex stage: no derivatives available, so textureLod.
vec3 wave_displacement(vec2 p, float dist) {
	vec3 d = vec3(0.0);
	for (int i = 0; i < num_cascades; i++) {
		float fd = cascade_fade[i];
		float w = 1.0 - smoothstep(fd * 0.65, fd, dist);
		if (w <= 0.002) {
			continue;
		}
		vec4 s = map_scales[i];
		vec3 c = textureLod(wave_displacements, vec3(p * s.xy, float(i)), 0.0).xyz;
		d += vec3(c.x * choppiness, c.y, c.z * choppiness) * (s.z * w);
	}
	return d;
}

// Filter weights for a cubic B-spline.
vec4 wave_cubic_weights(float a) {
	float a2 = a * a;
	float a3 = a2 * a;
	float w0 = -a3 + a2 * 3.0 - a * 3.0 + 1.0;
	float w1 = a3 * 3.0 - a2 * 6.0 + 4.0;
	float w2 = -a3 * 3.0 + a2 * 3.0 + a * 3.0 + 1.0;
	float w3 = a3;
	return vec4(w0, w1, w2, w3) / 6.0;
}

// Bicubic B-spline fetch. A 256-tap map stretched over a 512 m tile is 2 m per
// texel; bilinear on that reads as faceted diamonds on every swell face.
// Source: GPU Gems 2, ch. 20.
vec4 wave_texture_bicubic(sampler2DArray samp, vec3 uvw) {
	vec2 dims = vec2(textureSize(samp, 0).xy);
	vec2 dims_inv = 1.0 / dims;
	uvw.xy = uvw.xy * dims + 0.5;
	vec2 fuv = fract(uvw.xy);
	vec4 wx = wave_cubic_weights(fuv.x);
	vec4 wy = wave_cubic_weights(fuv.y);
	vec4 g = vec4(wx.xz + wx.yw, wy.xz + wy.yw);
	vec4 h = (vec4(wx.yw, wy.yw) / g + vec2(-1.5, 0.5).xyxy + floor(uvw.xy).xxyy) * dims_inv.xxyy;
	vec2 w = g.xz / (g.xz + g.yw);
	return mix(
			mix(texture(samp, vec3(h.yw, uvw.z)), texture(samp, vec3(h.xw, uvw.z)), w.x),
			mix(texture(samp, vec3(h.yz, uvw.z)), texture(samp, vec3(h.xz, uvw.z)), w.x), w.y);
}

// Gradient + foam, fragment stage. `p` is the REST xz (pre-displacement), which
// is what indexes the field; the varying carries it across from the vertex.
// All cascades contribute here, including the ones this ring refused to
// displace with: a wave too short for the mesh still tilts the surface, and
// handing its slope to the normal instead of to the vertices is the difference
// between detail and aliasing.
void wave_gradient(vec2 p, float dist, out vec2 grad, out float foam) {
	grad = vec2(0.0);
	foam = 0.0;
	float map_size = float(textureSize(wave_normals, 0).x);
	for (int i = 0; i < num_cascades; i++) {
		vec4 s = map_scales[i];
		vec3 uvw = vec3(p * s.xy, float(i));
		float ppm = map_size * min(s.x, s.y); // texels per metre
		vec4 t = mix(wave_texture_bicubic(wave_normals, uvw), texture(wave_normals, uvw),
				min(1.0, ppm * 0.1));
		grad += t.xy * s.w;
		foam += t.w;
	}
	foam = clamp(foam, 0.0, 1.0);
}

WaveSample sample_waves(vec2 p, float dist) {
	WaveSample o;
	o.disp = wave_displacement(p, dist);
	// Vertex-stage normal. Godot wants a NORMAL written in vertex() for the
	// depth prepass and for anything that reads it before fragment(); the real
	// shading normal is rebuilt per pixel from wave_gradient().
	vec2 g;
	float f;
	int n = num_cascades;
	g = vec2(0.0);
	f = 0.0;
	for (int i = 0; i < n; i++) {
		vec4 s = map_scales[i];
		vec4 t = textureLod(wave_normals, vec3(p * s.xy, float(i)), 0.0);
		g += t.xy * s.w;
		f += t.w;
	}
	o.normal = normalize(vec3(-g.x, 1.0, -g.y));
	o.foam = clamp(f, 0.0, 1.0);
	return o;
}

#endif
