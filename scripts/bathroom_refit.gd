extends RefCounted

const TUB := preload("res://assets/bathroom/bathtub_radion.glb")
const TOILET := preload("res://assets/bathroom/toilet_radion.glb")
const VANITY := preload("res://assets/bathroom/vanity_radion.glb")
const SOAP := preload("res://assets/bathroom/soap_dispenser.glb")

static func apply(home: Home) -> void:
	var tub := replace_fixture(home,"base-81",TUB,Vector3(1.86,.55,.74))
	replace_fixture(home,"base-83",TOILET,Vector3(.69,.78,.45))
	var vanity := replace_fixture(home,"base-84",VANITY,Vector3(.48,.94,.80),PI*.5,true)
	if vanity != null:
		place_mesh(vanity,SOAP,Vector3(.077,.145,.077),Vector3(.015,.826,.29),0.0,false)
		remove_details(home,["base-88","base-89","base-99","base-100","base-101","base-102","base-103","base-104","base-105"])
	if tub != null:
		fit_shower_screen(home)
		remove_details(home,["base-108","base-109","base-110","base-111","base-112","base-113"])

static func replace_fixture(home: Home, id: String, asset: PackedScene, size: Vector3,
		yaw := 0.0, floating := false) -> Node3D:
	var record: Dictionary = home.records.get(id,{})
	var original: Node3D = home.nodes.get(id)
	if original == null or record.is_empty() or bool(record.deleted):
		return null
	for mesh: MeshInstance3D in original.find_children("*","MeshInstance3D",true,false):
		mesh.hide()
	record.w = size.x
	record.h = size.y
	record.d = size.z
	var floor: Dictionary = home.records.get("base-40",{})
	if not floor.is_empty():
		record.y = home.rooms.floor_surface(floor)
	home.apply_item(id)
	var carrier := Node3D.new()
	carrier.name = "ImportedFixture"
	original.add_child(carrier)
	carrier.scale = Vector3.ONE / original.scale
	place_mesh(carrier,asset,size,Vector3.ZERO,yaw,floating)
	return carrier

static func place_mesh(parent: Node3D, asset: PackedScene, size: Vector3,
		offset: Vector3, yaw: float, floating: bool) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.position = offset
	var model := asset.instantiate() as Node3D
	holder.add_child(model)
	model.rotation.y = yaw
	var inverse := holder.global_transform.affine_inverse()
	var bounds := AABB()
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		var part := (inverse*mesh.global_transform)*mesh.get_aabb()
		bounds = bounds.merge(part) if bounds.has_volume() else part
	if not bounds.has_volume():
		return
	if floating:
		bounds.size.y = bounds.end.y
		bounds.position.y = 0.0
	holder.scale = size/bounds.size
	model.position = Vector3(-bounds.get_center().x,-bounds.position.y,-bounds.get_center().z)

static func fit_shower_screen(home: Home) -> void:
	var bath: Dictionary = home.records["base-81"]
	var screen: Dictionary = home.records.get("base-82",{})
	if screen.is_empty() or bool(screen.deleted):
		return
	screen.w = .78
	screen.x = float(bath.x)-float(bath.w)*.5+.42
	screen.z = float(bath.z)-float(bath.d)*.5+.035
	screen.y = float(bath.y)+float(bath.h)-.02
	home.apply_item("base-82")

static func remove_details(home: Home, ids: Array[String]) -> void:
	for id in ids:
		if home.records.has(id):
			home.records[id].deleted = true
			home.apply_item(id)
