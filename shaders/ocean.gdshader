shader_type spatial;
render_mode world_vertex_coords, specular_schlick_ggx, blend_mix, cull_disabled, depth_draw_always;

// Sea surface.
//
// Wave field and sky both live in shared includes: the same Gerstner set drives
// the CPU buoyancy in scripts/ocean.gd, and the same sky function drives the
// dome in sky.gdshader — so the water genuinely reflects the sky you see rather
// than a hand-picked tint.
//
// Optical model, in the order light actually takes:
//   1. reflection   — procedural sky along reflect(V, N), blurred by wave slope
//   2. refraction   — screen texture, offset by the surface normal
//   3. absorption   — Beer-Lambert over the real depth from DEPTH_TEXTURE
//   4. scattering   — light bounced back out of the water body
//   5. subsurface   — sun through the back of a crest
//   6. foam         — where the Jacobian folds, plus shore and wake
#include "res://shaders/wave_common.gdshaderinc"
#include "res://shaders/sky_common.gdshaderinc"

const float PI2 = 6.28318530718;
const float G = 9.81;

uniform float max_amp = 1.0;

// Water body optics. extinction is per-metre, per-channel: red dies in ~1.5 m,
// blue survives ~20 m. This is why shallow water is green and deep water black.
uniform vec3 extinction : source_color = vec3(0.95, 0.38, 0.24);
uniform vec3 scatter_color : source_color = vec3(0.012, 0.062, 0.070);
uniform float scatter_strength : hint_range(0.0, 3.0) = 1.0;
uniform vec3 foam_color : source_color = vec3(0.62, 0.70, 0.71);
uniform float refraction_strength : hint_range(0.0, 2.0) = 0.55;

uniform float base_roughness : hint_range(0.0, 1.0) = 0.045;
// Cox-Munk mean square slope: the statistical roughness of a wind-blown sea.
// This is what turns a mirror into the long shimmering glitter path.
uniform float mss : hint_range(0.0, 0.3) = 0.05;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.55;
uniform float foam_amount : hint_range(0.0, 2.0) = 0.85;
uniform float sss_strength : hint_range(0.0, 3.0) = 1.0;
uniform float boat_wave_gain : hint_range(0.5, 2.0) = 1.0;
// Irradiance of the whole sky hemisphere. A rough surface reflects the average
// of the dome, not the one patch a mirror would pick.
uniform vec3 sky_ambient : source_color = vec3(0.14, 0.18, 0.22);
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform vec2 surface_drift = vec2(0.0);   // Stokes + tidal drift — foam rides this
uniform vec2 current_vec = vec2(0.0);    // tidal stream at the boat, m/s
uniform float rain_amount : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D foam_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D height_map : filter_linear, repeat_enable;
// Boat-centred, non-periodic interaction field. r=height, g=vertical velocity,
// b=foam energy. The FFT remains the sea; this texture is what lets a hull,
// propeller, swimmer and impact leave water behind instead of drawing decals.
uniform sampler2D local_field : filter_linear;
uniform int local_field_on = 0;
uniform vec2 local_centre = vec2(0.0);
uniform float local_world_size = 64.0;
uniform float local_texel = 0.25;
// filter_linear, NOT mipmap: asking for mipmaps here makes the renderer build a
// full mip chain of the screen every single frame, and the only thing it bought
// was a slightly softer refraction in shallow water.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// Planar reflection of everything that is not the sea itself. Alpha is the
// coverage mask: where it is 0 the analytic sky reflection shows through.
uniform sampler2D reflect_tex : hint_default_transparent, filter_linear;
uniform int reflect_on = 0;
uniform float reflect_plane_y = 0.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform float terrain_size = 2048.0;
uniform int camera_under = 0;
uniform float absorb_k : hint_range(0.04, 1.2) = 0.75;
uniform int far_clip = 0;
uniform float near_radius = 380.0;
// 1/(2R) for Earth's radius. Drops the sea away below the true horizon, which
// is only ~5 km out at eye height — the single strongest scale cue at sea.
uniform float curvature_k = 0.0;

// Floating objects that push the water around them: the boat, the buoy, the
// flotsam. xy = world xz, z = radius, w = draft.
const int MAX_FLOATERS = 8;
uniform int num_floaters = 0;
uniform vec4 floaters[MAX_FLOATERS];
// xy = velocity on the water, w = 1 if this body leaves its own sea
// (a dinghy, a swimmer). The ship is 0: it already has the Kelvin wedge.
uniform vec4 floater_vel[MAX_FLOATERS];

// boat wake + hull water mask (pushed every frame from ocean.gd)
//
// The wake rides the boat's PAST TRACK, not its current heading. Anchoring it
// to the heading means the whole wedge swings around the boat the instant you
// put the helm over, and the wake visibly slides sideways across the water. A
// real wake is left behind in the water: its root stays at the transom, and
// everything astern of that keeps the shape of the path the boat actually
// sailed — so a turn draws an arc.
//
// trail[i]: xy = world xz, z = arc length back from the transom, w = the speed
// the boat had there (which is what set the wavelength at that point).
const int MAX_TRAIL = 32;
uniform int trail_count = 0;
uniform vec4 trail[MAX_TRAIL];
uniform float trail_age[MAX_TRAIL];
// Short-lived physical impulses shared with ocean.gd's CPU height queries.
// xy = origin, z = birth time, w = strength.
const int MAX_IMPACTS = 12;
uniform int impact_count = 0;
uniform vec4 impacts[MAX_IMPACTS];
// x = propagation speed, y = initial width, z = width growth, w = damping.
uniform vec4 impact_shape[MAX_IMPACTS];
uniform vec2 boat_pos = vec2(0.0);
uniform float boat_speed = 0.0;
// x = ahead speed, y = lateral slip, z = vertical hull speed, boat-local m/s.
uniform vec3 boat_motion = vec3(0.0);
uniform int hull_mask = 0;
uniform mat4 boat_inv = mat4(1.0);
// 1 when the camera is in the closed cabin. Then the house volume is
// clipped too — otherwise a crest rides through the sole (clip used to
// stop at y 0.52) and the wave is a sheet in the room until the trough.
uniform int interior_clip = 0;

// Lighthouse: two rotating beams. The sea does not pick up clustered
// SpotLights (radiance is already in EMISSION), so the glitter path is
// evaluated here — same idea as the moon path on a real dark sea.
uniform vec3 lh_pos = vec3(0.0);
uniform vec3 lh_dir_a = vec3(0.0, 0.0, -1.0);
uniform vec3 lh_dir_b = vec3(0.0, 0.0, 1.0);
uniform float lh_on = 0.0;

