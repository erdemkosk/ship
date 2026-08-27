shader_type spatial;
render_mode world_vertex_coords, specular_schlick_ggx, cull_back;

uniform sampler2D height_map : filter_linear, repeat_enable;
uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;
uniform float terrain_size = 2048.0;
uniform float wave_time = 0.0;
uniform int camera_under = 0;
uniform vec3 caustic_color : source_color = vec3(0.30, 0.52, 0.42);
// Wind drives how fast and how fine the caustic net moves.
uniform float caustic_scale : hint_range(0.2, 3.0) = 1.0;
uniform float caustic_energy : hint_range(0.0, 4.0) = 1.0;

uniform vec3 sand_color : source_color = vec3(0.72, 0.62, 0.42);
uniform vec3 wet_sand_color : source_color = vec3(0.38, 0.34, 0.24);
uniform vec3 deep_sand_color : source_color = vec3(0.16, 0.15, 0.12);
uniform vec3 moss_color : source_color = vec3(0.10, 0.22, 0.09);
uniform vec3 rock_color : source_color = vec3(0.22, 0.21, 0.19);
uniform vec3 murk_color : source_color = vec3(0.012, 0.035, 0.040);

varying vec3 v_world_pos;
varying vec3 v_normal;
varying float v_height;

float sample_h(vec2 xz) {
	return texture(height_map, xz / terrain_size + 0.5).r;
}

void vertex() {
	vec2 p = VERTEX.xz;
	float h = sample_h(p);
	float eps = 3.5;
	float hL = sample_h(p + vec2(-eps, 0.0));
	float hR = sample_h(p + vec2(eps, 0.0));
	float hD = sample_h(p + vec2(0.0, -eps));
	float hU = sample_h(p + vec2(0.0, eps));
	vec3 n = normalize(vec3(hL - hR, 2.0 * eps, hD - hU));
	VERTEX.y = h;
	NORMAL = n;
	v_normal = n;
	v_world_pos = VERTEX;
	v_height = h;
}

void fragment() {
	vec2 uv = v_world_pos.xz;
	float n1 = texture(detail_noise, uv * 0.035).r;
	float n2 = texture(detail_noise, uv * 0.09 + vec2(0.2, 0.1)).r;
	float n3 = texture(detail_noise, uv * 0.22).r;
	float slope = 1.0 - clamp(v_normal.y, 0.0, 1.0);

	vec3 col = mix(deep_sand_color, wet_sand_color, smoothstep(-28.0, -6.0, v_height));
	col = mix(col, sand_color, smoothstep(-1.2, 0.35, v_height));
	// dryer patch on island tops
	col = mix(col, sand_color * 1.08, smoothstep(0.2, 1.4, v_height) * 0.7);

	float moss = smoothstep(0.42, 0.72, n1) * smoothstep(-9.0, -1.5, v_height)
			* (1.0 - smoothstep(-0.4, 0.6, v_height));
	col = mix(col, moss_color, moss * 0.85);
	// darker weed streaks
	float weed = smoothstep(0.58, 0.82, n2) * moss;
	col = mix(col, moss_color * 0.55, weed * 0.6);

	float rocky = smoothstep(0.28, 0.55, slope) + smoothstep(0.7, 0.9, n3) * 0.35;
	rocky *= mix(0.25, 1.0, smoothstep(-3.0, 0.8, v_height));
	col = mix(col, rock_color, clamp(rocky, 0.0, 0.85));

	// grain + ripple in the sand
	col *= 0.90 + 0.14 * n3;
	vec3 n_detail = normalize(v_normal + vec3((n2 - 0.5) * 0.35, 0.0, (n3 - 0.5) * 0.35));

	ALBEDO = col;
	METALLIC = 0.0;
	ROUGHNESS = mix(0.92, 0.55, smoothstep(-0.2, 1.5, v_height));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_detail, 0.0)).xyz);

	// Caustics in the photic zone (visible shallows, gone in trenches / on land).
	//
	// This is a noise approximation, not a real refraction solve. The physical
	// version — projecting the wave field's curvature down through the water and
	// reading its Jacobian — was implemented and measured at roughly half the
	// frame budget, for a pattern this scene barely shows. The wind at least
	// drives its scale and speed, so it moves with the sea it belongs to.
	float photic = smoothstep(-16.0, -6.0, v_height) * (1.0 - smoothstep(-0.4, 1.2, v_height));
	float cs = 0.07 * caustic_scale;
	float c1 = texture(detail_noise, uv * cs + vec2(wave_time * 0.022 * caustic_scale, 0.0)).r;
	float c2 = texture(detail_noise, uv * cs * 0.8 + vec2(0.0, -wave_time * 0.017 * caustic_scale)).r;
	float cau = pow(c1 * c2, 2.2) * photic * 2.2 * caustic_energy;
	vec3 cau_col = caustic_color * cau;
	if (camera_under == 0) {
		cau_col *= 0.30;
	}
	EMISSION = cau_col * (0.35 + 0.65 * clamp(v_normal.y, 0.0, 1.0));

	// underwater murk: distance + depth kill visibility in trenches
	if (camera_under == 1) {
		float dist = length(CAMERA_POSITION_WORLD - v_world_pos);
		float optical = dist * 0.055 + max(-v_height, 0.0) * 0.048;
		float vis = exp(-optical);
		ALBEDO = mix(murk_color, ALBEDO, vis);
		EMISSION *= vis;
		ROUGHNESS = mix(1.0, ROUGHNESS, vis);
	}
}
