shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec2 focus = vec2(0.53, 0.61);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = (uv - focus) * vec2(1.0, 0.88);
	float outside = smoothstep(0.20, 0.59, length(d));
	float strength = amount * outside;
	vec4 sharp = textureLod(screen_texture, uv, 0.0);
	vec2 px = SCREEN_PIXEL_SIZE * (2.0 + 5.5 * strength);
	vec4 soft = textureLod(screen_texture, uv, 1.4 * strength) * 0.24;
	soft += texture(screen_texture, uv + vec2(px.x, 0.0)) * 0.12;
	soft += texture(screen_texture, uv - vec2(px.x, 0.0)) * 0.12;
	soft += texture(screen_texture, uv + vec2(0.0, px.y)) * 0.12;
	soft += texture(screen_texture, uv - vec2(0.0, px.y)) * 0.12;
	soft += texture(screen_texture, uv + px) * 0.07;
	soft += texture(screen_texture, uv - px) * 0.07;
	soft += texture(screen_texture, uv + vec2(px.x, -px.y)) * 0.07;
	soft += texture(screen_texture, uv + vec2(-px.x, px.y)) * 0.07;
	// A mild optical vignette makes this read as attention/depth of field,
	// rather than a UI panel laid over the world.
	soft.rgb *= 1.0 - 0.055 * strength;
	COLOR = mix(sharp, soft, strength * 0.82);
}
