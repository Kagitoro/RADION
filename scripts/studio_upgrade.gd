extends RefCounted

const DESK := preload("res://assets/studio/metal_office_desk/metal_office_desk_1k.gltf")
const ROOM_ID := "base-135"
const DESK_ID := "base-137"

static func apply(home: Home) -> void:
	if not home.records.has(ROOM_ID) or not home.records.has(DESK_ID):
		return
	if not bool(home.records[ROOM_ID].get("studio_refit", false)):
		refit_layout(home)
	if int(home.records[ROOM_ID].get("studio_refit", 0)) < 2:
		clear_desk_aisle(home)
		home.records[ROOM_ID].studio_refit = 2
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
	var dresser_center := original.position + Vector2(0.41, original.size.y - 0.305)
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
	if home.records.has("base-144"):
		var dresser: Dictionary = home.records["base-144"]
		dresser.x = dresser_center.x
		dresser.z = dresser_center.y
		home.apply_item("base-144")

static func clear_desk_aisle(home: Home) -> void:
	if not home.records.has("base-145"):
		return
	var chair: Dictionary = home.records["base-145"]
	if bool(chair.deleted):
		return
	var desk := home.rooms.room_world_bounds(home.records[DESK_ID])
	var chair_bounds := home.rooms.room_world_bounds(chair)
	const AISLE := 0.82
	var extra := AISLE - (chair_bounds.position.y - desk.end.y)
	if extra <= 0.0:
		return
	chair.z += extra
	chair.x = minf(float(chair.x), desk.get_center().x - 0.27)
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
