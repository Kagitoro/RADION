extends Node3D

const ITEM_ID := "base-45"
const PACK_SIZE := 6
const CAPACITY := 24
const SAMSUNG_DOORS := preload("res://assets/kitchen/samsung_fridge_doors.glb")
const FRESH_X := -.146
const FREEZER_X := .198
const FRESH_SHELVES := [.53, .86, 1.19, 1.52]
const INTERIOR_LIGHT_LAYER := 10
const BODY_WIDTH := .79
const BODY_HEIGHT := 1.94
const BODY_BOTTOM := .01
const DOOR_EDGE_GAP := .003
const DOOR_BOTTOM := BODY_BOTTOM + DOOR_EDGE_GAP
const DOOR_SEAM_CENTER := .053
const DOOR_RECESS := .025

var home: Home
var door: Node3D
var freezer_door: Node3D
var shelves := Node3D.new()
var interior := Node3D.new()
var lamp: OmniLight3D
var lower_lamp: OmniLight3D
var motion: Tween
var opened := false

func _init(game_home: Home) -> void:
	home = game_home

func build() -> void:
	var cabinet: Node3D = home.nodes[ITEM_ID]
	for mesh in cabinet.find_children("*","MeshInstance3D",true,false):
		mesh.hide()
	var world := home.night_world
	var shell := Color("#a7afb7")
	var liner := Color("#e0e7e8")
	interior.name = "InteriorLiner"
	add_child(interior)
	world.box(self,Vector3(0,BODY_BOTTOM+BODY_HEIGHT*.5,.386),Vector3(BODY_WIDTH,BODY_HEIGHT,.07),shell)
	for side in [-1,1]:
		world.box(self,Vector3(side*.364,.98,-.005),Vector3(.062,1.94,.75),shell)
		world.box(interior,Vector3(side*.325,1.09,-.002),Vector3(.022,1.66,.70),liner)
	world.box(self,Vector3(0,.065,-.005),Vector3(.666,.110,.75),shell)
	world.box(self,Vector3(0,1.91,-.005),Vector3(.666,.080,.75),shell)
	world.box(interior,Vector3(0,1.0,.343),Vector3(.63,1.74,.014),liner)
	world.box(interior,Vector3(0,.128,-.002),Vector3(.63,.014,.69),liner)
	world.box(interior,Vector3(0,1.862,-.002),Vector3(.63,.014,.69),liner)
	build_compartments()
	mark_interior(interior)
	var front := SAMSUNG_DOORS.instantiate() as Node3D
	add_child(front)
	door = front.get_node("FreshDoor")
	freezer_door = front.get_node("FreezerDoor")
	door.position = Vector3(-.38,.0,-.382+DOOR_RECESS)
	freezer_door.position = Vector3(.38,.0,-.382+DOOR_RECESS)
	# The embossed lettering shares the skin's front plane in the source.
	for leaf in [door, freezer_door]:
		var trim := leaf.get_node_or_null("Panel0") as MeshInstance3D
		if trim != null:
			trim.position.z -= .0015
	# The FBX contains two display overlays on top of the molded dispenser.
	# Give the display one backing surface so the depth buffer cannot alternate between them.
	for panel_name in ["Panel3", "Panel4", "Panel5"]:
		var panel := freezer_door.get_node_or_null(panel_name) as Node3D
		if panel != null:
			panel.hide()
	world.box(freezer_door,Vector3(-.14,1.38,-.058),Vector3(.142,.055,.004),Color("#10191f"))
	world.add_sign(freezer_door,"−18°   4°",Vector3(-.14,1.38,-.062),Vector3(0,PI,0),
		Color("#c9f2ff"),.00045)
	world.box(door,Vector3(.22,1.03,.035),Vector3(.408,1.85,.038),liner)
	world.box(freezer_door,Vector3(-.16,1.03,.069),Vector3(.285,1.85,.027),liner)
	for height in [.61, 1.01, 1.49]:
		world.box(door,Vector3(.22,height,.088),Vector3(.341,.016,.066),liner)
		world.box(door,Vector3(.22,height+.038,.127),Vector3(.341,.068,.012),Color("#99b7c5"))
		for side in [-1, 1]:
			world.box(door,Vector3(.22+side*.176,height+.025,.09),Vector3(.012,.064,.078),liner)
	var outer_edge := BODY_WIDTH*.5-DOOR_EDGE_GAP
	fit_door(door,-outer_edge,DOOR_SEAM_CENTER-DOOR_EDGE_GAP*.5)
	fit_door(freezer_door,DOOR_SEAM_CENTER+DOOR_EDGE_GAP*.5,outer_edge)
	# The recessed edge belongs to the freezer door and sits behind both front skins.
	var seam_edge := freezer_door.to_local(to_global(Vector3(DOOR_SEAM_CENTER,.98,-.408+DOOR_RECESS)))
	world.box(freezer_door,seam_edge,Vector3(.084,1.90,.012)/freezer_door.scale,Color("#272d32"))
	add_child(shelves)
	lamp = make_interior_light(Vector3(-.14,1.75,-.30),1.18)
	lower_lamp = make_interior_light(Vector3(-.14,.83,-.31),.84)
	refresh_stock()

