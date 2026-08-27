shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float warmth : hint_range(0.0, 1.0) = 0.0;
uniform float close : hint_range(0.0, 1.0) = 0.0;
uniform float wave_time = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	// Air over the stove shimmers. Only when you are in it — a whole-screen
	// boil looks like a broken camera, a few millimetres on the face does not.
	vec2 dist = vec2(
		sin(uv.y * 36.0 + wave_time * 7.4) * 0.0011,
		cos(uv.x * 28.0 - wave_time * 5.1) * 0.0007);
	vec3 scene = texture(screen_texture, uv + dist * close).rgb;
	vec3 warm = scene * vec3(1.10, 0.94, 0.78) + vec3(0.035, 0.012, 0.0);
	float vig = smoothstep(0.38, 1.08, distance(uv, vec2(0.5)));
	vec3 col = mix(scene, warm, warmth * 0.52);
	// Firelight on the face: the centre lifts, the edges stay the cabin dark.
	col += vec3(0.055, 0.022, 0.004) * warmth * (1.0 - vig);
	COLOR = vec4(col, 1.0);
}
