class_name ShopPanel
extends Control
## Night Shop counter: a grid of product cards with 3D thumbnails, a detail pane
## with a turning model, quantity and total. StreetShop owns stock and prices;
## this scene only shows them and reports what the player wants to buy.

signal buy_requested(index: int, quantity: int)
signal close_requested

const MINT := Color("#a9f6de")
const AMBER := Color("#ffc66b")
const INK := Color("#0d1315")
const CARD := Color("#162024")
const CARD_HOVER := Color("#1d2c31")
const MUTED := Color("#8aa39b")
const DANGER := Color("#ff7b6b")
const MAX_QUANTITY := 9

var items: Array = []
var owned: Array = []
var cards: Array[Button] = []
var selected := 0
var quantity := 1
var wallet := 0
var preview_world: SubViewport
var preview_pivot: Node3D
var preview_spin := 0.0

func _ready() -> void:
	%CloseButton.pressed.connect(close_requested.emit)
	%BuyButton.pressed.connect(func(): buy_requested.emit(selected,quantity))
	%Minus.pressed.connect(func(): change_quantity(-1))
	%Plus.pressed.connect(func(): change_quantity(1))
	style()
	build_preview()
	set_process(false)

func style() -> void:
	var window := StyleBoxFlat.new()
	window.bg_color = Color(INK,.97)
	window.border_color = Color(MINT,.55)
	window.set_border_width_all(1)
	window.border_width_top = 3
	window.set_corner_radius_all(14)
	window.set_content_margin_all(22)
	window.shadow_color = Color(MINT,.12)
	window.shadow_size = 24
	%Window.add_theme_stylebox_override("panel",window)
	var detail := StyleBoxFlat.new()
	detail.bg_color = Color("#111a1d")
	detail.border_color = Color("#23353a")
	detail.set_border_width_all(1)
	detail.set_corner_radius_all(10)
	detail.set_content_margin_all(14)
	%Detail.add_theme_stylebox_override("panel",detail)
	%Title.add_theme_color_override("font_color",MINT)
	%Title.add_theme_color_override("font_shadow_color",Color(MINT,.45))
	%Title.add_theme_constant_override("shadow_offset_x",0)
	%Title.add_theme_constant_override("shadow_offset_y",0)
	%Title.add_theme_constant_override("shadow_outline_size",8)
	%Open.add_theme_color_override("font_color",Color(MINT,.6))
	%Wallet.add_theme_color_override("font_color",AMBER)
	%StockLabel.add_theme_color_override("font_color",MUTED)
	%ItemEffect.add_theme_color_override("font_color",MINT)
	%ItemFlavor.add_theme_color_override("font_color",Color("#c5d3ce"))
	%Total.add_theme_color_override("font_color",AMBER)
	%Hint.add_theme_color_override("font_color",MUTED)
	for button in [%Minus,%Plus,%CloseButton]:
		dress_button(button,Color("#1b272b"),Color("#2a3b40"),Color("#e7f2ee"))
	dress_button(%BuyButton,Color("#2a8f78"),Color("#36b195"),Color("#04120e"))