func fit_door(leaf: Node3D, left: float, right: float) -> void:
	var bounds := AABB()
	var inverse := leaf.global_transform.affine_inverse()
	for mesh: MeshInstance3D in leaf.find_children("*","MeshInstance3D",true,false):
		if not mesh.visible:
			continue
		var local := (inverse * mesh.global_transform) * mesh.get_aabb()
		bounds = bounds.merge(local) if bounds.has_volume() else local
	var top := BODY_BOTTOM + BODY_HEIGHT - DOOR_EDGE_GAP
	leaf.scale.x = (right-left)/bounds.size.x
	leaf.scale.y = (top-DOOR_BOTTOM)/bounds.size.y
	leaf.position.x = left-bounds.position.x*leaf.scale.x
	leaf.position.y = DOOR_BOTTOM-bounds.position.y*leaf.scale.y

func build_compartments() -> void:
	var world := home.night_world
	var rails := Color("#b4ced6")
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(.65,.84,.86,.34)
	glass.roughness = .26
	for height in FRESH_SHELVES:
		var shelf := BoxMesh.new()
		shelf.size = Vector3(.62,.012,.49)
		world.mesh(interior,shelf,Vector3(0,height,.04),Color.WHITE).material_override = glass
		world.box(interior,Vector3(0,height,-.212),Vector3(.62,.019,.014),rails)
		for side in [-1, 1]:
			world.box(interior,Vector3(side*.312,height-.005,.04),Vector3(.009,.022,.50),rails)
	build_drawer(FRESH_X,.34,.373,.25)
	build_drawer(FREEZER_X,.34,.234,.25)

func build_drawer(x: float, height: float, width: float, panel_height: float) -> void:
	var world := home.night_world
	var plastic := Color("#bbd0da")
	world.box(interior,Vector3(x,height-panel_height*.5,.028),Vector3(width,.014,.50),plastic)
	world.box(interior,Vector3(x,height,-.230),Vector3(width,panel_height,.016),Color("#93b4c6"))
	world.box(interior,Vector3(x,height+panel_height*.28,-.245),Vector3(width*.54,.022,.015),Color("#dae6eb"))
	world.box(interior,Vector3(x,height,.281),Vector3(width,panel_height,.014),plastic)
	for side in [-1, 1]:
		world.box(interior,Vector3(x+side*(width*.5-.006),height,.025),Vector3(.012,panel_height,.495),plastic)

func mark_interior(root: Node3D) -> void:
	for mesh: GeometryInstance3D in root.find_children("*","GeometryInstance3D",true,false):
		mesh.set_layer_mask_value(INTERIOR_LIGHT_LAYER,true)

