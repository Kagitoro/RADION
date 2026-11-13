extends Node3D

const FOOD := [
	["Яблоки",2],["Бананы",2],["Апельсины",3],["Виноград",4],["Авокадо",4],["Томаты",3],
	["Хлеб",3],["Багет",3],["Круассан",4],["Пончики",5],["Печенье",4],["Батончик",2],
	["Молоко",4],["Йогурт",3],["Сыр",6],["Сок",4],["Вода",1],["Газировка",3],
	["Пицца",8],["Бургер",7],["Сэндвич",5],["Суши",9],["Лапша",4],["Мороженое",5],
]
const GEAR := [["DDJ-FLX4",120],["DDJ-GRV6",280],["DDJ-FLX10",480]]
const DECK_FACE := preload("res://assets/dj/flx4-face.png")
const DARK := Color("#222733")
const TRIM := Color("#485364")
const FOOD_COLORS := [Color("#de505b"),Color("#e3af4d"),Color("#59aa76"),Color("#785bbe"),Color("#579cbd"),Color("#ed8f4f")]

var world: NightWorld
var home: Home
var gear_shop: bool
var counter := Vector3.ZERO
var panel: PanelContainer
var catalog: ItemList
var wallet: Label
var result: Label
var buy_button: Button
var use_button: Button

var doors: Array[Node3D] = []
var customers: Array[PartyGuest] = []
var customer_routes: Array[PackedVector3Array] = []
var customer_stops := PackedInt32Array()
var customer_wait := PackedFloat32Array()
var cashier: PartyGuest
var entrance_z := 0.0
var door_open := 0.0

func _init(city: NightWorld, dj_shop: bool) -> void:
	world = city
	home = city.home
	gear_shop = dj_shop

func title() -> String:
	return "DECK ROOM" if gear_shop else "NORTHSIDE SUPERMARKET"

func build() -> void:
	var size := Vector2(14,9) if gear_shop else Vector2(23,10)
	position = Vector3(-66,0,24) if gear_shop else Vector3(-40,0,-29)
	rotation.y = PI if gear_shop else 0.0
	var accent := Color("#c69afb") if gear_shop else Color("#77ebbb")
	var front := size.y*.5
	var wing := size.x*.5-1.35
	world.box(self,Vector3(0,.04,0),Vector3(size.x,.08,size.y),Color("#606777"),true)
	world.box(self,Vector3(0,3.9,0),Vector3(size.x+.22,.18,size.y+.22),DARK,true)
	world.box(self,Vector3(0,1.95,-front),Vector3(size.x,3.9,.22),TRIM,true)
	for side in [-1,1]:
		world.box(self,Vector3(side*size.x*.5,1.95,0),Vector3(.22,3.9,size.y),TRIM,true)
		var center: float = side*(1.35+wing*.5)
		world.box(self,Vector3(center,.51,front),Vector3(wing,1.02,.22),DARK,true)
		world.box(self,Vector3(center,1.97,front),Vector3(wing,1.9,.14),Color("#354856"),true)
		world.box(self,Vector3(center,3.4,front),Vector3(wing,.98,.24),DARK,true)
	world.box(self,Vector3(0,3.26,front),Vector3(2.7,1.28,.24),DARK,true)
	world.box(self,Vector3(0,.035,front+.52),Vector3(2.7,.07,1.04),TRIM,true)
	world.add_sign(self,title(),Vector3(0,3.36,front+.135),Vector3.ZERO,accent,.012)
	world.add_sign(self,tr("Вход"),Vector3(0,2.82,front+.14),Vector3.ZERO,Color.WHITE,.003)
	for x in [-size.x*.3,0,size.x*.3]:
		world.box(self,Vector3(x,3.78,0),Vector3(.18,.05,size.y*.82),accent)
		world.point_light(self,Vector3(x,3.5,0),accent.lerp(Color.WHITE,.8),2.5,11)
	world.point_light(self,Vector3(0,3.15,front+.75),accent,1.75,8)
	counter = Vector3(size.x*.5-2.5,0,front-2.1)
	world.box(self,counter+Vector3.UP*.52,Vector3(2.8,1.04,.95),DARK,true)
	world.box(self,counter+Vector3.UP*1.07,Vector3(2.9,.09,1.02),TRIM)
	world.box(self,counter+Vector3(.65,1.22,0),Vector3(.44,.24,.16),DARK)
	world.add_sign(self,tr("КАССА"),counter+Vector3.UP*2.02,Vector3.ZERO,accent,.004)
	build_doors(front)
	if gear_shop:
		build_showroom()
	else:
		build_aisles()

