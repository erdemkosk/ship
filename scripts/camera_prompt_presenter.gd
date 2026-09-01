class_name CameraPromptPresenter
extends RefCounted
## Context-sensitive first-person interaction and equipment prompt text.


func update(prompt: Label, bag_focus: float, bag_selected: int, bag: Node,
		active_item_kind: String, walker, target, engaged: String, arms: Node,
		candidate: Dictionary, drops: float, drop_wipe: float,
		fog: float, wipe: float) -> void:
	if prompt == null:
		return
	var text := _prompt_text(bag_focus, bag_selected, bag, active_item_kind,
			walker, target, engaged, arms, candidate, drops, drop_wipe,
			fog, wipe)
	prompt.text = text
	prompt.visible = text != ""


func _prompt_text(bag_focus: float, bag_selected: int, bag: Node,
		active_item_kind: String, walker, target, engaged: String, arms: Node,
		candidate: Dictionary, drops: float, drop_wipe: float,
		fog: float, wipe: float) -> String:
	if bag_focus > 0.65:
		var active := bag.call("active_item_node") as Node3D if bag != null else null
		var slot_number := bag_selected + 1
		if active == null:
			var label := str(bag.call("slot_label", bag_selected)) \
					if bag != null else ""
			return "←/→ — choose   ·   %d: %s   ·   E — take   ·   I — shoulder" % [
					slot_number, label]
		if bag != null and not bool(bag.call("slot_occupied", bag_selected)):
			return "←/→ — choose   ·   %d: empty   ·   E — place   ·   I — shoulder" \
					% slot_number
		return "←/→ — choose   ·   %d: occupied   ·   find an empty slot" \
				% slot_number
	if active_item_kind == "utility_knife":
		return "LMB — slash   ·   I — open bag"
	if active_item_kind == "hunting_rifle":
		if bag != null and bool(bag.call("rifle_reloading")):
			return "Reloading — round / chamber / bolt   ·   I — open bag"
		if bag != null and not bool(bag.call("rifle_loaded")):
			return "Empty   ·   R — load & cycle bolt   ·   I — open bag"
		return "RMB — sights   ·   LMB — fire   ·   R — reload   ·   I — open bag"
	if _flag(walker, "on_sea_ladder"):
		return "W/S — climb   ·   SPACE — let go"
	if _flag(walker, "swimming"):
		if _flag(walker, "can_board"):
			return "SPACE — take the ladder"
		if _flag(walker, "submerged"):
			return "SPACE — swim up"
		return "You are in the sea — swim to the stern ladder   ·   CTRL: dive"
	if engaged == "helm":
		if not candidate.is_empty() and str(candidate["id"]) == "ignition":
			return "E — Ignition  (%s)" % _engine_action(target)
		return "E — let go of the wheel"
	if engaged == "telegraph":
		return "E — let go of the throttle"
	if engaged == "chart":
		return "E — leave the chart"
	if arms != null and str(arms.call("inspecting_id")) in ["radar", "sounder"]:
		return "E — stow the screen"
	if candidate.is_empty() and drops >= 0.22 and drop_wipe <= 0.0 \
			and _flag(target, "gear_worn"):
		return "3 — wipe the water off the mask"
	if candidate.is_empty() and fog >= 0.10 and wipe <= 0.0 \
			and _flag(target, "gear_worn"):
		return "E — wipe the mask"
	if _flag(target, "radio_held") and candidate.is_empty():
		return "E — hang up the handset"
	if candidate.is_empty():
		return ""
	var id := str(candidate["id"])
	if id == "radio" and _flag(target, "radio_held"):
		return "E — hang up the handset"
	if id in ["radar", "sounder"] and arms != null \
			and str(arms.call("inspecting_id")) == id:
		return "E — stow the screen"
	if id == "locker":
		return "E — %s the locker" % (
				"close" if _flag(target, "locker_open") else "open")
	if id == "divegear":
		return "E — %s the dive gear" % (
				"take off" if _flag(target, "gear_worn") else "put on")
	if id == "ignition":
		return "E — Ignition  (%s)" % _engine_action(target)
	if id.begins_with("fu_") and target.has_method("fuse_seated"):
		return "E — %s  (%s)" % [candidate["name"],
				"in" if bool(target.call("fuse_seated", id)) else "out"]
	if (id.begins_with("sw_") or id.begins_with("door_")) \
			and target.has_method("switch_state"):
		return "E — %s  (%s)" % [candidate["name"],
				"off" if bool(target.call("switch_state", id)) else "on"]
	return "E — %s" % candidate["name"]


func _engine_action(target) -> String:
	var state := int(target.get("engine"))
	return "stop" if state == 2 else ("cranking" if state == 1 else "start")


func _flag(object, property: StringName) -> bool:
	if object == null:
		return false
	var value: Variant = object.get(property)
	return typeof(value) == TYPE_BOOL and value
