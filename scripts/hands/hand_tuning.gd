extends RefCounted
class_name HandTuning
## The tuned numbers for hands: where a palm sits on a thing, how far each
## finger curls, and the stops of a choreographed sequence.
##
## Code still carries the defaults (GripMap.ENTRIES, HandRig.POSES, the
## reload controller). This file is the LAYER ON TOP of them — whatever the
## in-game editor (P) has been used to change. Empty file, nothing changes.
##
## Two locations:
##   res://data/hand_tuning.json    the project's copy, committed with the art.
##                                  Every run from a source checkout (editor
##                                  or `godot --path .`) reads and writes THIS.
##   user://hand_tuning.json        exported builds only: they cannot write
##                                  into the pack, so their edits land here and
##                                  overlay the shipped file key by key.
## A probe passes --tuning-file=PATH so it never touches either.
##
## Shape:
## {
##   "grips":   { "<id>": { "pos": [x,y,z], "fingers": [..], "palm": [..],
##                          "pose": "power", "palm_offset": 0.0,
##                          "along_fingers": 0.0 } },
##   "poses":   { "<name>": { "thumb": [a,b,c], "index": [..], ...,
##                            "thumb_splay": 0.0 } },
##   "markers": { "<object>/<marker>": { "pos": [x,y,z], "rot": [x,y,z] } },
##   "sequences": { "<name>": { "duration": s, "stops": [ {...}, ... ] } }
## }
## Vectors are plain arrays so the file stays readable in any diff tool.

const RES_PATH := "res://data/hand_tuning.json"
const USER_PATH := "user://hand_tuning.json"
const SECTIONS := ["grips", "poses", "markers", "sequences"]

static var _data := {}
static var _loaded := false
static var _dirty := false
## Bumped on every change or reload; caches built from this data key on it.
static var version := 0


static func data() -> Dictionary:
	if not _loaded:
		reload()
	return _data


static func reload() -> void:
	_data = {}
	for s in SECTIONS:
		_data[s] = {}
	if path_override == "":
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--tuning-file="):
				path_override = a.get_slice("=", 1)
	if path_override != "":
		_merge_file(path_override)
	else:
		_merge_file(RES_PATH)
		if _exported():
			_merge_file(USER_PATH)
	if OS.is_stdout_verbose() or _report_on_load:
		print(report())
	_loaded = true
	_dirty = false
	version += 1


static func _merge_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		push_warning("hand_tuning: %s is not a JSON object; ignored" % path)
		return
	for s in SECTIONS:
		var sec: Variant = (parsed as Dictionary).get(s, {})
		if sec is Dictionary:
			for k in sec:
				_data[s][k] = sec[k]


## Where a save goes. In the editor / a source checkout the project file, so
## the tuning is committed; anywhere else, the user directory.
static var path_override := ""


static func _exported() -> bool:
	return OS.has_feature("template")


static func save_path() -> String:
	if path_override != "":
		return path_override
	return USER_PATH if _exported() else RES_PATH


