class_name NightWorld
extends Node3D


var home: Home
var initialized := false
var street := Node3D.new()
var smoking_spot := Vector3.ZERO
var door_center := Vector3.ZERO
var floor_id := "night-courtyard"
var materials := {}
var prop_models := {}
var nightclub: Nightclub
var shop: StreetShop
var subway: SubwayStation
var district: NightDistrict

func _init(game_home: Home) -> void:
	home = game_home

func setup() -> void:
	add_child(street)
	install_floor()
	refresh()
	clear_street_trees()
	night_lighting()
	build_street()
	build_lounge()
	build_club_access()
	initialized = true

func install_floor() -> void:
	var model := Node3D.new()
	home.add_child(model)
	var row: Dictionary = home.make_template("floor")
	row.merge({"id":floor_id,"label":"Улица","x":0.0,"y":-.08,"z":0.0,
		"w":14.0,"h":.08,"d":16.0,"dimensions":[14.0,.08,16.0]},true)
	box(model,Vector3(0,.04,0),Vector3(14,.08,16),Color("#343840"))
	home.records[floor_id] = row
	home.originals[floor_id] = row.duplicate(true)
	home.nodes[floor_id] = model

func refresh() -> void:
	if not home.records.has("base-0"):
		return
	var wall: Dictionary = home.records["base-0"]
	var old_door: Dictionary = home.records["base-73"]
	door_center = Vector3(float(wall.x),float(wall.y),float(old_door.z))
	street.position = door_center
	smoking_spot = door_center+Vector3(-3.7,0,3.5)
	var floor_row: Dictionary = home.records.get(floor_id,{})
	if not floor_row.is_empty():
		floor_row.x = door_center.x-6.99
		floor_row.z = door_center.z
		home.apply_item(floor_id)
	old_door.deleted = true
	home.apply_item("base-73")
	var id := "night-front-door"
	if not home.records.has(id):
		var doorway: Dictionary = home.openings.draft("opening")
		doorway.label = "Вход на вечеринку"
		doorway.w = 1.12
		doorway.h = 2.20
		doorway.wall_id = str(wall.id)
		doorway.wall_offset = 0.0
		home.openings.insert(doorway,id)
		home.originals[id] = doorway.duplicate(true)
	var opening: Dictionary = home.records[id]
	opening.wall_offset = (door_center.z-float(wall.z))/float(home.openings.width(wall))
	opening.deleted = false
	home.openings.pose(opening,wall)
	home.apply_item(id)

func outside(point: Vector3) -> bool:
	return point.x<door_center.x-.07

func clear_street_trees() -> void:
	var bounds := Rect2(Vector2(door_center.x-78,door_center.z-36),Vector2(79,71))
	for grove in home.find_children("*","MultiMeshInstance3D",true,false):
		var instances: MultiMesh = grove.multimesh
		for index in range(instances.instance_count):
			var transform: Transform3D = instances.get_instance_transform(index)
			if bounds.has_point(Vector2(transform.origin.x,transform.origin.z)):
				transform.origin.x -= 82
				instances.set_instance_transform(index,transform)

func night_lighting() -> void:
	for node in home.find_children("*","WorldEnvironment",true,false):
		var env := (node as WorldEnvironment).environment
		env.ambient_light_color = Color("#9daed0")
		env.ambient_light_energy = .24
		var material := ShaderMaterial.new()
		material.shader = preload("res://assets/city/night_sky.gdshader")
		var sky := Sky.new()
		sky.sky_material = material
		env.sky = sky
	for light in home.find_children("*","DirectionalLight3D",true,false):
		light.light_energy = .055
		light.light_color = Color("#a6bded")
	for light in home.scene_lighting.get_children():
		light.light_energy *= .78

