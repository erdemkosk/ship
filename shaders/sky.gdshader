shader_type sky;

// Weather-driven procedural sky: FBM clouds that drift with the wind,
// sun/moon disk, night stars, and lightning that lights the cloud deck from
// within. The body lives in sky_common.gdshaderinc so the ocean shader can
// reflect the exact same sky. Parameters are pushed from scripts/weather.gd.
#include "res://shaders/sky_common.gdshaderinc"

void sky() {
	vec3 dir = EYEDIR;
	vec3 col = sky_color_n(dir, 0.0, 1.0, 2);
	// A hair of ground darkening right under the eye line; the sea itself now
	// reaches the true horizon, so this must not read as a band.
	col = mix(col, ground_color, smoothstep(-0.004, -0.05, dir.y));
	COLOR = col;
}
