shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	vec2 c = UV - vec2(0.5);
	float v = smoothstep(0.32, 0.95, length(c) * 1.35);
	COLOR = vec4(0.0, 0.005, 0.015, v * strength);
}
