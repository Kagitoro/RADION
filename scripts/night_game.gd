extends Node

const MainMenu = preload("res://scripts/main_menu.gd")
const ArrivalIntro = preload("res://scripts/arrival_intro.gd")
const DJStation = preload("res://scripts/dj_station.gd")
var dj: DJStation
var club_dj: DJStation
var intro: Node
var menu: Node
var home
var talk_actions: Label
var reply: Label3D
var reply_time := 0.0
var hint_time := 0.0
var pause_panel: PanelContainer
var guest: Node3D
var interact_hint: Label
var flashlight: SpotLight3D
var light_mode := 0

func _init(editor) -> void:
	home = editor

func setup() -> void:
	dj = DJStation.new(home)
	add_child(dj)
	dj.setup()
	club_dj = home.night_world.nightclub.setup_dj()
	var root: Control = home.hud.root
	talk_actions = home.hud.label("1  Запросить трек     2  На танцпол     3  В курилку\n4  Как ты сюда попал?     5  Позови друзей     6  Затеять спор     E  Закончить",15)
	root.add_child(talk_actions)
	talk_actions.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	talk_actions.offset_left = -350
	talk_actions.offset_right = 350
	talk_actions.offset_top = -86
	talk_actions.offset_bottom = -32
	talk_actions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	talk_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	talk_actions.hide()
	pause_panel = home.hud.panel()
	root.add_child(pause_panel)
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pause_panel.offset_left = -185
	pause_panel.offset_right = 185
	pause_panel.offset_top = -100
	var pause_content := VBoxContainer.new()
	pause_panel.add_child(pause_content)
	pause_content.add_child(home.hud.label("НОЧЬ / HOUSE PARTY",24))
	pause_content.add_child(home.hud.label("Собери 12 гостей внутри и удержи атмосферу.",14))
	pause_content.add_child(home.hud.label("J вечеринка · E ноутбук · C контроллер · 1–3 треки · M сведение · E разговор\nB пиво · N сигарета · K потушить · R энергетик · V тошнит",13))
	add_slider(pause_content,"Музыка",.85,func(value): home.party.music_gain = value)
	add_slider(pause_content,"Шаги",.63,func(value): home.player.step_audio.volume_db = -16.0+linear_to_db(maxf(.0001,value)))
	add_slider(pause_content,"Чувствительность мыши",.45,func(value): home.player.mouse_sensitivity = .0008+value*.0038)
	pause_content.add_child(home.hud.button("Продолжить",toggle_pause))
	pause_content.add_child(home.hud.button("Смотреть вступление",func():
		pause_panel.hide()
		intro.start(true)
	))
	pause_content.add_child(home.hud.button("Новая вечеринка",func():
		toggle_pause()
		home.party.stop()
		home.party.starting = true
	))
	pause_content.add_child(home.hud.button("Главное меню",func(): menu.show_menu()))
	pause_panel.hide()
	interact_hint = home.hud.label("",15)
	root.add_child(interact_hint)
	interact_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	interact_hint.offset_left = -290
	interact_hint.offset_right = 290
	interact_hint.offset_top = -79
	interact_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interact_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flashlight = SpotLight3D.new()
	flashlight.spot_range = 12
	flashlight.spot_angle = 25
	flashlight.light_color = Color("#dfebff")
	flashlight.light_energy = 1.2
	flashlight.position = Vector3(.12,-.12,0)
	flashlight.hide()
	home.player.camera.add_child(flashlight)
	intro = ArrivalIntro.new()
	add_child(intro)
	intro.setup(home,self)
	menu = MainMenu.new()
	add_child(menu)
	menu.setup(home,self)
	home.night_world.shop.setup()
	home.night_world.subway.setup()