func build_aisles() -> void:
	var names := [tr("Фрукты и овощи"),tr("Выпечка и снеки"),tr("Молочное и напитки"),tr("Готовая еда")]
	for aisle in range(names.size()):
		var x := -8.4+aisle*5.6
		world.box(self,Vector3(x,.88,-.9),Vector3(.92,1.76,7.6),TRIM,true)
		world.add_sign(self,names[aisle],Vector3(x,2.32,2.83),Vector3.ZERO,Color("#a6f4d7"),.004)
		for level in range(3):
			var y := .24+level*.56
			world.box(self,Vector3(x,y,-.9),Vector3(1.42,.07,7.6),DARK)
			for product in range(6):
				var item: Array = FOOD[aisle*6+product]
				var z := -4.0+product*1.21
				for side in [-1,1]:
					for unit in range(3):
						display_food(Vector3(x+side*.585,y+(.117 if aisle<2 else .155),z+unit*.24),aisle,product,FOOD_COLORS[product],unit==0)
					if level==1:
						world.add_sign(self,"%s · $%d" % [tr(item[0]),item[1]],Vector3(x+side*.72,y+.13,z+.23),Vector3(0,side*PI*.5,0),Color.WHITE,.00115)

func build_showroom() -> void:
	for i in range(GEAR.size()):
		var stand := Vector3(-4.5+i*4.5,0,-1.65)
		world.box(self,stand+Vector3.UP*.5,Vector3(2.4,1.0,1.55),DARK,true)
		world.box(self,stand+Vector3.UP*1.04,Vector3(2.52,.08,1.65),TRIM)
		var display := Node3D.new()
		add_child(display)
		display.position = stand+Vector3.UP*1.085
		build_controller(display,i)
		world.add_sign(self,"%s · $%d" % GEAR[i],stand+Vector3(0,1.56,.61),Vector3.ZERO,Color("#ebdcff"),.0035)

func build_controller(display: Node3D, index: int) -> void:
	var widths := [.482,.7114,.716]
	var depths := [.273,.3759,.400]
	var width: float = widths[index]
	var depth: float = depths[index]
	world.box(display,Vector3(0,.031,0),Vector3(width,.062,depth),Color("#181a20"))
	if index==0:
		var face := QuadMesh.new()
		face.size = Vector2(width,depth)
		var surface := StandardMaterial3D.new()
		surface.albedo_texture = DECK_FACE
		var top := world.mesh(display,face,Vector3.UP*.063,Color.WHITE)
		top.rotation.x = -PI*.5
		top.material_override = surface
	else:
		for channel in range(4):
			var x := (channel-1.5)*.039
			for row in range(4):
				knob(display,Vector3(x,.067,-.135+row*.037),.009,Color("#747e90"))
			world.box(display,Vector3(x,.064,.092),Vector3(.005,.004,.066),Color("#555f71"))
			world.box(display,Vector3(x,.072,.071),Vector3(.025,.012,.012),Color("#a0a5ac"))
	for side in [-1,1]:
		var x: float = side*width*.315
		var radius := .057 if index==0 else .096
		knob(display,Vector3(x,.067,-.025),radius,Color("#737e91"))
		knob(display,Vector3(x,.078,-.025),radius*.91,Color("#222630"))
		if index==2:
			knob(display,Vector3(x,.086,-.025),.028,Color("#5bbfea"))
		if index>0:
			for row in range(2):
				for pad in range(4):
					world.box(display,Vector3(x+(pad-1.5)*.032,.068,.098+row*.026),Vector3(.026,.008,.021),FOOD_COLORS[(pad+index)%FOOD_COLORS.size()])

func knob(parent: Node3D, at: Vector3, radius: float, tint: Color) -> void:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = .012
	shape.radial_segments = 32 if radius>.03 else 10
	world.mesh(parent,shape,at,tint)

func can_interact() -> bool:
	var at := to_local(home.player.global_position)
	if absf(at.x)> (7.0 if gear_shop else 11.5)-.18 or absf(at.z)> (4.5 if gear_shop else 5.0)-.18:
		return false
	return absf(at.y)<1.8 and Vector2(at.x-counter.x,at.z-counter.z).length()<2.35

func setup() -> void:
	populate()
	panel = UIKit.panel()
	home.hud.root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -295
	panel.offset_right = 295
	panel.offset_top = -235
	panel.offset_bottom = 235
	var content := VBoxContainer.new()
	panel.add_child(content)
	content.add_child(UIKit.label(title(),25))
	wallet = UIKit.label("",17)
	content.add_child(wallet)
	catalog = ItemList.new()
	catalog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalog.add_theme_constant_override("v_separation",8)
	content.add_child(catalog)
	result = UIKit.label("",16)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(result)
	var actions := HBoxContainer.new()
	content.add_child(actions)
	buy_button = Button.new()
	buy_button.text = tr("Купить")
	buy_button.pressed.connect(buy)
	actions.add_child(buy_button)
	use_button = Button.new()
	use_button.text = tr("Съесть / выпить")
	use_button.visible = not gear_shop
	use_button.pressed.connect(consume_food)
	actions.add_child(use_button)
	var exit := Button.new()
	exit.text = tr("Закрыть [Esc]")
	exit.pressed.connect(close)
	actions.add_child(exit)
	catalog.item_selected.connect(func(_index): refresh_actions())
	panel.hide()

