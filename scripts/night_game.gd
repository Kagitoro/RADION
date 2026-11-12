class_name NightGame
extends Node

var dj: DJStation
var club_dj: DJStation
var intro: ArrivalIntro
var menu: MainMenu
var home: Home
var talk_actions: Label
var reply: Label3D
var reply_time := 0.0
var hint_time := 0.0
const PAUSE_MENU := preload("res://ui/pause_menu.tscn")
const HINTS := preload("res://ui/interaction_hints.tscn")
var pause_panel: PauseMenu
var guest: Node3D
var interact_hint: Label
var flashlight: SpotLight3D
var light_mode := 0

## Conversation ends when the guest is farther than this (metres).
const TALK_RANGE := 3.5
## Max distance to start talking to a guest.
const GUEST_REACH := 2.6
## Minimum view-direction dot product to count as "looking at" a guest / the laptop.
const GUEST_AIM_DOT := .73
const LAPTOP_AIM_DOT := .94
const SMOKING_AREA_RADIUS := 2.2
const TALK_OPTIONS := {0: "talk_end", 1: "talk_1", 2: "talk_2", 3: "talk_3", 4: "talk_4", 5: "talk_5", 6: "talk_6"}
const TRACK_ACTIONS := ["track_1", "track_2", "track_3"]
const LIGHT_COLORS := [Color("#7fa5ff"), Color("#d97bc2"), Color("#ffba86")]
const LIGHT_NAMES := ["синий", "фиолетовый", "тёплый"]

func _init(game_home: Home) -> void:
	home = game_home

func setup() -> void:
	dj = DJStation.new(home)
	add_child(dj)
	dj.setup()
	club_dj = home.club.setup_dj()
	var root: Control = home.hud.root
	var hints: Control = HINTS.instantiate()
	root.add_child(hints)
	talk_actions = hints.get_node("%TalkActions")
	interact_hint = hints.get_node("%InteractHint")
	pause_panel = PAUSE_MENU.instantiate()
	root.add_child(pause_panel)
	pause_panel.resume_requested.connect(toggle_pause)
	pause_panel.intro_requested.connect(func():
		pause_panel.hide()
		intro.start(true)
	)
	pause_panel.new_party_requested.connect(func():
		toggle_pause()
		home.party.stop()
		home.party.starting = true
	)
	pause_panel.main_menu_requested.connect(func(): menu.show_menu())
	pause_panel.music_volume_changed.connect(func(value: float): home.party.music_gain = value)
	pause_panel.steps_volume_changed.connect(func(value: float): home.player.step_audio.volume_db = -16.0+linear_to_db(maxf(.0001,value)))
	pause_panel.language_changed.connect(GameSettings.set_language)
	pause_panel.restart_requested.connect(restart_game)
	pause_panel.mouse_sensitivity_changed.connect(func(value: float): home.player.mouse_sensitivity = .0008+value*.0038)
	pause_panel.hide()
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
	home.shop.setup()
	home.subway.setup()

func _process(delta: float) -> void:
	if interact_hint==null:
		return
	if reply_time > 0.0:
		reply_time -= delta
		if reply_time <= 0.0:
			clear_reply()
	if talk_actions.visible and (not is_instance_valid(guest) or guest.leaving or guest.global_position.distance_squared_to(home.player.global_position)>TALK_RANGE*TALK_RANGE):
		close_talk()
	interact_hint.visible = not home.modal and not talk_actions.visible
	hint_time -= delta
	if not interact_hint.visible or hint_time > 0.0:
		return
	hint_time = .10
	if home.shop.can_interact():
		interact_hint.text = "E · Night Shop"
		return
	var rider := home.subway.aimed_person()
	if rider != null:
		interact_hint.text = home.subway.hint_for(rider)
		return
	if home.party.events.near_fight():
		interact_hint.text = tr("E · Разнять гостей")
		return
	var station := current_dj()
	if station.party.near_deck() and station.aimed_controller():
		interact_hint.text = tr("E / ЛКМ · Подойти к пульту")
		return
	if station == club_dj and station.party.near_deck():
		interact_hint.text = tr("E · Ноутбук     C · FLX4")
		return
	if aimed_laptop(station):
		interact_hint.text = tr("E · Ноутбук     ЛКМ по контроллеру     J · Вечеринка")
		return
	var employee: Node3D = home.club.staff_target()
	if employee != null:
		interact_hint.text = "E · "+tr(employee.name_tag.text)
		return
	var target := aimed_guest()
	if target!=null:
		interact_hint.text = tr("E · Поговорить · %s") % target.display_name()
	elif home.party.near_deck():
		interact_hint.text = tr("E · Ноутбук     ЛКМ по контроллеру     J · Вечеринка")
	elif home.player.global_position.distance_to(home.night_world.smoking_spot)<SMOKING_AREA_RADIUS:
		interact_hint.text = tr("Курилка · N сигарета · K потушить · R энергетик")
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
	return (screen-camera.global_position).normalized().dot(-camera.global_basis.z)>LAPTOP_AIM_DOT

