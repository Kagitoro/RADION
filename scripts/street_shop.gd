class_name StreetShop
extends Node3D

static var SAVE := SavePaths.file("late_set_supplies.cfg")
## [name, price, effect, model, description]; model is the FPProps builder shown in the shop.
const ITEMS := [
	["Энергетик",4,"+15% к скорости бега на 45 с · R","energy_can","VOLT Energy, 330 мл. Ледяная банка из холодильника у кассы."],
	["Пиво",5,"1 бутылка · B","beer_bottle","Night Lager 5,2%. Тёмное стекло, капли конденсата, открывается большим пальцем."],
	["Сигареты",6,"5 сигарет · N","cigarette_pack","Пачка ORION. Зажигалка уже в кармане."],
	["Упаковка пива",26,"6 бутылок","six_pack","Шесть бутылок Night Lager в картонной переноске. Выгоднее, чем по одной."],
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
	# Shell: same footprint and collisions as before.
	world.box(self,Vector3(0,.06,0),Vector3(4.2,.12,2.55),trim,true)
	world.box(self,Vector3(0,2.53,0),Vector3(4.35,.20,2.7),metal,true)
	world.box(self,Vector3(0,1.25,-1.2),Vector3(4.15,2.5,.18),panel_color,true)
	for side in [-1,1]:
		world.box(self,Vector3(side*2,1.25,0),Vector3(.18,2.5,2.4),panel_color,true)
	world.box(self,Vector3(0,.53,1.11),Vector3(4,1.06,.24),metal,true)
	world.box(self,Vector3(0,2.28,1.19),Vector3(4.2,.44,.27),metal)
	build_counter()
	build_awning()
	build_sign()
	build_fridge(Vector3(-1.32,0,-.86))
	build_cigarette_rack(Vector3(.95,1.32,-1.07))
	build_snack_shelves(Vector3(.95,0,-.98))
	build_ceiling()
	world.point_light(self,Vector3(0,1.94,1.41),Color("#a9f6de"),1.55,6)

# --- kiosk dressing --------------------------------------------------------------

func part(parent: Node3D, mesh: Mesh, at: Vector3, surface: Material, turn := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.rotation = turn
	node.material_override = surface
	parent.add_child(node)
	return node

func box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

func glow(color: Color, energy: float) -> StandardMaterial3D:
	var surface := StandardMaterial3D.new()
	surface.albedo_color = color.darkened(.3)
	surface.emission_enabled = true
	surface.emission = color
	surface.emission_energy_multiplier = energy
	return surface

func finish(color: Color, rough := .6, metal := 0.0, texture: Texture2D = null) -> StandardMaterial3D:
	var surface := StandardMaterial3D.new()
	surface.albedo_color = color
	surface.roughness = rough
	surface.metallic = metal
	if texture!=null:
		surface.albedo_texture = texture
	return surface

func wood_texture() -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.frequency = .02
	noise.fractal_octaves = 3
	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 64
	texture.seamless = true
	texture.noise = noise
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0,.3,.5,.7,1])
	ramp.colors = PackedColorArray([Color("#4a2c18"),Color("#7a4e2c"),Color("#5c3820"),Color("#8a5c34"),Color("#4f301a")])
	texture.color_ramp = ramp
	return texture

