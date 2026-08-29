shader_type spatial;
render_mode specular_schlick_ggx, depth_draw_opaque, cull_back;

// Tobacco face only. The marks glow as mesh emission, not as a lamp
// washing the disc — that read as a light over the gauges.

uniform vec3 albedo : source_color = vec3(0.055, 0.050, 0.040);
uniform float dirt : hint_range(0.0, 1.0) = 0.62;
uniform float radium : hint_range(0.0, 1.0) = 0.04;
uniform float flicker : hint_range(0.0, 2.0) = 1.0;
uniform float seed = 0.0;

varying vec3 v_model;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_model = VERTEX;
}

void fragment() {
	vec2 p = v_model.xz * 18.0 + vec2(seed * 9.1, seed * 4.3);
	float n = noise(p) * 0.50 + noise(p * 3.1) * 0.32 + noise(p * 8.4) * 0.18;
	float r = length(v_model.xz);
	float vig = smoothstep(0.035, 0.090, r);
	float scratch = smoothstep(0.92, 1.0, fract(v_model.x * 42.0 + n * 3.0)) * 0.22;
	vec3 stain = vec3(0.038, 0.034, 0.024);
	vec3 base = mix(albedo, stain, dirt * (0.35 + n * 0.55));
	// Residual stain only. Phosphor lives on the ticks, not the plate.
	vec3 glow = vec3(0.18, 0.28, 0.08) * radium * flicker * (1.0 - vig);
	ALBEDO = base + vec3(scratch * 0.03);
	EMISSION = glow * 0.12;
	ROUGHNESS = mix(0.78, 0.94, dirt);
	SPECULAR = 0.18;
	METALLIC = 0.0;
}
