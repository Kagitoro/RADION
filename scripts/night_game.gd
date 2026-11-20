class_name NightGame
extends Node

var dj: DJStation
var phone: Control
var gestures: Control
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
const BACKPACK := preload("res://ui/backpack_panel.tscn")
## Player inventory (Tab wheel → Инвентарь).
var backpack: BackpackPanel
## GTA-style wheel on Tab (inventory, actions, emotes) and the E choice list.
var radial: RadialMenu
var interact_menu: InteractMenu
## Boxed subwoofer the player can carry, unpack and pack again.
var speaker_box: SpeakerBox
## Home DJ set: the controller (party.deck) and the laptop pack separately.
var deck_crate: DeckCrate
var laptop_crate: DeckCrate
## Green / red ghost for putting carried things down (wheel turns, LMB places).
var placement: PlacementGhost
var guest: Node3D
var interact_hint: Label
## Crosshair tip (name + key + action); hint_name / hint_kind come with interact_hint.text.
var tip: InteractTip
var hint_name := ""
var hint_kind := ""
var flashlight: SpotLight3D
var litter: Dictionary[int, Node3D] = {}
const KitchenFridge = preload("res://scripts/kitchen_fridge.gd")
var fridge: KitchenFridge
const CLEANUP_REWARD := 12
const LITTER := [
	["hall", Vector3(-4.85,0,-.64), "soda-can", Vector3(.105,.18,.105), .46],
	["living", Vector3(-5.1,0,1.24), "pizza-box", Vector3(.32,.064,.32), .25],
	["kitchen", Vector3(.67,0,-.50), "cup", Vector3(.13,.16,.13), -.56],
	["studio", Vector3(5.12,0,-.12), "soda-bottle", Vector3(.106,.23,.106), -.32],
]

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
	tip = InteractTip.new()
	hints.add_child(tip)
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
	pause_panel.main_menu_requested.connect(func():
		if WalkSession.active:
			WalkSession.leave()
		else:
			menu.show_menu()
	)
	pause_panel.music_volume_changed.connect(func(value: float): set_level("music",value))
	pause_panel.steps_volume_changed.connect(func(value: float): set_level("steps",value))
	pause_panel.language_changed.connect(GameSettings.set_language)
	pause_panel.graphics_changed.connect(set_graphics)
	# Applied by VisualQuality.apply once the scene is built.
	VisualQuality.level = GameSettings.graphics()
	pause_panel.restart_requested.connect(restart_game)
	if WalkSession.active:
		home.add_child(ChatBox.new(home))
		for name in ["IntroButton", "NewPartyButton", "RestartButton"]:
			pause_panel.get_node("%" + name).hide()
		pause_panel.get_node("%MainMenuButton").text = tr("Покинуть прогулку")
		pause_panel.get_node("%Controls").hide()
	pause_panel.mouse_sensitivity_changed.connect(func(value: float): set_level("mouse",value))
	pause_panel.hide()
	for key in GameSettings.DEFAULTS:
		apply_level(key,GameSettings.level(key))
	FpsCounter.apply(GameSettings.show_fps())
	backpack = BACKPACK.instantiate()
	root.add_child(backpack)
	backpack.close_requested.connect(close_backpack)
	backpack.use_requested.connect(use_from_backpack)
	backpack.hide()
	radial = RadialMenu.new(self)
	root.add_child(radial)
	radial.item_chosen.connect(radial_chosen)
	interact_menu = InteractMenu.new(self)
	root.add_child(interact_menu)
	placement = PlacementGhost.new(self)
	home.add_child(placement)
	if home.game_mode:
		speaker_box = SpeakerBox.new(self)
		home.add_child(speaker_box)
		speaker_box.position = Vector3(-4.45, 0.01, 3.0)
		separate_laptop()
		deck_crate = DeckCrate.new(self, home.party.deck, Vector3(0.56, 0.14, 0.34), Vector3(0.62, 0.2, 0.42), "Коробка с DJ-пультом", "DJ-пульт")
		home.add_child(deck_crate)
		if is_instance_valid(home.party.laptop):
			laptop_crate = DeckCrate.new(self, home.party.laptop, Vector3(0.4, 0.26, 0.3), Vector3(0.46, 0.12, 0.34), "Коробка с ноутбуком", "Ноутбук", 0.0)
			home.add_child(laptop_crate)
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
	phone = preload("res://scripts/radion_phone.gd").new(self)
	home.hud.root.add_child(phone)
	gestures = preload("res://scripts/stage_gestures.gd").new(self)
	home.hud.root.add_child(gestures)
	home.player.stage_gestures = gestures
	menu = MainMenu.new()
	add_child(menu)
	menu.setup(home,self)
	home.shop.setup()
	for store in home.night_world.retail:
		store.setup()
	if home.nodes.has(KitchenFridge.ITEM_ID) and home.game_mode:
		fridge = KitchenFridge.new(home)
		home.nodes[KitchenFridge.ITEM_ID].add_child(fridge)
		fridge.build()
	build_litter()
	if is_instance_valid(fridge):
		intro.attach_fridge_note(fridge.door)
	place_litter_on_floor.call_deferred()
	intro.update_objective()
	home.subway.setup()

