shader_type spatial;
// cull_back, not cull_disabled: a thin box already has an inward face and an
// outward face. Drawing both sides of each meant the windscreen shaded twice
// — the whole view, every pixel — the moment you looked out in the rain.
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Wheelhouse glass.
//
// Real clear glass is ALMOST NOT THERE: it passes ~92% of the light straight
// through. So this pane is plain low-alpha geometry — no screen-texture trick,
// no refraction offset, nothing that could blur or tint the view. What sells it
// as glass is the little that remains: a hard Fresnel sheen when the light
// rakes across the pane, a tight specular highlight, and a faint film of salt.
//
// The expensive rain field (beads, sheet, rills) is baked off-screen into
// `rain_field` at a few hundred thousand pixels, then sampled here. Standing
// at the glass used to mean that field ran on every view pixel. The wiper
// stays here so the blade stays sharp at 60.

#include "res://shaders/glass_rain.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.13, 0.16, 0.17, 1.0);
uniform float grime : hint_range(0.0, 1.0) = 0.10;
uniform float clarity : hint_range(0.0, 1.0) = 0.95;
uniform float rain : hint_range(0.0, 1.0) = 0.0;
uniform int has_wiper = 0;
uniform int wiper_on = 0;
uniform float wiper_ang = 0.0;
uniform float wiper_phase = 0.0;
uniform float wiper_rate = 2.6;
uniform sampler2D rain_field : filter_linear, hint_default_black;

const vec2 PANE_SPAN = vec2(4.4, 2.0);

varying vec3 v_world;
varying vec2 v_pane;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Pane-local coordinates: the pane is a thin box, so drop the thin axis and
	// keep the two that span the glass. Everything drawn ON the glass — salt,
	// rain, the wiper's arc — is anchored to these and NOT to world space.
	vec3 an = abs(NORMAL);
	if (an.x > an.y && an.x > an.z) {
		v_pane = VERTEX.zy;
	} else if (an.z >= an.x && an.z > an.y) {
		v_pane = VERTEX.xy;
	} else {
		v_pane = VERTEX.xz;
	}
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float ndv = clamp(abs(dot(n, normalize(VIEW))), 1e-3, 1.0);
	float fres = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);

	vec2 gp = v_pane * 4.5;
	float dirt = gnoise(gp) * 0.55 + gnoise(gp * 3.7) * 0.45;
	float streak = gnoise(vec2(v_pane.x * 18.0, v_pane.y * 1.2));
	float film = clamp(mix(dirt, streak, 0.35) * grime, 0.0, 1.0);

	float wet = 0.0;
	float rim = 0.0;
	float glint = 0.0;
	if (rain > 0.004) {
		vec2 fuv = v_pane / PANE_SPAN + vec2(0.5);
		vec4 field = texture(rain_field, fuv);
		wet = field.r;
		rim = field.g;
		glint = field.b;

		if (has_wiper == 1 && wiper_on == 1) {
			vec2 rel = vec2(v_pane.x, v_pane.y + 0.72);
			float r = length(rel);
			float ang = atan(rel.x, rel.y);
			if (r < 1.12 && abs(ang) < 1.15) {
				float sN = clamp(ang / 1.02, -1.0, 1.0);
				float a1 = asin(sN);
				float pc = mod(wiper_phase, TAU);
				float d1 = mod(pc - mod(a1, TAU), TAU);
				float d2 = mod(pc - mod(PI - a1, TAU), TAU);
				float since = min(d1, d2) / max(wiper_rate, 1e-3);
				float refill = mix(5.0, 1.1, rain);
				float back = smoothstep(0.0, refill, since);
				wet *= mix(0.05, 1.0, back);
				rim *= mix(0.04, 1.0, back);
				glint *= mix(0.02, 1.0, back);
				float bow = smoothstep(0.16, 0.02, abs(ang - wiper_ang));
				wet = max(wet, bow * 0.40 * rain);
				glint = max(glint, bow * 0.22 * rain);
			}
		}

		vec2 q = vec2(v_pane.x * 5.5, v_pane.y * 2.4);
		float sheet = gnoise(q);
		float gx = gnoise(vec2(q.x + 0.30, q.y)) - sheet;
		float gy = gnoise(vec2(q.x, q.y + 0.30)) - sheet;
		n = normalize(n + (TANGENT * gx + BINORMAL * gy) * wet * 0.22);
	}

	NORMAL = n;
	ALBEDO = mix(tint.rgb, vec3(0.28, 0.33, 0.36), wet);
	ALPHA = clamp((1.0 - clarity) + fres * 0.08 + film * 0.16
			+ wet * 0.64 + rim * 0.10, 0.02, 0.80);
	METALLIC = 0.0;
	SPECULAR = mix(0.22, 0.42, wet);
	ROUGHNESS = mix(0.26, 0.16, wet);
	ROUGHNESS = mix(ROUGHNESS, 0.58, film * 0.55);
	EMISSION = vec3(0.34, 0.39, 0.44) * glint * (0.28 + 0.55 * rain);
}
