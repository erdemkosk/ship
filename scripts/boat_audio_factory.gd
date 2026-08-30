class_name BoatAudioFactory
extends RefCounted
## Pure audio asset builders used by the boat.
##
## Keeping waveform synthesis out of boat.gd leaves that node responsible for
## placing and driving sounds, while this factory only creates fallback streams.


static func ignition_click() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.06)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(n)
		var raw := (randf() * 2.0 - 1.0) * (1.0 - t) * (1.0 - t) * 0.45
		lp = lp * 0.7 + raw * 0.3
		samples[i] = lp
	return _pcm(samples, rate, false)


static func starter() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 2.4)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var spin := 8.5 + t * 1.6
		var pulse := pow(0.5 + 0.5 * sin(t * TAU * spin), 3.2)
		var grind := (randf() * 2.0 - 1.0) * 0.35 + sin(t * TAU * 42.0) * 0.12
		lp = lp * 0.82 + grind * pulse * 0.18
		samples[i] = clampf(lp, -0.7, 0.7)
	return _pcm(samples, rate, false)


static func diesel_idle() -> AudioStreamWAV:
	## A wooden boat's diesel: low thump, no hiss. The loop is long so the
	## chug does not read as a sample. Highs are cooked out here; the bus
	## low-pass only decides how much timber is in the way.
	var rate := 22050
	var n := int(rate * 2.6)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var brown := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / float(rate)
		brown = brown * 0.96 + (randf() * 2.0 - 1.0) * 0.04
		var fire := 0.5 + 0.5 * sin(t * TAU * 23.5)
		fire *= fire * 0.38
		var sub := sin(t * TAU * 11.75) * 0.28
		var mid := sin(t * TAU * 47.0) * 0.08
		var raw := sub + fire + mid + brown * 0.40
		lp = lp * 0.90 + raw * 0.10
		samples[i] = clampf(lp * 0.92, -0.85, 0.85)
	return _pcm(samples, rate, true)


static func _pcm(samples: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	var sample_count := samples.size()
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = sample_count
	return stream