func cleanup_remaining() -> int:
	return litter.size()

func build_litter() -> void:
	for index in range(LITTER.size()):
		if home.shop.cleaned_litter & (1 << index):
			continue
		var entry: Array = LITTER[index]
		var spot := home.rooms.room_point(entry[0],entry[1])
		var original := home.rooms.room_floor(entry[0])
		var floor: Dictionary = home.records.get(original.get("id",""),{})
		if not floor.is_empty():
			spot.y = home.rooms.floor_surface(floor)
		var piece := Node3D.new()
		add_child(piece)
		piece.global_position = spot + Vector3.UP * .018
		if not home.night_world.place_prop(piece,"food/" + entry[2],Vector3.ZERO,entry[3],entry[4]):
			home.night_world.box(piece,Vector3.UP*.075,Vector3(.14,.15,.13),Color("#db8668"))
		var marker := Label3D.new()
		marker.text = "•"
		marker.font_size = 36
		marker.pixel_size = .003
		marker.modulate = Color("#ffd18e")
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.visibility_range_end = 4.0
		marker.position.y = .33
		piece.add_child(marker)
		litter[index] = piece
		piece.visible = intro.note_read

func place_litter_on_floor() -> void:
	await get_tree().physics_frame
	if not is_inside_tree() or not home.is_inside_tree():
		return
	var space := home.get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = .17
	var standing := CapsuleShape3D.new()
	standing.radius = .19
	standing.height = 1.57
	var volume := PhysicsShapeQueryParameters3D.new()
	volume.shape = sphere
	volume.collision_mask = 1
	volume.exclude = [home.player.get_rid()]
	for index in litter:
		var piece := litter[index]
		var center := piece.global_position
		var zone: String = LITTER[index][0]
		var original := home.rooms.room_floor(zone)
		var floor: Dictionary = home.records.get(original.get("id",""),{})
		for offset in [Vector3.ZERO,Vector3(.4,0,0),Vector3(-.4,0,0),Vector3(0,0,.4),Vector3(0,0,-.4),Vector3(.55,0,.4),Vector3(-.55,0,-.4)]:
			var point: Vector3 = center + offset
			if not floor.is_empty() and not home.rooms.inside_room(floor,Vector2(point.x,point.z),-.19):
				continue
			var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.30,point-Vector3.UP*.18,1,volume.exclude)
			var hit := space.intersect_ray(ray)
			if hit.is_empty() or hit.normal.y < .8 or hit.position.y > center.y+.10:
				continue
			volume.shape = sphere
			volume.transform.origin = hit.position + Vector3.UP*.18
			if not space.intersect_shape(volume,1).is_empty():
				continue
			volume.shape = standing
			var reachable := false
			for direction in [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT]:
				var feet: Vector3 = hit.position + direction*.65
				if not floor.is_empty() and not home.rooms.inside_room(floor,Vector2(feet.x,feet.z),-.12):
					continue
				volume.transform.origin = feet + Vector3.UP*.84
				if not space.intersect_shape(volume,1).is_empty():
					continue
				var sight := PhysicsRayQueryParameters3D.create(feet+Vector3.UP*1.64,hit.position+Vector3.UP*.17,1,volume.exclude)
				if not space.intersect_ray(sight).is_empty():
					continue
				reachable = true
				break
			if reachable:
				piece.global_position = hit.position + Vector3.UP*.009
				break

