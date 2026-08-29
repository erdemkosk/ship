shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Camera-facing ribbon. UV.x is across the bolt (0 left, 1 right), UV.y
// is distance along the channel. A hard-edged quad reads as cardboard;
// the profile is a thin core plus a soft halo, so the mesh can be wide
// without looking like stacked cards.

uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float core_gain : hint_range(0.0, 12.0) = 4.2;
uniform vec3 tint : source_color = vec3(0.78, 0.88, 1.0);

void fragment() {
	float gate = 1.0 - smoothstep(reveal, reveal + 0.07, UV.y);
	if (gate < 0.01) {
		discard;
	}
	float x = abs(UV.x * 2.0 - 1.0);
	float core = exp(-x * x * 220.0);
	float inner = exp(-x * x * 48.0);
	float halo = exp(-x * x * 7.5);
	float air = exp(-x * x * 2.2);
	float flicker = 0.82 + 0.18 * sin(UV.y * 62.0 + TIME * 90.0);
	float pulse = 0.88 + 0.12 * sin(TIME * 48.0);
	float a = (core * 1.15 + inner * 0.45 + halo * 0.16 + air * 0.04)
			* fade * flicker * pulse * gate;
	vec3 col = tint * (
			core * core_gain
			+ inner * 1.6
			+ halo * 0.35
			+ air * 0.06) * fade * flicker * gate;
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
	EMISSION = col;
}