func make_interior_light(at: Vector3, energy: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	add_child(light)
	light.position = at
	light.light_color = Color("#e4f4ff")
	light.light_energy = energy
	light.omni_range = 1.15
	light.light_cull_mask = 1 << (INTERIOR_LIGHT_LAYER - 1)
	light.light_bake_mode = Light3D.BAKE_DISABLED
	light.light_indirect_energy = 0.0
	light.light_volumetric_fog_energy = 0.0
	light.shadow_enabled = false
	light.hide()
	return light

func aimed() -> bool:
	if not is_visible_in_tree():
		return false
	var camera := home.player.camera
	var eye := to_local(camera.global_position)
	var end := camera.global_position - camera.global_basis.z*2.3
	var direction := to_local(end)-eye
	var face := AABB(Vector3(-.415,.02,-.46),Vector3(.83,1.94,.19))
	var face_hit = face.intersects_segment(eye,eye+direction)
	if eye.z > -.29 or face_hit == null:
		return false
	var ray := PhysicsRayQueryParameters3D.create(camera.global_position,end,1,[home.player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or hit.collider == home.bodies.get(ITEM_ID) or (
		camera.global_position.distance_squared_to(hit.position) >= camera.global_position.distance_squared_to(to_global(face_hit)))

func aimed_bottle() -> Node3D:
	if not opened or not aimed():
		return null
	var camera := home.player.camera
	var origin := to_local(camera.global_position)
	var end := to_local(camera.global_position-camera.global_basis.z*2.4)
	var nearest: Node3D
	var distance := INF
	for bottle in shelves.get_children():
		if not bottle.is_visible() or not bottle.has_meta("fridge_bottle"):
			continue
		var bounds := AABB(bottle.position-Vector3(.036,.11,.036),Vector3(.072,.22,.072))
		var hit = bounds.intersects_segment(origin,end)
		if hit != null and origin.distance_squared_to(hit) < distance:
			distance = origin.distance_squared_to(hit)
			nearest = bottle
	return nearest

func click_bottle() -> bool:
	var bottle := aimed_bottle()
	if bottle == null:
		return false
	var shop := home.shop
	if shop.fridge_beer <= 0:
		return false
	shop.fridge_beer -= 1
	shop.beer += 1
	shop.save_stock()
	bottle.hide()
	bottle.queue_free()
	return true

func hint() -> String:
	if not opened:
		return tr("E · Открыть холодильник")
	return tr("Холодильник: %d · с собой: %d · E закрыть\nЛКМ по бутылке / 1 взять · 2 положить · 3 убрать упаковку · 4 взять упаковку") % [home.shop.fridge_beer,home.shop.beer]

func toggle() -> void:
	opened = not opened
	if motion != null:
		motion.kill()
	if opened:
		lamp.show()
		lower_lamp.show()
	var duration := .63 if opened else .49
	motion = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	motion.tween_property(door,"rotation:y",deg_to_rad(116.0) if opened else 0.0,duration)
	motion.tween_property(freezer_door,"rotation:y",deg_to_rad(-108.0) if opened else 0.0,duration)
	if not opened:
		motion.chain().tween_callback(func():
			lamp.hide()
			lower_lamp.hide()
		)

func transfer(option: int) -> void:
	if not opened:
		return
	var shop := home.shop
	var count := PACK_SIZE if option >= 3 else 1
	var deposit := option == 2 or option == 3
	var available := shop.beer if deposit else shop.fridge_beer
	if available < count:
		GameEvents.notify(tr("Бутылок недостаточно"))
		return
	if deposit and shop.fridge_beer + count > CAPACITY:
		GameEvents.notify(tr("Холодильник заполнен"))
		return
	var change := count if deposit else -count
	shop.fridge_beer += change
	shop.beer -= change
	shop.save_stock()
	refresh_stock()

func refresh_stock() -> void:
	for child in shelves.get_children():
		child.hide()
		child.queue_free()
	var world := home.night_world
	var stock := clampi(home.shop.fridge_beer,0,CAPACITY)
	var packs := floori(float(stock)/PACK_SIZE)
	var loose := stock % PACK_SIZE
	for index in range(packs):
		var origin := Vector3(0,FRESH_SHELVES[3-index]+.007,.015)
		world.box(shelves,origin+Vector3.UP*.044,Vector3(.27,.088,.18),Color("#97724f"))
		for slot in range(PACK_SIZE):
			add_bottle(origin+Vector3((slot%3-1)*.082,.048,-.043 if slot<3 else .043))
	for index in range(loose):
		var at := Vector3(((index%3)-1)*.106,FRESH_SHELVES[3-packs]+.007,
			-.155+floori(index/3.0)*.115)
		add_bottle(at)
	mark_interior(shelves)

func add_bottle(at: Vector3) -> void:
	var item := Node3D.new()
	item.set_meta("fridge_bottle",true)
	shelves.add_child(item)
	item.position = at + Vector3.UP*.108
	home.party.consumables.build_bottle(item)