func show_litter() -> void:
	for piece in litter.values():
		piece.show()

func aimed_cleanup() -> Node3D:
	var camera := home.player.camera
	var candidates: Array = home.party.events.puddles.duplicate()
	if intro.opening_completed and intro.note_read:
		candidates.append_array(litter.values())
	var target: Node3D
	var best := .85
	for item in candidates:
		var heights := [.10,.24,.36] if item.get_parent() == self else [.06]
		for height in heights:
			var point: Vector3 = item.global_position + Vector3.UP * height
			var offset := point - camera.global_position
			if offset.length_squared() > 3.0 * 3.0:
				continue
			var score := offset.normalized().dot(-camera.global_basis.z)
			if score < best:
				continue
			var ray := PhysicsRayQueryParameters3D.create(camera.global_position,point,1,[home.player.get_rid()])
			if not home.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				continue
			target = item
			best = score
	return target

func clean(target: Node3D) -> void:
	var index: Variant = litter.find_key(target)
	if index == null:
		home.party.events.puddles.erase(target)
		GameEvents.notify(tr("След отмыт"))
	else:
		litter.erase(index)
		home.shop.cleaned_litter |= 1 << int(index)
		if litter.is_empty():
			home.party.cash += CLEANUP_REWARD
			intro.cleanup_complete()
			GameEvents.notify(tr("Дом убран · заработано $%d") % CLEANUP_REWARD)
		else:
			GameEvents.notify(tr("Осталось убрать: %d") % litter.size())
		home.shop.save_stock()
		intro.update_objective()
	target.hide()
	target.queue_free()

var shadow_timer := 0.0

func _process(delta: float) -> void:
	if interact_hint==null:
		return
	shadow_timer -= delta
	if shadow_timer<=0.0:
		shadow_timer = .3
		VisualQuality.update_shadow_budget(home.player.camera)
	if reply_time > 0.0:
		reply_time -= delta
		if reply_time <= 0.0:
			clear_reply()
	if talk_actions.visible and (not is_instance_valid(guest) or guest.leaving or guest.global_position.distance_squared_to(home.player.global_position)>TALK_RANGE*TALK_RANGE):
		close_talk()
	interact_hint.visible = not home.modal and not talk_actions.visible
	# The old bottom chip only keeps the text (tests and helpers read it); the
	# player sees the tip next to the crosshair: name + key + action.
	interact_hint.self_modulate.a = 0.0
	hint_time -= delta
	if hint_time > 0.0:
		return
	hint_time = .10
	update_hint()
	if is_instance_valid(fridge):
		fridge.highlight(fridge.aimed_bottle() if interact_hint.visible else null)
	if interact_hint.visible:
		tip.show_tip(hint_name, interact_hint.text)
	else:
		tip.show_tip("", "")
	home.hud.hint.text = control_hints()

## Bottom-left keys: always WASD / Tab / Esc, plus what the hands can do now.
func control_hints() -> String:
	var keys := []
	var consumables = home.party.consumables
	if placement.active:
		keys.append(tr("ЛКМ поставить · Колесо повернуть · E отменить"))
	elif crates().any(func(crate): return crate.carried()) or home.night_world.delivery.held >= 0:
		keys.append(tr("E поставить"))
	elif not consumables.holding.is_empty():
		keys.append(tr("ЛКМ пить") if consumables.sips_left > 0 else tr("ЛКМ пусто"))
		keys.append(tr("G выбросить"))
	elif consumables.holding_cigarette():
		keys.append(tr("ЛКМ затяжка · G выбросить"))
	keys.append(tr("WASD идти · Tab меню · Esc пауза"))
	return " · ".join(keys)

func set_hint(name: String, text: String, kind := "") -> void:
	hint_name = name
	hint_kind = kind
	interact_hint.text = text

