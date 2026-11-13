class_name FPViewModel
extends Node3D
## First-person hands rig attached to the player camera.
## Layout: ViewModel/Sway/{Right/RightHand, Left/LeftHand, Mouth}. Each pivot
## (Right, Left) is the grip point of the held item: animations move the pivot,
## the item sits on it and the hand is posed around it with `hold()`. Actions are Animation
## resources played by `anim`; Sway adds look lag, walk bob and breathing on top.
## Track paths are relative to this node; "../.." is the Player.

## Render layer only the player camera sees (not mirrors).
const LAYER := 8

signal event(event_name: String)
## Emitted when an action clip reaches its end.
signal clip_finished(clip_name: String)

var player: Player
var sway: Node3D
var right: FPHand
var left: FPHand
var right_pivot: Node3D
var left_pivot: Node3D
var mouth: Node3D
var anim: AnimationPlayer
var last_basis := Basis.IDENTITY
var lag := Vector2.ZERO
var lag_velocity := Vector2.ZERO
var clock := 0.0
## Hands are only shown while an action needs them.
var active := false

func _init(owner_player: Player) -> void:
	player = owner_player
	name = "ViewModel"

func _ready() -> void:
	sway = Node3D.new()
	sway.name = "Sway"
	add_child(sway)
	right_pivot = Node3D.new()
	right_pivot.name = "Right"
	left_pivot = Node3D.new()
	left_pivot.name = "Left"
	right = FPHand.new(false)
	left = FPHand.new(true)
	for pair in [[right_pivot,right],[left_pivot,left]]:
		sway.add_child(pair[0])
		pair[0].add_child(pair[1])
		pair[0].visible = false
	right_pivot.position = Vector3(.3,-.6,-.3)
	left_pivot.position = Vector3(-.3,-.6,-.3)
	mouth = Node3D.new()
	mouth.name = "Mouth"
	# Presentation point for the lips: a bit lower and further than the real
	# mouth so items brought to it stay readable instead of filling the screen.
	mouth.position = Vector3(0,-.072,-.13)
	sway.add_child(mouth)
	anim = new_player()
	last_basis = global_basis

func _process(delta: float) -> void:
	clock += delta
	# Look lag: the hands trail the camera rotation a little, like a held weight.
	var current := global_basis
	var turn := last_basis.inverse()*current
	last_basis = current
	var euler := turn.get_euler()
	# Turning right (negative yaw) leaves the hands slightly to the left, looking up leaves them low.
	lag_velocity += Vector2(euler.y,-euler.x)*2.4
	lag_velocity += (-lag*170.0-lag_velocity*18.0)*delta
	lag += lag_velocity*delta
	lag = lag.limit_length(.06)
	var pace := Vector2(player.velocity.x,player.velocity.z).length()
	var walk := clampf(pace/3.3,0.0,1.0) if player.is_on_floor() else 0.0
	var bob := Vector3(sin(player.head_bob*.5)*.008,-absf(sin(player.head_bob))*.006,0)*walk
	var breath := Vector3(0,sin(clock*1.7)*.0025,0)
	var drunk := Vector3(sin(clock*.9)*.012,sin(clock*1.3)*.006,0)*player.intoxication
	sway.position = Vector3(lag.x,lag.y,0)+bob+breath+drunk
	sway.rotation = Vector3(lag.y*1.2,lag.x*1.4,lag.x*1.8)

## Places a hand around its pivot: `at` is the wrist offset, `turn` the hand
## rotation, `bend` the wrist bend that sends the forearm off screen.
## With `wrap_radius` the fingers are fitted around a cylinder standing on the
## pivot's Y axis (bottles, cans) so they rest on the surface, never inside it.
func hold(hand: FPHand, at: Vector3, turn: Vector3, bend: Vector3, pose: String, wrap_radius := 0.0) -> void:
	hand.position = at
	hand.rotation = turn
	hand.wrist_bend = bend
	hand.fitted.clear()
	if wrap_radius>0.0:
		var to_hand := hand.transform.affine_inverse()
		# The thumb wraps the far side of the item, away from the camera.
		hand.fit_cylinder(pose,to_hand*Vector3.ZERO,to_hand.basis*Vector3.UP,wrap_radius,to_hand.basis*Vector3.FORWARD)
	hand.set_pose(pose)