varying vec3 v_world_pos;
varying vec3 v_normal;
// Rest (pre-displacement) xz. This is what indexes the wave field: the
// displacement map is a function of where the water STARTED, not of where the
// pinch moved it to. Interpolating it across the quad is what lets the fragment
// stage re-fetch the gradient per pixel.
varying vec2 v_rest;
// Slope from everything that is not the FFT field -- wake, floaters, shore chop.
// It has to reach the fragment stage because the base normal is rebuilt there.
varying vec2 v_slope;
varying float v_crest;
varying float v_shore;
varying float v_floor_h;
varying float v_wake;
varying float v_fold;
varying float v_disturb;
varying float v_rip;
varying float v_hull_wash;
varying float v_bow_wash;
varying float v_local_foam;
// xy = track axis, z = distance aft, w = signed cross-track distance. Packed in
// one slot: Metal's forward path has a strict varying-count ceiling.
varying vec4 v_wake_frame;

// Rain on water: each cell drops once per cycle and throws an expanding ring.
// Two scales so it does not read as a regular grid.
vec2 rain_ripple(vec2 p, float t) {
	vec2 g = vec2(0.0);
	for (int i = 0; i < 2; i++) {
		float sc = 4.2 + float(i) * 9.7;
		// Rotate the second lattice so the two never line up into a grid.
		vec2 q = (i == 0) ? p : vec2(p.x * 0.80 - p.y * 0.60, p.x * 0.60 + p.y * 0.80);
		vec2 sp = q * sc + float(i) * 37.0;
		vec2 c = floor(sp);
		float h = sky_hash12(c);
		// Only some cells carry a drop at any time, and it lands off-centre.
		float active = step(0.42, sky_hash12(c + 5.1));
		vec2 off = vec2(sky_hash12(c + 3.7), sky_hash12(c + 11.3)) - 0.5;
		vec2 f = fract(sp) - 0.5 - off * 0.7;
		float age = fract(t * 0.8 + h);
		float d = length(f) + 1e-4;
		float ring = sin(d * 15.0 - age * 12.0) * exp(-d * 6.0) * (1.0 - age) * (1.0 - age);
		g += (f / d) * ring * active * (0.9 - 0.45 * float(i));
	}
	return g;
}

float terrain_h(vec2 xz) {
	return texture(height_map, xz / terrain_size + 0.5).r;
}

vec4 local_water(vec2 p) {
	if (local_field_on == 0) {
		return vec4(0.0);
	}
	vec2 uv = (p - local_centre) / max(local_world_size, 1.0) + 0.5;
	float edge = min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y));
	if (edge <= 0.0) {
		return vec4(0.0);
	}
	float rim = smoothstep(0.0, 0.055, edge);
	return textureLod(local_field, clamp(uv, vec2(0.001), vec2(0.999)), 0.0) * rim;
}

vec2 local_water_gradient(vec2 p) {
	if (local_field_on == 0) {
		return vec2(0.0);
	}
	float e = max(local_texel, 0.05);
	float hx0 = local_water(p - vec2(e, 0.0)).r;
	float hx1 = local_water(p + vec2(e, 0.0)).r;
	float hz0 = local_water(p - vec2(0.0, e)).r;
	float hz1 = local_water(p + vec2(0.0, e)).r;
	return vec2(hx1 - hx0, hz1 - hz0) / (2.0 * e);
}

vec3 lh_glitter(vec3 p, vec3 n, vec3 v, vec3 bdir) {
	vec3 to_l = lh_pos - p;
	float dist = length(to_l);
	if (dist > 900.0) {
		return vec3(0.0);
	}
	vec3 L = to_l / max(dist, 0.01);
	// ~16° outer cone, tighter core. Two opposing beams from the optic.
	float cone = smoothstep(0.948, 0.988, dot(-L, bdir));
	if (cone < 0.002) {
		return vec3(0.0);
	}
	vec3 H = normalize(L + v);
	float spec = pow(clamp(dot(n, H), 0.0, 1.0), 14.0);
	float wash = pow(clamp(dot(n, L), 0.0, 1.0), 1.6) * 0.45;
	float atten = 3.2 / (1.0 + dist * 0.0028);
	return vec3(1.0, 0.90, 0.62) * cone * atten * (spec * 2.6 + wash);
}

