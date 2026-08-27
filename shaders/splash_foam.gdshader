shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform float age : hint_range(0.0, 1.0) = 0.0;
uniform vec4 foam_color : source_color = vec4(0.72, 0.80, 0.82, 1.0);

void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p) * 2.0;
	// Ease-out: real ripples race out then slow, instead of crawling linearly.
	float t = 1.0 - pow(1.0 - clamp(age, 0.0, 1.0), 1.65);
	float outer = mix(0.08, 0.92, t);
	float thick = mix(0.07, 0.038, t);
	float ring = smoothstep(outer - thick, outer, r) * (1.0 - smoothstep(outer, outer + thick, r));
	float wash = (1.0 - smoothstep(0.0, outer, r)) * 0.14 * (1.0 - t);
	float fade = 1.0 - t;
	float a = (ring * 0.95 + wash) * fade;
	ALBEDO = foam_color.rgb;
	ALPHA = clamp(a * foam_color.a, 0.0, 1.0);
}
