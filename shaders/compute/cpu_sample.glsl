#[compute]
#version 460
/**
 * Downsamples the displacement/normal maps into a small CPU-readable buffer.
 *
 * The whole reason this project could keep the boat floating on the wave you can
 * see was that one analytic function ran on both sides. An FFT field has no such
 * function -- it only exists as a texture on the GPU. This pass is the
 * replacement contract: the CPU reads back the SAME texels the vertex shader
 * displaces with, just coarser.
 *
 * Coarser is fine. The field is periodic with the cascade's tile length, so a
 * GRID x GRID block covers the entire field, and a 9 m hull riding 40-200 m
 * waves does not care about the centimetre band. What it cannot tolerate is a
 * DIFFERENT field, which is what a separately-seeded CPU wave set would be.
 *
 * Each cell is two vec4s:
 *   [0] xyz = displacement (hx, hy, hz)
 *   [1] xy  = height gradient, z = dhx_dx, w = accumulated foam
 */

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) restrict readonly uniform image2DArray displacement_map;
layout(rgba16f, set = 0, binding = 1) restrict readonly uniform image2DArray normal_map;

layout(std430, set = 1, binding = 0) restrict writeonly buffer CPUBuffer {
	vec4 cpu_data[]; // grid_size^2 * 2 * num_cascades
};

layout(push_constant) restrict readonly uniform PushConstants {
	uint cascade_index;
	uint map_size;
	uint grid_size;
	uint pad;
};

void main() {
	const uvec2 cell = gl_GlobalInvocationID.xy;
	if (cell.x >= grid_size || cell.y >= grid_size) return;

	// Box filter over the block this cell stands for. Point-sampling instead
	// would alias the short waves straight into the buoyancy, and a boat that
	// twitches on chop it cannot possibly feel reads as broken physics.
	const uint stride = max(1u, map_size / grid_size);
	const ivec2 base = ivec2(cell * stride);

	vec3 disp = vec3(0.0);
	vec4 grad = vec4(0.0);
	for (uint j = 0u; j < stride; ++j) {
		for (uint i = 0u; i < stride; ++i) {
			ivec3 id = ivec3(base + ivec2(i, j), int(cascade_index));
			disp += imageLoad(displacement_map, id).xyz;
			grad += imageLoad(normal_map, id);
		}
	}
	const float inv = 1.0 / float(stride * stride);
	disp *= inv;
	grad *= inv;

	const uint idx = (cascade_index * grid_size * grid_size + cell.y * grid_size + cell.x) * 2u;
	cpu_data[idx] = vec4(disp, 0.0);
	cpu_data[idx + 1u] = grad;
}