func open() -> void:
	home.set_modal(true)
	panel.show()
	result.text = tr("Привет! Что подсказать?") if gear_shop else tr("Добрый вечер! Что берём?")
	refresh(0)
	catalog.grab_focus()

func close() -> void:
	panel.hide()
	home.set_modal(false)

func refresh(index: int) -> void:
	wallet.text = tr("Кошелёк · $%d") % home.party.cash
	catalog.clear()
	var rows := GEAR if gear_shop else FOOD
	for i in range(rows.size()):
		var status := ""
		if gear_shop and owns(i):
			status = tr("  ·  Куплен")
		elif not gear_shop:
			var quantity := int(home.shop.food_stock.get(rows[i][0],0))
			if quantity>0:
				status = tr("  ·  В сумке: %d") % quantity
		catalog.add_item("%s   ·   $%d%s" % [tr(rows[i][0]),rows[i][1],status])
	catalog.select(index)
	catalog.ensure_current_is_visible()
	refresh_actions()

func owns(index: int) -> bool:
	return (home.shop.owned_controllers & (1 << index)) != 0

func refresh_actions() -> void:
	var index := catalog.get_selected_items()[0]
	buy_button.disabled = owns(index) if gear_shop else false
	use_button.disabled = gear_shop or int(home.shop.food_stock.get(FOOD[index][0],0))<=0

func buy() -> void:
	var index := catalog.get_selected_items()[0]
	var item: Array = GEAR[index] if gear_shop else FOOD[index]
	if gear_shop and owns(index):
		return
	if home.party.cash<item[1]:
		result.text = tr("Недостаточно денег.")
		return
	home.party.cash -= int(item[1])
	if gear_shop:
		home.shop.owned_controllers |= 1 << index
	else:
		home.shop.food_stock[item[0]] = int(home.shop.food_stock.get(item[0],0))+1
	home.shop.save_stock()
	result.text = tr("Куплено: %s") % tr(item[0])
	refresh(index)

func consume_food() -> void:
	if gear_shop:
		return
	var index := catalog.get_selected_items()[0]
	var item: Array = FOOD[index]
	var quantity := int(home.shop.food_stock.get(item[0],0))
	if quantity<=0:
		return
	home.shop.food_stock[item[0]] = quantity-1
	home.player.intoxication = maxf(0.0,home.player.intoxication-.04)
	home.shop.save_stock()
	result.text = tr("Перекус: %s") % tr(item[0])
	refresh(index)

func build_doors(front: float) -> void:
	entrance_z = front
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(.27,.61,.69,.26)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = .23
	for side in [-1,1]:
		var leaf := Node3D.new()
		add_child(leaf)
		doors.append(leaf)
		leaf.position = Vector3(side*.66,0,front+.16)
		var pane := BoxMesh.new()
		pane.size = Vector3(1.25,2.30,.025)
		world.mesh(leaf,pane,Vector3.UP*1.18,Color.WHITE).material_override = glass
		world.box(leaf,Vector3.UP*1.18,pane.size,Color.TRANSPARENT,true,true)
		for x in [-.64,.64]:
			world.box(leaf,Vector3(x,1.18,0),Vector3(.047,2.35,.06),DARK)
		for y in [.035,1.05,2.35]:
			world.box(leaf,Vector3(0,y,0),Vector3(1.30,.055,.06),TRIM)
	world.box(self,Vector3(0,2.44,front+.16),Vector3(2.72,.13,.19),DARK)

func populate() -> void:
	cashier = PartyGuest.new(8 if gear_shop else 4,null,home.party.psx_assets)
	add_child(cashier)
	cashier.position = counter+Vector3(0,.08,-.79)
	cashier.rotation.y = PI
	cashier.name_tag.text = tr("Продавец") if gear_shop else tr("Кассир")
	for i in range(2 if gear_shop else 4):
		var visitor := PartyGuest.new(10+i,null,home.party.psx_assets)
		add_child(visitor)
		visitor.name_tag.hide()
		var x: float = (-4.5+i*4.5) if gear_shop else (-5.6+i*3.72)
		var route := PackedVector3Array([
			Vector3(x,.08,2.2 if gear_shop else 3.3),
			Vector3(x,.08,-.39 if gear_shop else -.4),
			Vector3(x+.45,.08,.35 if gear_shop else 1.35),
		])
		visitor.position = route[i%route.size()]
		customers.append(visitor)
		customer_routes.append(route)
		customer_stops.append((i+1)%route.size())
		customer_wait.append(float(i)*.65)

