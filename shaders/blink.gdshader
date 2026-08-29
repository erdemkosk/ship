shader_type canvas_item;
render_mode unshaded, blend_mix;

// Two lids, FPS only. `close` 0 is open, 1 is shut. Upper lid does most of
// the travel; the lower one comes up a little, the way a real blink does.

uniform float close : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float c = close;
	float lid = 0.0;
	vec3 flesh = vec3(0.045, 0.028, 0.022);
	if (c > 0.001) {
		float x = UV.x * 2.0 - 1.0;
		float bow = (1.0 - x * x) * 0.10 * c;
		float top_edge = mix(-0.06, 0.54 + bow, c);
		float bot_edge = mix(1.06, 0.46 - bow, c);
		float top_lid = 1.0 - smoothstep(top_edge - 0.022, top_edge + 0.006, UV.y);
		float bot_lid = smoothstep(bot_edge - 0.006, bot_edge + 0.018, UV.y);
		lid = max(top_lid, bot_lid);
	}
	COLOR = vec4(flesh, lid);
}
