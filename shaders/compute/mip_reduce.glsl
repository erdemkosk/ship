#[compute]
#version 460
/**
 * One level of a mip chain for the wave normal maps: 2x2 box average.
 *
 * Without this the sea shimmers. The normal map is a 256-tap field tiled every
 * few metres, so past a hundred metres a single screen pixel covers many texels
 * and point-sampling one of them turns real wave slope into crawling noise.
 * Fading whole cascades out with distance would stop the shimmer and take the
 * band's long waves with it, which is the wrong trade: a 20 m wave is still
 * worth drawing at 300 m even though the 20 cm wave in the same cascade is not.
 * A mip chain separates them properly — each pixel reads the level its own
 * footprint warrants, so the long end survives and only the short end averages
 * away.
 *
 * Gradients and foam coverage are both linear quantities, so a plain box filter
 * is the correct reduction for them.
 *
 * Works on a single array layer at a time: Godot 4.7 can only slice an array
 * texture into TEXTURE_SLICE_2D views, so there is no way to bind a whole
 * cascade stack at one mip level. One dispatch per (level, cascade).
 */

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) restrict readonly uniform image2D src;
layout(rgba16f, set = 0, binding = 1) restrict writeonly uniform image2D dst;

layout(push_constant) restrict readonly uniform PushConstants {
	uint dst_size;
	uint pad0;
	uint pad1;
	uint pad2;
};

void main() {
	const ivec2 d = ivec2(gl_GlobalInvocationID.xy);
	if (d.x >= int(dst_size) || d.y >= int(dst_size)) {
		return;
	}
	const ivec2 s = d * 2;
	vec4 v = imageLoad(src, s)
			+ imageLoad(src, s + ivec2(1, 0))
			+ imageLoad(src, s + ivec2(0, 1))
			+ imageLoad(src, s + ivec2(1, 1));
	imageStore(dst, d, v * 0.25);
}
