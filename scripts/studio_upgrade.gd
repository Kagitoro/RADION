extends RefCounted

const DESK := preload("res://assets/studio/metal_office_desk/metal_office_desk_1k.gltf")
const ROOM_ID := "base-135"
const DESK_ID := "base-137"

static func apply(home: Home) -> void:
	if not home.records.has(ROOM_ID) or not home.records.has(DESK_ID):
		return
	if not bool(home.records[ROOM_ID].get("studio_refit", false)):
		refit_layout(home)
	if int(home.records[ROOM_ID].get("studio_refit", 0)) < 3:
		park_chair_at_desk(home)
	if int(home.records[ROOM_ID].get("studio_refit", 0)) < 4:
		move_dresser_to_window(home)
	if int(home.records[ROOM_ID].get("studio_refit", 0)) < 6:
		align_closet_with_corner(home)
		home.records[ROOM_ID].studio_refit = 6
	remove_studio_trim(home)
	install_desk(home)

static func refit_layout(home: Home) -> void:
	var removed := ["base-138", "base-139", "base-140", "base-141", "base-147", "base-150", "base-151"]
	for index in range(170, 215):
		removed.append("base-%d" % index)
	for id in removed:
		if home.records.has(id):
			home.records[id].deleted = true
			home.apply_item(id)

	var room: Dictionary = home.records[ROOM_ID]
	var original := home.rooms.room_world_bounds(room)
	var bed_center := original.end - Vector2(1.85, 0.875)
	home.rooms.begin_room_resize(ROOM_ID)
	home.rooms.preview_room_resize(Rect2(original.position - Vector2(0, 0.75),
			original.size + Vector2(0, 0.75)))
	home.rooms.finish_room_resize()
	var expanded := home.rooms.room_world_bounds(room)
	if home.records.has("base-27"):
		var shared: Dictionary = home.records["base-27"]
		var shared_bounds := home.rooms.room_world_bounds(shared)
		var missing := shared_bounds.position.y - expanded.position.y
		if missing > 0.08 and absf(float(shared.x) - expanded.position.x) < 0.15:
			home.construction.commit({"pieces": [{"template":"wall", "label":"Стена спальни",
					"x":shared.x, "y":shared.y, "z":expanded.position.y + missing * 0.5,
					"w":missing, "h":shared.h, "d":shared.d, "r":-90.0, "room_owner":"studio"}]}, false, false)
	if home.records.has("base-143"):
		var bed: Dictionary = home.records["base-143"]
		bed.x = bed_center.x
		bed.z = bed_center.y
		bed.r = -90.0
		home.apply_item("base-143")

static func move_dresser_to_window(home: Home) -> void:
	var dresser: Dictionary = home.records.get("base-144",{})
	if dresser.is_empty() or bool(dresser.deleted):
		return
	var room: Dictionary = home.records[ROOM_ID]
	var bounds := home.rooms.room_world_bounds(room)
	dresser.r = 90.0
	var footprint := home.rooms.room_world_bounds(dresser)
	dresser.x = bounds.end.x-.12-footprint.size.x*.5
	dresser.z = bounds.end.y-minf(2.30,bounds.size.y*.63)
	dresser.y = home.rooms.floor_surface(room)
	home.apply_item("base-144")

static func remove_studio_trim(home: Home) -> void:
	# These inherited strips were placed against the old room dimensions.
	for id in ["base-162","base-163","base-164","base-165","base-166","base-167","base-168","base-169",
			"window-kitchen","base-53"]:
		if home.records.has(id) and not bool(home.records[id].deleted):
			home.records[id].deleted = true
			home.apply_item(id)
	var passage: Node3D = home.nodes.get("passage-base-27")
	if passage != null:
		var inverse := passage.global_transform.affine_inverse()
		for mesh: MeshInstance3D in passage.find_children("*","MeshInstance3D",true,false):
			var bounds := (inverse * mesh.global_transform) * mesh.get_aabb()
			if bounds.end.y < .12 and bounds.size.x > .4:
				mesh.hide()
	# The original ceiling still contains four suspension pins for the removed acoustic cloud.
	for index in range(1388,1392):
		var pin := home.house.get_node_or_null("Node895/Node894/Node893/Mesh%d" % index) as MeshInstance3D
		if pin != null:
			pin.hide()
	var closet: Node3D = home.nodes.get("base-146")
	if closet != null:
		var filler := closet.get_node_or_null("Node573/Node572/Node571/Mesh883") as MeshInstance3D
		if filler != null:
			filler.hide()

static func align_closet_with_corner(home: Home) -> void:
	var closet: Dictionary = home.records.get("base-146",{})
	var wall: Dictionary = home.records.get("base-27",{})
	if closet.is_empty() or wall.is_empty() or bool(closet.deleted) or bool(wall.deleted):
		return
	var inner_edge := home.rooms.room_world_bounds(wall).end.x
	var closet_edge := home.rooms.room_world_bounds(closet).position.x
	closet.x += inner_edge+.006-closet_edge
	var side_wall: Dictionary = home.records.get("base-36",{})
	if not side_wall.is_empty() and not bool(side_wall.deleted):
		var corner := home.rooms.room_world_bounds(side_wall).end.y
		closet.z += corner+.006-home.rooms.room_world_bounds(closet).position.y
	home.apply_item("base-146")

static func park_chair_at_desk(home: Home) -> void:
	if not home.records.has("base-145") or bool(home.records[DESK_ID].deleted):
		return
	var chair: Dictionary = home.records["base-145"]
	if bool(chair.deleted):
		return
	var desk := home.rooms.room_world_bounds(home.records[DESK_ID])
	var chair_bounds := home.rooms.room_world_bounds(chair)
	chair.x += desk.get_center().x - chair_bounds.get_center().x
	chair.z += desk.end.y + 0.025 - chair_bounds.position.y
	home.apply_item("base-145")

static func install_desk(home: Home) -> void:
	var desk: Node3D = home.nodes[DESK_ID]
	if desk.has_node("MetalOfficeDesk"):
		return
	for child in desk.get_children():
		if child is Node3D:
			child.hide()
	var carrier := Node3D.new()
	carrier.name = "MetalOfficeDesk"
	desk.add_child(carrier)
	var model := DESK.instantiate() as Node3D
	carrier.add_child(model)
	var bounds := AABB()
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var local := (model.global_transform.affine_inverse() * part.global_transform) * part.get_aabb()
		bounds = local if not bounds.has_volume() else bounds.merge(local)
		for surface in part.mesh.get_surface_count():
			var material := part.get_active_material(surface) as StandardMaterial3D
			if material != null:
				var dark := material.duplicate() as StandardMaterial3D
				dark.albedo_color *= Color(0.40, 0.41, 0.43)
				dark.roughness = maxf(0.56, dark.roughness)
				part.set_surface_override_material(surface, dark)
	var dimensions := home.vector(home.originals[DESK_ID].dimensions)
	dimensions.y *= 0.56
	carrier.scale = dimensions / bounds.size
	model.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z)
