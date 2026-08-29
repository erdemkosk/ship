@tool
class_name WaveGenerator extends Node
## GPU wave field: TMA/JONSWAP spectrum -> Stockham FFT -> displacement + normal
## map arrays, one layer per cascade, plus a small CPU mirror for buoyancy.
##
## FFT pipeline adapted from GodotOceanWaves by Ethan Truong (MIT), see
## shaders/compute/LICENSE-GodotOceanWaves.txt. Additions here: per-cascade
## spectral band limiting, and the CPU readback path this project's physics
## needs (the original has no buoyancy at all).

const G := 9.81
## Water depth fed to the dispersion relation. Open water for the surface: the
## per-location shoaling this project already does (Green's law in ocean.gd)
## rides on top of a deep-water field, and doing it twice would double-count.
const DEPTH := 80.0
## Resolution of the CPU mirror, per cascade. The field is periodic over
## tile_length, so this grid is the WHOLE field, just coarse.
## Energy the FFT pipeline produces per unit of analytic spectrum.
##
## spectrum_compute draws amplitudes as sqrt(2*S*D*w_norm) against unit-variance
## Gaussians, where Tessendorf's convention is (1/sqrt2)*sqrt(S*D*w_norm) -- a
## factor 2 in amplitude, so 4 in energy. The modulate stage then sums h0(k) and
## conj(h0(-k)), two independent draws, doubling it again. 4 x 2 = 8.
## Measured on this pipeline at 8 +/- 0.4, the residual being the box filter in
## cpu_sample quietly eating part of the shortest cascade.
const SPECTRUM_ENERGY_FACTOR := 8.0
## Shortest wave the field carries. This used to be a metre, on the reasoning
## that finer waves are sub-pixel and their slope could come from the tiled
## detail normal maps instead. That was the wrong trade: those maps repeat every
## 1.3 m under the bow, which is the single most obvious tell that water is
## rendered rather than simulated. The FFT already has the resolution — the
## finest cascade is 7.3 m over 256 texels, so 2.85 cm per texel — it was just
## being told not to use it. Now it runs to (near) its own grid Nyquist and the
## detail maps are gone.
##
## Sub-metre content does alias slightly on the close ring's 0.5 m quads. Its
## amplitudes there are under a millimetre, so what aliases is invisible; what
## the band buys is a repeat period of 7.3 m instead of 1.3 m.
const SHORTEST_WAVE := 0.08
const CPU_GRID := 64
const FLOATS_PER_CELL := 8  # vec4 displacement + vec4 gradient/foam
## Mip levels on the normal maps. Without a chain the far sea shimmers: one
## screen pixel covers many texels and point-sampling one of them turns wave
## slope into crawling noise. Down to 4x4 is plenty — beyond that the whole tile
## is under a pixel anyway.
const NORMAL_MIPS := 7

var map_size := 256
var cascades: Array[WaveCascade] = []

var context: RenderingContext
var pipelines := {}
var descriptors := {}
var displacement_maps := Texture2DArrayRD.new()
var normal_maps := Texture2DArrayRD.new()

## CPU mirror of the GPU field. Layout per cascade c, cell (x, z):
##   base = ((c*CPU_GRID + z)*CPU_GRID + x) * FLOATS_PER_CELL
##   [0..2] displacement xyz   [4..5] height gradient   [6] dhx_dx   [7] foam
var cpu_data := PackedFloat32Array()
var cpu_ready := false
## Bumps on every landed readback, so consumers can tell a fresh frame from a
## repeat without comparing the arrays.
var cpu_frame := 0

var _normal_mips := 1
var _mip_pipelines: Array = []
var _mip_sets: Array = []
var _mip_sizes := PackedInt32Array()
var _readback_pending := false
var _cpu_bytes := 0
var _initialised := false


func configure(size: int, cascade_set: Array[WaveCascade]) -> void:
	map_size = clampi(size, 64, 512)
	cascades = cascade_set
	_assign_bands()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260813
	for i in cascades.size():
		cascades[i].spectrum_seed = Vector2i(rng.randi_range(-10000, 10000),
				rng.randi_range(-10000, 10000))
		# Offset the phase clocks so two cascades never march in step and beat
		# a visible pulse through the surface.
		cascades[i].time = 120.0 + PI * i
		cascades[i].should_generate_spectrum = true
	_init_gpu()


