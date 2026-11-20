class_name SpeakerBox
extends Node3D
## A boxed subwoofer the player can carry. E on the box: take it. E while
## carrying: "Поставить" unpacks it as a subwoofer, "Кинуть" puts the box down.
## E on the subwoofer: "Упаковать" turns it back into a box.

enum State { BOXED, CARRIED, DEPLOYED }

const BOX_SIZE := Vector3(0.62, 0.66, 0.58)
const SPEAKER_SIZE := Vector3(0.56, 0.6, 0.56)
const REACH := 2.4
## Where the box rides while carried (camera space).
const HOLD := Vector3(0.0, -0.67, -0.74)

var state := State.BOXED
## Overridden by DeckCrate (the DJ set packs into a flatter box).
var box_size := BOX_SIZE
var crate_name := "Коробка с сабвуфером"
var item_name := "Сабвуфер"
var game: Node
var box_visual: Node3D
var speaker_visual: Node3D
var body: StaticBody3D
var shape: CollisionShape3D

func _init(night_game: Node) -> void:
	game = night_game

func _ready() -> void:
	box_visual = Node3D.new()
	add_child(box_visual)
	var cardboard := StandardMaterial3D.new()
	cardboard.albedo_color = Color("#a8794a")
	cardboard.roughness = 0.9
	var tape := StandardMaterial3D.new()
	tape.albedo_color = Color("#d9c08a")
	tape.roughness = 0.6
	add_box(box_visual, Vector3(0, box_size.y * 0.5, 0), box_size, cardboard)
	add_box(box_visual, Vector3(0, box_size.y + 0.002, 0), Vector3(0.09, 0.004, box_size.z + 0.004), tape)
	add_box(box_visual, Vector3(0, box_size.y * 0.5, box_size.z * 0.5 + 0.002), Vector3(0.09, box_size.y, 0.004), tape)
	speaker_visual = Node3D.new()
	add_child(speaker_visual)
	build_subwoofer(speaker_visual)
	body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("speaker_box", self)
	add_child(body)
	shape = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	apply_state()

func add_box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.material_override = material
	part.position = at
	parent.add_child(part)

## Black cabinet with one big woofer facing the front (+Z), on small feet.
func build_subwoofer(parent: Node3D) -> void:
	var cabinet := StandardMaterial3D.new()
	cabinet.albedo_color = Color("#2b2d34")
	cabinet.roughness = 0.75
	var cone := StandardMaterial3D.new()
	cone.albedo_color = Color("#0b0b0d")
	cone.roughness = 0.95
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color("#5b5f68")
	trim.metallic = 0.7
	trim.roughness = 0.35
	var feet := 0.03
	add_box(parent, Vector3(0, feet + (SPEAKER_SIZE.y - feet) * 0.5, 0), Vector3(SPEAKER_SIZE.x, SPEAKER_SIZE.y - feet, SPEAKER_SIZE.z), cabinet)
	for x in [-1, 1]:
		for z in [-1, 1]:
			add_box(parent, Vector3(x * 0.22, feet * 0.5, z * 0.22), Vector3(0.06, feet, 0.06), trim)
	var center := Vector3(0, feet + (SPEAKER_SIZE.y - feet) * 0.5, SPEAKER_SIZE.z * 0.5)
	add_disc(parent, center + Vector3(0, 0, 0.004), 0.235, 0.012, trim)
	add_disc(parent, center + Vector3(0, 0, 0.012), 0.205, 0.016, cone)
	add_disc(parent, center + Vector3(0, 0, 0.022), 0.07, 0.02, trim)

func add_disc(parent: Node3D, at: Vector3, radius: float, depth: float, material: Material) -> void:
	var part := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = depth
	mesh.radial_segments = 28
	part.mesh = mesh
	part.material_override = material
	part.position = at
	part.rotation.x = PI * 0.5
	parent.add_child(part)

