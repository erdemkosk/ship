shader_type spatial;
render_mode world_vertex_coords, specular_schlick_ggx, cull_back;

// Wooden hull that knows where the waterline is.
//
// Wet wood is darker and much glossier than dry wood, and the band just above
// the water stays wet between waves. Without this the boat reads as a prop
// sitting on the sea rather than as something floating in it.

uniform vec3 albedo : source_color = vec3(0.23, 0.16, 0.11);
uniform float dry_roughness : hint_range(0.0, 1.0) = 0.9;
uniform float water_y = 0.0;      // world height of the sea under the boat
uniform float wet_band : hint_range(0.0, 1.2) = 0.42;
uniform float soak : hint_range(0.0, 1.0) = 0.0;  // spray-soaked topsides

varying vec3 v_world;

void vertex() {
	v_world = VERTEX;
}

void fragment() {
	// 1 at and below the waterline, fading out over `wet_band` above it.
	float wet = 1.0 - smoothstep(water_y, water_y + wet_band, v_world.y);
	wet = max(wet, soak * 0.55);
	ALBEDO = albedo * mix(1.0, 0.42, wet);
	ROUGHNESS = mix(dry_roughness, 0.16, wet);
	SPECULAR = mix(0.5, 0.62, wet);
	METALLIC = 0.0;
}
