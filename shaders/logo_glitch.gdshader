shader_type canvas_item;
render_mode unshaded, blend_mix;

// Light title-card glitch: RGB split, a few horizontal slices, faint scan.
// `amount` 0 is clean; keep it low or the logo reads as a TV fault, not a name.

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float a = amount;
	float band = floor(uv.y * 36.0);
	float tick = floor(time * 19.0);
	float slice = (hash(band + tick) - 0.5) * a * 0.055;
	uv.x += slice;
	uv.x = clamp(uv.x, 0.001, 0.999);

	float split = a * 0.010;
	vec4 mid = texture(TEXTURE, uv);
	float r = texture(TEXTURE, vec2(clamp(uv.x + split, 0.0, 1.0), uv.y)).r;
	float b = texture(TEXTURE, vec2(clamp(uv.x - split, 0.0, 1.0), uv.y)).b;
	float scan = 1.0 - a * 0.12 * (0.5 + 0.5 * sin(uv.y * 780.0 + time * 28.0));
	COLOR = vec4(r * scan, mid.g * scan, b * scan, mid.a);
}