func _assign_bands() -> void:
	## Each cascade owns wavelengths from its own tile length down to the next
	## cascade's. Without this every cascade carries the entire spectrum and the
	## same swell is summed once per cascade.
	var n := cascades.size()
	for i in n:
		var c := cascades[i]
		c.k_min = TAU / maxf(c.tile_length, 0.5)
		if i + 1 < n:
			c.k_max = TAU / maxf(cascades[i + 1].tile_length, 0.5)
		else:
			# Last cascade stops at SHORTEST_WAVE, or its grid Nyquist if that is
			# the coarser of the two.
			c.k_max = minf(TAU / SHORTEST_WAVE, PI * float(map_size) / maxf(c.tile_length, 0.5))
		c.should_generate_spectrum = true


## Index of the cascade that carries swell. It is the longest one, and it gets
## its own wind, its own direction and its own significant height so that the
## swell can outlive the weather that made it.
const SWELL_CASCADE := 0


func set_sea_state(wind_speed: float, wind_dir_deg: float, hs_wind: float,
		fetch_km := 120.0, steep := 1.0,
		swell_wind := -1.0, swell_dir_deg := 1e9, hs_swell := 0.0) -> void:
	## Aim the cascade set at a sea state.
	##
	## The set is driven as two groups, because a real sea is two seas. The wind
	## sea answers the wind that is blowing now. The swell is the remains of the
	## wind that blew before, running from wherever it blew from — which is why a
	## real surface looks like it has history, and why the old code faked it by
	## bolting a second wave set on at a fixed 58 degrees. Here it falls out of
	## giving the longest cascade its own state and letting ocean.gd age the two
	## on different clocks.
	var sw_u: float = swell_wind if swell_wind > 0.0 else wind_speed
	var sw_dir: float = swell_dir_deg if swell_dir_deg < 1e8 else wind_dir_deg
	for i in cascades.size():
		var c := cascades[i]
		var swell_group := i == SWELL_CASCADE and hs_swell > 0.001
		c.wind_speed = maxf(sw_u if swell_group else wind_speed, 0.5)
		c.wind_direction = sw_dir if swell_group else wind_dir_deg
		# Swell is old and far-travelled, so it is long-crested and long-fetch;
		# wind sea is short-crested and takes the fetch it is given.
		c.fetch_length = maxf(fetch_km * 4.0 if swell_group else fetch_km, 1.0)
		c.spread = 0.06 if swell_group else 0.2
		c.swell = 1.6 if swell_group else 0.8
		# Foam accumulates where the FFT Jacobian drops below `whitecap`. On a
		# calm field that determinant sits just under 1, so a threshold tuned for
		# a storm sea (0.5) yields literally zero foam at Beaufort 6 — which is
		# what the first calibration pass did. Drive it from the wind instead, so
		# whitecaps arrive with the weather the way they do at sea.
		# Measured on this pipeline: at Beaufort 7 these give ~5% mean coverage
		# broken into distinct crests, which is about what a real sea shows. Push
		# whitecap past ~0.95 and the determinant is under it nearly everywhere,
		# so the sea goes uniformly milky instead of growing whitecaps.
		# Coverage is brutally non-linear near 1.0: the Jacobian spends most of
		# its time just under unity, so the last few hundredths take the sea from
		# scattered crests to uniformly milky (0.99 measured at 65% coverage,
		# which is a mistake, not a gale).
		#
		# The slope is NEGATIVE in wind on purpose. Whitecaps still increase with
		# the weather — that arrives on its own, because a windier spectrum folds
		# the surface harder — so a threshold that ALSO climbs double-counts it.
		# Measured here: 0.92 gives ~8% coverage at Beaufort 7 and ~28% at
		# Beaufort 8; backing off to 0.90 puts Beaufort 8 at ~20%, which is
		# roughly what a real gale shows.
		c.whitecap = clampf(0.92 - (wind_speed - 14.0) * 0.004 + (steep - 0.9) * 0.03,
				0.88, 0.95)
		c.foam_amount = clampf(1.5 + wind_speed * 0.16, 1.5, 8.5)
		c.mark_dirty()
	_normalise(hs_wind, hs_swell)


func _normalise(hs_wind: float, hs_swell: float) -> void:
	## JONSWAP gives a spectrum shape; a cascade set gives it in pieces. Integrate
	## each piece's variance over the band it actually owns (feathered edges and
	## all, exactly as the shader weights it), then scale so the pieces sum to the
	## sea state that was asked for. Without this every cascade carries a full
	## spectrum and the sea comes out at three times the height of the wind.
	## The two groups are normalised separately, so the swell keeps its own height
	## while the wind sea rises and falls underneath it.
	var swell_on := hs_swell > 0.001 and cascades.size() > 1
	var m0_wind := 0.0
	var m0_swell := 0.0
	for i in cascades.size():
		var m0 := _band_variance(cascades[i])
		if swell_on and i == SWELL_CASCADE:
			m0_swell = m0
		else:
			m0_wind += m0
	var want_w: float = pow(maxf(hs_wind, 0.02) / 4.0, 2.0)
	var gain_w: float = want_w / maxf(m0_wind * SPECTRUM_ENERGY_FACTOR, 1e-9)
	var gain_s := gain_w
	if swell_on:
		var want_s: float = pow(maxf(hs_swell, 0.001) / 4.0, 2.0)
		gain_s = want_s / maxf(m0_swell * SPECTRUM_ENERGY_FACTOR, 1e-9)
	for i in cascades.size():
		cascades[i].alpha_gain = gain_s if (swell_on and i == SWELL_CASCADE) else gain_w
		cascades[i].mark_dirty()