## Fills interact_hint.text ("KEY · action", several split by spaces) and
## hint_name (what the player looks at) for the crosshair tip.
func update_hint() -> void:
	if placement.active:
		set_hint("", "")
		return
	for crate in crates():
		if crate.carried():
			set_hint(tr(crate.crate_name), tr("E · Установить / поставить"))
			return
		if crate.aimed():
			set_hint(tr(crate.item_name) if crate.deployed() else tr(crate.crate_name), tr("E · Взаимодействовать") if crate.deployed() else tr("E · Поднять"))
			return
	var delivery := home.night_world.delivery
	var delivery_hint: String = delivery.hint()
	if not delivery_hint.is_empty():
		if delivery.held < 0 and delivery.aimed_cargo():
			set_hint(tr("Сабвуфер"), tr("E · Поднять"))
		elif delivery.is_seated():
			set_hint("", delivery_hint)
		else:
			set_hint(tr("Сабвуфер") if delivery.held >= 0 else tr("Грузовик"), delivery_hint)
		return
	if aimed_map_door() != null:
		set_hint(tr("Дверь"), tr("E · Открыть / закрыть"))
		return
	if intro.entry_aimed():
		set_hint(tr("Входная дверь"), tr("E · Закрыть") if intro.entry_opened else tr("E · Открыть"))
		return
	if aimed_cleanup() != null:
		set_hint(tr("Мусор"), tr("E · Убрать"))
		return
	if is_instance_valid(fridge) and not fridge.aimed_part().is_empty():
		if intro.entry_opened and not intro.note_read:
			set_hint(tr("Записка"), tr("E · Прочитать"))
			return
		set_hint(fridge.hint_name(), fridge.hint())
		return
	for store in home.night_world.retail:
		if store.can_interact():
			set_hint(store.title(), tr("E · Взаимодействовать"))
			return
	if home.shop.can_interact():
		set_hint("Night Shop", tr("E · Взаимодействовать"))
		return
	var rider := home.subway.aimed_person()
	if rider != null:
		set_hint("", home.subway.hint_for(rider))
		return
	if home.party.events.near_fight():
		set_hint(tr("Драка"), tr("E · Разнять гостей"))
		return
	var station := current_dj()
	if station == club_dj and station.party.near_deck():
		set_hint(tr("Пульт клуба"), tr("E · Ноутбук   C · FLX4"))
		return
	if aimed_laptop(station):
		set_hint(tr("Ноутбук"), tr("E · Взаимодействовать"))
		return
	if station.party.near_deck() and station.aimed_controller():
		set_hint(tr("DJ-пульт"), tr("E · Взаимодействовать   ЛКМ · Подойти к пульту"))
		return
	var employee: Node3D = home.club.staff_target()
	if employee != null:
		set_hint(tr(employee.name_tag.text), tr("E · Поговорить"), "staff")
		return
	var target := aimed_guest()
	if target != null:
		set_hint(target.display_name(), tr("E · Поговорить"), "guest")
	elif home.party.near_deck():
		set_hint(tr("DJ-пульт"), tr("E · Взаимодействовать"))
	elif home.player.global_position.distance_to(home.night_world.smoking_spot) < SMOKING_AREA_RADIUS:
		set_hint(tr("Курилка"), "")
	else:
		set_hint("", "")

func current_dj() -> DJStation:
	if club_dj.panel.visible or club_dj.using_controller or club_dj.party.near_deck():
		return club_dj
	return dj

func click_controller() -> bool:
	return WalkSession.can_control_decks() and current_dj().click_controller()

func aimed_map_door() -> Node3D:
	var camera := home.player.camera
	var eye := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(eye, eye - camera.global_basis.z * 2.2, 1, [home.player.get_rid()])
	var hit := home.get_world_3d().direct_space_state.intersect_ray(query)
	var leaf := hit.get("collider") as AnimatableBody3D
	if leaf == null:
		return null
	var door := leaf.get_parent() as Node3D
	return door if door != null and door.is_in_group("map_doors") else null

