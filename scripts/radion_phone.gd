extends Control

const BOUNDS := Rect2(-77,-36,85,72)
const ACCENT := Color("#79d6ff")
var game: NightGame
var shell: PanelContainer
var body: VBoxContainer
var map_view: Control
var selected := -1
var page := "home"
const PhoneModel := preload("res://scripts/radion_phone_model.gd")
var apps: SubViewport
var device: Node3D
var hand: FPHand
var lift: Tween
const READ_POSITION := Vector3(.018,-.012,-.165)
const POCKET_POSITION := Vector3(.105,-.29,-.23)

func _init(owner_game: NightGame) -> void:
	game = owner_game

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	apps = SubViewport.new()
	apps.size = Vector2i(390,834)
	apps.disable_3d = true
	apps.gui_disable_input = false
	apps.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(apps)
	shell = PanelContainer.new()
	apps.add_child(shell)
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	device = Node3D.new()
	game.home.player.camera.add_child(device)
	device.position = POCKET_POSITION
	PhoneModel.build(device,apps.get_texture())
	device.hide()
	hand = FPHand.new(true)
	device.add_child(hand)
	hand.position = Vector3(-.066,-.150,-.032)
	hand.rotation = Vector3(1.28,.08,-.40)
	hand.wrist_bend = Vector3(.05,0,.12)
	hand.set_pose("relaxed")
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("#141321")
	frame.border_color = Color("#141321")
	frame.set_border_width_all(5)
	frame.set_corner_radius_all(38)
	frame.content_margin_left = 19
	frame.content_margin_right = 19
	frame.content_margin_top = 28
	frame.content_margin_bottom = 14
	shell.add_theme_stylebox_override("panel",frame)
	var stack := VBoxContainer.new()
	stack.custom_minimum_size = Vector2(345,510)
	shell.add_child(stack)
	var status := UIKit.label("",15)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.text = "22:48                              ▰"
	var island := Panel.new()
	var island_style := StyleBoxFlat.new()
	island_style.bg_color = Color("#030305")
	island_style.set_corner_radius_all(12)
	island.add_theme_stylebox_override("panel",island_style)
	island.mouse_filter = Control.MOUSE_FILTER_IGNORE
	apps.add_child(island)
	island.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	island.offset_left = -43
	island.offset_right = 43
	island.offset_top = 14
	island.offset_bottom = 36
	stack.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var home_button := Button.new()
	home_button.text = "━━━━━━"
	home_button.tooltip_text = tr("Домой")
	home_button.pressed.connect(show_page.bind("home"))
	stack.add_child(home_button)
	var close_button := Button.new()
	close_button.text = tr("Убрать телефон [P / Esc]")
	close_button.pressed.connect(close)
	stack.add_child(close_button)
	hide()

func open() -> void:
	game.home.set_modal(true)
	apps.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if lift!=null:
		lift.kill()
	device.position = POCKET_POSITION
	device.rotation = Vector3(-.42,-.24,-.28)
	device.show()
	lift = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	lift.tween_property(device,"position",READ_POSITION,.48)
	lift.tween_property(device,"rotation",Vector3.ZERO,.48)
	show()
	show_page("home")

func close() -> void:
	if lift!=null:
		lift.kill()
	hide()
	game.home.set_modal(false)
	lift = create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	lift.tween_property(device,"position",POCKET_POSITION,.27)
	lift.tween_property(device,"rotation",Vector3(-.35,-.24,-.24),.27)
	lift.chain().tween_callback(func():
		device.hide()
		apps.render_target_update_mode = SubViewport.UPDATE_DISABLED)

