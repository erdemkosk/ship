class_name LocalWaterField
extends RefCounted
## Camera/boat-centred dispersive height field layered over the spectral ocean.

const GRID := 256
const WORLD_SIZE := 64.0
const CELL := WORLD_SIZE / float(GRID)
const MAX_IMPULSES := 24

var texture := Texture2DArrayRD.new()
var centre := Vector2.ZERO

var _context: RenderingContext
var _fields: Array[RenderingContext.Descriptor] = []
var _sets: Array[RID] = []
var _pipeline: Callable
var _impulse_buffer: RenderingContext.Descriptor
var _pending: Array = []
var _front := 0
var _cell_origin := Vector2i.ZERO
var _ready := false


func setup(world_centre: Vector2) -> void:
	centre = world_centre
	_cell_origin = Vector2i(roundi(centre.x / CELL), roundi(centre.y / CELL))
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		return
	_context = RenderingContext.create(rd)
	var shader := _context.load_shader("res://shaders/compute/local_wave_step.glsl")
	var usage := RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
			| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
			| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	for _i in 2:
		_fields.append(_context.create_texture(Vector2i(GRID, GRID),
				RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, usage, 1))
	_impulse_buffer = _context.create_storage_buffer(MAX_IMPULSES * 16)
	for i in 2:
		_sets.append(_context.create_descriptor_set(
				[_fields[i], _fields[1 - i]], shader, 0))
	var impulse_set := _context.create_descriptor_set([_impulse_buffer], shader, 1)
	_pipeline = _context.create_pipeline([GRID / 16, GRID / 16, 1],
			[_sets[0], impulse_set], shader)
	texture.texture_rd_rid = _fields[_front].rid
	_ready = true


func inject(world_pos: Vector2, radius_m: float, velocity_impulse: float) -> void:
	_pending.append([world_pos, radius_m, velocity_impulse])
	if _pending.size() > MAX_IMPULSES:
		_pending.pop_front()


func update(delta: float, world_centre: Vector2) -> void:
	if not _ready:
		return
	var new_origin := Vector2i(roundi(world_centre.x / CELL), roundi(world_centre.y / CELL))
	var scroll := new_origin - _cell_origin
	_cell_origin = new_origin
	centre = Vector2(new_origin) * CELL
	if abs(scroll.x) >= GRID or abs(scroll.y) >= GRID:
		scroll = Vector2i(GRID, GRID)
	var packed := PackedFloat32Array()
	packed.resize(MAX_IMPULSES * 4)
	var count := mini(_pending.size(), MAX_IMPULSES)
	for i in count:
		var item: Array = _pending[i]
		var grid_pos: Vector2 = (item[0] - centre) / CELL + Vector2.ONE * (GRID * 0.5)
		packed[i * 4] = grid_pos.x
		packed[i * 4 + 1] = grid_pos.y
		packed[i * 4 + 2] = maxf(float(item[1]) / CELL, 0.5)
		packed[i * 4 + 3] = float(item[2])
	_pending.clear()
	_context.device.buffer_update(_impulse_buffer.rid, 0, packed.to_byte_array().size(),
			packed.to_byte_array())
	var dst := 1 - _front
	var pc := RenderingContext.create_push_constant([
		minf(delta, 1.0 / 30.0), CELL, 0.72, 3.4,
		count, scroll.x, scroll.y, GRID,
	])
	var cl := _context.compute_list_begin()
	_pipeline.call(_context, cl, pc, [_sets[_front], _sets[0] if false else _context.create_descriptor_set([_impulse_buffer], _context.load_shader("res://shaders/compute/local_wave_step.glsl"), 1)])
	_context.compute_list_end()
	_front = dst
	texture.texture_rd_rid = _fields[_front].rid


func is_ready() -> bool:
	return _ready


func release() -> void:
	texture.texture_rd_rid = RID()
	if _context != null:
		_context.free()
		_context = null
	_ready = false
