#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// r = height, g = vertical velocity, b = foam energy, a = reserved.
layout(rgba16f, set = 0, binding = 0) restrict readonly uniform image2D source_field;
layout(rgba16f, set = 0, binding = 1) restrict writeonly uniform image2D target_field;

layout(set = 1, binding = 0, std430) restrict readonly buffer ImpulseBuffer {
	vec4 impulses[]; // xy grid position, z radius in cells, w velocity impulse
};

layout(push_constant, std430) uniform Params {
	float dt;
	float cell_size;
	float damping;
	float wave_speed;
	int impulse_count;
	int scroll_x;
	int scroll_y;
	int grid_size;
} params;

vec4 read_cell(ivec2 p) {
	if (p.x < 0 || p.y < 0 || p.x >= params.grid_size || p.y >= params.grid_size) {
		return vec4(0.0);
	}
	return imageLoad(source_field, p);
}

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	if (id.x >= params.grid_size || id.y >= params.grid_size) {
		return;
	}
	ivec2 old_id = id + ivec2(params.scroll_x, params.scroll_y);
	vec4 state = read_cell(old_id);
	float h_l = read_cell(old_id + ivec2(-1, 0)).r;
	float h_r = read_cell(old_id + ivec2( 1, 0)).r;
	float h_d = read_cell(old_id + ivec2(0, -1)).r;
	float h_u = read_cell(old_id + ivec2(0,  1)).r;
	float lap = (h_l + h_r + h_d + h_u - 4.0 * state.r)
			/ max(params.cell_size * params.cell_size, 1e-4);
	float velocity = state.g + lap * params.wave_speed * params.wave_speed * params.dt;
	float foam_add = 0.0;
	for (int i = 0; i < params.impulse_count; i++) {
		vec2 d = vec2(id) - impulses[i].xy;
		float radius = max(impulses[i].z, 0.5);
		float q2 = dot(d, d) / (radius * radius);
		float kernel = exp(-q2 * 2.4);
		velocity += impulses[i].w * kernel;
		foam_add = max(foam_add, abs(impulses[i].w) * kernel * 0.12);
	}
	velocity *= exp(-params.damping * params.dt);
	float height = state.r + velocity * params.dt;
	// Aerated prop wash and a slammed crest remain visible for several seconds;
	// height damps much faster than the bubbles carried by that water.
	float foam = max(state.b * exp(-0.22 * params.dt), foam_add);
	// Absorbing rim: the local patch hands back to the FFT sea without reflection.
	vec2 edge = min(vec2(id), vec2(params.grid_size - 1 - id));
	float rim = smoothstep(1.0, 14.0, min(edge.x, edge.y));
	imageStore(target_field, id, vec4(height * rim, velocity * rim, foam * rim, 0.0));
}