func _band_variance(c: WaveCascade) -> float:
	## m0 = integral of the TMA spectrum over this cascade's band, in m^2.
	var alpha := jonswap_alpha(c.wind_speed, c.fetch_length * 1e3)
	var w_p := jonswap_peak_frequency(c.wind_speed, c.fetch_length * 1e3)
	# Integrate in log-omega so one step count covers swell and chop alike.
	var w_lo := _omega_of_k(c.k_min * 0.5)
	var w_hi := _omega_of_k(c.k_max * 2.0)
	if w_hi <= w_lo:
		return 0.0
	var steps := 256
	var span := log(w_hi / w_lo)
	var m0 := 0.0
	for i in steps:
		var t := (float(i) + 0.5) / float(steps)
		var w := w_lo * exp(span * t)
		var dw := w * span / float(steps)
		m0 += _tma(w, w_p, alpha) * _band_weight(_k_of_omega(w), c) * dw
	return m0


func _band_weight(k: float, c: WaveCascade) -> float:
	## Mirrors the feathered band gate in spectrum_compute.glsl. The shader
	## scales the amplitude by sqrt(band), so energy scales by band.
	if k < c.k_min * 0.5 or k > c.k_max * 2.0:
		return 0.0
	return smoothstep(c.k_min * 0.5, c.k_min, k) * (1.0 - smoothstep(c.k_max, c.k_max * 2.0, k))


func _tma(w: float, w_p: float, alpha: float) -> float:
	var sigma := 0.07 if w <= w_p else 0.09
	var r: float = exp(-(w - w_p) * (w - w_p) / (2.0 * sigma * sigma * w_p * w_p))
	var jonswap: float = (alpha * G * G) / pow(w, 5.0) * exp(-1.25 * pow(w_p / w, 4.0)) \
			* pow(3.3, r)
	var w_h: float = minf(w * sqrt(DEPTH / G), 2.0)
	var kita: float = 0.5 * w_h * w_h if w_h <= 1.0 else 1.0 - 0.5 * (2.0 - w_h) * (2.0 - w_h)
	return jonswap * kita


func _omega_of_k(k: float) -> float:
	return sqrt(G * k * tanh(k * DEPTH))


func _k_of_omega(w: float) -> float:
	## Invert w^2 = g k tanh(k d) by Newton, seeded from the deep-water root.
	var k: float = maxf(w * w / G, 1e-6)
	for i in 8:
		var t := tanh(k * DEPTH)
		var f := G * k * t - w * w
		var dfdk: float = G * (t + k * DEPTH * (1.0 - t * t))
		k -= f / maxf(dfdk, 1e-9)
		k = maxf(k, 1e-6)
	return k


