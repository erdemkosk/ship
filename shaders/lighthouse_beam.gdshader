shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// The visible shaft of a lighthouse beam.
//
// The spot light's own volumetric fog only reaches as far as the froxel volume
// (~110 m); this mesh carries the beam the rest of the way out to sea. It is a
// hollow cone, so everything here is about making a surface read as a VOLUME:
//
//   thickness — a tube seen from the side is thickest down its middle and
//               vanishes at the silhouette. That is what makes the edges soft
//               instead of the cardboard-cutout look of a flat wash.
//   soft hit  — fade where the cone passes into the sea or the rock, or you get
//               a hard intersection line drawn across the water.
//   haze      — the shaft is only visible because of what is floating in the
//               air, so it should be grainy and drifting, and it should get
//               brighter as the air gets thicker.
//   flare     — when the beam swings onto you it should bloom, not just sit
//               there at the same brightness.

uniform vec4 beam_color : source_color = vec4(1.0, 0.93, 0.68, 1.0);
uniform float intensity : hint_range(0.0, 8.0) = 1.0;
uniform float haze : hint_range(0.0, 3.0) = 1.0;
uniform float reach : hint_range(0.1, 3.0) = 1.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform float soft_metres = 26.0;
// How fast the shaft fades toward its silhouette. The wide outer cone wants a
// much softer edge than the bright core.
uniform float edge_soft : hint_range(0.3, 4.0) = 1.0;
// Two nested cones per beam: a tight bright core inside a wide dim halo. A
// single cone has one hard silhouette and always reads as a sheet of card; the
// halo is what gives the shaft a soft outside.
uniform float gain : hint_range(0.0, 2.0) = 1.0;

varying vec3 v_world;
varying vec3 v_beam_dir;
varying float v_len;

float bhash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float bnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(bhash(i), bhash(i + vec2(1.0, 0.0)), f.x),
			mix(bhash(i + vec2(0.0, 1.0)), bhash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Local +Y is the wide, far end of the cone, so this points down the beam.
	v_beam_dir = normalize((MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	v_len = length((MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz) * 2.0;
}

void fragment() {
	// UV.y: 1 at the lantern, 0 at the far end.
	float along = clamp(UV.y, 0.0, 1.0);

	// --- volume thickness through a hollow tube ------------------------------
	float ndv = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float thick = pow(clamp(ndv, 0.0, 1.0), edge_soft);

	// --- how far the light gets before the air eats it -----------------------
	float fall = pow(along, mix(2.2, 1.05, clamp(reach, 0.0, 1.0)));

	// --- soft intersection with the sea, the rock, the tower -----------------
	float draw_d = texture(depth_tex, SCREEN_UV).x;
	vec4 vpos = INV_PROJECTION_MATRIX * vec4(vec3(SCREEN_UV * 2.0 - 1.0, draw_d), 1.0);
	float scene_z = -(vpos.xyz / vpos.w).z;
	float soft = clamp((scene_z + VERTEX.z) / soft_metres, 0.0, 1.0);

	// --- drifting haze so the shaft is not a flat wash -----------------------
	vec2 hp = vec2(dot(v_world.xz, vec2(0.7, 0.7)) * 0.06, v_world.y * 0.06 - TIME * 0.05);
	float grain = bnoise(hp * 3.0) * 0.6 + bnoise(hp * 9.0) * 0.4;
	float mote = mix(0.62, 1.35, grain);

	// --- flare when the beam swings onto the camera --------------------------
	vec3 tocam = normalize(CAMERA_POSITION_WORLD - v_world);
	float aim = clamp(dot(v_beam_dir, tocam), 0.0, 1.0);
	// A gentle lift when it swings onto you — not a flashbang.
	float flare = pow(aim, 14.0);

	float a = fall * thick * soft * mote * intensity * haze * gain * (0.10 + flare * 0.06);
	a = clamp(a, 0.0, 0.55);

	ALBEDO = beam_color.rgb;
	ALPHA = a;
	EMISSION = beam_color.rgb * a * 1.5;
}
