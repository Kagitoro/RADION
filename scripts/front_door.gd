extends Node3D

signal state_changed(value: bool)

@export var swing_degrees := 88.0
var opened := false
var motion: Tween
var home: Node

func setup(game_home: Node, initially_open: bool) -> void:
	home = game_home
	opened = initially_open
	$Leaf.rotation.y = deg_to_rad(swing_degrees) if opened else 0.0

func set_open(value: bool) -> void:
	if value == opened:
		return
	opened = value
	if is_instance_valid(motion):
		motion.kill()
	motion = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	motion.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var lever := get_node_or_null("Leaf/LeverPivot") as Node3D
	if lever != null and opened:
		motion.tween_property(lever,"rotation:x",deg_to_rad(-26.0),.13)
		motion.tween_property(lever,"rotation:x",deg_to_rad(-20.0),.07)
		motion.tween_property(lever,"rotation:x",deg_to_rad(-26.0),.06)
		motion.parallel().tween_property($Leaf,"rotation:y",deg_to_rad(swing_degrees),.65)
		motion.tween_property(lever,"rotation:x",0.0,.18)
		state_changed.emit(opened)
		return
	if lever != null:
		motion.parallel().tween_property(lever,"rotation:x",0.0,.15)
	motion.tween_property($Leaf,"rotation:y",deg_to_rad(swing_degrees) if opened else 0.0,.65 if opened else .55)
	state_changed.emit(opened)

func _physics_process(_delta: float) -> void:
	if opened or not is_instance_valid(home) or (WalkSession.active and not multiplayer.is_server()):
		return
	for guest in home.party.guests:
		if guest.cursor >= guest.route.size() or guest.global_position.distance_squared_to(global_position)>5.0:
			continue
		var destination: Vector3 = guest.route[-1]
		var door_x: float = home.night_world.door_center.x
		if (guest.global_position.x-door_x)*(destination.x-door_x)<0.0:
			set_open(true)
			return
