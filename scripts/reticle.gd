extends Control
## The aiming mark. Deliberately almost nothing: this boat has no HUD, and the
## reticle exists for exactly one reason — when four fittings crowd one bracket,
## you have to be able to see WHICH one E will take.
##
## Resting state is a single hairline dot. When something is selectable, four
## short ticks close in around it and brighten. Nothing spins, nothing pulses:
## it reads as a focus, not as a video-game crosshair.

const DOT := Color(0.86, 0.88, 0.90, 0.30)
const LIVE := Color(1.0, 0.76, 0.40, 0.92)
const FAR_R := 17.0
const NEAR_R := 8.0
const TICK := 5.0

var aim_target := 0.0
var _aim := 0.0


func _process(delta: float) -> void:
	# Snappier closing than opening: finding a target should feel like a click,
	# losing one like it drifted away.
	var k: float = 1.0 - exp(-delta * (16.0 if aim_target > _aim else 9.0))
	var next: float = _aim + (aim_target - _aim) * k
	if absf(next - _aim) > 0.001:
		_aim = next
		queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var e: float = _aim * _aim * (3.0 - 2.0 * _aim)
	draw_circle(c, 1.4, DOT.lerp(LIVE, e))
	if e <= 0.01:
		return
	var r: float = lerpf(FAR_R, NEAR_R, e)
	var col: Color = LIVE
	col.a *= e
	# Four ticks on the diagonals — off the horizon and off the vertical, so
	# they never sit on top of a mast or a rail and vanish into it.
	for i in 4:
		var a: float = PI * 0.25 + float(i) * PI * 0.5
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * r, c + d * (r + TICK), col, 1.0, true)
