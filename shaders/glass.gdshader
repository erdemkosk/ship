shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

// Wheelhouse glass. Old, salted, never quite clean.
//
// Real glass is not a dark quad: it bends what is behind it, it throws a hard
// reflection at grazing angles, and on a working boat it carries a film of salt
// and a few decades of grime that only show when the light rakes across it.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.52, 0.58, 0.58, 1.0);
uniform float refraction : hint_range(0.0, 0.2) = 0.035;
uniform float grime : hint_range(0.0, 1.0) = 0.55;
uniform float clarity : hint_range(0.0, 1.0) = 0.72;

varying vec3 v_world;

float ghash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(ghash(i), ghash(i + vec2(1.0, 0.0)), f.x),
			mix(ghash(i + vec2(0.0, 1.0)), ghash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float ndv = clamp(abs(dot(n, normalize(VIEW))), 1e-3, 1.0);
	// Schlick for glass (n = 1.5 -> F0 = 0.04).
	float fres = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);

	// Salt film and old grime, thicker toward the corners of the pane.
	vec2 gp = v_world.xz * 5.5 + v_world.y * 3.0;
	float dirt = gnoise(gp) * 0.55 + gnoise(gp * 3.7) * 0.45;
	float streak = gnoise(vec2(v_world.x * 22.0, v_world.y * 1.4));
	dirt = mix(dirt, streak, 0.35);
	float film = clamp(dirt * grime, 0.0, 1.0);

	// What is behind the pane, bent by it.
	vec2 off = n.xy * refraction * (1.0 - film * 0.5);
	vec3 behind = textureLod(screen_tex, clamp(SCREEN_UV + off, vec2(0.002), vec2(0.998)),
			film * 2.5).rgb;

	ALBEDO = tint.rgb * mix(0.9, 1.35, film);
	// Clear glass passes almost everything; grime is what you actually see.
	ALPHA = clamp(mix(1.0 - clarity, 1.0, film * 0.75 + fres * 0.8), 0.06, 0.95);
	EMISSION = behind * (1.0 - film) * clarity * 0.55;
	METALLIC = 0.0;
	SPECULAR = 0.55;
	ROUGHNESS = mix(0.03, 0.34, film);
}
