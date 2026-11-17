extends Node3D
## Put the hinge at the edge of a clear doorway.

@export var swing_degrees := 95.0
var opened := false
var motion: Tween

func set_open(value: bool) -> void:
	if value == opened:
		return
	opened = value
	if is_instance_valid(motion):
		motion.kill()
	motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	motion.tween_property($Leaf, "rotation:y", deg_to_rad(swing_degrees) if opened else 0.0, 0.32)