func build_street() -> void:
	box(street,Vector3(-10,-.026,0),Vector3(7,.05,16),Color("#191c24"))
	for index in range(7):
		box(street,Vector3(-10,.003,-7.4+index*2.25),Vector3(.10,.008,1.0),Color("#b4b1a1"))
	for z in [-7.7,7.7]:
		box(street,Vector3(-3.6,.02,z),Vector3(7.0,.12,.18),Color("#626674"),true)
		box(street,Vector3(-7,.65,z),Vector3(13.9,.055,.055),Color("#454e5e"))
		box(street,Vector3(-7,.42,z),Vector3(13.9,.04,.04),Color("#454e5e"))
		box(street,Vector3(-7,.65,z),Vector3(13.9,1.3,.08),Color.TRANSPARENT,true,true)
		for post in range(8):
			box(street,Vector3(-.5-post*1.8,.43,z),Vector3(.055,.86,.055),Color("#454e5e"))
	for side in [-1,1]:
		var z: float = side*4.85
		box(street,Vector3(-13.85,.67,z),Vector3(.09,1.34,6.3),Color.TRANSPARENT,true,true)
		for height in [.40,.78]:
			box(street,Vector3(-13.85,height,z),Vector3(.05,.05,6.3),Color("#505965"))
		for post in range(5):
			box(street,Vector3(-13.85,.5,side*(1.7+post*1.55)),Vector3(.065,1.0,.065),Color("#505965"))
	for z in [-5.8,5.8]:
		lamp(Vector3(-6.5,0,z))
	build_shelter()
	add_sign(street,"NOCH / HOUSE PARTY",Vector3(-.16,2.52,0),Vector3(0,-PI*.5,0),Color("#df8aaf"),.0024)
	add_sign(street,tr("КУРИЛКА"),Vector3(-4.4,2.20,3.5),Vector3(0,PI*.5,0),Color("#81bdc7"),.0021)
	for side in [-1,1]:
		var planter := Vector3(-1.2,0,side*2.9)
		var plant := place_prop(street,"furniture/pottedPlant",planter,Vector3(.63,.98,.63))
		box(street,planter+Vector3.UP*.24,Vector3(.62,.48,.62),Color("#414955"),true,plant)
	place_prop(street,"furniture/trashcan",Vector3(-5.95,0,4.35),Vector3(.39,.64,.39))
	box(street,Vector3(-5.95,.32,4.35),Vector3(.39,.64,.39),Color.TRANSPARENT,true,true)
	NightDistrict.place_car(street,0,Vector3(-9,0,-4.6))
	NightDistrict.place_car(street,1,Vector3(-9,0,4.7))

func build_club_access() -> void:
	district = NightDistrict.new(self)
	street.add_child(district)
	district.build()
	for index in range(6):
		box(street,Vector3(-10,.009,-1.25+index*.5),Vector3(3.55,.008,.24),Color("#a5a9ad"))
	for side in [-1,1]:
		lamp(Vector3(-21.63,0,side*2.25))
		add_sign(street,"RADION / CLUB  →",Vector3(-14,1.85,side*2.0),Vector3(0,PI*.5,0),Color("#8deaff"),.0028)
	nightclub = Nightclub.new(self)
	street.add_child(nightclub)
	nightclub.build()
	shop = StreetShop.new(self)
	street.add_child(shop)
	shop.build()
	subway = SubwayStation.new(self)
	street.add_child(subway)
	subway.build()

func club_ground_at(point: Vector2) -> float:
	if not is_instance_valid(nightclub):
		return -INF
	var local := point-Vector2(door_center.x,door_center.z)
	return door_center.y if NightDistrict.BOUNDS.has_point(local) else -INF