func build_counter() -> void:
	var top := part(self,box_mesh(Vector3(4.1,.06,.56)),Vector3(0,1.09,1.14),finish(Color.WHITE,.35,0.0,wood_texture()))
	top.name = "CounterTop"
	var top_body := StaticBody3D.new()
	top_body.position = Vector3(0,1.06,1.13)
	var shape := CollisionShape3D.new()
	var volume := BoxShape3D.new()
	volume.size = Vector3(4.1,.11,.52)
	shape.shape = volume
	top_body.add_child(shape)
	add_child(top_body)
	# Glowing strip under the counter lip.
	part(self,box_mesh(Vector3(3.9,.018,.02)),Vector3(0,1.035,1.42),glow(Color("#a9f6de"),2.6))
	# Register: body, tilted screen, receipt slot and a card terminal.
	var register := Node3D.new()
	register.position = Vector3(1.25,1.12,1.0)
	add_child(register)
	part(register,box_mesh(Vector3(.36,.12,.30)),Vector3(0,.06,0),finish(Color("#1a1e22"),.4,.3))
	part(register,box_mesh(Vector3(.30,.18,.02)),Vector3(0,.25,-.05),finish(Color("#15181b"),.3,.4),Vector3(-.35,0,0))
	part(register,box_mesh(Vector3(.26,.14,.004)),Vector3(0,.252,-.038),glow(Color("#46ffa6"),1.4),Vector3(-.35,0,0))
	var total := Label3D.new()
	total.text = "$ 0.00"
	total.font_size = 40
	total.pixel_size = .0016
	total.modulate = Color("#0a2a18")
	total.position = Vector3(0,.255,-.034)
	total.rotation = Vector3(-.35,0,0)
	total.outline_size = 0
	register.add_child(total)
	part(register,box_mesh(Vector3(.08,.03,.13)),Vector3(-.28,.015,.08),finish(Color("#2b2f33"),.4,.2))
	part(register,box_mesh(Vector3(.06,.004,.04)),Vector3(-.28,.032,.06),glow(Color("#7fc8ff"),1.2))
	# Gum and lighters impulse rack on the counter.
	var rack := Node3D.new()
	rack.position = Vector3(-1.2,1.12,1.18)
	add_child(rack)
	part(rack,box_mesh(Vector3(.42,.05,.18)),Vector3(0,.025,0),finish(Color("#c7c2b8"),.5,.4))
	for index in range(7):
		var lighter := FPProps.lighter(false)
		lighter.position = Vector3(-.17+index*.057,.05,0)
		lighter.rotation.y = PI*.5
		rack.add_child(lighter)
		var plastic := lighter.get_child(0) as MeshInstance3D
		plastic.material_override = finish(Color.from_hsv(float(index)/7.0,.7,.75),.3)
		for child in lighter.get_children():
			if child is MeshInstance3D and child.position.x!=0 and child.position.y<.05:
				child.material_override = plastic.material_override

func build_awning() -> void:
	var stripes := 12
	var width := 4.4/stripes
	for index in range(stripes):
		var tint := Color("#2e8a78") if index%2==0 else Color("#e8efe9")
		part(self,box_mesh(Vector3(width,.02,.78)),Vector3(-2.2+width*(index+.5),2.04,1.62),finish(tint,.7),Vector3(.32,0,0))
	# Hanging valance flaps along the front edge.
	for index in range(stripes):
		var tint := Color("#2e8a78") if index%2==0 else Color("#e8efe9")
		part(self,box_mesh(Vector3(width,.16,.012)),Vector3(-2.2+width*(index+.5),1.86,1.99),finish(tint,.75))

func build_sign() -> void:
	world.add_sign(self,"NIGHT SHOP",Vector3(0,2.30,1.34),Vector3.ZERO,Color("#c9fff0"),.0050)
	var tube := glow(Color("#a9f6de"),4.0)
	# Neon frame around the lettering.
	for y in [2.13,2.47]:
		part(self,FPProps.cylinder_mesh(.012,1.7,8),Vector3(0,y,1.335),tube,Vector3(0,0,PI*.5))
	for x in [-.85,.85]:
		part(self,FPProps.cylinder_mesh(.012,.34,8),Vector3(x,2.30,1.335),tube)
	var open := Label3D.new()
	open.text = "OPEN 24/7"
	open.font_size = 36
	open.pixel_size = .0032
	open.modulate = Color("#ff5a6a")
	open.position = Vector3(1.55,2.30,1.335)
	open.outline_size = 0
	add_child(open)
	var price_board := Label3D.new()
	price_board.text = "NIGHT LAGER   $5\nVOLT ENERGY   $4\nORION         $6\nSIX-PACK     $26"
	price_board.font_size = 30
	price_board.pixel_size = .0022
	price_board.modulate = Color("#fff3d6")
	price_board.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	price_board.position = Vector3(-1.95+.02,1.75,.2)
	price_board.rotation.y = PI*.5
	price_board.outline_size = 0
	add_child(price_board)
	part(self,box_mesh(Vector3(.02,.5,.8)),Vector3(-1.9,1.75,.2),finish(Color("#16201f"),.8))

