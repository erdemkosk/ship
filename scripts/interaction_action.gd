extends RefCounted
class_name InteractionAction
## Executes the gameplay half of an interaction after the hand reaches contact.
## The camera owns input and aiming; it should not know how radios, rails,
## switches or tackle mutate the boat.


static func allowed(target: Node, spec: Dictionary) -> bool:
	if target == null:
		return false
	var gate := str(spec.get("gate", ""))
	return gate == "" or (target.has_method("switch_state") \
			and bool(target.call("switch_state", gate)))


static func execute(target: Node, id: String, spec: Dictionary) -> bool:
	if not allowed(target, spec):
		return false
	match str(spec.get("action", "")):
		"radio":
			var property := str(spec.get("toggle_property", "radio_held"))
			target.set(property, not bool(target.get(property)))
			return true
		"rail":
			var rail := str(spec.get("rail", id))
			for peer: String in spec.get("exclusive_rails", ["radar", "sounder"]):
				if peer != rail and target.has_method("set_%s_pull" % peer):
					target.call("set_%s_pull" % peer, 0.0)
			var setter := "set_%s_pull" % rail
			if not target.has_method(setter):
				return false
			var current: float = float(target.get(rail + "_pull"))
			target.call(setter, 0.0 if current > 0.5 else 1.0)
			return true
		"tackle":
			var property := str(spec.get("action_property", "tackle"))
			var receiver: Node = target.get(property)
			if receiver == null or not receiver.has_method("toggle"):
				return false
			receiver.call("toggle")
			return true
		"toggle":
			if not target.has_method("toggle_switch"):
				return false
			target.call("toggle_switch", id)
			return true
	return false