func build_shelter() -> void:
	for x in [-5.5,-2.2]:
		for z in [2.2,4.8]:
			box(street,Vector3(x,1.12,z),Vector3(.07,2.24,.07),Color("#343c4b"),true)
	box(street,Vector3(-3.85,2.28,3.5),Vector3(3.6,.10,2.9),Color("#2b3445"))
	var bench := place_prop(street,"furniture/bench",Vector3(-5.15,0,3.50),Vector3(1.8,.90,.42),PI*.5)
	box(street,Vector3(-5.15,.26,3.50),Vector3(.42,.52,1.8),Color("#74644f"),true,bench)
	var table := place_prop(street,"furniture/tableRound",Vector3(-3.4,0,3.5),Vector3(.65,.89,.65))
	box(street,Vector3(-3.4,.86,3.5),Vector3(.65,.055,.65),Color("#595b61"),true,table)
	box(street,Vector3(-3.4,.42,3.5),Vector3(.09,.84,.09),Color("#303641"),true,table)
	place_prop(street,"food/soda-can",Vector3(-3.21,.89,3.40),Vector3(.062,.115,.062))
	place_prop(street,"food/cup",Vector3(-3.55,.89,3.42),Vector3(.08,.10,.08))
	var ashtray := CylinderMesh.new()
	ashtray.top_radius = .10
	ashtray.bottom_radius = .09
	ashtray.height = .035
	mesh(street,ashtray,Vector3(-3.4,.91,3.5),Color("#8d9297"))
	point_light(street,Vector3(-3.8,2.03,3.5),Color("#9ac2ea"),.52,4.0)

func build_lounge() -> void:
	for row in home.records.values():
		if not home.rooms.built_room(row) or bool(row.deleted):
			continue
		var bounds: Rect2 = home.rooms.room_world_bounds(row)
		if bounds.size.x<3.5 or bounds.size.y<3.5:
			continue
		var lounge := Node3D.new()
		home.add_child(lounge)
		var bar_at := Vector3(bounds.end.x-.70,float(home.rooms.floor_surface(row)),bounds.get_center().y)
		# Bar, shelves and a bench occupy the edge of the room, leaving the center open.
		var bar := place_prop(lounge,"furniture/kitchenBar",bar_at,Vector3(1.78,.99,.68),-PI*.5)
		box(lounge,bar_at+Vector3(0,.495,0),Vector3(.68,.99,1.78),Color("#252b36"),true,bar)
		for z in [-.53,.53]:
			var stool_at := bar_at+Vector3(-.70,0,z)
			var stool := place_prop(lounge,"furniture/stoolBar",stool_at,Vector3(.36,.76,.36))
			box(lounge,stool_at+Vector3.UP*.38,Vector3(.35,.76,.35),Color("#55405f"),true,stool)
		var sofa_at := Vector3(bounds.get_center().x,float(home.rooms.floor_surface(row)),bounds.end.y-.45)
		var sofa := place_prop(lounge,"furniture/loungeSofa",sofa_at,Vector3(1.85,.86,.70),PI)
		box(lounge,sofa_at+Vector3.UP*.30,Vector3(1.85,.60,.70),Color("#34424c"),true,sofa)
		place_prop(lounge,"furniture/speaker",sofa_at+Vector3(-1.18,0,0),Vector3(.29,.76,.28),PI)
		place_prop(lounge,"furniture/lampRoundTable",bar_at+Vector3(0,.99,.69),Vector3(.18,.30,.18))
		place_prop(lounge,"furniture/plantSmall1",bar_at+Vector3(0,.99,-.70),Vector3(.15,.21,.15))
		place_prop(lounge,"food/plate",bar_at+Vector3(0,.99,-.31),Vector3(.30,.024,.30))
		place_prop(lounge,"food/pizza",bar_at+Vector3(0,1.008,-.31),Vector3(.26,.04,.26))
		place_prop(lounge,"food/pizza-box",bar_at+Vector3(0,.99,.35),Vector3(.30,.04,.30),.16)
		place_prop(lounge,"food/soda-glass",bar_at+Vector3(-.17,.99,.08),Vector3(.069,.135,.069))
		place_prop(lounge,"food/soda-bottle",bar_at+Vector3(.16,.99,-.01),Vector3(.075,.24,.075))
		place_prop(lounge,"food/burger",bar_at+Vector3(0,.99,.04),Vector3(.10,.083,.10),-.36)
		place_prop(lounge,"food/fries",bar_at+Vector3(.15,.99,.15),Vector3(.085,.11,.078))
		point_light(lounge,Vector3(bounds.get_center().x,2.39,bounds.get_center().y),Color("#ac8edb"),.43,5.8)
		add_sign(lounge,"AFTER HOURS",Vector3(bounds.end.x-.11,1.93,bounds.get_center().y),Vector3(0,-PI*.5,0),Color("#b987d9"),.0020)