func build_fridge(at: Vector3) -> void:
	var fridge := Node3D.new()
	fridge.position = at
	add_child(fridge)
	var shell := finish(Color("#d9dde0"),.35,.6)
	part(fridge,box_mesh(Vector3(1.24,2.0,.06)),Vector3(0,1.0,-.24),shell)
	for x in [-.6,.6]:
		part(fridge,box_mesh(Vector3(.05,2.0,.52)),Vector3(x,1.0,0),shell)
	part(fridge,box_mesh(Vector3(1.24,.12,.52)),Vector3(0,.06,0),finish(Color("#1c2124"),.5,.4))
	part(fridge,box_mesh(Vector3(1.24,.1,.52)),Vector3(0,1.95,0),shell)
	part(fridge,box_mesh(Vector3(1.1,.12,.02)),Vector3(0,1.95,.265),glow(Color("#7fe8ff"),2.2))
	part(fridge,box_mesh(Vector3(1.14,1.75,.01)),Vector3(0,1.02,-.205),glow(Color("#dff6ff"),.9))
	var can_mesh := FPProps.lathe(PackedVector2Array(FPProps.CAN_PROFILE),20)
	var can_skin := finish(Color.WHITE,.3,.5,FPProps.can_wrap())
	var bottle_mesh := FPProps.lathe(PackedVector2Array(FPProps.BOTTLE_PROFILE),16)
	var bottle_glass := finish(Color("#4a2208"),.12,.0)
	var label_mesh := FPProps.cylinder_mesh(.0331,.072,16)
	var label_skin := finish(Color.WHITE,.7,0.0,FPProps.beer_label())
	var shelf := finish(Color("#c9d1d6"),.3,.7)
	for row in range(4):
		var y := .2+row*.43
		part(fridge,box_mesh(Vector3(1.12,.015,.44)),Vector3(0,y,-.01),shelf)
		for column in range(14):
			var x := -.52+column*.08
			for depth in range(2):
				var spot := Vector3(x,y+.008,-.1+depth*.12)
				if row>=2:
					part(fridge,can_mesh,spot,can_skin,Vector3(0,-.4+column*.13,0))
				elif column%2==0:
					part(fridge,bottle_mesh,spot,bottle_glass)
					part(fridge,label_mesh,spot+Vector3(0,.066,0),label_skin,Vector3(0,PI*.5,0))
	var door := StandardMaterial3D.new()
	door.albedo_color = Color(.75,.9,1.0,.12)
	door.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	door.roughness = .05
	door.metallic_specular = 1.0
	for side in [-1,1]:
		part(fridge,box_mesh(Vector3(.58,1.78,.012)),Vector3(side*.29,1.02,.255),door)
		part(fridge,box_mesh(Vector3(.58,1.78,.03)),Vector3(side*.29,1.02,.255),frame_material())
		part(fridge,FPProps.cylinder_mesh(.012,.5,10),Vector3(side*.04,1.1,.29),finish(Color("#cfd4d8"),.25,.9))
	var inside := OmniLight3D.new()
	inside.light_color = Color("#d8f4ff")
	inside.light_energy = .9
	inside.omni_range = 1.6
	inside.position = Vector3(0,1.2,.1)
	fridge.add_child(inside)

## Door frame drawn as an outline only (inner area left clear).
func frame_material() -> StandardMaterial3D:
	var surface := StandardMaterial3D.new()
	surface.albedo_color = Color("#9aa3a8")
	surface.metallic = .8
	surface.roughness = .3
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	surface.alpha_scissor_threshold = .5
	var image := Image.create(32,96,false,Image.FORMAT_RGBA8)
	image.fill(Color(1,1,1,0))
	for y in range(96):
		for x in range(32):
			if x<2 or x>29 or y<2 or y>93:
				image.set_pixel(x,y,Color.WHITE)
	surface.albedo_texture = ImageTexture.create_from_image(image)
	return surface