void vertex() {
	vec2 p = VERTEX.xz;
	float floor_h = terrain_h(p);
	float shore = 1.0 - smoothstep(0.05, 5.8, -floor_h);
	shore *= 1.0 - smoothstep(0.12, 2.4, floor_h);

	// Distance drives which cascades may move this vertex — see cascade_fade.
	float cam_dist = distance(p, CAMERA_POSITION_WORLD.xz);
	// Analytic interaction waves are short-range detail. Past the dense 0.5 m
	// mesh they alias into diamonds and razor-straight ridges; fade their actual
	// displacement before that boundary while leaving wake foam visible.
	// Only the dense close mesh can carry these wavelengths cleanly. Begin the
	// handoff early and make it broad enough that no circular cutoff is visible.
	float interaction_geom = 1.0 - smoothstep(7.5, 13.5, cam_dist);
	WaveSample w = sample_waves(p, cam_dist);
	vec3 disp = w.disp;
	vec2 extra_slope = vec2(0.0);
	vec4 local = local_water(p);
	// The compute field is quarter-metre data. Keep its geometry on the dense
	// close clipmap and hand its remaining slope to the fragment shader; this
	// broad fade is shared by overlapping rings, so no circular seam can open.
	float local_geom = 1.0 - smoothstep(18.0, 24.0, cam_dist);
	disp.y += local.r * local_geom * boat_wave_gain;
	v_local_foam = local.b * (1.0 - smoothstep(22.0, 31.0, cam_dist));

	// Green's law: a wave that feels the bottom slows down, shortens and grows.
	// scripts/ocean.gd applies the same factor to the CPU height query, so the
	// boat keeps floating on the wave you can see even over a shoal.
	float depth_here = max(-floor_h, 0.4);
	float shoal = clamp(pow(clamp(18.0 / depth_here, 1.0, 30.0), 0.25), 1.0, 2.2);
	disp.y *= shoal;

	// Tide rip: where a fast stream runs over a shoal the surface stands up in
	// short steep chop and tears off ragged lines of foam. It is the one thing
	// that makes a current visible from a boat.
	float cur_spd = length(current_vec);
	v_rip = clamp(cur_spd - 0.40, 0.0, 1.6) * smoothstep(26.0, 6.0, depth_here);

	// Floating things write their own waves ON TOP of the FFT field, so the
	// swell keeps running through them — that crossing is the whole point.
	// A still body is a capillary ring. A moving one also leaves expanding
	// rings and a short V, the way a dinghy or a swimmer does.
	v_disturb = 0.0;
	v_hull_wash = 0.0;
	v_bow_wash = 0.0;
	for (int i = 0; i < num_floaters; i++) {
		vec2 fp = floaters[i].xy;
		float rad = max(floaters[i].z, 0.15);
		float str = floaters[i].w;
		vec2 fvel = floater_vel[i].xy;
		float body = floater_vel[i].w;
		float spd = length(fvel);
		float reach = rad * mix(2.6, 11.0, body);
		float dd = length(p - fp);
		if (dd >= reach) {
			continue;
		}
		// The ship already owns the track-based Kelvin wake below. Giving it the
		// same time-driven radial oscillator as a plank made the whole waterline
		// shiver even at rest: energy appeared from nowhere at the hull centre.
		// body == 0 is therefore only a Kelvin-wake source. Actual floating
		// objects and the swimmer (body == 1) still disturb the local surface.
		if (body < 0.5) {
			continue;
		}
		vec2 dir = (p - fp) / max(dd, 1e-4);
		float k = dd / rad;
		float kr = k - 1.1;
		float env = exp(-kr * kr * 14.0);
		float ph = kr * 9.0 - wave_time * 3.6;
		disp.y += sin(ph) * str * 0.45 * env;
		extra_slope += dir * cos(ph) * str * 0.45 * env * 9.0 / rad;
		v_disturb = max(v_disturb, env);
		float fall = exp(-dd / max(rad * 4.8, 1.2));
		float a0 = str * (0.10 + 0.20 * clamp(spd * 0.35, 0.0, 1.0));
		float r1 = dd * 5.4 - wave_time * 3.4;
		float r2 = dd * 9.2 - wave_time * 5.6;
		disp.y += (sin(r1) * 0.62 + sin(r2) * 0.32) * a0 * fall;
		extra_slope += dir * (cos(r1) * 0.62 * 5.4 + cos(r2) * 0.32 * 9.2) * a0 * fall;
		v_disturb = max(v_disturb, fall * 0.85);
		if (spd < 0.35) {
			continue;
		}
		vec2 ahead = fvel / spd;
		vec2 rel = p - fp;
		float along = -dot(rel, ahead);
		float lat = dot(rel, vec2(-ahead.y, ahead.x));
		if (along > 0.15 && along < 9.0) {
			float lam = 1.05 + spd * 0.28;
			float kt = PI2 / max(lam, 0.7);
			float wedge = along * 0.40 + 0.35;
			float e_lat = 1.0 - smoothstep(0.55, 1.15, abs(lat) / max(wedge, 0.2));
			float decay = exp(-along * 0.28);
			float wamp = a0 * 1.15 * e_lat * decay;
			float phd = kt * (0.70 * along + 1.15 * abs(lat));
			disp.y += sin(phd) * wamp;
			extra_slope += ahead * cos(phd) * wamp * kt * 0.70;
			extra_slope += vec2(-ahead.y, ahead.x) * sign(lat)
					* cos(phd) * wamp * kt * 1.15;
			v_disturb = max(v_disturb, e_lat * decay * 0.7);
		}
	}

	// Water-entry impulses. Unlike the old foam disk this displaces the actual
	// surface, and ocean.gd evaluates the same pulse for buoyancy queries.
	for (int i = 0; i < impact_count; i++) {
		float age = wave_time - impacts[i].z;
		if (age < 0.0 || age > 6.0) {
			continue;
		}
		vec2 rel = p - impacts[i].xy;
		float dist = length(rel);
		float radius = age * impact_shape[i].x;
		float sigma = impact_shape[i].y + age * impact_shape[i].z;
		// The ambient FFT surface bends the ring instead of letting it cut across
		// every crest as a mathematically perfect circle.
		float warped_dist = dist + w.disp.y * 0.32;
		float q = (warped_dist - radius) / sigma;
		float decay = exp(-age * impact_shape[i].w);
		float spreading = inversesqrt(1.0 + radius * 0.32);
		float amp = impacts[i].w * 0.18 * decay * spreading;
		// Broad Ricker packet: one rounded crest with shoulders, not a knife line.
		float pulse = (1.0 - 2.0 * q * q) * exp(-q * q);
		disp.y += pulse * amp * interaction_geom;
		vec2 idir = rel / max(dist, 1e-4);
		float dp_dq = (4.0 * q * q * q - 6.0 * q) * exp(-q * q);
		extra_slope += idir * dp_dq * amp / sigma * interaction_geom;
		v_disturb = max(v_disturb, abs(pulse) * decay * 0.9);
	}

	// Water attached to the hull: a pressure ridge at the bow and a thin wash
	// along both shoulders. It is evaluated in boat space, so roll, pitch and
	// heave move the contact line across the actual sides instead of leaving a
	// painted stripe at mean sea level.
	if (hull_mask == 1) {
		vec3 hp = (boat_inv * vec4(vec3(p.x, disp.y, p.y), 1.0)).xyz;
		float hx = 1.48;
		if (hp.z < -3.20) {
			float ht = clamp((-3.20 - hp.z) / 1.50, 0.0, 1.0);
			hx = mix(1.48, 0.16, ht * ht);
		}
		float outside = abs(hp.x) - hx;
		float side_band = exp(-outside * outside / 0.075)
				* smoothstep(-0.10, 0.05, outside)
				* smoothstep(-4.65, -3.75, hp.z)
				* (1.0 - smoothstep(4.0, 5.0, hp.z));
		float bow_band = exp(-pow((hp.z + 4.05) / 0.72, 2.0))
				* exp(-pow(abs(hp.x) / max(hx + 0.35, 0.35), 4.0));
		float contact = 1.0 - smoothstep(0.18, 0.72, abs(hp.y + 0.18));
		float ahead = abs(boat_motion.x);
		// Dynamic pressure rises with v². The linear term keeps steerage-speed
		// wash readable; the quadratic term makes a fast displacement hull build
		// a proper bow shoulder instead of looking identical at every throttle.
		float ahead_drive = ahead * 0.10 + ahead * ahead * 0.052;
		float drive = clamp(ahead_drive + abs(boat_motion.y) * 0.34
				+ abs(boat_motion.z) * 0.42, 0.0, 2.6);
		float pressure = (side_band * 0.55 + bow_band) * contact * drive;
		// Keep the geometry response shallow. A deep procedural ridge attached to
		// the hull visibly breathed as the physics velocity changed; the actual
		// far-field displacement belongs to the Kelvin wake and one-shot impacts.
		disp.y += pressure * 0.065 * boat_wave_gain;
		float wash_gain = mix(1.0, boat_wave_gain, 0.55);
		v_hull_wash = clamp(pressure * 1.65 * wash_gain, 0.0, 1.0);
		v_bow_wash = clamp(bow_band * contact * drive * 1.65 * wash_gain, 0.0, 1.0);
		v_disturb = max(v_disturb, v_hull_wash);
	}

	// --- Kelvin wake ---------------------------------------------------------
	// Two families of waves inside a 19.47 deg half-angle wedge, independent of
	// speed: transverse crests across the track, and divergent crests fanning
	// off the cusp lines. Speed only sets the wavelength.
	//
	// `along` and `lat` are measured against the boat's track: arc length back
	// along the path, and signed distance from it. On a straight course this is
	// identical to the old boat-frame version; in a turn it bends the wedge into
	// the arc the boat actually left behind.
	v_wake = 0.0;
	v_wake_frame = vec4(0.0, 1.0, -1.0, 0.0);
	float along = -1.0;
	float lat = 0.0;
	float spd = 0.0;
	float wake_age = 0.0;
	vec2 axis = vec2(0.0, 1.0);
	if (trail_count > 1 && distance(p, boat_pos) < 170.0) {
		float best = 1e9;
		for (int i = 0; i < trail_count - 1; i++) {
			vec2 a = trail[i].xy;
			vec2 ab = trail[i + 1].xy - a;
			float l2 = max(dot(ab, ab), 1e-4);
			float u = clamp(dot(p - a, ab) / l2, 0.0, 1.0);
			vec2 d = p - (a + ab * u);
			float dd = dot(d, d);
			if (dd < best) {
				best = dd;
				float dl = sqrt(dd);
				// Sign says which side of the track we are on; the divergent
				// arms are mirror images about it.
				float sgn = (ab.x * d.y - ab.y * d.x) < 0.0 ? -1.0 : 1.0;
				lat = dl * sgn;
				along = mix(trail[i].z, trail[i + 1].z, u);
				spd = mix(trail[i].w, trail[i + 1].w, u);
				wake_age = mix(trail_age[i], trail_age[i + 1], u);
				axis = normalize(ab + vec2(1e-6, 0.0));
			}
		}
	}
	spd = clamp(spd, 0.0, 26.0);
	if (along >= 0.0 && along < 155.0 && spd > 0.55) {
		v_wake_frame = vec4(axis, along, lat);
		float lam = PI2 * spd * spd / G;                // transverse wavelength
		float kt = PI2 / max(lam, 0.9);
		float high_froude = smoothstep(7.0, 15.0, spd);
		float speed01 = smoothstep(1.5, 11.0, spd);
		// A finite fast hull's apparent V narrows even though the stationary-phase
		// Kelvin limit is 19.47 degrees. This keeps full-power wash energetic rather
		// than spreading it into an implausibly wide white triangle.
		float wedge_slope = mix(0.3536, 0.235, high_froude);
		float wedge = along * wedge_slope + 1.05;
		float e_lat = 1.0 - smoothstep(0.62, 1.06, abs(lat) / wedge);
		float decay = exp(-along * 0.016) / sqrt(max(along, 1.2));
		float age_decay = exp(-wake_age / 13.5);
		// Do not saturate at harbour speed: resistance-wave energy keeps growing,
		// but caps before a game-speed boat can throw a several-metre wall of water.
		float speed_energy = clamp(pow(spd / 4.2, 1.35), 0.0, 5.2);
		// A 19 m displacement wake is perfectly resolvable on the 2 m mid ring;
		// a one-metre dead-slow ripple is not. Reach therefore follows wavelength
		// instead of using the old universal 13.5 m cutoff.
		float geom_reach = mix(21.0, 122.0, smoothstep(2.1, 11.0, spd));
		float wake_geom = 1.0 - smoothstep(geom_reach * 0.82, geom_reach, cam_dist);
		// Close the transom-to-Kelvin hand-off with an AFT-MOVING turbulent train.
		// The far Kelvin pattern is correctly steady in the vessel frame, but the
		// prop wash and the short waves it sheds are parcels of water: they must
		// travel down the track instead of looking bolted to the camera/boat.
		float aft_flow = spd * mix(0.18, 0.37, speed01);
		float shed_coord = along - wave_time * aft_flow;
		float near_w = mix(0.68, 1.15, speed01) + along * 0.045;
		float near_env = exp(-lat * lat / (near_w * near_w))
				* (1.0 - smoothstep(19.0, 36.0, along)) * wake_geom * age_decay;
		float near_k = mix(2.7, 1.35, speed01);
		float near_phase = shed_coord * near_k + abs(lat) * 1.45;
		float near_amp = mix(0.035, 0.22, speed01) * boat_wave_gain;
		disp.y += (-0.08 + sin(near_phase) * 0.82) * near_amp * near_env;
		extra_slope += axis * cos(near_phase) * near_k * 0.82 * near_amp * near_env;
		extra_slope += vec2(-axis.y, axis.x) * sign(lat) * cos(near_phase)
				* 1.45 * 0.82 * near_amp * near_env;

		// Two broken shear shoulders flank the prop stream. They widen with speed
		// and move aft with it, disturbing dark water as geometry rather than merely
		// whitening a static centre strip.
		float shear_centre = near_w * mix(0.52, 0.76, speed01);
		float shear_width = 0.32 + along * 0.020;
		float shear_q = (abs(lat) - shear_centre) / max(shear_width, 0.20);
		float shear_env = exp(-shear_q * shear_q)
				* (1.0 - smoothstep(22.0, 40.0, along)) * wake_geom * age_decay;
		float shear_k = mix(3.2, 1.75, speed01);
		float shear_phase = shed_coord * shear_k + abs(lat) * 2.15 + 1.7;
		float shear_amp = near_amp * mix(0.30, 0.58, speed01);
		disp.y += sin(shear_phase) * shear_amp * shear_env;
		extra_slope += axis * cos(shear_phase) * shear_k * shear_amp * shear_env;
		extra_slope += vec2(-axis.y, axis.x) * sign(lat) * cos(shear_phase)
				* 2.15 * shear_amp * shear_env;

		// The far-field system is deliberately lower than the near turbulent train.
		// Resistance-wave energy grows with speed, but never into the multi-metre
		// ridge produced by the first uncapped full-power pass.
		float amp = 0.12 * boat_wave_gain * speed_energy * e_lat * decay
				* smoothstep(0.0, 3.0, along) * wake_geom * age_decay;
		// Source phase is explicit. Starting sin() at zero postponed the first crest
		// by lambda/4; at full power that can be tens of metres, which looked as if
		// the wake appeared in empty water after the boat had already passed.
		float ph_t = kt * along + 1.18;
		// The visible divergent family stays shorter than the very long transverse
		// component at high Froude number, as real stern/quarter waves do.
		float lam_d = clamp(lam * mix(0.62, 0.34, high_froude), 1.8, 46.0);
		float kd = PI2 / lam_d;
		float ph_d = kd * (0.76 * along + 1.32 * abs(lat)) + 0.72;
		disp.y += amp * (sin(ph_t) * 0.45 + sin(ph_d) * 0.9);
		extra_slope += axis * amp * (kt * cos(ph_t) * 0.45
				+ kd * cos(ph_d) * 0.9 * 0.76);
		extra_slope += vec2(-axis.y, axis.x) * sign(lat)
				* amp * kd * cos(ph_d) * 0.9 * 1.32;
		// Foam lives in two thin places, not across the whole wedge:
		//   track — the churned water directly astern, roughly a hull's width,
		//           spreading slowly and dying within ~20 m
		//   cusp  — the breaking crest that runs along each edge of the wedge
		float half_w = mix(0.58, 0.92, speed01) + along * mix(0.026, 0.043, speed01);
		float track_decay = mix(0.15, 0.052, speed01);
		float track = exp(-lat * lat / (half_w * half_w)) * exp(-along * track_decay);
		// Uneven aerated parcels expose their aft motion. A non-zero floor keeps
		// prop wash connected to the transom while the bright patches move away.
		float shed_wave = sin(shed_coord * 0.58
				+ sin(shed_coord * 0.17 + lat * 1.25));
		float shed_packets = mix(0.58, 1.18, 0.5 + 0.5 * shed_wave);
		track *= mix(1.0, shed_packets, speed01);
		float edge = abs(lat) / max(wedge, 0.7) - 0.80;
		float cusp = exp(-edge * edge * 40.0) * exp(-along * mix(0.070, 0.034, speed01))
				* mix(0.18, 0.34, speed01);
		float foam_energy = clamp(pow(spd / 10.5, 1.25), 0.0, 1.35);
		v_wake = clamp((track + cusp) * foam_energy
				* mix(1.0, boat_wave_gain, 0.45) * age_decay, 0.0, 1.0);
	}

	// Shore chop: extra small waves where water meets sand / islets.
	if (shore > 0.02) {
		float sch = sin(p.x * 2.4 + p.y * 1.7 + wave_time * 3.2)
				* sin(p.x * 1.1 - p.y * 2.0 - wave_time * 2.4);
		disp.y += sch * 0.11 * shore;
		extra_slope += vec2(cos(p.x * 2.4 + wave_time * 3.2), cos(p.y * 1.7 + wave_time * 3.2))
				* 0.12 * shore;
	}

	VERTEX += disp;
	// Earth curvature — drops the surface away with the square of the distance.
	VERTEX.y -= cam_dist * cam_dist * curvature_k;

	vec3 n = normalize(w.normal + vec3(-extra_slope.x, 0.0, -extra_slope.y));
	NORMAL = n;
	v_normal = n;
	v_rest = p;
	v_slope = extra_slope;
	v_world_pos = VERTEX;
	v_crest = clamp(disp.y / max(max_amp, 0.001), -1.0, 1.0);
	v_shore = shore;
	v_floor_h = floor_h;

	// Whitecaps come out of the FFT unpack pass, which accumulates foam where the
	// surface folds and decays it exponentially everywhere else — a real
	// persistent foam field, sampled per pixel below. What stays here is the
	// shallow-water term the field cannot know about: a wave breaks when its
	// height passes ~0.78 of the depth under it.
	v_fold = clamp(2.0 * abs(disp.y) / depth_here - 0.55, 0.0, 1.0) * 0.6;
}

