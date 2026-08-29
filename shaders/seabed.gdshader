shader_type spatial;
render_mode world_vertex_coords, specular_schlick_ggx, cull_back;

uniform sampler2D height_map : filter_linear, repeat_enable;
uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;
uniform float terrain_size = 2048.0;
uniform float wave_time = 0.0;
uniform int camera_under = 0;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 caustic_color : source_color = vec3(0.30, 0.52, 0.42);
uniform float caustic_scale : hint_range(0.2, 3.0) = 1.0;
uniform float caustic_energy : hint_range(0.0, 4.0) = 1.0;

uniform vec3 sand_color : source_color = vec3(0.72, 0.62, 0.42);
uniform vec3 wet_sand_color : source_color = vec3(0.38, 0.34, 0.24);
uniform vec3 deep_sand_color : source_color = vec3(0.16, 0.15, 0.12);
uniform vec3 moss_color : source_color = vec3(0.10, 0.22, 0.09);
uniform vec3 rock_color : source_color = vec3(0.22, 0.21, 0.19);

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
	float n4 = texture(detail_noise, uv * 0.55 + vec2(0.7, 0.3)).r;
	float slope = 1.0 - clamp(v_normal.y, 0.0, 1.0);

	// Silt of the basin — not beach sand. Close, it is mud and grit. Far, it
	// is not there.
	vec3 silt = mix(vec3(0.028, 0.032, 0.028), vec3(0.050, 0.044, 0.034), n1);
	silt = mix(silt, vec3(0.016, 0.018, 0.016), smoothstep(0.52, 0.88, n2));
	silt *= 0.82 + 0.22 * n4;

	vec3 col = mix(silt, deep_sand_color, smoothstep(-40.0, -18.0, v_height) * 0.55);
	col = mix(col, wet_sand_color, smoothstep(-14.0, -5.0, v_height));
	col = mix(col, sand_color, smoothstep(-1.2, 0.35, v_height));
	col = mix(col, sand_color * 1.08, smoothstep(0.2, 1.4, v_height) * 0.7);

	float moss = smoothstep(0.42, 0.72, n1) * smoothstep(-12.0, -1.5, v_height)
			* (1.0 - smoothstep(-0.4, 0.6, v_height));
	col = mix(col, moss_color * 0.55, moss * 0.85);
	float weed = smoothstep(0.58, 0.82, n2) * moss;
	col = mix(col, moss_color * 0.32, weed * 0.6);

	float rocky = smoothstep(0.22, 0.52, slope) + smoothstep(0.7, 0.9, n3) * 0.35;
	rocky *= mix(0.45, 1.0, smoothstep(-22.0, 0.8, v_height));
	col = mix(col, rock_color * 0.55, clamp(rocky, 0.0, 0.85));

	col *= 0.88 + 0.16 * n3;
	vec3 n_detail = normalize(v_normal
			+ vec3((n2 - 0.5) * 0.40, 0.0, (n3 - 0.5) * 0.40)
			+ vec3((n4 - 0.5) * 0.18, 0.0, (n1 - 0.5) * 0.12));

	ALBEDO = col;
	METALLIC = 0.0;
	ROUGHNESS = mix(0.97, 0.55, smoothstep(-0.2, 1.5, v_height));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_detail, 0.0)).xyz);

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

	float dist = length(CAMERA_POSITION_WORLD - v_world_pos);
	float frag_depth = max(-v_height, 0.0);
	float sun_up = clamp(sun_dir.y, 0.0, 1.0);
	float k = mix(0.145, 0.058, sun_up);
	float sun_left = exp(-frag_depth * k) * (0.06 + 0.94 * sun_up);
	float vis_sun = sun_left * exp(-dist * (camera_under == 1 ? 0.048 : 0.028));
	// In the dark the floor is not a lit plane — it is a shape that appears
	// in the last few metres and is gone beyond that. That is the scare.
	float close = exp(-dist * 0.30) * smoothstep(13.0, 2.0, dist);
	float seen = camera_under == 1 ? max(vis_sun, close * 0.70) : vis_sun;
	seen = clamp(seen, 0.0, 1.0);
	ALBEDO = mix(vec3(0.0), ALBEDO, seen);
	ALBEDO = mix(vec3(dot(ALBEDO, vec3(0.25, 0.50, 0.25))), ALBEDO, clamp(sun_left * 1.8, 0.0, 1.0));
	EMISSION *= seen * photic;
	ROUGHNESS = mix(1.0, ROUGHNESS, seen);
}