func _process(delta: float) -> void:
	if not is_instance_valid(home.player):
		return
	var player := to_local(home.player.global_position)
	if absf(player.x)>25.0 or absf(player.z)>25.0:
		return
	var approaching := absf(player.x)<2.0 and absf(player.z-entrance_z)<2.35 and absf(player.y)<2.0
	door_open = move_toward(door_open,1.0 if approaching else 0.0,delta*2.5)
	for i in range(doors.size()):
		doors[i].position.x = (-1.0 if i==0 else 1.0)*(.66+door_open*1.34)
	if not is_instance_valid(cashier):
		return
	cashier.pose(delta,0.0,false)
	for i in range(customers.size()):
		var guest := customers[i]
		var route := customer_routes[i]
		var target := route[customer_stops[i]]
		customer_wait[i] = maxf(0.0,customer_wait[i]-delta)
		var walking := customer_wait[i]<=0.0
		if walking:
			var direction := guest.position.direction_to(target)
			guest.rotation.y = lerp_angle(guest.rotation.y,atan2(-direction.x,-direction.z),minf(1.0,delta*7.0))
			guest.position = guest.position.move_toward(target,delta*.72)
			if guest.position.distance_squared_to(target)<.004:
				customer_stops[i] = (customer_stops[i]+1)%route.size()
				customer_wait[i] = 2.5+float(i)*.8
				walking = false
		guest.pose(delta,0.0,walking)

func display_food(at: Vector3, aisle: int, product: int, tint: Color, detail: bool) -> void:
	match aisle:
		0:
			var shapes := [Vector3(.19,.17,.19),Vector3(.22,.085,.09),Vector3(.19,.19,.19),Vector3(.15,.14,.16),Vector3(.15,.21,.16),Vector3(.18,.15,.18)]
			var colors := [Color("#bc343c"),Color("#efc542"),Color("#e58627"),Color("#73397b"),Color("#45633c"),Color("#de4e3b")]
			world.sphere(self,at,shapes[product],colors[product])
			if product==1:
				world.sphere(self,at+Vector3(.035,.035,0),Vector3(.13,.075,.09),colors[product])
			elif detail:
				world.box(self,at+Vector3.UP*.091,Vector3(.025,.038,.026),Color("#526137"))
		1:
			world.sphere(self,at,Vector3(.18,.13,.20),Color("#b77a42") if product<4 else tint)
			if detail:
				world.sphere(self,at+Vector3.UP*.05,Vector3(.14,.035,.15),Color("#e6ae65"))
		2:
			var bottle := CylinderMesh.new()
			bottle.top_radius = .071
			bottle.bottom_radius = .076
			bottle.height = .23
			bottle.radial_segments = 10
			world.mesh(self,bottle,at,tint)
			if detail:
				knob(self,at+Vector3.UP*.121,.045,Color("#e8e8df"))
		3:
			world.box(self,at-Vector3.UP*.065,Vector3(.19,.04,.22),Color("#30343c"))
			match product:
				0:
					world.sphere(self,at,Vector3(.18,.035,.19),Color("#cf8847"))
					world.sphere(self,at+Vector3.UP*.016,Vector3(.15,.018,.16),Color("#e4bb54"))
					for offset in [Vector3(-.039,.026,-.029),Vector3(.036,.026,.01),Vector3(-.014,.026,.043)]:
						world.sphere(self,at+offset,Vector3(.037,.008,.037),Color("#9f402e"))
				1:
					world.sphere(self,at-Vector3.UP*.015,Vector3(.156,.047,.15),Color("#bb7842"))
					world.sphere(self,at+Vector3.UP*.006,Vector3(.164,.026,.16),Color("#627237"))
					world.sphere(self,at+Vector3.UP*.036,Vector3(.16,.076,.155),Color("#d09352"))
				2:
					world.box(self,at,Vector3(.13,.06,.12),Color("#dfba82"))
					world.box(self,at+Vector3.UP*.015,Vector3(.138,.012,.127),Color("#608b40"))
					world.box(self,at+Vector3.UP*.028,Vector3(.13,.019,.12),Color("#ead1a2"))
				3:
					for offset in [-.05,.05]:
						world.sphere(self,at+Vector3(offset,0,0),Vector3(.074,.069,.075),Color("#242e2c"))
						world.sphere(self,at+Vector3(offset,.035,0),Vector3(.059,.016,.060),Color("#f3d9c1"))
				_:
					world.sphere(self,at,Vector3(.16,.105,.16),tint)