func add_slider(parent: VBoxContainer, text: String, value: float, changed: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label: Label = home.hud.label(text,13)
	label.custom_minimum_size.x = 175
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = .01
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 120
	slider.value_changed.connect(changed)
	row.add_child(slider)

func _process(delta: float) -> void:
	if interact_hint==null:
		return
	if reply_time > 0.0:
		reply_time -= delta
		if reply_time <= 0.0:
			clear_reply()
	if talk_actions.visible and (not is_instance_valid(guest) or guest.leaving or guest.global_position.distance_squared_to(home.player.global_position)>12.25):
		close_talk()
	interact_hint.visible = not home.modal and not talk_actions.visible
	hint_time -= delta
	if not interact_hint.visible or hint_time > 0.0:
		return
	hint_time = .10
	if home.night_world.shop.can_interact():
		interact_hint.text = "E · Night Shop"
		return
	var rider: Node3D = home.night_world.subway.aimed_person()
	if rider != null:
		interact_hint.text = "E · Поговорить" if home.night_world.subway.helped.has(rider) else "E · Дать  · "+rider.name_tag.text
		return
	if home.party.events.near_fight():
		interact_hint.text = "E · Разнять гостей"
		return
	var station := current_dj()
	if station.party.near_deck() and station.aimed_controller():
		interact_hint.text = "E / ЛКМ · Подойти к пульту"
		return
	if station == club_dj and station.party.near_deck():
		interact_hint.text = "E · Ноутбук     C · FLX4"
		return
	if aimed_laptop(station):
		interact_hint.text = "E · Ноутбук     ЛКМ по контроллеру     J · Вечеринка"
		return
	var employee: Node3D = home.night_world.nightclub.staff_target()
	if employee != null:
		interact_hint.text = "E · "+employee.name_tag.text
		return
	var target := aimed_guest()
	if target!=null:
		interact_hint.text = "E · Поговорить · "+target.guest_name
	elif home.party.near_deck():
		interact_hint.text = "E · Ноутбук     ЛКМ по контроллеру     J · Вечеринка"
	elif home.player.global_position.distance_to(home.night_world.smoking_spot)<2.2:
		interact_hint.text = "Курилка · N сигарета · K потушить · R энергетик"
	else:
		interact_hint.text = ""

func current_dj() -> DJStation:
	if club_dj.panel.visible or club_dj.using_controller or club_dj.party.near_deck():
		return club_dj
	return dj

func click_controller() -> bool:
	return current_dj().click_controller()

func aimed_laptop(station: DJStation) -> bool:
	if not station.party.near_deck():
		return false
	var camera: Camera3D = home.player.camera
	var screen: Vector3 = station.party.deck.get_node("LaptopScreen").global_position
	return (screen-camera.global_position).normalized().dot(-camera.global_basis.z)>.94

func aimed_guest() -> Node3D:
	var camera: Camera3D = home.player.camera
	var best := .73
	var result: Node3D
	for person in home.party.guests:
		if person.leaving:
			continue
		var point: Vector3 = person.global_position+Vector3.UP*1.35*float(person.body_height)
		var difference := point-camera.global_position
		if difference.length()>2.6:
			continue
		var score := difference.normalized().dot(-camera.global_basis.z)
		if score<=best:
			continue
		var query := PhysicsRayQueryParameters3D.create(camera.global_position,point,1,[home.player.get_rid()])
		if not home.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		best = score
		result = person
	return result

func interact() -> void:
	if home.night_world.shop.can_interact():
		home.night_world.shop.open()
		return
	var rider: Node3D = home.night_world.subway.aimed_person()
	if rider != null:
		home.night_world.subway.give(rider)
		return
	if home.party.events.near_fight():
		close_talk()
		home.party.events.end_fight(true)
		return
	if talk_actions.visible:
		close_talk()
		return
	var station := current_dj()
	if station.click_controller():
		return
	if aimed_laptop(station) or (station == club_dj and station.party.near_deck()):
		station.open(true)
		return
	var employee: Node3D = home.night_world.nightclub.staff_target()
	if employee != null:
		if not home.night_world.nightclub.shift.handle_staff(employee):
			home.night_world.nightclub.speak(employee)
		return
	var person := aimed_guest()
	if person==null:
		if home.party.near_deck():
			dj.open(true)
		return
	if is_instance_valid(person.partner):
		person.partner.partner = null
		person.partner.speech.hide()
		person.partner = null
	if not home.party.conversation.is_empty():
		var pair: Dictionary = home.party.conversation
		if pair.first==person or pair.second==person:
			home.party.conversation.clear()
	person.follow(PackedVector3Array())
	person.partner = home.player
	person.dancing = false
	guest = person
	say(person,"Я "+person.guest_name+". Мой родной город — "+person.hometown+" ("+person.origin+").")
	talk_actions.show()

func say(person: Node3D, message: String, duration: float = 0.0) -> void:
	clear_reply()
	reply = person.floating_label(message,2.20*person.body_height,40)
	reply.name = "PlayerConversationReply"
	reply.pixel_size = .0023
	reply.outline_size = 10
	reply.width = 550
	reply.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reply.modulate = Color("#fff4ce")
	reply_time = duration

func clear_reply() -> void:
	if is_instance_valid(reply):
		reply.hide()
		reply.queue_free()
	reply = null
	reply_time = 0.0

func choose(number: int) -> void:
	if not is_instance_valid(guest):
		close_talk()
		return
	var party = home.party
	var person := guest
	match number:
		6:
			if not party.events.start_fight(person):
				say(person,"Давай спокойно. Здесь все отдыхают.")
		0:
			close_talk()
		1:
			party.requested = person.preference
			party.request_time = 40
			say(person,"Поставишь «"+str(party.TRACKS[person.preference])+"»? Под него хочется двигаться.")
		2:
			var pool: Array[Vector2i] = party.dance_floor
			if pool.is_empty():
				say(person,"Танцпол пока закрыт. Увидимся, когда включишь музыку.")
				return
			close_talk(false)
			say(person,"Я к колонкам. Увидимся на танцполе!",4.0)
			party.route_to(person,pool[party.rng.randi_range(0,pool.size()-1)])
		3:
			if party.connected.is_empty():
				say(person,"Давай чуть позже.")
				return
			close_talk(false)
			say(person,"Я выхожу. Встретимся под навесом.",4.0)
			party.route_to(person,party.closest_cell(home.night_world.smoking_spot,party.connected))
		4:
			say(person,person.party_role+". "+person.connection)
		5:
			if person.social_cooldown > 0:
				say(person,"Я уже написал. Дай им немного времени.")
				return
			if party.atmosphere < 52:
				say(person,"Сначала раскачаем танцпол. Тогда будет кого звать.")
				return
			party.bonus = minf(20,party.bonus+4)
			party.arrival = minf(party.arrival,3.0)
			person.social_cooldown = 32
			say(person,"Скинул друзьям адрес. Скоро подтянутся.")

func close_talk(wander: bool = true) -> void:
	talk_actions.hide()
	clear_reply()
	if is_instance_valid(guest):
		guest.partner = null
		guest.rest = 0.0
		if wander and home.party.active and not home.party.connected.is_empty():
			home.party.find_destination(guest)
	guest = null

func toggle_pause() -> void:
	if talk_actions.visible:
		close_talk()
	pause_panel.visible = not pause_panel.visible
	home.set_modal(pause_panel.visible)

func key(code: int) -> void:
	if home.night_world.shop.is_open():
		if code==KEY_ESCAPE:
			home.night_world.shop.close()
		return
	var station := current_dj()
	if station.panel.visible:
		if code==KEY_ESCAPE and not station.chooser.visible:
			station.close()
		return
	if code==KEY_ESCAPE:
		if talk_actions.visible:
			close_talk()
		else:
			toggle_pause()
		return
	if home.modal or home.player.collapsed or home.player.vomiting:
		return
	if talk_actions.visible:
		if code>=KEY_0 and code<=KEY_6:
			choose(code-KEY_0)
		elif code==KEY_E:
			close_talk()
		return
	match code:
		KEY_E: interact()
		KEY_J:
			var shift = home.night_world.nightclub.shift
			if shift.nearby():
				if not shift.active:
					shift.start()
			else:
				home.party.toggle()
		KEY_H:
			home.night_world.nightclub.shift.assign_staff()
		KEY_C:
			if station.party.near_deck():
				station.open(false)
		KEY_B: home.party.consume(true)
		KEY_N: home.party.consume(false)
		KEY_K: home.party.extinguish()
		KEY_V: home.player.vomit()
		KEY_R: home.night_world.shop.drink_energy()
		KEY_F: flashlight.visible = not flashlight.visible
		KEY_M:
			if home.party.near_deck():
				home.party.beat_mix()
		KEY_1,KEY_2,KEY_3:
			if home.party.near_deck():
				home.party.switch_track(code-KEY_1)
		KEY_L:
			light_mode = (light_mode+1)%3
			home.party.deck_light.light_color = [Color("#7fa5ff"),Color("#d97bc2"),Color("#ffba86")][light_mode]
			home.hud.notice("Свет · "+["синий","фиолетовый","тёплый"][light_mode])
