extends Node3D
## Wires the scene together and registers input actions in code
## (no hard-coded keys elsewhere; rebindable via InputMap).

const GameInputActions := preload("res://scripts/input_actions.gd")
const WorldSetup := preload("res://scripts/world_setup.gd")



func _enter_tree() -> void:
	GameInputActions.register_defaults()


func _open_menu() -> void:
	if get_tree().get_first_node_in_group("main_menu") != null:
		return
	var menu: Node3D = (load("res://scripts/main_menu.gd") as GDScript).new()
	menu.call("setup", $CameraRig, $Boat, $Ocean, $Weather)
	add_child(menu)


func return_to_menu() -> void:
	## ESC from play. The world stays; the shot and the words come back.
	_open_menu()


func _ready() -> void:
	var ocean: Node3D = $Ocean
	var boat: RigidBody3D = $Boat
	var weather: Node3D = $Weather
	var rig: Node3D = $CameraRig
	var ui: CanvasLayer = $UI

	var seabed: Node3D = $Seabed
	WorldSetup.connect_world(self, boat, ocean, weather, rig, seabed, ui)

	# The menu needs NOTHING to appear: double-click, editor play, exported
	# build — every ordinary launch opens on it. The only thing that skips it
	# is a command-line verification probe (--probe-*, --dive-test, ...),
	# because those need the bare world on frame one; a player never passes
	# arguments, so a player never sees anything but the menu.
	var uargs := OS.get_cmdline_user_args()
	var want_menu := true
	for a in uargs:
		if a.begins_with("--") and a != "--no-storm" and not a.begins_with("--time=") \
				and not a.begins_with("--menu"):
			want_menu = false
	if want_menu:
		_open_menu()
	# The in-game hand editor. Dormant until P; costs nothing until then.
	var hand_editor: CanvasLayer = (load("res://scripts/hands/hand_editor.gd") as GDScript).new()
	hand_editor.call("setup", rig, boat)
	add_child(hand_editor)
	if not uargs.is_empty():
		var harness: Node = (load("res://scripts/testing/verification_harness.gd") as GDScript).new()
		harness.call("configure", rig, boat, ocean, weather)
		add_child(harness)
		harness.call("run", uargs)
