shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx, depth_draw_opaque, shadows_disabled;

uniform float wave_time = 0.0;
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform int camera_under = 0;

varying float v_along;
varying vec3 v_world_pos;

void vertex() {
	v_along = UV.y;
	float sway = sin(wave_time * 1.35 + VERTEX.x * 0.45 + VERTEX.z * 0.38) * 0.22;
	float sway2 = cos(wave_time * 0.9 + VERTEX.z * 0.55) * 0.10;
	float k = UV.y * UV.y;
	VERTEX.x += (sway + wind_dir.x * 0.08) * k;
	VERTEX.z += (sway2 + wind_dir.y * 0.08) * k;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 tip = vec3(0.10, 0.22, 0.08);
	vec3 base = vec3(0.03, 0.07, 0.04);
	ALBEDO = mix(base, tip, v_along);
	ROUGHNESS = 0.92;
	METALLIC = 0.0;
	if (camera_under == 1) {
		float dist = length(CAMERA_POSITION_WORLD - v_world_pos);
		float close = exp(-dist * 0.22) * smoothstep(16.0, 1.5, dist);
		ALBEDO *= close;
	}
}
