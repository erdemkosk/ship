class_name BoatElectricalModel
extends RefCounted
## Pure state for the boat's fuse cartridges and switchboard topology.

const WELL_SWITCHES: Array[StringName] = [
	&"sw_cabin", &"sw_helm", &"sw_beacon", &"sw_anchor",
]

var _fuses: Dictionary = {}


func register_fuse(id: StringName) -> void:
	_fuses[id] = true


func toggle_fuse(id: StringName) -> bool:
	var seated := not bool(_fuses.get(id, true))
	_fuses[id] = seated
	return seated


func is_seated(id: StringName) -> bool:
	var fuse_id := StringName(str(id).replace("sw_", "fu_")) if str(id).begins_with("sw_") \
			else id
	return bool(_fuses.get(fuse_id, true))


func switch_is_in_well(id: StringName) -> bool:
	return id in WELL_SWITCHES