func aimed_laptop(station: DJStation) -> bool:
	var anchor: Node3D = station.party.laptop_screen()
	if anchor == null:
		return false
	var camera: Camera3D = home.player.camera
	var screen: Vector3 = anchor.global_position
	# The home laptop can stand apart from the controller: be near the laptop itself.
	if screen.distance_to(camera.global_position) > 1.9:
		return false
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
	if home.night_world.delivery.interact():
		return
	var door := aimed_map_door()
	if door != null:
		if WalkSession.active:
			WalkSession.toggle_map_door(door)
		else:
			door.set_open(not door.opened)
		return
	if not talk_actions.visible:
		if intro.entry_aimed():
			intro.toggle_entrance()
			return
		var cleanup := aimed_cleanup()
		if cleanup != null:
			clean(cleanup)
			return
		if is_instance_valid(fridge) and not fridge.aimed_part().is_empty():
			if intro.entry_opened and not intro.note_read:
				intro.read_note()
				return
			fridge.interact()
			return
	for store in home.night_world.retail:
		if store.can_interact():
			store.open()
			return
	if home.shop.can_interact():
		home.shop.open()
		return
	var rider := home.subway.aimed_person()
	if rider != null:
		home.subway.begin_encounter(rider)
		return
	if home.party.events.near_fight():
		close_talk()
		home.party.events.end_fight(true)
		return
	if talk_actions.visible:
		close_talk()
		return
	var station := current_dj()
	if WalkSession.can_control_decks() and station.click_controller():
		return
	if WalkSession.can_control_decks() and (aimed_laptop(station) or (station == club_dj and station.party.near_deck())):
		station.open(true)
		return
	var employee: Node3D = home.club.staff_target()
	if employee != null:
		if employee==home.club.staff[2] and intro.home_soundcheck_done and not intro.samir_confirmed and not home.club.shift.active:
			var scene := preload("res://scripts/samir_booking.gd").new()
			add_child(scene)
			scene.start(self,employee)
			return
		if not home.club.shift.handle_staff(employee):
			home.club.speak(employee)
		return
	var person := aimed_guest()
	if person==null:
		if WalkSession.can_control_decks() and home.party.near_deck():
			dj.open(true)
		return
	if home.party.receiving_party_state():
		say(person, person.introduction(), 4.0)
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

## A settings slider moved (pause menu or main menu): apply it and remember it.
func set_level(key: String, value: float) -> void:
	apply_level(key,value)
	GameSettings.set_level(key,value)

func set_graphics(value: int) -> void:
	VisualQuality.set_level(value)
	VisualQuality.update_shadow_budget(home.player.camera)
	GameSettings.set_graphics(value)

func apply_level(key: String, value: float) -> void:
	match key:
		"music": home.party.music_gain = value
		"steps": home.player.step_audio.volume_db = -16.0+linear_to_db(maxf(.0001,value))
		"mouse": home.player.mouse_sensitivity = .0008+value*.0038
		"master": GameSettings.apply_master(value)

# --- inventory (Tab) --------------------------------------------------------------

## Always in the pocket; shown in the inventory (name, description).
const LIGHTER := ["Зажигалка","Красная одноразовая. Щёлкает со второго раза."]

## What the player carries: [id, name, count, key, description, model].
# --- Tab wheel ----------------------------------------------------------------

## Old inventory panel, opened from the Tab wheel: [id, name, count, key, description, model].
func backpack_items() -> Array:
	var shop := home.shop
	var items := []
	items.append(["beer","Пиво",shop.beer,"",StreetShop.ITEMS[1][4],"beer_bottle"])
	items.append(["energy","Энергетик",shop.energy,"",StreetShop.ITEMS[0][4],"energy_can"])
	items.append(["cigarettes","Сигареты",home.party.cigarettes,"",StreetShop.ITEMS[2][4],"cigarette_pack"])
	items.append(["lighter",LIGHTER[0],1,"",LIGHTER[1],"lighter"])
	return items

func backpack_open() -> bool:
	return is_instance_valid(backpack) and backpack.visible

func toggle_backpack() -> void:
	if backpack_open():
		close_backpack()
	elif not home.modal and not home.player.collapsed and not home.player.vomiting:
		backpack.open(backpack_items(),home.party.cash)
		home.set_modal(true)

func close_backpack() -> void:
	if not backpack_open():
		return
	backpack.close()
	home.set_modal(false)

