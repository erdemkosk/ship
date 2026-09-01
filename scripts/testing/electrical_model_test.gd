extends SceneTree
## Fast, scene-independent contract test for the switchboard topology.

var _failed := false


func _initialize() -> void:
	var model := BoatElectricalModel.new()
	for fuse: StringName in [&"fu_cabin", &"fu_helm", &"fu_beacon", &"fu_anchor"]:
		model.register_fuse(fuse)
	_assert(model.is_seated(&"sw_cabin"), "registered cabin fuse must be seated")
	_assert(model.switch_is_in_well(&"sw_anchor"), "anchor switch belongs in fuse well")
	_assert(not model.switch_is_in_well(&"sw_wiper"), "wiper switch belongs on dash")
	_assert(not model.toggle_fuse(&"fu_cabin"), "first toggle must pull cartridge")
	_assert(not model.is_seated(&"sw_cabin"), "switch mapping must see pulled cartridge")
	_assert(model.toggle_fuse(&"fu_cabin"), "second toggle must reseat cartridge")
	_assert(model.is_seated(&"fu_cabin"), "direct fuse lookup must see reseated cartridge")
	if not _failed:
		print("[electrical-model] mapping=true topology=true toggle=true")
	quit(1 if _failed else 0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