func _init_gpu() -> void:
	if context != null:
		context.free()
		context = null
		pipelines.clear()
		descriptors.clear()
	_initialised = false
	if cascades.is_empty():
		return

	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		# Headless / dummy renderer: there is no device to run compute on. Bail
		# quietly rather than throwing a null for every shader in the pipeline.
		return
	context = RenderingContext.create(rd)
	var num_cascades := cascades.size()
	var dims := Vector2i(map_size, map_size)
	var num_fft_stages := int(log(map_size) / log(2.0))

	var sh_spectrum := context.load_shader("res://shaders/compute/spectrum_compute.glsl")
	var sh_butterfly := context.load_shader("res://shaders/compute/fft_butterfly.glsl")
	var sh_modulate := context.load_shader("res://shaders/compute/spectrum_modulate.glsl")
	var sh_fft := context.load_shader("res://shaders/compute/fft_compute.glsl")
	var sh_transpose := context.load_shader("res://shaders/compute/transpose.glsl")
	var sh_unpack := context.load_shader("res://shaders/compute/fft_unpack.glsl")
	var sh_cpu := context.load_shader("res://shaders/compute/cpu_sample.glsl")
	var sh_mip := context.load_shader("res://shaders/compute/mip_reduce.glsl")

	var store := RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	var sample_bit := RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var update_bit := RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	var copy_bit := RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	descriptors["spectrum"] = context.create_texture(dims,
			RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, store | copy_bit, num_cascades)
	descriptors["butterfly_factors"] = context.create_storage_buffer(
			num_fft_stages * map_size * 4 * 4)
	descriptors["fft_buffer"] = context.create_storage_buffer(
			num_cascades * map_size * map_size * 4 * 2 * 2 * 4)
	descriptors["displacement_map"] = context.create_texture(dims,
			RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
			store | sample_bit | update_bit, num_cascades)
	var mips := clampi(int(log(float(map_size)) / log(2.0)) - 1, 1, NORMAL_MIPS)
	descriptors["normal_map"] = context.create_texture(dims,
			RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
			store | sample_bit | update_bit, num_cascades, RDTextureView.new(),
			PackedByteArray(), mips)
	_normal_mips = mips

	_cpu_bytes = num_cascades * CPU_GRID * CPU_GRID * FLOATS_PER_CELL * 4
	descriptors["cpu_buffer"] = context.create_storage_buffer(_cpu_bytes)
	cpu_data = PackedFloat32Array()
	cpu_data.resize(num_cascades * CPU_GRID * CPU_GRID * FLOATS_PER_CELL)
	cpu_ready = false

	# A uniform set carries the read/write qualifiers of the shader it was built
	# against, and Godot 4.7 rejects a set whose qualifiers do not match the
	# pipeline using it. The spectrum image is writeonly in one shader and
	# readonly in the next, so every shader gets its own sets rather than sharing.
	var maps: Array[RenderingContext.Descriptor] = [
			descriptors["displacement_map"], descriptors["normal_map"]]
	var fft_pair: Array[RenderingContext.Descriptor] = [
			descriptors["butterfly_factors"], descriptors["fft_buffer"]]
	var spec: Array[RenderingContext.Descriptor] = [descriptors["spectrum"]]
	var fftbuf: Array[RenderingContext.Descriptor] = [descriptors["fft_buffer"]]

	var g16 := map_size / 16
	pipelines["spectrum"] = context.create_pipeline([g16, g16, 1],
			[context.create_descriptor_set(spec, sh_spectrum, 0)], sh_spectrum)
	pipelines["modulate"] = context.create_pipeline([g16, g16, 1], [
			context.create_descriptor_set(spec, sh_modulate, 0),
			context.create_descriptor_set(fftbuf, sh_modulate, 1)], sh_modulate)
	pipelines["butterfly"] = context.create_pipeline([map_size / 2 / 64, num_fft_stages, 1],
			[context.create_descriptor_set([descriptors["butterfly_factors"]], sh_butterfly, 0)],
			sh_butterfly)
	pipelines["fft"] = context.create_pipeline([1, map_size, 4],
			[context.create_descriptor_set(fft_pair, sh_fft, 0)], sh_fft)
	pipelines["transpose"] = context.create_pipeline([map_size / 32, map_size / 32, 4],
			[context.create_descriptor_set(fft_pair, sh_transpose, 0)], sh_transpose)
	pipelines["unpack"] = context.create_pipeline([g16, g16, 1], [
			context.create_descriptor_set(maps, sh_unpack, 0),
			context.create_descriptor_set(fftbuf, sh_unpack, 1)], sh_unpack)
	pipelines["cpu_sample"] = context.create_pipeline([CPU_GRID / 8, CPU_GRID / 8, 1], [
			context.create_descriptor_set(maps, sh_cpu, 0),
			context.create_descriptor_set([descriptors["cpu_buffer"]], sh_cpu, 1)], sh_cpu)

	# One reduction pipeline per mip level. Each needs its own dispatch size and
	# its own pair of single-level views, so they cannot share a pipeline object.
	_mip_pipelines.clear()
	_mip_sets.clear()
	_mip_sizes.clear()
	var nrid: RID = descriptors["normal_map"].rid
	for level in range(1, _normal_mips):
		var dst_size: int = maxi(map_size >> level, 1)
		var groups: int = maxi((dst_size + 7) / 8, 1)
		var sets_this_level: Array = []
		for layer in num_cascades:
			var slice_src := context.create_mip_slice(nrid, layer, level - 1)
			var slice_dst := context.create_mip_slice(nrid, layer, level)
			sets_this_level.append(
					context.create_descriptor_set([slice_src, slice_dst], sh_mip, 0))
		# One pipeline per level (dispatch size differs); the per-cascade sets are
		# swapped in at call time.
		_mip_pipelines.append(context.create_pipeline([groups, groups, 1],
				[sets_this_level[0]], sh_mip))
		_mip_sets.append(sets_this_level)
		_mip_sizes.append(dst_size)

	# Butterfly factors depend only on map_size, so they are built once.
	var cl := context.compute_list_begin()
	pipelines["butterfly"].call(context, cl)
	context.compute_list_end()

	displacement_maps.texture_rd_rid = RID()
	normal_maps.texture_rd_rid = RID()
	displacement_maps.texture_rd_rid = descriptors["displacement_map"].rid
	normal_maps.texture_rd_rid = descriptors["normal_map"].rid
	_initialised = true


