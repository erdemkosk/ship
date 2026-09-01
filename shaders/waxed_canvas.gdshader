shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.10, 0.11, 0.09, 1.0);
uniform vec4 worn_color : source_color = vec4(0.18, 0.17, 0.12, 1.0);
uniform float roughness_base : hint_range(0.0, 1.0) = 0.94;
uniform float weave_scale : hint_range(20.0, 400.0) = 175.0;
uniform float wear_amount : hint_range(0.0, 1.0) = 0.30;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}

void fragment() {
	vec2 cloth_uv = UV * weave_scale;
	float warp = sin(cloth_uv.x * 3.14159265);
	float weft = sin((cloth_uv.y + floor(cloth_uv.x) * 0.50) * 3.14159265);
	float weave = warp * weft;
	float broad_stain = value_noise(UV * 7.0 + vec2(1.7, 4.2));
	float salt = smoothstep(0.64, 0.91,
			value_noise(UV * 18.0 + vec2(8.1, 2.4))) * wear_amount;
	float edge = pow(clamp(1.0 - min(min(UV.x, 1.0 - UV.x),
			min(UV.y, 1.0 - UV.y)) * 7.0, 0.0, 1.0), 2.2);
	float worn = clamp(salt + edge * wear_amount * 0.52, 0.0, 0.72);
	vec3 colour = mix(base_color.rgb, worn_color.rgb, worn);
	colour *= 0.91 + broad_stain * 0.13 + weave * 0.025;
	ALBEDO = colour;
	ROUGHNESS = clamp(roughness_base - broad_stain * 0.08 + salt * 0.05,
			0.62, 1.0);
	NORMAL_MAP = normalize(vec3(warp * 0.055, weft * 0.055, 1.0));
	NORMAL_MAP_DEPTH = 0.32;
}