static func save() -> bool:
	var path := save_path()
	if path.begins_with("res://"):
		DirAccess.make_dir_recursive_absolute(
				ProjectSettings.globalize_path("res://data"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("hand_tuning: cannot write %s (%s)" % [path,
				error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(_strip_empty(data()), "\t"))
	f.close()
	_dirty = false
	return true


static func snapshot() -> Dictionary:
	return data().duplicate(true)


static func restore(snap: Dictionary) -> void:
	_data = snap.duplicate(true)
	for s in SECTIONS:
		if not _data.has(s):
			_data[s] = {}
	_loaded = true
	_dirty = true
	version += 1


## One line naming the file in force and what came out of it. Printed on
## every load with --verbose, and by the --tuning-report probe, so "is my
## tuning actually in this build?" is answerable on any machine.
static func report() -> String:
	var d := data()
	var where := path_override if path_override != "" else RES_PATH
	var lines: Array = ["[hand tuning] reading %s (exists: %s)%s" % [where,
			FileAccess.file_exists(where),
			", exported build also reads %s" % USER_PATH if _exported() else ""]]
	for s in SECTIONS:
		var sec: Dictionary = d.get(s, {})
		if not sec.is_empty():
			lines.append("  %s: %d — %s" % [s, sec.size(),
					", ".join(PackedStringArray(sec.keys()))])
	if lines.size() == 1:
		lines.append("  nothing tuned; the code's own numbers are in force")
	if not _exported() and FileAccess.file_exists(USER_PATH) and path_override == "":
		lines.append("  note: %s exists and is IGNORED from source (it is for exported builds only)" % USER_PATH)
	return "\n".join(PackedStringArray(lines))


static var _report_on_load := false


static func set_report_on_load(on: bool) -> void:
	_report_on_load = on


static func is_dirty() -> bool:
	return _dirty


static func _strip_empty(d: Dictionary) -> Dictionary:
	var out := {}
	for s in SECTIONS:
		var sec: Dictionary = d.get(s, {})
		if not sec.is_empty():
			out[s] = sec
	return out


# --- section accessors ------------------------------------------------------

static func grip(id: String) -> Dictionary:
	return data()["grips"].get(id, {})


static func set_grip(id: String, fields: Dictionary) -> void:
	if fields.is_empty():
		data()["grips"].erase(id)
	else:
		data()["grips"][id] = fields
	_dirty = true
	version += 1


static func pose(name: String) -> Dictionary:
	return data()["poses"].get(name, {})


static func set_pose(name: String, fields: Dictionary) -> void:
	if fields.is_empty():
		data()["poses"].erase(name)
	else:
		data()["poses"][name] = fields
	_dirty = true
	version += 1


## A grip is not one thing. The same fore-end is held differently while
## aiming, while working the bolt, and while the rifle is being lowered into
## its sling — so every marker entry may be qualified by the situation, and
## "<key>@<situation>" is read on top of the plain "<key>".
static func situated(key: String, situation: String) -> Dictionary:
	var base: Dictionary = marker(key)
	if situation == "":
		return base
	var over: Dictionary = marker(situation_key(key, situation))
	if over.is_empty():
		return base
	var out: Dictionary = base.duplicate()
	for k in over:
		out[k] = over[k]
	return out


## Where a held object itself sits, camera-local. Same per-situation rule as
## a grip; `fallback` is the code's own hold.
static func hold_frame(key: String, situation: String,
		fallback: Transform3D) -> Transform3D:
	var m := situated(key, situation)
	if m.is_empty():
		return fallback
	var xf := fallback
	if m.has("pos"):
		xf.origin = from_json(m["pos"])
	if m.has("quat"):
		var q: Array = m["quat"]
		if q.size() == 4:
			xf.basis = Basis(Quaternion(float(q[0]), float(q[1]), float(q[2]),
					float(q[3])).normalized())
	return xf


static func situation_key(key: String, situation: String) -> String:
	return "%s@%s" % [key, situation]


## The finger pose a tool's grip should use, when the editor has given that
## grip a pose of its own. Code passes the name it would otherwise use.
static func marker_pose(key: String, fallback: String, situation := "") -> String:
	return str(situated(key, situation).get("pose", fallback))


static func marker(key: String) -> Dictionary:
	return data()["markers"].get(key, {})


static func set_marker(key: String, fields: Dictionary) -> void:
	if fields.is_empty():
		data()["markers"].erase(key)
	else:
		data()["markers"][key] = fields
	_dirty = true
	version += 1


static func sequence(name: String) -> Dictionary:
	return data()["sequences"].get(name, {})


static func set_sequence(name: String, fields: Dictionary) -> void:
	if fields.is_empty():
		data()["sequences"].erase(name)
	else:
		data()["sequences"][name] = fields
	_dirty = true
	version += 1


# --- overlay helpers --------------------------------------------------------

## GripMap spec with this file's grip fields written over the catalog's.
## Vectors come back as Vector3 so callers never see the array form.
static func overlay_grip(id: String, spec: Dictionary) -> Dictionary:
	var over := grip(id)
	if over.is_empty() or spec.is_empty():
		return spec
	var out: Dictionary = spec.duplicate()
	for k in over:
		out[k] = from_json(over[k])
	return out


## The pose table with this file's poses written over the code's.
static func overlay_poses(base: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	var poses: Dictionary = data()["poses"]
	for name in poses:
		var p: Dictionary = poses[name]
		var entry: Dictionary = (out.get(name, {}) as Dictionary).duplicate()
		for k in p:
			entry[k] = p[k]
		out[name] = entry
	return out


## Apply a saved marker transform (object-local metres / degrees) to a node.
## Returns true when something was applied.
static func apply_marker(key: String, node: Node3D, situation := "") -> bool:
	var m := situated(key, situation)
	if m.is_empty() or node == null:
		return false
	var xf := node.transform
	if m.has("pos"):
		xf.origin = from_json(m["pos"])
	if m.has("quat"):
		# The orientation itself. Euler numbers are ambiguous where the rifle
		# grips sit (Y = ±90°); a quaternion is not.
		var q: Array = m["quat"]
		if q.size() == 4:
			xf.basis = Basis(Quaternion(float(q[0]), float(q[1]), float(q[2]),
					float(q[3])).normalized())
	elif m.has("rot"):
		var e: Vector3 = from_json(m["rot"])
		xf.basis = Basis.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y),
				deg_to_rad(e.z)))
	node.transform = xf
	return true


static func from_json(v: Variant) -> Variant:
	if v is Array:
		var a: Array = v
		if a.size() == 3 and (a[0] is float or a[0] is int):
			return Vector3(float(a[0]), float(a[1]), float(a[2]))
		if a.size() == 2 and (a[0] is float or a[0] is int):
			return Vector2(float(a[0]), float(a[1]))
	return v


static func to_json(v: Variant) -> Variant:
	if v is Vector3:
		var p: Vector3 = v
		return [snappedf(p.x, 0.0001), snappedf(p.y, 0.0001), snappedf(p.z, 0.0001)]
	if v is Vector2:
		var q: Vector2 = v
		return [snappedf(q.x, 0.0001), snappedf(q.y, 0.0001)]
	if v is float:
		return snappedf(v, 0.0001)
	return v
