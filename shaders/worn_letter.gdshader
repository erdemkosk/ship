shader_type spatial;
render_mode specular_schlick_ggx, depth_draw_opaque, cull_back;

// Paint left on a transom after years of sun and spray. Holes are the wood
// showing through; what remains is chalky, never gilt.

uniform vec3 albedo : source_color = vec3(0.62, 0.54, 0.38);
uniform float wear : hint_range(0.0, 1.0) = 0.45;
uniform float seed = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.94;

varying vec3 v_model;

void vertex() {
	v_model = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y);
}

void fragment() {
	vec2 p = v_model.xy * 19.0 + vec2(seed * 13.7, seed * 7.1);
	float n = noise(p) * 0.50 + noise(p * 3.4) * 0.32 + noise(p * 9.2) * 0.18;
	// Edge of a letter flakes first — the stroke centre holds on longer.
	float edge = smoothstep(0.02, 0.11, length(v_model.xy));
	float keep = n - wear * (0.55 + edge * 0.38);
	ALPHA = keep > 0.10 ? 1.0 : 0.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;

	float dirt = noise(p * 0.42 + vec2(4.2, 1.7));
	vec3 col = albedo * mix(0.52, 1.08, dirt);
	col = mix(col, vec3(0.36, 0.32, 0.26), wear * 0.40 * (1.0 - n));
	ALBEDO = col;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.28;
}
