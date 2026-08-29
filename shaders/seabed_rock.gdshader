shader_type spatial;
render_mode specular_schlick_ggx, shadows_disabled;

uniform int camera_under = 0;
uniform vec3 rock_color : source_color = vec3(0.11, 0.10, 0.09);

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = rock_color;
	ROUGHNESS = 0.96;
	METALLIC = 0.0;
	if (camera_under == 1) {
		float dist = length(CAMERA_POSITION_WORLD - v_world_pos);
		float close = exp(-dist * 0.28) * smoothstep(14.0, 1.8, dist);
		ALBEDO *= close * 0.85;
	}
}