// Linear view-space depth of whatever opaque geometry sits behind this pixel.
// INV_PROJECTION_MATRIX only exists inside fragment(), so it comes in as an arg.
float scene_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).x;
	vec4 view = inv_proj * vec4(vec3(uv * 2.0 - 1.0, d), 1.0);
	return -(view.xyz / view.w).z;
}

void fragment() {
	// never draw sea inside the hull. The clip is the INTERIOR below the
	// deck, not a 2.4 m box around the whole house: a tall box leans
	// outboard through the waterline the moment she heels, and punches a
	// sharp parallelogram out of the sea along the gunwale.
	if (hull_mask == 1) {
		vec3 lp = (boat_inv * vec4(v_world_pos, 1.0)).xyz;
		// Underwater, only deepen the keel cut. The old 20 cm pad on XZ
		// punched a rectangle of missing sea in front of the stem — the
		// bow is a wedge, not a box.
		float keel = camera_under == 1 ? 0.16 : 0.0;
		float hx = 1.48;
		if (lp.z < -3.20) {
			float t = clamp((-3.20 - lp.z) / 1.50, 0.0, 1.0);
			hx = mix(1.48, 0.16, t * t);
		}
		bool cut = abs(lp.x) < hx && lp.z > -4.58 && lp.z < 4.62
				&& lp.y > -1.18 - keel && lp.y < 0.50;
		if (interior_clip == 1) {
			cut = cut || (abs(lp.x) < 1.62 && lp.z > -0.35 && lp.z < 4.55
					&& lp.y > 0.56 && lp.y < 2.82);
		}
		if (cut) {
			discard;
		}
	}
	if (far_clip == 1 && length(v_world_pos.xz - boat_pos) < near_radius) {
		discard;
	}
	// Don't draw water over dry island tops.
	if (v_floor_h > v_world_pos.y + 0.08) {
		discard;
	}

	float dist = length(CAMERA_POSITION_WORLD - v_world_pos);

	// --- surface normal ------------------------------------------------------
	// The wave normal comes entirely from the FFT cascades now. There used to be
	// four tiled detail-normal fetches layered on top, at world scales that
	// repeated every 43, 11, 4.8 and 1.3 metres. The FFT field reaches 8 cm on
	// its own, so those layers were adding a visible repeat to detail it already
	// had — and costing three to four texture reads per pixel of sea to do it.
	//
	// What survives here is rain: ring waves stippled onto the surface, and the
	// way a downpour flattens the small chop into a matte sheet.
	float detail_fade = clamp(1.0 - dist / 260.0, 0.0, 1.0);
	detail_fade *= detail_fade;
	float near_fade = clamp(1.0 - dist / 32.0, 0.0, 1.0);
	vec2 pert = vec2(0.0);
	if (rain_amount > 0.01 && near_fade > 0.02) {
		pert += rain_ripple(v_world_pos.xz, wave_time) * rain_amount * 0.30 * near_fade;
	}
	// Sub-grid prop turbulence: two advected noise bands become moving slopes in
	// the holes between foam. Without this, the white texture changes but the
	// underlying water remains a calm mirror and the whole wake reads as a decal.
	if (v_wake > 0.012 && v_wake_frame.z >= 0.0 && dist < 72.0) {
		float wake_speed01 = smoothstep(1.5, 11.0, boat_speed);
		float wake_aft_flow = boat_speed * mix(0.18, 0.37, wake_speed01);
		float wake_coord = v_wake_frame.z - wave_time * wake_aft_flow;
		vec2 wake_axis = normalize(v_wake_frame.xy + vec2(1e-6, 0.0));
		vec2 wake_perp = vec2(-wake_axis.y, wake_axis.x);
		vec2 wake_uv = vec2(wake_coord, v_wake_frame.w);
		float turb_a = texture(foam_noise, wake_uv * vec2(0.42, 0.82)).r - 0.5;
		float turb_b = texture(foam_noise,
				wake_uv.yx * vec2(0.91, 0.33) + vec2(17.3, 8.1)).r - 0.5;
		float wake_near = 1.0 - smoothstep(27.0, 48.0, v_wake_frame.z);
		float wake_dist = 1.0 - smoothstep(46.0, 72.0, dist);
		float turb_amp = mix(0.025, 0.22, wake_speed01)
				* sqrt(v_wake) * wake_near * wake_dist;
		pert += (wake_axis * turb_a + wake_perp * turb_b) * turb_amp;
	}

	// Base wave normal, rebuilt per pixel rather than interpolated from the
	// vertex. One sample per quad is fine at 0.5 m quads and a faceted mess at
	// 9 m ones — and this is also where the cascades too short for this ring's
	// geometry come back in, as slope rather than as crawling vertices.
	vec2 wgrad;
	float wfoam;
	wave_gradient(v_rest, dist, wgrad, wfoam);
	// Re-sample the interaction field per pixel. The vertex slope keeps the
	// silhouette honest; this fetch preserves quarter-metre prop and impact
	// detail between half-metre close-ring vertices.
	wgrad += local_water_gradient(v_rest) * boat_wave_gain
			* (1.0 - smoothstep(22.0, 31.0, dist));
	// Heavy rain visibly flattens the small chop — the sea goes matte under a
	// downpour. It used to damp the detail-normal layers; now it damps the real
	// gradient, which is the same statement about the same waves.
	wgrad *= (1.0 - rain_amount * 0.4) * normal_strength;
	vec3 base_n = normalize(vec3(-wgrad.x - v_slope.x, 1.0, -wgrad.y - v_slope.y));
	float fold = max(wfoam, v_fold);
	vec3 wn = normalize(base_n + vec3(pert.x, 0.0, pert.y));

	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	vec3 view_n = (VIEW_MATRIX * vec4(wn, 0.0)).xyz;
	float ndotv = clamp(dot(wn, view_dir), 1e-4, 1.0);

	// --- foam ----------------------------------------------------------------
	// Foam is not painted on the water, it floats on it: everything below is
	// sampled in a frame that drifts downwind at the Stokes drift speed, so a
	// patch of foam keeps moving after the wave that made it has gone.
	// Three noise fetches, and on open water there is usually nothing for them
	// to break up. One cheap test on the varyings decides whether to pay.
	float foam_src = max(max(fold, v_shore),
			max(max(max(v_wake, v_disturb), v_rip), v_local_foam));
	float foam = 0.0;
	float shore_foam = 0.0;
	float foam_hi = 0.0;
	if (foam_src > 0.002) {
		// Foam is not painted on the water, it floats on it: sampled in a frame
		// that drifts downwind, so a patch keeps moving after the wave that made
		// it has gone.
		vec2 foam_p = v_world_pos.xz - surface_drift * wave_time;
		float foam_n = texture(foam_noise, foam_p * 0.11).r;
		vec2 wdir_f = normalize(wind_dir + vec2(0.0001));
		vec2 along_uv = vec2(dot(foam_p, wdir_f), dot(foam_p, vec2(-wdir_f.y, wdir_f.x)));
		float streak = texture(foam_noise, along_uv * vec2(0.07, 0.28)).r;
		// Two noise scales: the wind streak decides which crests carry foam, the
		// fine scale breaks each patch into bubbles instead of a milk sheet.
		foam_hi = texture(foam_noise, foam_p * 1.30).r;
		float foam_tex = clamp(foam_n * (0.30 + 1.5 * streak), 0.0, 1.0)
				* (0.20 + 1.15 * foam_hi);
		// Foam sits on the shoulder and crest of a wave, never in the trough.
		float crest_gate = smoothstep(-0.30, 0.30, v_crest);
		foam = smoothstep(0.04, 0.62, fold) * foam_tex * foam_amount * crest_gate;
		foam = clamp(foam, 0.0, 1.0);
		foam *= foam * (3.0 - 2.0 * foam);  // sharpen: churned edges, not airbrush
		float shore_pulse = 0.55 + 0.45 * sin(wave_time * 2.4 + v_floor_h * 9.0 + foam_n * 5.0);
		shore_foam = v_shore * foam_n * shore_pulse * 0.85;
		// Ragged, not geometric: the noise has to bite hard enough that the wedge
		// edge never reads as a drawn line.
		float wake_n = foam_n * 0.42 + foam_hi * 0.68;
		// Aerated wash is a lace of bubbles with dark water holes, not an opaque
		// white carpet. Speed extends v_wake upstream; it does not force every pixel
		// in that envelope to pure foam.
		float wake_foam = smoothstep(0.34, 0.96,
				v_wake * (0.22 + 1.08 * wake_n)) * (0.38 + foam_hi * 0.24);
		// Foam albedo is ~10x the water's, so even a little of it doubles the
		// brightness. A waterline ring gets a hint, not a halo.
		float floater_foam = v_disturb * (0.15 + 0.85 * foam_hi) * 0.035;
		float side_wash = max(v_hull_wash - v_bow_wash, 0.0);
		float hull_foam = side_wash * (0.20 + 0.80 * foam_hi) * 0.16
				+ v_bow_wash * (0.30 + 0.92 * foam_hi) * 0.62;
		float local_foam = smoothstep(0.012, 0.34, v_local_foam)
				* (0.22 + 0.88 * foam_hi);
		// Rip foam is drawn out into lines by the flow, not scattered like
		// whitecaps, so it is streaked along the current.
		vec2 cdir = normalize(current_vec + vec2(1e-5));
		vec2 rip_uv = vec2(dot(foam_p, cdir) * 0.06, dot(foam_p, vec2(-cdir.y, cdir.x)) * 0.55);
		float rip_n = texture(foam_noise, rip_uv).r;
		float rip_foam = smoothstep(0.35, 0.95, v_rip * (0.4 + 1.5 * rip_n)) * 0.5;
		foam = clamp(foam + shore_foam + wake_foam + floater_foam
				+ hull_foam + local_foam + rip_foam, 0.0, 1.0);
	}

	// --- roughness -----------------------------------------------------------
	// GGX alpha from mean square slope. Whatever chop we stopped drawing gets
	// folded back in here, so energy is spread rather than lost.
	float lost = 1.0 - detail_fade;
	// A rip is rougher water: the extra short chop it stands up is far too small
	// to draw, so it arrives as slope variance.
	float wake_speed01 = smoothstep(1.5, 11.0, boat_speed);
	float wake_break = v_wake * wake_speed01
			* (1.0 - smoothstep(34.0, 82.0, max(v_wake_frame.z, 0.0)));
	float mss_eff = (mss + v_rip * 0.04 + wake_break * 0.060)
			* (1.0 - rain_amount * 0.45);
	// Cox-Munk variance is a distribution of unresolved slopes, not a direct
	// perceptual-roughness value. Feeding it to GGX at full strength turned the
	// far sea into one grey average and erased the dark/bright faces that sell
	// scale in the reference. Preserve energy, but keep directional structure.
	float alpha_g = sqrt(0.72 * mss_eff * (0.08 + 0.92 * lost)
			+ base_roughness * base_roughness);
	float rough = clamp(alpha_g, base_roughness, 0.42);
	rough = mix(rough, 0.72, foam);

	// --- reflection ----------------------------------------------------------
	vec3 refl_dir = reflect(-view_dir, wn);
	// Steep faces are allowed to see the dark lower hemisphere. Folding every
	// negative ray upward made a gale one flat reflection of the bright horizon.
	refl_dir.y = max(refl_dir.y, -0.22);
	vec3 reflection = sky_color(normalize(refl_dir), clamp(rough * 2.2, 0.0, 1.0), 0.0);
	reflection = mix(reflection, sky_ambient, clamp(rough * 0.72, 0.0, 0.30));
	// Everything that is not sky: boat, buoy, flotsam, the lighthouse. The
	// mirror camera is an ordinary right-handed camera placed at the reflected
	// position, so its image comes out horizontally flipped relative to the
	// main view — hence 1 - u, and the sideways wobble has to flip with it.
	if (reflect_on == 1) {
		vec2 ruv = vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y);
		// Distort by slope RELATIVE to a flat water plane. Using the complete
		// view-space normal added the camera's pitch as a permanent UV offset;
		// mast lights then detached from the hull and jumped as the camera moved.
		vec3 flat_view_n = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
		vec2 refl_slope = view_n.xy - flat_view_n.xy;
		ruv += vec2(-refl_slope.x, refl_slope.y) * 0.022
				* clamp(1.0 - rough * 1.35, 0.0, 1.0);
		vec4 pr = texture(reflect_tex, clamp(ruv, vec2(0.002), vec2(0.998)));
		// Alpha is the coverage mask for solid things, but anything drawn with
		// additive blending — the lighthouse beams, the lantern glass — adds
		// colour without ever writing alpha. Take brightness as coverage too, or
		// the one light for miles never lands on the water.
		float emissive_cov = smoothstep(0.10, 0.72,
				dot(pr.rgb, vec3(0.34, 0.5, 0.16))) * 0.86;
		float cov = max(pr.a, emissive_cov);
		// One plane cannot fit a whole sea: fade the planar term out where this
		// fragment is far from the plane it was rendered for, and let the
		// analytic sky carry those pixels instead.
		// The lookup is exact for a flat mirror at any height; what it cannot
		// know is that the real surface is not flat. Fade where this fragment
		// is far from the plane the reflection was rendered for — but gently,
		// because cutting it hard makes reflections blink in and out as the
		// swell passes under them.
		float pw = 1.0 - smoothstep(2.5, 9.0, abs(v_world_pos.y - reflect_plane_y));
		reflection = mix(reflection, pr.rgb,
				cov * clamp(1.0 - rough * 1.1, 0.0, 1.0) * mix(0.6, 1.0, pw));
	}

	// Schlick with water's real F0 (n = 1.333 -> 0.02).
	float f0 = 0.02;
	float fresnel = f0 + (1.0 - f0) * pow(1.0 - ndotv, 5.0);
	// A rough surface never reaches a perfect grazing mirror.
	fresnel = mix(fresnel, clamp(fresnel, 0.0, 0.84), clamp(rough * 1.25, 0.0, 0.72));

	// --- refraction + absorption --------------------------------------------
	float water_dist = -(VIEW_MATRIX * vec4(v_world_pos, 1.0)).z;
	// The seabed depth alone is a lower bound on how much water the light has to
	// cross, so exp(-extinction * that) is an UPPER bound on what can come
	// through. Over open ocean it is already zero, and then the depth and screen
	// reads below cannot change the answer — so skip all three of them.
	float floor_thick = max(v_world_pos.y - v_floor_h, 0.0) * absorb_k;
	vec3 transmit = exp(-extinction * floor_thick);
	vec3 behind_col = vec3(0.0);
	if (max(transmit.r, max(transmit.g, transmit.b)) > 0.008) {
		vec2 base_uv = SCREEN_UV;
		vec2 refr_uv = base_uv + view_n.xy * refraction_strength * 0.045
				/ max(water_dist * 0.6, 1.0);
		refr_uv = clamp(refr_uv, vec2(0.001), vec2(0.999));
		float behind = scene_depth(refr_uv, INV_PROJECTION_MATRIX);
		// If the refracted sample grabbed something in FRONT of the water (the
		// boat hull, a rock), fall back to the straight sample — otherwise its
		// edges smear across the surface.
		if (behind < water_dist) {
			refr_uv = base_uv;
			behind = scene_depth(base_uv, INV_PROJECTION_MATRIX);
		}
		float thickness = max(max(behind - water_dist, 0.0), floor_thick);
		transmit = exp(-extinction * thickness);
		behind_col = texture(screen_tex, refr_uv).rgb;
	} else {
		transmit = vec3(0.0);
	}
	// Whatever the water body does not swallow shows through; what it swallows
	// is re-emitted as the diffuse scatter below.
	transmit *= 1.0 - clamp(scatter_strength, 0.0, 1.0) * 0.15;

	// --- subsurface: sun through the back of a crest -------------------------
	float back = clamp(dot(-sun_dir, view_dir), 0.0, 1.0);
	float crest = max(v_crest, 0.0);
	float sss = pow(back, 3.0) * crest * crest * (1.0 - foam) * sss_strength;

	// Split the surface the way the physics does:
	//   diffuse  — light scattered back out of the water body, and foam, both of
	//              which are genuinely lit by sun + sky, so they go to ALBEDO and
	//              the engine lights them (and darkens them in shadow).
	//   emissive — the reflected sky and the light transmitted up through the
	//              water. Both are radiance that has already been lit; running
	//              them through a BRDF a second time would be double counting.
	// With the sun near the horizon a crest shadows the trough behind it. Cheap
	// stand-in for the real thing: the lower the sun, the more the troughs go
	// dark. Without it a low sun lights every part of the sea equally, which is
	// the giveaway that the surface is a shaded plane rather than terrain.
	float sun_elev = clamp(sun_dir.y, 0.0, 1.0);
	float wave_shadow = mix(1.0, smoothstep(-0.65, 0.10, v_crest),
			clamp(1.0 - sun_elev * 2.2, 0.0, 1.0) * 0.75);

	vec3 diffuse_albedo = mix(scatter_color * scatter_strength * (1.0 - fresnel) * wave_shadow,
			foam_color * mix(0.55, 1.0, wave_shadow), foam);
	vec3 col = behind_col * transmit * (1.0 - fresnel) * (1.0 - foam)
			+ reflection * fresnel * (1.0 - foam * 0.7)
			+ scatter_color * sun_color * sun_energy * sss * 9.0 * wave_shadow;

	// --- underwater ----------------------------------------------------------
	// Water → air. Critical angle ~48.6° (cos ≈ 0.66). The window is where
	// this ray, against the LOCAL normal, still refracts; everywhere else is
	// TIR — a dark mirror of the basin. Mesh normals used to stay out of it
	// because they faceted the sun into clipmap quads. The sun stays a
	// refracted sky sample (and a screen-space lamp in the post), not a disc
	// painted on the mesh. The normal only tears the window.
	if (camera_under == 1) {
		float water_z = -(VIEW_MATRIX * vec4(v_world_pos, 1.0)).z;
		float behind = scene_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
		if (behind + 0.04 < water_z) {
			discard;
		}
		vec3 I = -view_dir;
		vec2 micro = texture(foam_noise, v_world_pos.xz * 1.9 + wave_time * vec2(0.06, -0.04)).rg;
		vec3 n_u = normalize(wn + vec3(micro.x - 0.5, 0.0, micro.y - 0.5)
				* (0.38 + 0.22 * rain_amount) * near_fade);
		n_u = normalize(n_u + vec3(0.0, -0.10 * foam - 0.06 * fold, 0.0));
		float ci = clamp(dot(I, n_u), 0.0, 1.0);
		// cos(θc) for n=1.333. Soften a few degrees so the tear is a shard
		// edge, not a pixel staircase.
		float win = smoothstep(0.615, 0.725, ci);
		// The optical window is overhead, never a bright horizon stripe.  At the
		// clipmap hand-off any remaining near-critical light is multiple-scattered
		// into the water volume instead of exposing the coarse far plate.
		win *= 1.0 - smoothstep(65.0, 145.0, dist);
		vec3 air = refract(I, -n_u, 1.333);
		if (dot(air, air) < 1e-5) {
			air = I;
			air.y = max(air.y, 0.04);
		}
		air = normalize(air);
		vec3 through = sky_color(air, clamp(rough * 1.6, 0.0, 1.0), 0.0);
		float thin = smoothstep(0.02, 0.52, max(v_crest, 0.0));
		through *= 0.50 + 0.76 * thin + 0.20 * sun_energy;
		// Shredded sun: only along the refracted ray. Follows the slope, not
		// the clipmap.
		float sun_along = max(dot(air, sun_dir), 0.0);
		through += sun_color * pow(sun_along, 72.0) * sun_energy * (0.25 + 1.1 * thin) * win;

		vec2 suv = clamp(SCREEN_UV + n_u.xz * 0.035 + view_n.xy * 0.018,
				vec2(0.002), vec2(0.998));
		vec3 scene = textureLod(screen_tex, suv, 0.0).rgb;
		float scene_l = dot(scene, vec3(0.299, 0.587, 0.114));
		// Outside Snell's window the ceiling reflects the underwater world. Screen
		// colour is the available scene term; a low, depth-coloured irradiance keeps
		// empty open water from becoming a featureless black polygon.
		vec3 dark = scatter_color * (0.42 + 0.34 * sun_energy)
				+ vec3(0.004, 0.018, 0.021);
		// SCREEN_TEXTURE also contains the bright sky behind the transparent sea.
		// That is not an underwater reflection: accepting it painted the sky's
		// horizon as a ruler-straight white line through the basin. Depth admits
		// nearby hull/seabed geometry and rejects background radiance.
		float solid_scene = 1.0 - smoothstep(120.0, 300.0, behind);
		vec3 mirror = mix(dark, scene * vec3(0.50, 0.74, 0.78) + dark * 0.35,
				smoothstep(0.025, 0.22, scene_l) * 0.62 * solid_scene);
		col = mix(mirror, through, win);

		float specks = texture(foam_noise, v_world_pos.xz * 3.8 - wave_time * 0.12).r;
		float trapped = smoothstep(0.64, 0.93, specks)
				* (0.20 + 0.80 * foam + 0.40 * fold) * near_fade;
		col += foam_color * trapped * (0.18 + 0.55 * sun_energy);
		col = mix(col, foam_color * (0.10 + 0.32 * sun_energy), foam * 0.50);

		vec3 beer_u = exp(-extinction * max(water_z, 0.0) * 0.075);
		col *= mix(beer_u, vec3(1.0), 0.12);
		col = mix(dark, col, clamp(beer_u.g * 1.55, 0.0, 1.0));
		float volume_handoff = smoothstep(55.0, 145.0, dist);
		col = mix(col, dark * (0.75 + 0.25 * sun_energy), volume_handoff);
		diffuse_albedo = vec3(0.0);
		rough = 1.0;
	}

	ALBEDO = diffuse_albedo;
	METALLIC = 0.0;
	// SPECULAR 0.5 == F0 0.04; water is 0.02.
	SPECULAR = mix(0.25, 0.42, foam);
	ROUGHNESS = rough;
	NORMAL = camera_under == 1 ? vec3(0.0, 0.0, 1.0) : normalize(view_n);
	EMISSION = col + foam_color * shore_foam * 0.12;
	if (lh_on > 0.02 && camera_under == 0) {
		EMISSION += lh_glitter(v_world_pos, wn, view_dir, lh_dir_a) * lh_on;
		EMISSION += lh_glitter(v_world_pos, wn, view_dir, lh_dir_b) * lh_on;
	}
	ALPHA = 1.0;
}