func place_prop(parent: Node3D, asset: String, at: Vector3, size: Vector3, yaw: float = 0.0) -> bool:
	var path := "res://assets/venue/"+asset+".glb"
	var template: Node3D = prop_models.get(asset)
	if template == null:
		if not FileAccess.file_exists(path):
			return false
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_file(path,state) != OK:
			return false
		template = document.generate_scene(state) as Node3D
		if template == null:
			return false
		add_child(template)
		template.hide()
		prop_models[asset] = template
	var model := template.duplicate() as Node3D
	var mount := Node3D.new()
	parent.add_child(mount)
	mount.name = asset.get_file()
	mount.add_child(model)
	model.show()
	var bounds := AABB()
	var found := false
	for node in model.find_children("*","MeshInstance3D",true,false):
		var part := node as MeshInstance3D
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var relative := mount.global_transform.affine_inverse()*part.global_transform
		var mesh_bounds := relative*part.get_aabb()
		bounds = bounds.merge(mesh_bounds) if found else mesh_bounds
		found = true
	if not found or minf(bounds.size.x,minf(bounds.size.y,bounds.size.z)) <= .0001:
		mount.free()
		return false
	model.scale = size/bounds.size
	var base := Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
	model.position = -base*model.scale
	mount.position = at
	mount.rotation.y = yaw
	return true

func dress_bar() -> void:
	nightclub.open_venue()
	district.populate()
	if not is_instance_valid(home.party.bottle_template()):
		return
	for index in range(4):
		var bottle := home.party.bottle_template().duplicate() as Node3D
		street.add_child(bottle)
		bottle.show()
		bottle.position = Vector3(-3.55+index*.105,.89,3.65)

func lamp(at: Vector3) -> void:
	box(street,at+Vector3.UP*1.7,Vector3(.08,3.4,.08),Color("#363e4a"),true)
	box(street,at+Vector3(.2,3.37,0),Vector3(.53,.06,.18),Color("#a1bac6"))
	point_light(street,at+Vector3(.2,3.2,0),Color("#ffc995"),1.10,7.5)

func point_light(parent: Node3D, point: Vector3, tint: Color, energy: float, range_value: float) -> void:
	var light := OmniLight3D.new()
	light.position = point
	light.light_color = tint
	light.light_energy = energy
	light.omni_range = range_value
	parent.add_child(light)

func add_sign(parent: Node3D, text: String, at: Vector3, angle: Vector3, color: Color, pixels: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 42
	label.pixel_size = pixels
	label.modulate = color
	label.position = at
	label.rotation = angle
	label.outline_size = 4
	parent.add_child(label)

func box(parent: Node3D, at: Vector3, size: Vector3, tint: Color, solid: bool = false, invisible: bool = false) -> void:
	var shape := BoxMesh.new()
	shape.size = size
	if not invisible:
		mesh(parent,shape,at,tint)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = at
		var collision := CollisionShape3D.new()
		var volume := BoxShape3D.new()
		volume.size = size
		collision.shape = volume
		body.add_child(collision)
		parent.add_child(body)

func sphere(parent: Node3D, at: Vector3, scale_value: Vector3, tint: Color) -> void:
	var shape := SphereMesh.new()
	shape.radial_segments = 14
	shape.rings = 7
	mesh(parent,shape,at,tint).scale = scale_value

func mesh(parent: Node3D, shape: Mesh, at: Vector3, tint: Color) -> MeshInstance3D:
	var model := MeshInstance3D.new()
	model.mesh = shape
	model.position = at
	var key := tint.to_html()
	if not materials.has(key):
		var finish := StandardMaterial3D.new()
		finish.albedo_color = tint
		finish.roughness = .68
		materials[key] = finish
	model.material_override = materials[key]
	parent.add_child(model)
	return model
