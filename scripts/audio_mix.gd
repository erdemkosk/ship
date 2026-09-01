class_name AudioMix
extends RefCounted
## Shared output contract. Continuous beds should peak around -12 dBFS,
## important mechanical events around -8..-5 dBFS, and exceptional impulses
## may reach -4 dBFS. The final limiter is a safety rail for coincident peaks,
## not a loudness effect.

const MASTER_CEILING_DB := -1.0
const MASTER_THRESHOLD_DB := -5.5


static func ensure_master_headroom() -> void:
	var master := AudioServer.get_bus_index(&"Master")
	if master < 0:
		return
	for effect_index in AudioServer.get_bus_effect_count(master):
		var existing := AudioServer.get_bus_effect(master, effect_index)
		if existing is AudioEffectLimiter:
			_configure_limiter(existing as AudioEffectLimiter)
			return
	var limiter := AudioEffectLimiter.new()
	_configure_limiter(limiter)
	# Last in the chain: every source and every bus send has already summed.
	AudioServer.add_bus_effect(master, limiter)


static func _configure_limiter(limiter: AudioEffectLimiter) -> void:
	limiter.ceiling_db = MASTER_CEILING_DB
	limiter.threshold_db = MASTER_THRESHOLD_DB
	limiter.soft_clip_db = 2.0
	limiter.soft_clip_ratio = 8.0
