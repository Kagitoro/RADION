class_name DeckCrate
extends SpeakerBox
## A piece of the home DJ set (the FLX4 controller = party.deck, or the laptop
## = party.laptop) that packs into a flat box: E at it → "Упаковать"; the box
## is carried like the subwoofer box and "Установить" sets the piece back up
## wherever the green ghost allows.

## The content origin sits this far above the surface it stands on.
const DECK_LIFT := 0.036
const PACKED_META := &"deck_packed"

var party: Node
var content: Node3D
var content_size := Vector3(0.95, 0.34, 0.6)
var lift := DECK_LIFT

func _init(night_game: Node, piece: Node3D, footprint_size: Vector3, box: Vector3, box_label: String, label: String, surface_lift := DECK_LIFT) -> void:
	super(night_game)
	party = night_game.home.party
	content = piece
	content_size = footprint_size
	box_size = box
	crate_name = box_label
	item_name = label
	lift = surface_lift
	state = State.DEPLOYED

## No subwoofer model here: the "unpacked" look is the real deck node.
func build_subwoofer(_parent: Node3D) -> void:
	pass

func apply_state() -> void:
	box_visual.visible = state != State.DEPLOYED
	(shape.shape as BoxShape3D).size = box_size
	shape.position.y = box_size.y * 0.5
	shape.disabled = state != State.BOXED
	var deck: Node3D = content
	deck.visible = state == State.DEPLOYED
	if state == State.DEPLOYED:
		deck.remove_meta(PACKED_META)
	else:
		# Far away, so near_deck() / laptop aiming stop matching while packed.
		deck.set_meta(PACKED_META, true)
		deck.position = Vector3(0, -500, 0)
	for part: GeometryInstance3D in box_visual.find_children("*", "GeometryInstance3D", true, false):
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if state == State.CARRIED else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func footprint(unpacked: bool) -> Vector3:
	return content_size if unpacked else box_size

## Ghost of the deck: its meshes only (no lights, screens, sounds or bodies).
func silhouette(unpacked: bool) -> Node3D:
	if not unpacked:
		return box_visual.duplicate() as Node3D
	var copy := content.duplicate(0) as Node3D
	for node in copy.find_children("*", "", true, false):
		if node is Light3D or node is SubViewport or node is AudioStreamPlayer3D or node is CollisionObject3D or node is Camera3D:
			node.free()
	return copy

func can_pack() -> bool:
	if party.active or party.starting:
		GameEvents.notify(tr("Сначала останови вечеринку."))
		return false
	return true

## E at the deck → "Упаковать": the box appears where the deck stood.
func pack() -> void:
	if state != State.DEPLOYED or not can_pack():
		return
	var deck: Node3D = content
	if get_parent() != game.home:
		reparent(game.home)
	# On the floor in front of the player: the desk's collider is taller than
	# its top, a box left where the deck stood could not be reached.
	var floor_point = drop_spot()
	var origin: Vector3 = floor_point if floor_point != null else deck.global_position - Vector3.UP * lift
	global_transform = Transform3D(Basis(Vector3.UP, game.home.player.rotation.y), origin)
	visible = true
	state = State.BOXED
	apply_state()

func place_at(at: Transform3D, unpacked: bool, surface: Node = null) -> void:
	if not unpacked:
		super(at, false, surface)
		return
	var deck: Node3D = content
	deck.global_transform = Transform3D(at.basis, at.origin + Vector3.UP * lift)
	state = State.DEPLOYED
	visible = false
	apply_state()

## Free floor next to the player for the packed box: ahead, then the sides,
## then behind (standing at the desk the front is usually blocked).
func drop_spot():
	var player: CharacterBody3D = game.home.player
	var forward := -player.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	var space := get_world_3d().direct_space_state
	var skip: Array[RID] = [player.get_rid(), body.get_rid()]
	for direction in [forward, right, -right, -forward]:
		var chest := player.global_position + Vector3.UP * 0.6
		var target: Vector3 = chest + direction * 0.75
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(chest, target + direction * 0.3, 1, skip)).is_empty():
			continue
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(target, target + Vector3.DOWN * 1.5, 1, skip))
		if not down.is_empty() and (down.normal as Vector3).y > 0.9:
			return down.position
	return null