func aimed_guest() -> Node3D:
	var camera: Camera3D = home.player.camera
	var best := GUEST_AIM_DOT
	var result: Node3D
	for person in home.party.guests:
		if person.leaving:
			continue
		var point: Vector3 = person.global_position+Vector3.UP*1.35*float(person.body_height)
		var difference := point-camera.global_position
		if difference.length()>GUEST_REACH:
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
	if home.shop.can_interact():
		home.shop.open()
		return
	var rider := home.subway.aimed_person()
	if rider != null:
		home.subway.give(rider)
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
	var employee: Node3D = home.club.staff_target()
	if employee != null:
		if not home.club.shift.handle_staff(employee):
			home.club.speak(employee)
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
	say(person,person.introduction())
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
				say(person,tr("Давай спокойно. Здесь все отдыхают."))
		0:
			close_talk()
		1:
			party.requested = person.preference
			party.request_time = 40
			say(person,tr("Поставишь «%s»? Под него хочется двигаться.") % str(party.TRACKS[person.preference]))
		2:
			var pool: Array[Vector2i] = party.dance_floor_cells()
			if pool.is_empty():
				say(person,tr("Танцпол пока закрыт. Увидимся, когда включишь музыку."))
				return
			close_talk(false)
			say(person,tr("Я к колонкам. Увидимся на танцполе!"),4.0)
			party.invite_to_dance(person)
		3:
			if not party.has_walkable_area():
				say(person,tr("Давай чуть позже."))
				return
			close_talk(false)
			say(person,tr("Я выхожу. Встретимся под навесом."),4.0)
			party.route_to(person,party.cell_near(home.night_world.smoking_spot))
		4:
			say(person,person.backstory())
		5:
			if person.social_cooldown > 0:
				say(person,tr("Я уже написал. Дай им немного времени."))
				return
			if party.atmosphere < 52:
				say(person,tr("Сначала раскачаем танцпол. Тогда будет кого звать."))
				return
			party.bonus = minf(20,party.bonus+4)
			party.arrival = minf(party.arrival,3.0)
			person.social_cooldown = 32
			say(person,tr("Скинул друзьям адрес. Скоро подтянутся."))

func close_talk(wander: bool = true) -> void:
	talk_actions.hide()
	clear_reply()
	if is_instance_valid(guest):
		guest.partner = null
		guest.rest = 0.0
		if wander and home.party.active and home.party.has_walkable_area():
			home.party.find_destination(guest)
	guest = null

## "Start over" from the pause menu: wipe progress and rebuild the game.
func restart_game() -> void:
	GameReset.restart(get_tree())

func toggle_pause() -> void:
	if talk_actions.visible:
		close_talk()
	pause_panel.visible = not pause_panel.visible
	home.set_modal(pause_panel.visible)

## Routes a gameplay input event to the matching action.
func handle_input(event: InputEvent) -> void:
	if home.shop.is_open():
		if event.is_action_pressed("pause"):
			home.shop.close()
		return
	var station := current_dj()
	if station.panel.visible:
		if event.is_action_pressed("pause") and not station.music_library.chooser.visible:
			station.close()
		return
	if event.is_action_pressed("pause"):
		if talk_actions.visible:
			close_talk()
		else:
			toggle_pause()
		return
	if home.modal or home.player.collapsed or home.player.vomiting:
		return
	if talk_actions.visible:
		for option in TALK_OPTIONS:
			if event.is_action_pressed(TALK_OPTIONS[option]):
				choose(option)
				return
		if event.is_action_pressed("interact"):
			close_talk()
		return
	if event.is_action_pressed("interact"):
		interact()
	elif event.is_action_pressed("start_party"):
		var shift = home.club.shift
		if shift.nearby():
			if not shift.active:
				shift.start()
		else:
			home.party.toggle()
	elif event.is_action_pressed("delegate_staff"):
		home.club.shift.assign_staff()
	elif event.is_action_pressed("open_mixer"):
		if station.party.near_deck():
			station.open(false)
	elif event.is_action_pressed("drink_beer"):
		home.party.consume(true)
	elif event.is_action_pressed("smoke"):
		home.party.consume(false)
	elif event.is_action_pressed("extinguish"):
		home.party.extinguish()
	elif event.is_action_pressed("vomit"):
		home.player.vomit()
	elif event.is_action_pressed("drink_energy"):
		home.shop.drink_energy()
	elif event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible
	elif event.is_action_pressed("beat_mix"):
		if home.party.near_deck():
			home.party.beat_mix()
	elif event.is_action_pressed("cycle_lights"):
		light_mode = (light_mode+1)%LIGHT_COLORS.size()
		home.party.deck_light.light_color = LIGHT_COLORS[light_mode]
		GameEvents.notify(tr("Свет · %s") % tr(LIGHT_NAMES[light_mode]))
	else:
		for index in TRACK_ACTIONS.size():
			if event.is_action_pressed(TRACK_ACTIONS[index]):
				if home.party.near_deck():
					home.party.switch_track(index)
				return
