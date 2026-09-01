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


static func diesel_load() -> AudioStreamWAV:
	## Combustion body that enters with shaft load. It deliberately contains no
	## idle character; layered below the recording it turns chug into weight.
	var rate := 22050
	var n := rate * 2
	var samples := PackedFloat32Array()
	samples.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var pulse := pow(0.5 + 0.5 * sin(t * TAU * 18.0), 5.0)
		var body := sin(t * TAU * 36.0) * 0.30 + sin(t * TAU * 72.0) * 0.10
		var raw := sin(t * TAU * 18.0) * 0.34 + pulse * body
		lp = lerpf(lp, raw, 0.16)
		samples[i] = clampf(lp * 0.78, -0.72, 0.72)
	return _pcm(samples, rate, true)


static func reverse_gear() -> AudioStreamWAV:
	## A subdued gearbox/shaft whine. Astern must read by colour before the
	## player looks at the telegraph, without becoming a modern transmission.
	var rate := 22050
	var n := rate * 2
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var t := float(i) / float(rate)
		var wobble := sin(t * TAU * 3.0) * 2.5
		var gear := sin(t * TAU * (84.0 + wobble)) * 0.34
		gear += sin(t * TAU * (168.0 + wobble * 2.0)) * 0.10
		gear *= 0.82 + sin(t * TAU * 6.0) * 0.12
		samples[i] = gear * 0.62
	return _pcm(samples, rate, true)


static func diesel_strain() -> AudioStreamWAV:
	## Low irregular knock for high propeller slip, an accelerating shaft or a
	## grounded hull. This is load without speed, not simply "more rpm".
	var rate := 22050
	var n := rate * 2
	var samples := PackedFloat32Array()
	samples.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var knock := pow(0.5 + 0.5 * sin(t * TAU * 12.0), 10.0)
		var raw := sin(t * TAU * 12.0) * 0.22
		raw += knock * (sin(t * TAU * 24.0) * 0.40 + sin(t * TAU * 48.0) * 0.16)
		lp = lerpf(lp, raw, 0.12)
		samples[i] = clampf(lp * 0.78, -0.70, 0.70)
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