func build_cigarette_rack(at: Vector3) -> void:
	var rack := Node3D.new()
	rack.position = at
	add_child(rack)
	part(rack,box_mesh(Vector3(1.6,.72,.08)),Vector3(0,.3,-.04),finish(Color("#1a1d20"),.5,.3))
	part(rack,box_mesh(Vector3(1.6,.03,.03)),Vector3(0,.67,.02),glow(Color("#ffe2b0"),2.0))
	var body := box_mesh(Vector3(.056,.086,.022))
	var face := QuadMesh.new()
	face.size = Vector2(.056,.086)
	var paper := finish(Color.WHITE,.5,0.0,FPProps.pack_texture())
	var tints := [Color("#b0231c"),Color("#1f4fa0"),Color("#2c2c2c"),Color("#c8a34f"),Color("#2e7d4f")]
	for row in range(3):
		for column in range(18):
			var spot := Vector3(-.74+column*.087,.08+row*.2,.012)
			var tint: Color = tints[(column/4+row)%tints.size()]
			part(rack,body,spot,finish(tint,.55))
			part(rack,face,spot+Vector3(0,0,.0115),paper)

func build_snack_shelves(at: Vector3) -> void:
	var shelves := Node3D.new()
	shelves.position = at
	add_child(shelves)
	var board := finish(Color("#2a3236"),.5,.4)
	var noise := FastNoiseLite.new()
	noise.seed = 5
	for row in range(2):
		var y := .38+row*.42
		part(shelves,box_mesh(Vector3(1.6,.03,.36)),Vector3(0,y,0),board)
		for column in range(9):
			var hue := fposmod(noise.get_noise_2d(column*7,row*3)*2.0+.1*column,1.0)
			var bag := box_mesh(Vector3(.13,.2,.06))
			var snack := part(shelves,bag,Vector3(-.7+column*.175,y+.115,.02),finish(Color.from_hsv(hue,.75,.85),.25,.35))
			snack.rotation.x = -.12
			snack.scale = Vector3(1,1,1.4)
	part(shelves,box_mesh(Vector3(1.6,.02,.02)),Vector3(0,.82,.19),glow(Color("#a9f6de"),1.2))

func build_ceiling() -> void:
	for x in [-1.0,1.0]:
		part(self,box_mesh(Vector3(1.2,.04,.12)),Vector3(x,2.41,0),finish(Color("#c9cfd2"),.4,.5))
		part(self,FPProps.cylinder_mesh(.018,1.1,10),Vector3(x,2.38,0),glow(Color("#f2fbff"),3.2),Vector3(0,0,PI*.5))
	world.point_light(self,Vector3(0,2.21,.02),Color("#f3f7ff"),1.25,3.5)

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
	panel.open()
	home.set_modal(true)

func close() -> void:
	panel.close()
	home.set_modal(false)

func refresh() -> void:
	panel.set_stock(tr("$%d   ·   Пиво %d   ·   Энергетики %d   ·   Сигареты %d") % [home.party.cash,beer,energy,home.party.cigarettes])
	panel.set_wallet(home.party.cash)
	panel.set_owned([energy,beer,home.party.cigarettes,beer])

func buy(index: int, quantity := 1) -> void:
	if not is_open() or not can_interact():
		return
	quantity = maxi(1,quantity)
	var price: int = ITEMS[index][1]*quantity
	if home.party.cash<price:
		panel.set_message(tr("Не хватает денег."),false)
		return
	home.party.cash -= price
	match index:
		0: energy += quantity
		1: beer += quantity
		2: home.party.cigarettes += 5*quantity
		3: beer += 6*quantity
	save_stock()
	refresh()
	panel.set_message(tr("Куплено · %s × %d") % [tr(ITEMS[index][0]),quantity],true)
	panel.celebrate()

func drink_energy() -> void:
	if energy<=0:
		GameEvents.notify(tr("Энергетиков нет · купи в Night Shop"))
		return
	if home.player.energy_boost>0.0:
		GameEvents.notify(tr("Энергетик ещё действует · %d с") % ceili(home.player.energy_boost))
		return
	if not home.party.consumables.drink_energy():
		return
	energy -= 1
	save_stock()

## The drink kicks in mid-animation, on the last gulp.
func apply_energy() -> void:
	home.player.energy_boost = Balance.ENERGY_DRINK_DURATION
	home.party.consumables.sound("heartbeat",-4)
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
