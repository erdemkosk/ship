shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.12, 0.14, 0.10, 1.0);
uniform float motion : hint_range(0.0, 1.0) = 0.0;
uniform float phase = 0.0;

void vertex() {
	// Sub-millimetre canvas settling plus a little extra while the pack is
	// travelling over the shoulder. Subdivided meshes make this deformation
	// spatial; it is not a rigid box merely bobbing as one piece.
	float weave = sin(VERTEX.x * 34.0 + phase) * sin(VERTEX.y * 29.0 - phase * 0.73);
	float fold = sin((VERTEX.y + VERTEX.z) * 18.0 - phase * 1.2);
	VERTEX += NORMAL * (weave * 0.0013 + fold * 0.0024 * motion);
}

void fragment() {
	// Fine perpendicular canvas threads plus broad, irregular dye wear. This is
	// intentionally procedural so the weave remains visible on every curved
	// panel without relying on an external placeholder texture.
	float warp = sin(UV.x * 920.0);
	float weft = sin(UV.y * 810.0 + warp * 0.55);
	float fibres = warp * 0.45 + weft * 0.45 + warp * weft * 0.10;
	float wear = sin(UV.x * 31.0 + sin(UV.y * 19.0))
		* sin(UV.y * 27.0 - UV.x * 7.0);
	ALBEDO = albedo.rgb * (0.89 + fibres * 0.045 + wear * 0.018);
	NORMAL_MAP = normalize(vec3(warp * 0.14, weft * 0.14, 1.0));
	NORMAL_MAP_DEPTH = 0.24;
	ROUGHNESS = 0.96;
	METALLIC = 0.0;
}