func is_ready() -> bool:
	return _initialised


func update(delta: float) -> void:
	if not _initialised:
		return
	for c in cascades:
		c.time += delta
		# Constants normalise foam_amount into a 0..10 slider.
		c.foam_grow_rate = delta * c.foam_amount * 7.5
		c.foam_decay_rate = delta * maxf(0.5, 10.0 - c.foam_amount) * 1.15

	var cl := context.compute_list_begin()
	for i in cascades.size():
		_dispatch_cascade(cl, i)
	# Mip chain: every level reads the one above it, so each needs the previous
	# dispatch finished before it starts.
	for m in _mip_pipelines.size():
		context.compute_list_add_barrier(cl)
		var pc := RenderingContext.create_push_constant([_mip_sizes[m], 0, 0, 0])
		for layer in _mip_sets[m].size():
			_mip_pipelines[m].call(context, cl, pc, [_mip_sets[m][layer]])
	context.compute_list_add_barrier(cl)
	for i in cascades.size():
		pipelines["cpu_sample"].call(context, cl,
				RenderingContext.create_push_constant([i, map_size, CPU_GRID, 0]))
	context.compute_list_end()

	if not _readback_pending:
		_readback_pending = true
		context.device.buffer_get_data_async(descriptors["cpu_buffer"].rid,
				_on_readback, 0, _cpu_bytes)


func _dispatch_cascade(cl: int, i: int) -> void:
	var p := cascades[i]
	if p.should_generate_spectrum:
		var alpha := jonswap_alpha(p.wind_speed, p.fetch_length * 1e3) * p.alpha_gain
		var omega := jonswap_peak_frequency(p.wind_speed, p.fetch_length * 1e3)
		pipelines["spectrum"].call(context, cl, RenderingContext.create_push_constant([
				p.spectrum_seed.x, p.spectrum_seed.y, p.tile_length, p.tile_length,
				alpha, omega, p.wind_speed, deg_to_rad(p.wind_direction), DEPTH,
				p.swell, p.detail, p.spread, p.k_min, p.k_max, i, 0]))
		p.should_generate_spectrum = false
	pipelines["modulate"].call(context, cl, RenderingContext.create_push_constant(
			[p.tile_length, p.tile_length, DEPTH, p.time, i, 0, 0, 0]))

	var fft_pc := RenderingContext.create_push_constant([i, 0, 0, 0])
	# No second transpose: rotating the field by PI/2 is invisible on an ocean.
	pipelines["fft"].call(context, cl, fft_pc)
	pipelines["transpose"].call(context, cl, fft_pc)
	context.compute_list_add_barrier(cl)
	pipelines["fft"].call(context, cl, fft_pc)
	pipelines["unpack"].call(context, cl, RenderingContext.create_push_constant(
			[i, p.whitecap, p.foam_grow_rate, p.foam_decay_rate]))


func _on_readback(bytes: PackedByteArray) -> void:
	_readback_pending = false
	if bytes.size() < _cpu_bytes:
		return
	cpu_data = bytes.to_float32_array()
	cpu_ready = true
	cpu_frame += 1


# Source: https://wikiwaves.org/Ocean-Wave_Spectra#JONSWAP_Spectrum
static func jonswap_alpha(wind_speed := 20.0, fetch_length := 550e3) -> float:
	return 0.076 * pow(wind_speed * wind_speed / (fetch_length * G), 0.22)


static func jonswap_peak_frequency(wind_speed := 20.0, fetch_length := 550e3) -> float:
	return 22.0 * pow(G * G / (wind_speed * fetch_length), 1.0 / 3.0)


func release() -> void:
	## Drop the GPU side. Called from ocean.gd's _exit_tree so teardown order is
	## ours rather than the engine's: the ShaderMaterials still hold references
	## to these texture resources, and freeing the RIDs out from under them
	## leaves "resource still in use" on the way out.
	displacement_maps.texture_rd_rid = RID()
	normal_maps.texture_rd_rid = RID()
	if context != null:
		context.free()
		context = null
	_initialised = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		release()
