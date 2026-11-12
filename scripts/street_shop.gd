class_name StreetShop
extends Node3D

static var SAVE := SavePaths.file("late_set_supplies.cfg")
const ITEMS := [
	["Энергетик",4,"+15% к скорости бега на 45 с · R"],
	["Пиво",5,"1 бутылка · B"],
	["Сигареты",6,"5 сигарет · N"],
	["Упаковка пива",26,"6 бутылок"],
]

var world: NightWorld
var home: Home
const PANEL := preload("res://ui/shop_panel.tscn")
var panel: ShopPanel
var cashier: Node3D
var beer := 0
var fridge_beer := 3
var energy := 0
var cleaned_litter := 0
var pose_time := 0.0

func _init(night_world: NightWorld) -> void:
	world = night_world
	home = world.home

func build() -> void:
	position = Vector3(-26.1,0,8.2)
	rotation.y = PI*.5
	var metal := Color("#263a3d")
	var panel_color := Color("#416367")
	var trim := Color("#232d36")
	world.box(self,Vector3(0,.06,0),Vector3(4.2,.12,2.55),trim,true)
	world.box(self,Vector3(0,2.53,0),Vector3(4.35,.20,2.7),metal,true)
	world.box(self,Vector3(0,1.25,-1.2),Vector3(4.15,2.5,.18),panel_color,true)
	for side in [-1,1]:
		world.box(self,Vector3(side*2,1.25,0),Vector3(.18,2.5,2.4),panel_color,true)
	world.box(self,Vector3(0,.53,1.11),Vector3(4,1.06,.24),metal,true)
	world.box(self,Vector3(0,1.06,1.13),Vector3(4.1,.11,.52),trim,true)
	world.box(self,Vector3(0,2.28,1.19),Vector3(4.2,.44,.27),metal)
	world.box(self,Vector3(0,2.01,1.48),Vector3(4.35,.07,.68),trim)
	world.add_sign(self,"NIGHT SHOP",Vector3(0,2.30,1.34),Vector3.ZERO,Color("#a9f6de"),.0050)
	world.point_light(self,Vector3(0,1.94,1.41),Color("#a9f6de"),1.55,6)
	world.point_light(self,Vector3(0,2.21,.02),Color("#ffe0b2"),1.05,3)
	for y in [.92,1.34,1.76]:
		world.box(self,Vector3(0,y,-.95),Vector3(3.66,.07,.44),trim)
		for column in range(8):
			var at := Vector3(-1.61+column*.46,y+.036,-.94)
			if column<5:
				world.place_prop(self,"food/soda-can",at,Vector3(.13,.23,.13))
			else:
				world.box(self,at+Vector3.UP*.085,Vector3(.14,.17,.075),Color("#e3ba74") if column%2==0 else Color("#8cb6b4"))
	world.box(self,Vector3(1.25,1.15,1.04),Vector3(.27,.09,.19),Color("#15191f"))

func setup() -> void:
	load_stock()
	cashier = PartyGuest.new(9,null,home.party.psx_assets)
	add_child(cashier)
	cashier.position = Vector3(0,.12,.28)
	cashier.rotation.y = PI
	cashier.name_tag.hide()
	panel = PANEL.instantiate()
	home.hud.root.add_child(panel)
	panel.set_items(ITEMS)
	panel.buy_requested.connect(buy)
	panel.close_requested.connect(close)
	panel.hide()

func is_open() -> bool:
	return is_instance_valid(panel) and panel.visible

func can_interact() -> bool:
	var at := to_local(home.player.global_position)
	return absf(at.x)<2.45 and at.z>1.38 and at.z<3.05 and absf(at.y)<.65

func open() -> void:
	if not can_interact():
		return
	panel.set_message("")
	refresh()
	panel.show()
	home.set_modal(true)

func close() -> void:
	panel.hide()
	home.set_modal(false)

func refresh() -> void:
	panel.set_stock(tr("$%d   ·   Пиво %d   ·   Энергетики %d   ·   Сигареты %d") % [home.party.cash,beer,energy,home.party.cigarettes])

func buy(index: int) -> void:
	if not is_open() or not can_interact():
		return
	var price: int = ITEMS[index][1]
	if home.party.cash<price:
		panel.set_message(tr("Не хватает денег."))
		return
	home.party.cash -= price
	match index:
		0: energy += 1
		1: beer += 1
		2: home.party.cigarettes += 5
		3: beer += 6
	save_stock()
	refresh()
	panel.set_message(tr("Куплено · %s") % tr(ITEMS[index][0]))

func drink_energy() -> void:
	if energy<=0:
		GameEvents.notify(tr("Энергетиков нет · купи в Night Shop"))
		return
	if home.player.energy_boost>0.0:
		GameEvents.notify(tr("Энергетик ещё действует · %d с") % ceili(home.player.energy_boost))
		return
	energy -= 1
	home.player.energy_boost = Balance.ENERGY_DRINK_DURATION
	save_stock()
	GameEvents.notify(tr("Энергетик · бег быстрее на 45 с"))

func save_stock() -> void:
	var config := ConfigFile.new()
	config.set_value("supplies","cash",home.party.cash)
	config.set_value("supplies","beer",beer)
	config.set_value("supplies","fridge_beer",fridge_beer)
	config.set_value("supplies","energy",energy)
	config.set_value("supplies","cigarettes",home.party.cigarettes)
	config.set_value("supplies","cleaned_litter",cleaned_litter)
	if config.save(SAVE)!=OK:
		push_warning("Не удалось сохранить покупки Night Shop")

func load_stock() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE)!=OK:
		return
	home.party.cash = maxi(0,int(config.get_value("supplies","cash",home.party.cash)))
	home.party.cigarettes = maxi(0,int(config.get_value("supplies","cigarettes",home.party.cigarettes)))
	beer = maxi(0,int(config.get_value("supplies","beer",beer)))
	fridge_beer = clampi(int(config.get_value("supplies","fridge_beer",3)),0,24)
	energy = maxi(0,int(config.get_value("supplies","energy",energy)))
	cleaned_litter = int(config.get_value("supplies","cleaned_litter",0))

func _process(delta: float) -> void:
	if not is_instance_valid(cashier):
		return
	var view := get_viewport().get_camera_3d()
	if view==null or view.global_position.distance_squared_to(global_position)>24.0*24.0:
		return
	pose_time += delta
	if pose_time>=.05:
		cashier.pose(pose_time,0.0,false)
		pose_time = 0.0
