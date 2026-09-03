extends RefCounted
class_name RifleReloadStops
## The reload, as a row of STOPS in time.
##
## The hand goes to the bolt, opens it, leaves for the pocket, shows the round,
## carries it to the chamber, seats it, returns to the bolt, closes it, comes
## home to the grip. Each of those is a moment with a time and a finger pose;
## the code interpolates between them and the rifle's own animation is slaved
## to the same numbers. The rifle (animation, audio, cartridge visibility) and
## the reload controller (hands) both read from HERE, so a stop moved in the
## editor moves everything at once.
##
## Defaults are the authored values; data/hand_tuning.json's
## sequences.rifle_reload.stops overlays them per stop as {"t":, "pose":}.

const HAND_TUNING := preload("res://scripts/hands/hand_tuning.gd")
const SEQUENCE := "rifle_reload"

## In order. "start" is pinned at 0; "duration" is the end of the reload.
const ORDER := ["start", "bolt_open_start", "bolt_open_end", "cartridge_show",
		"cartridge_move", "cartridge_insert", "inserted", "bolt_close_start",
		"bolt_close_end", "duration"]

const DEFAULT_TIMES := {
	"start": 0.0,
	"bolt_open_start": 0.25,
	"bolt_open_end": 0.95,
	# 0.40 s to leave the shot and reach the pouch — the dip has to be a
	# movement the eye can follow, not a flick.
	"cartridge_show": 1.35,
	# A moment down there with the round in the fingers before it comes up.
	"cartridge_move": 1.55,
	"cartridge_insert": 2.05,
	"inserted": 2.30,
	"bolt_close_start": 2.45,
	"bolt_close_end": 2.90,
	"duration": 3.30,
}

## The pose the hand takes from this stop until the next one.
const DEFAULT_POSES := {
	"start": "bolt_grip",
	"bolt_open_start": "bolt_grip",
	# Empty hand on the way down: it opens as it leaves the knob and closes
	# on the cartridge at the pouch.
	"bolt_open_end": "open",
	"cartridge_show": "pinch",
	"cartridge_move": "pinch",
	"cartridge_insert": "pinch",
	"inserted": "bolt_grip",
	"bolt_close_start": "bolt_grip",
	"bolt_close_end": "rifle_primary",
	"duration": "rifle_primary",
}

const MIN_GAP := 0.02

static var _cache := {}
static var _cache_version := -1


static func _table() -> Dictionary:
	if _cache_version == HAND_TUNING.version and not _cache.is_empty():
		return _cache
	var times: Dictionary = DEFAULT_TIMES.duplicate()
	var poses: Dictionary = DEFAULT_POSES.duplicate()
	var saved: Dictionary = HAND_TUNING.sequence(SEQUENCE).get("stops", {})
	for name in saved:
		if not times.has(name):
			continue
		var st: Dictionary = saved[name]
		if st.has("t"):
			times[name] = float(st["t"])
		if st.has("pose"):
			poses[name] = str(st["pose"])
	times["start"] = 0.0
	# Keep the row monotonic whatever the file says.
	for i in range(1, ORDER.size()):
		var prev: float = times[ORDER[i - 1]]
		if float(times[ORDER[i]]) < prev + MIN_GAP:
			times[ORDER[i]] = prev + MIN_GAP
	_cache = {"times": times, "poses": poses}
	_cache_version = HAND_TUNING.version
	return _cache


static func times() -> Dictionary:
	return _table()["times"]


static func time_of(name: String) -> float:
	return float(times().get(name, 0.0))


static func pose_of(name: String) -> String:
	return str(_table()["poses"].get(name, "bolt_grip"))


## The stop whose interval contains t (the last stop at or before t).
static func stop_at(t: float) -> String:
	var tm := times()
	var cur := "start"
	for name: String in ORDER:
		if t >= float(tm[name]):
			cur = name
	return cur


static func pose_at(t: float) -> String:
	return pose_of(stop_at(t))


## Move one stop. It cannot pass the stop before it; pushed into the stops
## after it, it carries them along (the gaps between later stops are kept),
## which is what dragging a stop later ought to mean.
static func set_time(name: String, t: float) -> void:
	if name == "start" or not DEFAULT_TIMES.has(name):
		return
	var tm := times()
	var i := ORDER.find(name)
	var lo: float = float(tm[ORDER[i - 1]]) + MIN_GAP
	t = snappedf(maxf(t, lo), 0.001)
	var shift := 0.0
	if i + 1 < ORDER.size():
		shift = maxf(t + MIN_GAP - float(tm[ORDER[i + 1]]), 0.0)
	_write(name, "t", t)
	if shift > 0.0:
		for j in range(i + 1, ORDER.size()):
			_write(ORDER[j], "t", snappedf(float(tm[ORDER[j]]) + shift, 0.001))


static func set_pose(name: String, pose: String) -> void:
	if not DEFAULT_POSES.has(name):
		return
	_write(name, "pose", pose)


static func _write(name: String, field: String, value: Variant) -> void:
	var seq: Dictionary = HAND_TUNING.sequence(SEQUENCE).duplicate(true)
	var stops: Dictionary = seq.get("stops", {})
	var st: Dictionary = stops.get(name, {})
	st[field] = value
	stops[name] = st
	seq["stops"] = stops
	HAND_TUNING.set_sequence(SEQUENCE, seq)