func show_page(next: String) -> void:
	page = next
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	match page:
		"home":
			body.add_child(UIKit.label("22:48",56))
			body.add_child(UIKit.label("RADION",19))
			add_app(tr("Сообщения"),"messages")
			add_app(tr("Новости"),"news")
			add_app(tr("Карты"),"map")
		"messages":
			body.add_child(UIKit.label(tr("Сообщения"),30))
			add_text(tr("Кир"))
			for message in game.intro.phone_messages:
				add_text(tr(message))
			if game.intro.phone_messages.is_empty():
				add_text(tr("Пока нет новых сообщений."))
			if game.intro.opening_completed:
				add_text(tr("Майя · Старое голосовое"))
				add_text(tr("Где ты? Ты сказал десять минут. Мы ждём уже сорок. Я поставила Нико. Перезвони."))
		"news":
			body.add_child(UIKit.label(tr("Новости района"),30))
			add_text(tr("RADION · Сегодня ночной сет. Вход со стороны очереди у Самира."))
			add_text(tr("Northside Supermarket · Открыты четыре продуктовых отдела."))
			add_text(tr("Deck Room · В шоуруме DDJ-FLX4, DDJ-GRV6 и DDJ-FLX10."))
		"map":
			body.add_child(UIKit.label(tr("Карты"),27))
			map_view = Control.new()
			map_view.custom_minimum_size = Vector2(345,245)
			map_view.draw.connect(draw_map)
			body.add_child(map_view)
			var locations := ItemList.new()
			locations.custom_minimum_size.y = 142
			for place in places():
				locations.add_item(place[0])
			if selected>=0:
				locations.select(selected)
			locations.item_selected.connect(func(index): selected = index; map_view.queue_redraw())
			body.add_child(locations)
		_:
			pass

func add_app(label: String, target: String) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 50
	button.pressed.connect(show_page.bind(target))
	body.add_child(button)

func add_text(value: String) -> void:
	var label := UIKit.label(value,16)
	label.custom_minimum_size.x = 345
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(label)

func places() -> Array:
	var world := game.home.night_world
	var subway := SubwayStation.OPENING.get_center()
	var target := Vector3.ZERO
	if game.intro.home_soundcheck_done and not game.intro.first_set_done:
		target = world.street.to_local(world.nightclub.staff[2].global_position)
	return [
		[tr("Дом"),Vector3.ZERO],
		["RADION",world.nightclub.position+Vector3(0,0,Nightclub.ENTRY_Z)],
		["Night Shop",world.shop.position],
		["Northside Supermarket",world.retail[0].position+Vector3(0,0,5)],
		["Deck Room",world.retail[1].position-Vector3(0,0,4.5)],
		[tr("Метро"),Vector3(subway.x,0,subway.y)],
		[tr("Миссия: %s") % game.intro.objective.text if game.intro.objective.visible else tr("Миссия: первый вечер"),target],
	]

func map_point(point: Vector3) -> Vector2:
	var relative := (Vector2(point.x,point.z)-BOUNDS.position)/BOUNDS.size
	return Vector2(12,10)+relative.clamp(Vector2.ZERO,Vector2.ONE)*(map_view.size-Vector2(24,20))

func draw_map() -> void:
	map_view.draw_rect(Rect2(Vector2.ZERO,map_view.size),Color("#202c35"))
	var route := NightDistrict.TRAFFIC_ROUTE
	for i in range(route.size()):
		map_view.draw_line(map_point(route[i]),map_point(route[(i+1)%route.size()]),Color("#667282"),8,true)
	var player := game.home.night_world.street.to_local(game.home.player.global_position)
	var list := places()
	if selected>=0:
		map_view.draw_dashed_line(map_point(player),map_point(list[selected][1]),ACCENT,2,5)
	for i in range(list.size()):
		map_view.draw_circle(map_point(list[i][1]),6 if i==selected else 4,Color("#f7b771") if i==6 else Color("#a4e6b8"))
	map_view.draw_circle(map_point(player),5,ACCENT)

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouse:
		return
	var camera := game.home.player.camera
	var half := PhoneModel.DISPLAY*.5
	var start := device.to_local(camera.project_ray_origin(event.global_position))
	var direction := device.global_basis.inverse()*camera.project_ray_normal(event.global_position)
	if absf(direction.z)<.001:
		return
	var distance := (.0071-start.z)/direction.z
	var hit := start+direction*distance
	if distance<0 or absf(hit.x)>half.x or absf(hit.y)>half.y:
		return
	var forwarded := event.duplicate() as InputEventMouse
	forwarded.position = Vector2(hit.x/PhoneModel.DISPLAY.x+.5,.5-hit.y/PhoneModel.DISPLAY.y)*Vector2(apps.size)
	forwarded.global_position = forwarded.position
	apps.push_input(forwarded,true)
	accept_event()