func use_from_backpack(id: String) -> void:
	close_backpack()
	match id:
		"beer": home.party.take("beer")
		"energy": home.party.take("energy")
		"cigarettes": home.party.consume(false)

## Tab closes the inventory panel (the GUI would otherwise eat Tab as focus-next).
func _input(event: InputEvent) -> void:
	if backpack_open() and event.is_action_pressed("inventory"):
		close_backpack()
		get_viewport().set_input_as_handled()

func radial_content() -> Dictionary:
	var peeing: bool = home.player.pee != null and home.player.pee.forced
	var party_label := "Остановить вечеринку" if home.party.active else "Запустить вечеринку"
	if home.club.shift.nearby():
		party_label = "Начать смену"
	var emotes := []
	for index in StageGestures.GESTURES.size():
		emotes.append({"id": str(index), "label": StageGestures.GESTURES[index], "icon": StageGestures.ICONS[index]})
	return {
		"root": [
			{"id": "inventory", "label": "Инвентарь", "icon": "inventory"},
			{"id": "actions", "label": "Действия", "icon": "actions"},
			{"id": "cancel", "label": "Отменить", "icon": "cancel"},
			{"id": "emotes", "label": "Эмоции", "icon": "emotes"},
		],
		"actions": [
			{"id": "pee", "label": "Перестать" if peeing else "Помочиться", "icon": "pee"},
			{"id": "party", "label": party_label, "icon": "party", "enabled": WalkSession.can_control_decks()},
		],
		"emotes": emotes,
	}

func open_radial() -> void:
	if home.modal or home.player.collapsed or home.player.vomiting or radial.opened or interact_menu.opened:
		return
	if placement.active or crates().any(func(crate): return crate.carried()):
		GameEvents.notify(tr("Сначала поставь коробку."))
		return
	home.set_overlay(true)
	radial.open(radial_content())

func radial_closed() -> void:
	home.set_overlay(false)

func radial_chosen(page: String, id: String) -> void:
	match page:
		"root":
			if id == "inventory":
				toggle_backpack.call_deferred()
		"actions":
			match id:
				"pee": home.player.pee.toggle()
				"party": start_party_action()
		"emotes":
			# The menu closes this frame; start the gesture once input is back.
			gestures.play_gesture.call_deferred(int(id))

## J used to do this: start the club shift near its deck, or the home party.
## The studio laptop leaves the controller node, so each packs and moves alone.
func separate_laptop() -> void:
	var party := home.party
	var model := party.deck.get_node_or_null("StudioLaptop") as Node3D
	var screen := party.deck.get_node_or_null("LaptopScreen") as Node3D
	if model == null or screen == null:
		return
	var holder := Node3D.new()
	holder.name = "StudioLaptopSet"
	party.add_child(holder)
	holder.global_transform = model.global_transform
	model.reparent(holder)
	screen.reparent(holder)
	party.laptop = holder

func start_party_action() -> void:
	if not WalkSession.can_control_decks():
		GameEvents.notify(tr("В этой сессии пультом управляет хост."))
		return
	var shift = home.club.shift
	if shift.nearby():
		if not shift.active:
			if intro.opening_completed and not intro.first_set_done:
				if not intro.samir_confirmed:
					GameEvents.notify(tr("Сначала поговори с Самиром у входа."))
					return
				if not home.club.near_deck():
					GameEvents.notify(tr("Поднимись к пульту на сцене."))
					return
			shift.start()
	else:
		home.party.toggle()

# --- E choice list -------------------------------------------------------------

## E: one action → do it right away; several, or one of these (pick up, pack,
## talk) → the choice list.
const MENU_ACTIONS := ["Поднять", "Упаковать", "Поговорить"]

func open_interaction() -> void:
	if placement.active or radial.opened or interact_menu.opened:
		return
	var choice := interaction_choices()
	if choice.is_empty():
		interact()
		return
	var options: Array = choice[1]
	var always_menu := options.any(func(option): return MENU_ACTIONS.any(func(label): return option[0] == tr(label)))
	if options.size() == 1 and not always_menu:
		(options[0][1] as Callable).call()
		return
	interact_menu.open(choice[0], options)
	home.set_overlay(true)

