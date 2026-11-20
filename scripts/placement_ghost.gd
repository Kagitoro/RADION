class_name PlacementGhost
extends Node3D
## "Place it" mode: a see-through copy of the object follows the crosshair on
## the floor, green where it fits and red where it does not. Mouse wheel turns
## it, LMB places it, E cancels (the object stays in the hands).

const REACH := 3.2
const STEP := deg_to_rad(15.0)
const OK_COLOR := Color(0.25, 0.95, 0.45, 0.42)
const BAD_COLOR := Color(1.0, 0.22, 0.2, 0.42)

var game: Node
var size := Vector3.ONE
var ignored: Array[RID] = []
var on_place: Callable
var on_cancel: Callable
var yaw_offset := 0.0
var shown_yaw := 0.0
var valid := false
## Collider under the ghost (the truck, a table…), handed to on_place.
var surface: Node
var active := false
var material := StandardMaterial3D.new()

func _init(night_game: Node) -> void:
	game = night_game
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	hide()

## silhouette: a node to show (it is reparented here and tinted); footprint:
## box size used for the free-space check; place(transform) / cancel() callbacks.
func begin(silhouette: Node3D, footprint: Vector3, skip: Array[RID], place: Callable, cancel: Callable) -> void:
	finish()
	for child in get_children():
		child.queue_free()
	add_child(silhouette)
	silhouette.transform = Transform3D.IDENTITY
	silhouette.visible = true
	for node: Node3D in silhouette.find_children("*", "Node3D", true, false):
		node.visible = true
	for part: GeometryInstance3D in silhouette.find_children("*", "GeometryInstance3D", true, false):
		part.material_override = material
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for body in silhouette.find_children("*", "CollisionObject3D", true, false):
		body.queue_free()
	size = footprint
	ignored = skip.duplicate()
	ignored.append(game.home.player.get_rid())
	on_place = place
	on_cancel = cancel
	yaw_offset = 0.0
	shown_yaw = game.home.player.rotation.y
	active = true
	show()
	update_pose(1.0)

func finish() -> void:
	active = false
	hide()

func _input(event: InputEvent) -> void:
	if not active or game.home.modal:
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP: yaw_offset += STEP
			MOUSE_BUTTON_WHEEL_DOWN: yaw_offset -= STEP
			MOUSE_BUTTON_LEFT:
				if valid:
					var placed := global_transform
					finish()
					on_place.call(placed, surface)
				else:
					GameEvents.notify(tr("Здесь не поставить."))
			_: return
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") or event.is_action_pressed("pause"):
		finish()
		on_cancel.call()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if active:
		update_pose(delta)

func update_pose(delta: float) -> void:
	var camera: Camera3D = game.home.player.camera
	var space := get_world_3d().direct_space_state
	var eye := camera.global_position
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye - camera.global_basis.z * REACH, 1, ignored))
	var point: Vector3
	var floor_ok := false
	if hit.is_empty():
		# Looking past the floor: drop straight down from the end of the reach.
		var far := eye - camera.global_basis.z * REACH
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(far, far + Vector3.DOWN * 3.0, 1, ignored))
		point = far if down.is_empty() else down.position
		floor_ok = not down.is_empty() and (down.normal as Vector3).y > 0.9
		surface = null if down.is_empty() else down.collider
	else:
		point = hit.position
		floor_ok = (hit.normal as Vector3).y > 0.9
		surface = hit.collider
	var target_yaw: float = game.home.player.rotation.y + yaw_offset
	shown_yaw = lerp_angle(shown_yaw, target_yaw, clampf(delta * 14.0, 0.0, 1.0))
	global_transform = Transform3D(Basis(Vector3.UP, shown_yaw), point + Vector3.UP * 0.006)
	valid = floor_ok and fits(point, target_yaw)
	material.albedo_color = OK_COLOR if valid else BAD_COLOR

func fits(point: Vector3, yaw: float) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = size - Vector3(0.04, 0.04, 0.04)
	query.shape = shape
	query.transform = Transform3D(Basis(Vector3.UP, yaw), point + Vector3.UP * (size.y * 0.5 + 0.03))
	query.collision_mask = 1
	query.exclude = ignored
	return game.home.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
