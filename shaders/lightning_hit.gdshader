shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, shadows_disabled, fog_disabled;

// Soft splash on the sea. A solid quad becomes a white sheet in the
// reflection; this is a radial falloff so it reads as a strike, not a card.

uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform vec3 tint : source_color = vec3(0.72, 0.84, 1.0);

void fragment() {
	vec2 c = UV - vec2(0.5);
	float r = length(c) * 2.15;
	float hot = exp(-r * r * 14.0);
	float ring = exp(-r * r * 3.2);
	float a = (hot * 0.95 + ring * 0.22) * fade;
	vec3 col = tint * (hot * 3.4 + ring * 0.55) * fade;
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
	EMISSION = col;
}