func crates() -> Array:
	return [speaker_box, deck_crate, laptop_crate].filter(func(crate): return is_instance_valid(crate))

## [title, [[label, Callable], …]] for what the player carries or aims at;
## empty when the plain interact() should handle it.
func interaction_choices() -> Array:
	var delivery := home.night_world.delivery
	for crate in crates():
		if crate.carried():
			return [tr(crate.crate_name), [
				[tr("Установить"), start_box_placement.bind(crate, true)],
				[tr("Поставить"), start_box_placement.bind(crate, false)]]]
	if delivery.held >= 0:
		var choices := [[tr("Поставить"), start_cargo_placement]]
		if delivery.aimed_bed():
			choices.push_front([tr("Погрузить в кузов") if delivery.open else tr("Открыть борт"), delivery.interact])
		return [tr("Сабвуфер"), choices]
	# One-action things in front of the crosshair win over boxes and the DJ set.
	if is_instance_valid(fridge) and fridge.aimed_part() == "shelf" and home.shop.beer > 0 and home.shop.energy > 0 			and not (intro.entry_opened and not intro.note_read):
		return [tr("Холодильник"), [[tr("Положить пиво"), fridge.put.bind("beer")], [tr("Положить энергетик"), fridge.put.bind("energy")]]]
	if aimed_map_door() != null or intro.entry_aimed() or aimed_cleanup() != null 			or (is_instance_valid(fridge) and not fridge.aimed_part().is_empty()):
		return []
	for crate in crates():
		if crate.aimed():
			if crate.deployed():
				return [tr(crate.item_name), [[tr("Упаковать"), crate.pack]]]
			return [tr(crate.crate_name), [[tr("Поднять"), crate.pick_up]]]
	if delivery.aimed_cargo():
		return [tr("Сабвуфер"), [[tr("Поднять"), delivery.interact]]]
	# Home DJ set: the laptop and the controller, each can be used or packed.
	if current_dj() == dj and WalkSession.can_control_decks():
		if is_instance_valid(laptop_crate) and laptop_crate.deployed() and aimed_laptop(dj):
			return [tr("Ноутбук"), [[tr("Взаимодействовать"), dj.open.bind(true)], [tr("Упаковать"), laptop_crate.pack]]]
		if is_instance_valid(deck_crate) and deck_crate.deployed() and home.party.near_deck():
			return [tr("DJ-пульт"), [[tr("Взаимодействовать"), dj.open.bind(false)], [tr("Упаковать"), deck_crate.pack]]]
	# Sellers: the shop first, then a word.
	for store in home.night_world.retail:
		if store.can_interact():
			return [store.title(), [[tr("Магазин"), store.open], [tr("Поговорить"), talk_to_seller.bind(store.cashier)]]]
	if home.shop.can_interact():
		return ["Night Shop", [[tr("Магазин"), home.shop.open], [tr("Поговорить"), talk_to_seller.bind(home.shop.cashier)]]]
	# Guests and club staff: talking goes through the menu too.
	if not talk_actions.visible and hint_kind in ["staff", "guest"]:
		return [hint_name, [[tr("Поговорить"), interact]]]
	return []

const SELLER_LINES := [
	"Ночь длинная — бери энергетик заранее.",
	"Касса работает до утра, не торопись.",
	"Слышал, у тебя сегодня сет? Удачи.",
	"Пиво холодное, только что привезли.",
	"Опять не спится? Понимаю.",
]

func talk_to_seller(seller: Node3D) -> void:
	if is_instance_valid(seller):
		say(seller, tr(SELLER_LINES.pick_random()), 4.0)

## "Установить" / "Поставить": the box leaves the hands and a ghost shows where it goes.
func start_box_placement(crate: SpeakerBox, unpacked: bool) -> void:
	crate.visible = false
	var skip: Array[RID] = [crate.body.get_rid()]
	placement.begin(crate.silhouette(unpacked), crate.footprint(unpacked), skip,
			func(at: Transform3D, surface: Node): crate.place_at(at, unpacked, surface),
			func(): crate.visible = true)

