class_name GameInputActions
extends RefCounted
## Single registry for the project's runtime input contract.

const KEY_ACTIONS: Dictionary = {
	"boat_forward": [KEY_W, KEY_UP], "boat_backward": [KEY_S, KEY_DOWN],
	"boat_left": [KEY_A, KEY_LEFT], "boat_right": [KEY_D, KEY_RIGHT],
	"toggle_panel": [KEY_TAB], "toggle_camera": [KEY_F], "use": [KEY_E],
	"jump": [KEY_SPACE], "toggle_fps": [KEY_QUOTEDBL, KEY_APOSTROPHE],
	"dive": [KEY_CTRL, KEY_C], "watch": [KEY_B], "backpack": [KEY_I],
	"bag_previous": [KEY_LEFT, KEY_UP], "bag_next": [KEY_RIGHT, KEY_DOWN],
	"bag_left": [KEY_A, KEY_LEFT], "bag_right": [KEY_D, KEY_RIGHT],
	"bag_up": [KEY_W, KEY_UP], "bag_down": [KEY_S, KEY_DOWN],
	"rifle_reload": [KEY_R], "anchor": [KEY_G], "light_cabin": [KEY_1],
	"light_helm": [KEY_2], "light_beacon": [KEY_3], "light_flood": [KEY_6],
	"wiper": [KEY_5], "hand_editor": [KEY_P],
}

const MOUSE_ACTIONS: Dictionary = {
	"knife_attack": MOUSE_BUTTON_LEFT,
	"rifle_fire": MOUSE_BUTTON_LEFT,
	"rifle_aim": MOUSE_BUTTON_RIGHT,
}


static func register_defaults() -> void:
	for action: String in KEY_ACTIONS:
		_register_keys(action, KEY_ACTIONS[action])
	for action: String in MOUSE_ACTIONS:
		_register_mouse(action, MOUSE_ACTIONS[action])


static func _register_keys(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key: Key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)


static func _register_mouse(action: String, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)