## Removes everything except the hand from a pivot.
func clear_pivot(pivot: Node3D) -> void:
	for child in pivot.get_children():
		if not child is FPHand:
			# Detach now so a new prop can take the same name this frame.
			pivot.remove_child(child)
			child.queue_free()

## Euler rotation for an item whose local +Y points along `up` and local +X
## leans toward `side` (where the gripping hand sits).
static func axis_turn(up: Vector3, side: Vector3) -> Vector3:
	var y := up.normalized()
	var x := (side-y*side.dot(y)).normalized()
	var z := x.cross(y).normalized()
	return Basis(x,y,z).get_euler()

func emit_event(event_name: String) -> void:
	event.emit(event_name)

func is_playing() -> bool:
	return anim.is_playing()

## Every action gets a fresh AnimationPlayer: clips reference props that are
## freed afterwards, and removing a clip a player still holds crashes the engine.
func new_player() -> AnimationPlayer:
	var player_node := AnimationPlayer.new()
	player_node.name = "Actions"
	add_child(player_node)
	player_node.animation_finished.connect(func(clip_name: StringName):
		if player_node==anim:
			active = false
			clip_finished.emit(str(clip_name))
	)
	return player_node

## Swaps in an empty player once an action is over, so the finished clip
## never resolves tracks of props that were just freed.
func retire_player() -> void:
	if anim.is_playing():
		return
	var old := anim
	anim = new_player()
	old.name = "OldActions"
	old.queue_free()

## Baked action clips (assets/fp/anims/<name>.tres) replace the code-built
## ones when present: they key every hand bone, so they can be edited in the
## Godot animation editor (see assets/fp/preview/<name>.tscn).
const BAKED_FOLDER := "res://assets/fp/anims/"
static var use_baked := true

static func baked_clip(clip_name: String) -> Animation:
	var path := BAKED_FOLDER+clip_name+".tres"
	if not use_baked or not ResourceLoader.exists(path):
		return null
	return load(path) as Animation

func play(clip: Animation, clip_name: String) -> void:
	var baked := baked_clip(clip_name)
	if baked!=null:
		clip = baked
	for hand in [right,left]:
		hand.drive_bones = baked==null
		hand.sync_bones()
	var old := anim
	anim = new_player()
	if is_instance_valid(old):
		old.name = "OldActions"
		old.stop()
		old.queue_free()
	var library := AnimationLibrary.new()
	library.add_animation(clip_name,clip)
	anim.add_animation_library("",library)
	active = true
	anim.play(clip_name)

## Adds a cubic value track. keys: [[time, value], ...]; ease < 1 eases out, > 1 eases in.
static func track(clip: Animation, path: String, keys: Array, cubic := true) -> void:
	var index := clip.add_track(Animation.TYPE_VALUE)
	clip.track_set_path(index,NodePath(path))
	clip.track_set_interpolation_type(index,Animation.INTERPOLATION_CUBIC if cubic else Animation.INTERPOLATION_LINEAR)
	clip.value_track_set_update_mode(index,Animation.UPDATE_CONTINUOUS)
	for key in keys:
		clip.track_insert_key(index,key[0],key[1],key[2] if key.size()>2 else 1.0)

## Discrete (step) track, for visibility and pose names.
static func steps(clip: Animation, path: String, keys: Array) -> void:
	var index := clip.add_track(Animation.TYPE_VALUE)
	clip.track_set_path(index,NodePath(path))
	clip.value_track_set_update_mode(index,Animation.UPDATE_DISCRETE)
	for key in keys:
		clip.track_insert_key(index,key[0],key[1])

## Calls `method` on a node at given times: [[time, [args]], ...].
static func calls(clip: Animation, path: String, method: String, keys: Array) -> void:
	var index := clip.add_track(Animation.TYPE_METHOD)
	clip.track_set_path(index,NodePath(path))
	for key in keys:
		clip.track_insert_key(index,key[0],{"method":method,"args":key[1]})

## Named events at times: [[time, "name"], ...] -> event signal.
static func events(clip: Animation, keys: Array) -> void:
	var index := clip.add_track(Animation.TYPE_METHOD)
	clip.track_set_path(index,NodePath("."))
	for key in keys:
		clip.track_insert_key(index,key[0],{"method":"emit_event","args":[key[1]]})