func start_cargo_placement() -> void:
	var delivery := home.night_world.delivery
	var silhouette: Node3D = delivery.held_silhouette()
	delivery.show_held(false)
	var skip: Array[RID] = []
	placement.begin(silhouette, delivery.CARGO_SIZE, skip, delivery.place_held,
			delivery.show_held.bind(true))

func interact_menu_closed() -> void:
	home.set_overlay(false)

## "E · Открыть дверь     C · FLX4" -> "Открыть дверь".
static func hint_title(text: String) -> String:
	var first := text.split("   ")[0].strip_edges()
	var dot := first.find("·")
	return first.substr(dot + 1).strip_edges() if dot >= 0 and dot < 12 else first

func toggle_pause() -> void:
	if talk_actions.visible:
		close_talk()
	pause_panel.visible = not pause_panel.visible
	home.set_modal(pause_panel.visible)

## Routes a gameplay input event to the matching action.
func handle_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var gesture_key := key != null and key.physical_keycode == KEY_G
	var delivery := home.night_world.delivery
	if delivery.is_seated() and not event.is_action_pressed("pause"):
		if not home.modal:
			if event.is_action_pressed("interact"):
				delivery.interact()
			elif event.is_action_pressed("open_mixer"):
				delivery.toggle_camera()
		return
	if gestures.visible:
		if gesture_key or event.is_action_pressed("pause"):
			gestures.close()
		return
	var phone_key := key!=null and key.pressed and not key.echo and key.physical_keycode==KEY_P
	if phone.visible:
		if phone_key or event.is_action_pressed("pause"):
			phone.close()
		return
	if phone_key and not home.modal and not intro.active and not home.player.collapsed and not home.player.vomiting:
		phone.open()
		return
	if home.subway.encounter != null:
		home.subway.encounter_input(event)
		return
	for store in home.night_world.retail:
		if store.panel.visible:
			if event.is_action_pressed("pause"):
				store.close()
			return
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
	if backpack_open():
		if event.is_action_pressed("pause") or event.is_action_pressed("inventory"):
			close_backpack()
		return
	if home.modal or home.player.collapsed or home.player.vomiting:
		return
	if not WalkSession.can_control_decks() and (
			event.is_action_pressed("open_mixer")
			or event.is_action_pressed("beat_mix")
			or TRACK_ACTIONS.any(func(action): return event.is_action_pressed(action))):
		GameEvents.notify(tr("В этой сессии пультом управляет хост."))
		return
	if talk_actions.visible:
		for option in TALK_OPTIONS:
			if event.is_action_pressed(TALK_OPTIONS[option]):
				choose(option)
				return
		if event.is_action_pressed("interact"):
			close_talk()
		return
	if gesture_key and home.party.throw_held():
		return
	if gesture_key and delivery.cargo_action():
		return
	if event.is_action_pressed("inventory"):
		open_radial()
	elif event.is_action_pressed("interact"):
		open_interaction()
	elif is_instance_valid(fridge) and fridge.opened and fridge.aimed() and fridge_stock_input(event):
		return
	elif event.is_action_pressed("delegate_staff"):
		home.club.shift.assign_staff()
	elif event.is_action_pressed("open_mixer"):
		if station.party.near_deck():
			station.open(false)
	elif event.is_action_pressed("extinguish"):
		home.party.extinguish()
	elif event.is_action_pressed("vomit"):
		home.player.vomit()
	elif event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible
	elif event.is_action_pressed("beat_mix"):
		if home.party.near_deck():
			home.party.beat_mix()
	elif event.is_action_pressed("cycle_lights"):
		if not WalkSession.active or (home.party.active and not home.night_world.outside(home.player.global_position)):
			WalkSession.operate_party_lights(key != null and key.shift_pressed)
	else:
		for index in TRACK_ACTIONS.size():
			if event.is_action_pressed(TRACK_ACTIONS[index]):
				if home.party.near_deck():
					home.party.switch_track(index)
				return

func fridge_stock_input(event: InputEvent) -> bool:
	for index in range(1,5):
		if event.is_action_pressed(TALK_OPTIONS[index]):
			fridge.transfer(index)
			return true
	return false
