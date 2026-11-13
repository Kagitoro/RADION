extends Node3D

const ITEM_ID := "base-45"
const PACK_SIZE := 6
const CAPACITY := 24

var home: Home
var door := Node3D.new()
var shelves := Node3D.new()
var lamp: OmniLight3D
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
	world.box(self,Vector3(0,.98,.386),Vector3(.79,1.94,.07),shell)
	for side in [-1,1]:
		world.box(self,Vector3(side*.364,.98,-.005),Vector3(.062,1.94,.75),shell)
		world.box(self,Vector3(side*.325,1.09,-.002),Vector3(.022,1.66,.70),liner)
	for height in [.08,1.91]:
		world.box(self,Vector3(0,height,-.002),Vector3(.69,.08,.75),shell)
	world.box(self,Vector3(0,.20,0),Vector3(.67,.19,.71),liner)
	for height in [.36,.73,1.14,1.54]:
		world.box(self,Vector3(0,height,0),Vector3(.658,.029,.65),liner)
		world.box(self,Vector3(0,height,-.333),Vector3(.655,.031,.028),Color("#80a4ad"))
	add_child(door)
	door.position = Vector3(-.38,.0,-.382)
	world.box(door,Vector3(.38,.99,-.025),Vector3(.772,1.88,.086),Color("#b6c1c8"))
	world.box(door,Vector3(.38,.99,.023),Vector3(.718,1.81,.034),Color("#384249"))
	world.box(door,Vector3(.38,.99,.047),Vector3(.69,1.78,.028),liner)
	for height in [.48,.95,1.38]:
		world.box(door,Vector3(.38,height,.072),Vector3(.60,.046,.07),liner)
	world.box(door,Vector3(.67,1.22,-.095),Vector3(.039,.28,.047),Color("#252c33"))
	world.box(door,Vector3(.34,1.76,-.071),Vector3(.14,.033,.006),Color("#46535d"))
	add_child(shelves)
	lamp = OmniLight3D.new()
	add_child(lamp)
	lamp.position = Vector3(0,1.79,-.18)
	lamp.light_color = Color("#d5f6ff")
	lamp.light_energy = .62
	lamp.omni_range = 1.55
	lamp.hide()
	refresh_stock()

func aimed() -> bool:
	if not is_visible_in_tree():
		return false
	var camera := home.player.camera
	var eye := to_local(camera.global_position)
	if eye.z > -.29:
		return false
	var target := to_global(Vector3(0,1.16,-.47))
	var offset := target - camera.global_position
	if offset.length_squared() > 2.1*2.1 or offset.normalized().dot(-camera.global_basis.z) < .81:
		return false
	var ray := PhysicsRayQueryParameters3D.create(camera.global_position,target,1,[home.player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or hit.collider == home.bodies.get(ITEM_ID)

func hint() -> String:
	if not opened:
		return tr("E · Открыть холодильник")
	return tr("Холодильник: %d · с собой: %d · E закрыть\n1 взять · 2 положить · 3 убрать упаковку · 4 взять упаковку") % [home.shop.fridge_beer,home.shop.beer]

func toggle() -> void:
	opened = not opened
	if motion != null:
		motion.kill()
	lamp.visible = opened
	motion = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	motion.tween_property(door,"rotation:y",1.63 if opened else 0.0,.34)

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
	var packs := floori(float(home.shop.fridge_beer)/PACK_SIZE)
	var loose := home.shop.fridge_beer % PACK_SIZE
	for index in range(packs):
		var origin := Vector3(0,[.375,.755,1.155,1.555][index],.13)
		world.box(shelves,origin+Vector3.UP*.044,Vector3(.27,.088,.18),Color("#97724f"))
		for slot in range(PACK_SIZE):
			add_bottle(origin+Vector3((slot%3-1)*.082,.048,-.043 if slot<3 else .043))
	for index in range(loose):
		add_bottle(Vector3(-.24+index*.114,1.155,-.19))

func add_bottle(at: Vector3) -> void:
	var item := Node3D.new()
	shelves.add_child(item)
	item.position = at + Vector3.UP*.108
	home.party.consumables.build_bottle(item)
