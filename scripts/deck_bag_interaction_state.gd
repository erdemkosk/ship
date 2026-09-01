class_name DeckBagInteractionState
extends RefCounted

var open := false
var focus := 0.0
var saved_yaw := 0.0
var saved_pitch := 0.0
var selected := 0
var last_tool := 0
var take_pending := false


func set_open(value: bool, view_yaw: float, view_pitch: float) -> bool:
	if open == value:
		return false
	open = value
	if value:
		saved_yaw = view_yaw
		saved_pitch = view_pitch
	else:
		take_pending = false
	return true


func update_focus(delta: float) -> float:
	var goal := 1.0 if open else 0.0
	var duration := 0.78 if open else 0.62
	focus = move_toward(focus, goal, delta / duration)
	return focus


func shift(direction: int, slot_count: int) -> void:
	if slot_count > 0:
		selected = posmod(selected + direction, slot_count)


func move(direction: Vector2i, slot_count: int) -> void:
	## Four tools form the upper row; the rifle occupies the lower row.
	if slot_count < 5:
		return
	if direction.y > 0:
		if selected >= 0 and selected < 4:
			last_tool = selected
		selected = 4
		return
	if direction.y < 0:
		if selected == 4:
			selected = clampi(last_tool, 0, 3)
		return
	if direction.x != 0:
		if selected == 4:
			selected = 0 if direction.x > 0 else 3
		else:
			selected = posmod(selected + direction.x, 4)
		last_tool = selected


func reset() -> void:
	open = false
	focus = 0.0
	take_pending = false
