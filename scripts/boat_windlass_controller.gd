class_name BoatWindlassController
extends RefCounted
## Windlass rotation and chain-locker depletion presentation.


func update(delta: float, windlass: Node3D, tackle: Node,
		chain_visual: Object) -> void:
	if windlass == null or tackle == null:
		return
	windlass.rotation.x += float(tackle.get("chain_rate")) / 0.16 * delta
	var chain_out := 0.0
	if "chain_out" in tackle:
		chain_out = float(tackle.get("chain_out"))
	var stowed := 1.0 - clampf(chain_out / 42.0, 0.0, 1.0)
	if chain_visual != null:
		chain_visual.call("tick", stowed, tackle)
