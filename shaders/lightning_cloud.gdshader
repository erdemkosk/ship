shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// The anvil lighting up from inside. Billboarded so it stays a volume
// in the cloud, not a card stuck to the bolt.

uniform float fade : hint_range(0.0, 2.0) = 0.0;
uniform vec3 tint : source_color = vec3(0.74, 0.82, 1.0);

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 pos = origin + right * VERTEX.x + up * VERTEX.y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(pos, 1.0);
}

void fragment() {
	vec2 c = UV - vec2(0.5);
	float r = length(c) * 2.0;
	float core = exp(-r * r * 6.5);
	float veil = exp(-r * r * 1.6);
	float a = (core * 0.55 + veil * 0.22) * fade;
	vec3 col = tint * (core * 1.8 + veil * 0.45) * fade;
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
	EMISSION = col;
}
