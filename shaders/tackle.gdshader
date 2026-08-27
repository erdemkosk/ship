shader_type spatial;
render_mode specular_schlick_ggx, depth_draw_opaque;

// Anchor and cable.
//
// Everything else on the boat lives in the air. This lives in both, and that is
// the whole reason it needs a shader of its own: on a plain material the chain
// stayed exactly as bright twenty metres down as it was on deck, so it read as
// something painted on top of the water rather than something in it — the very
// thing that made the sinking anchor look like a reflection.
//
// So it takes the water's own absorption: the deeper a link is, the more of the
// sea's colour it has already turned into. Same idea as the seabed weed, same
// numbers, so the cable agrees with everything around it.

uniform vec3 albedo : source_color = vec3(0.30, 0.30, 0.31);
uniform float rough : hint_range(0.0, 1.0) = 0.42;
uniform float metal : hint_range(0.0, 1.0) = 0.80;
uniform float water_y = 0.0;
uniform vec3 murk : source_color = vec3(0.020, 0.055, 0.062);
// How fast it goes. Roughly the water's green-channel extinction.
uniform float absorb = 0.155;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float depth = max(water_y - v_world.y, 0.0);
	float vis = exp(-depth * absorb);
	ALBEDO = mix(murk, albedo, vis);
	ROUGHNESS = mix(0.95, rough, vis);
	// Wet iron below the surface stops behaving like polished metal long before
	// it stops being visible; letting it keep its specular down there is what
	// puts a hard highlight on a link at fifteen metres.
	METALLIC = metal * vis;
	SPECULAR = 0.5 * vis;
}