func apply_state() -> void:
	box_visual.visible = state != State.DEPLOYED
	speaker_visual.visible = state == State.DEPLOYED
	var extent := SPEAKER_SIZE if state == State.DEPLOYED else box_size
	(shape.shape as BoxShape3D).size = extent
	shape.position.y = extent.y * 0.5
	shape.disabled = state == State.CARRIED
	for part: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if state == State.CARRIED else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func carried() -> bool:
	return state == State.CARRIED

func deployed() -> bool:
	return state == State.DEPLOYED

func aimed() -> bool:
	if state == State.CARRIED:
		return false
	var camera: Camera3D = game.home.player.camera
	var eye := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(eye, eye - camera.global_basis.z * REACH, 1, [game.home.player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == body

func hint() -> String:
	if carried():
		return tr("E · Установить / поставить")
	if aimed():
		return "E · " + (tr(item_name) if deployed() else tr(crate_name))
	return ""

func pick_up() -> void:
	if game.home.party.hands_busy():
		GameEvents.notify(tr("Руки заняты."))
		return
	state = State.CARRIED
	ride(false)
	apply_state()

## Puts the box down in front of the player; unpack = stand the subwoofer up.
func put_down(unpack: bool) -> void:
	var spot = floor_spot()
	if spot == null:
		GameEvents.notify(tr("Здесь не поставить."))
		return
	global_position = spot
	# Woofer (+Z) faces the player.
	rotation = Vector3(0, game.home.player.rotation.y, 0)
	state = State.DEPLOYED if unpack else State.BOXED
	apply_state()

## A see-through copy for the placement ghost (box or unpacked subwoofer).
func silhouette(unpacked: bool) -> Node3D:
	return (speaker_visual if unpacked else box_visual).duplicate() as Node3D

func footprint(unpacked: bool) -> Vector3:
	return SPEAKER_SIZE if unpacked else box_size

## Placement ghost confirmed: stand here as a box or as the subwoofer. On a
## moving body (the delivery truck bed) it becomes its child and rides along.
func place_at(at: Transform3D, unpacked: bool, surface: Node = null) -> void:
	var holder: Node = surface if surface is CharacterBody3D else game.home
	if get_parent() != holder:
		reparent(holder)
	ride(holder == game.home.night_world.delivery.truck)
	global_transform = at
	visible = true
	state = State.DEPLOYED if unpacked else State.BOXED
	apply_state()

## On the truck bed the box rides along without blocking the truck itself.
func ride(on_truck: bool) -> void:
	var delivery = game.home.night_world.delivery
	if on_truck:
		delivery.add_rider(body)
	else:
		delivery.remove_rider(body)

func pack() -> void:
	state = State.BOXED
	apply_state()

## Floor point ~1 m ahead of the player, or null when blocked.
func floor_spot():
	var player: CharacterBody3D = game.home.player
	var forward := -player.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var space := get_world_3d().direct_space_state
	var chest := player.global_position + Vector3.UP * 0.9
	var ahead := chest + forward * 1.0
	var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(chest, ahead + forward * 0.3, 1, [player.get_rid(), body.get_rid()]))
	if not wall.is_empty():
		ahead = chest + forward * maxf(0.0, chest.distance_to(wall.position) - 0.45)
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(ahead, ahead + Vector3.DOWN * 2.5, 1, [player.get_rid(), body.get_rid()]))
	if down.is_empty() or (down.normal as Vector3).y < 0.7 or ahead.distance_to(chest) < 0.35:
		return null
	return down.position

func _process(_delta: float) -> void:
	if state != State.CARRIED:
		return
	var camera: Camera3D = game.home.player.camera
	var yaw := Basis(Vector3.UP, game.home.player.rotation.y)
	global_transform = Transform3D(yaw, camera.global_position + yaw * Vector3(HOLD.x, 0, HOLD.z) + Vector3(0, HOLD.y - box_size.y * 0.5, 0))