func dress_button(button: Button, fill: Color, hover: Color, text: Color) -> void:
	for state in ["normal","hover","pressed","focus","disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = {"normal":fill,"hover":hover,"pressed":hover.darkened(.15),"focus":hover,"disabled":fill.darkened(.4)}[state]
		box.set_corner_radius_all(8)
		box.set_content_margin_all(6)
		if state=="focus":
			box.border_color = MINT
			box.set_border_width_all(2)
		button.add_theme_stylebox_override(state,box)
	button.add_theme_color_override("font_color",text)
	button.add_theme_color_override("font_hover_color",text)
	button.add_theme_color_override("font_pressed_color",text)
	button.add_theme_color_override("font_focus_color",text)

## items: [[name, price, effect, model, description], ...] — text is translated here.
func set_items(new_items: Array) -> void:
	items = new_items
	for child in %Items.get_children():
		%Items.remove_child(child)
		child.queue_free()
	cards.clear()
	for index in items.size():
		var card := make_card(index)
		%Items.add_child(card)
		cards.append(card)
	select(0)

func make_card(index: int) -> Button:
	var item: Array = items[index]
	var card := Button.new()
	card.custom_minimum_size = Vector2(250,200)
	card.toggle_mode = true
	card.focus_mode = Control.FOCUS_ALL
	card.pivot_offset = Vector2(125,100)
	card.clip_contents = true
	for state in ["normal","hover","pressed","focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = CARD_HOVER if state!="normal" else CARD
		box.set_corner_radius_all(12)
		box.border_color = MINT if state in ["pressed","focus"] else Color("#26363b")
		box.set_border_width_all(2 if state in ["pressed","focus"] else 1)
		card.add_theme_stylebox_override(state,box)
	card.add_theme_stylebox_override("hover_pressed",card.get_theme_stylebox("pressed"))
	var icon := TextureRect.new()
	icon.texture = thumbnail(str(item[3]) if item.size()>3 else "")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(10,6)
	icon.size = Vector2(230,130)
	card.add_child(icon)
	var title := Label.new()
	title.text = tr(item[0])
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.add_theme_font_size_override("font_size",17)
	title.position = Vector2(14,140)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(title)
	var price := Label.new()
	price.name = "Price"
	price.text = "$%d" % item[1]
	price.add_theme_font_size_override("font_size",20)
	price.add_theme_color_override("font_color",AMBER)
	price.position = Vector2(14,164)
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(price)
	var stock := Label.new()
	stock.name = "Owned"
	stock.add_theme_font_size_override("font_size",13)
	stock.add_theme_color_override("font_color",MUTED)
	stock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stock.position = Vector2(110,170)
	stock.size = Vector2(126,20)
	stock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(stock)
	card.pressed.connect(func(): select(index))
	card.focus_entered.connect(func(): select(index))
	card.mouse_entered.connect(func(): bump(card,1.03))
	card.mouse_exited.connect(func(): bump(card,1.0))
	return card

func bump(control: Control, amount: float) -> void:
	var motion := control.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	motion.tween_property(control,"scale",Vector2.ONE*amount,.18)

func select(index: int) -> void:
	if items.is_empty():
		return
	var changed := index!=selected
	selected = clampi(index,0,items.size()-1)
	if changed:
		quantity = 1
	for card_index in cards.size():
		cards[card_index].set_pressed_no_signal(card_index==selected)
	if is_visible_in_tree() and not cards[selected].has_focus():
		cards[selected].grab_focus()
	var item: Array = items[selected]
	%ItemName.text = tr(item[0])
	%ItemEffect.text = tr(item[2])
	%ItemFlavor.text = tr(item[4]) if item.size()>4 else ""
	show_model(str(item[3]) if item.size()>3 else "")
	refresh_total()

func change_quantity(step: int) -> void:
	quantity = clampi(quantity+step,1,MAX_QUANTITY)
	refresh_total()
	bump(%Count,1.25)
	get_tree().create_timer(.12).timeout.connect(func(): bump(%Count,1.0))

func refresh_total() -> void:
	if items.is_empty():
		return
	var cost: int = items[selected][1]*quantity
	%Count.text = str(quantity)
	%Total.text = "$%d" % cost
	var affordable := cost<=wallet
	%Total.add_theme_color_override("font_color",AMBER if affordable else DANGER)
	%BuyButton.text = tr("Купить") if affordable else tr("Не хватает денег")
	%BuyButton.disabled = not affordable
	%Minus.disabled = quantity<=1
	%Plus.disabled = quantity>=MAX_QUANTITY

func set_wallet(cash: int) -> void:
	if cash!=wallet and is_visible_in_tree():
		var counter := create_tween()
		counter.tween_method(func(value: float): %Wallet.text = "$%d" % roundi(value),float(wallet),float(cash),.35)
	else:
		%Wallet.text = "$%d" % cash
	wallet = cash
	refresh_total()

## Units the player already carries, per item.
func set_owned(counts: Array) -> void:
	owned = counts
	for index in mini(cards.size(),counts.size()):
		var label := cards[index].get_node("Owned") as Label
		label.text = tr("есть: %d") % counts[index]

func set_stock(text: String) -> void:
	%StockLabel.text = text

func set_message(text: String, good := true) -> void:
	%MessageLabel.text = text
	%MessageLabel.add_theme_color_override("font_color",MINT if good else DANGER)
	if text!="" and not good:
		var shake := create_tween()
		var home_x: float = %Window.position.x
		for offset in [8.0,-7.0,5.0,-3.0,0.0]:
			shake.tween_property(%Window,"position:x",home_x+offset,.04)

## Small payoff after a purchase: the card pops and the preview spins.
func celebrate() -> void:
	if selected<cards.size():
		var card := cards[selected]
		var pop := card.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.tween_property(card,"scale",Vector2.ONE*1.07,.1)
		pop.tween_property(card,"scale",Vector2.ONE,.22)
	preview_spin += TAU

func open() -> void:
	show()
	set_process(true)
	preview_world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	%Window.scale = Vector2.ONE*.94
	%Window.modulate.a = 0.0
	%Dim.modulate.a = 0.0
	var motion := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	motion.tween_property(%Window,"scale",Vector2.ONE,.22)
	motion.tween_property(%Window,"modulate:a",1.0,.18)
	motion.tween_property(%Dim,"modulate:a",1.0,.25)
	if selected<cards.size():
		cards[selected].grab_focus()

func close() -> void:
	set_process(false)
	preview_world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	hide()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_MINUS, KEY_KP_SUBTRACT:
				change_quantity(-1)
				accept_event()
			KEY_EQUAL, KEY_KP_ADD:
				change_quantity(1)
				accept_event()
			KEY_ENTER, KEY_KP_ENTER:
				if not %BuyButton.disabled:
					buy_requested.emit(selected,quantity)
				accept_event()

func _process(delta: float) -> void:
	if preview_pivot==null:
		return
	preview_pivot.rotation.y += .6*delta
	if preview_spin>0.0:
		var step := minf(preview_spin,delta*9.0)
		preview_pivot.rotation.y += step
		preview_spin -= step
	preview_pivot.position.y = sin(Time.get_ticks_msec()*.002)*.006

# --- 3D product renders -----------------------------------------------------------

var thumbnails := {}

## A lit little stage in its own world: used for thumbnails and the live preview.
static func make_stage(size: Vector2i, transparent := true) -> SubViewport:
	var view := SubViewport.new()
	view.size = size
	view.own_world_3d = true
	view.transparent_bg = transparent
	view.msaa_3d = Viewport.MSAA_4X
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR if transparent else Environment.BG_COLOR
	env.background_color = Color("#111a1d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#9fb3c8")
	env.ambient_light_energy = .55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	view.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-.7,-.6,0)
	key.light_energy = 1.4
	key.light_color = Color("#fff1dc")
	view.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(-.2,2.5,0)
	rim.light_energy = 1.1
	rim.light_color = MINT
	view.add_child(rim)
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.fov = 30
	view.add_child(camera)
	return view

## Builds the model and frames it in the camera.
static func stage_model(view: SubViewport, model: String) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	view.add_child(pivot)
	var builders := {
		"energy_can": FPProps.energy_can, "beer_bottle": FPProps.beer_bottle,
		"cigarette_pack": FPProps.cigarette_pack, "six_pack": FPProps.six_pack,
	}
	if not builders.has(model):
		return pivot
	var prop: Node3D = builders[model].call(false)
	pivot.add_child(prop)
	var bounds := AABB()
	var first := true
	for mesh in prop.find_children("*","MeshInstance3D",true,false):
		var box: AABB = (mesh as MeshInstance3D).get_aabb()
		box = (prop.global_transform.affine_inverse()*(mesh as MeshInstance3D).global_transform)*box if mesh.is_inside_tree() else box
		bounds = box if first else bounds.merge(box)
		first = false
	var center := bounds.get_center()
	prop.position = -center
	prop.rotation.y = -.5
	var radius := maxf(bounds.size.length()*.5,.02)
	var camera := view.get_node("Camera") as Camera3D
	var distance := radius/sin(deg_to_rad(camera.fov*.5))*1.05
	camera.position = Vector3(0,radius*.35,distance)
	camera.look_at(Vector3.ZERO)
	return pivot

func thumbnail(model: String) -> Texture2D:
	if thumbnails.has(model):
		return thumbnails[model]
	var view := make_stage(Vector2i(320,180))
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(view)
	stage_model(view,model)
	thumbnails[model] = view.get_texture()
	return thumbnails[model]

func build_preview() -> void:
	preview_world = make_stage(Vector2i(300,190))
	%Preview.add_child(preview_world)
	preview_world.render_target_update_mode = SubViewport.UPDATE_DISABLED

func show_model(model: String) -> void:
	if preview_world==null:
		return
	if preview_pivot!=null:
		preview_world.remove_child(preview_pivot)
		preview_pivot.queue_free()
	preview_pivot = stage_model(preview_world,model)
	var appear := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	preview_pivot.scale = Vector3.ONE*.7
	appear.tween_property(preview_pivot,"scale",Vector3.ONE,.3)
