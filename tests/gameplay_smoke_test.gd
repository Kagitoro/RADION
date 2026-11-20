class_name GameplaySmokeTest
extends RefCounted
## Night-game checks: DJ controller and laptop, house party, club shift,
## Night Shop and the arrival intro. Runs after HomeSmokeTest.

var home: Home
var errors: Array[String]

func _init(target: Home) -> void:
	home = target

func run(collected: Array[String]) -> void:
	errors = collected
	await check_main_menu()
	await check_story_entry()
	await check_dj_station()
	await check_house_party()
	check_traffic_spacing()
	await check_night_shop()
	await check_cigarette()
	await check_music_library()
	await check_club()
	await check_subway()
	await check_intro()
	await check_home_interactions()
	var phone := home.night_game.phone
	home._unhandled_input(key_event(KEY_P))
	expect(phone.visible and home.modal, "Телефон: P не открыл экран")
	for app in ["messages","news","map"]:
		phone.show_page(app)
		expect(phone.body.get_child_count()>0, "Телефон: пустой экран "+app)
	expect(phone.places().size()==8 and phone.places()[7][0]=="Skyline Rooftop", "Телефон: отсутствуют метки карты или Skyline Rooftop")
	home._unhandled_input(key_event(KEY_ESCAPE))
	expect(not phone.visible and not home.modal, "Телефон: Esc не вернул управление")
	check_city_retail()
	await check_localization()
	await check_language_setting()
	check_translation_coverage()
	home.set_modal(false)

func expect(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)

func wait(seconds: float) -> void:
	await home.get_tree().create_timer(seconds).timeout

func stand_near_house_deck() -> void:
	var deck: Vector3 = home.party.deck.global_position
	home.player.velocity = Vector3.ZERO
	home.player.global_position = Vector3(deck.x + .8, deck.y - .9, deck.z)

func check_dj_station() -> void:
	var game := home.night_game
	var dj := game.dj
	var desk: Dictionary = home.records["base-137"]
	var bed: Dictionary = home.records["base-143"]
	var gap := float(bed.z) - float(bed.w) * 0.5 - float(desk.z) - float(desk.d) * 0.5
	expect(gap >= 1.0 and bool(home.records["base-140"].deleted),
			"Студия: проход у кровати или свободная столешница не применились")
	var desk_bounds := home.rooms.room_world_bounds(desk)
	var chair_bounds := home.rooms.room_world_bounds(home.records["base-145"])
	var bed_bounds := home.rooms.room_world_bounds(bed)
	expect(not chair_bounds.intersects(desk_bounds) and bed_bounds.position.y-chair_bounds.end.y >= .40,
			"Студия: кресло перекрывает проход к кровати")
	var lcd := home.party.deck.get_node_or_null("StudioLaptop") as Node3D
	if lcd != null:
		var display := lcd.find_child("Screen", true, false) as MeshInstance3D
		expect(display != null and display.material_override.albedo_texture == dj.laptop_view.get_texture(),
				"Студия: волны не подключены к экрану нового ноутбука")
	else:
		expect(false, "Студия: новый ноутбук не добавлен")
	stand_near_house_deck()
	expect(home.party.near_deck(), "DJ: игрок у пульта не считается рядом с ним")
	expect(game.current_dj() == dj, "DJ: дома выбран не домашний пульт")
	# Laptop (file browser)
	dj.open(true)
	expect(dj.panel.visible and home.modal, "DJ: ноутбук не открывается")
	dj.close()
	expect(not dj.panel.visible and not home.modal, "DJ: ноутбук не закрывается")
	# Controller through the real key path (C), then Esc
	home._unhandled_input(key_event(KEY_C))
	expect(dj.using_controller and home.modal, "DJ: клавиша C не открывает контроллер")
	await wait(.7)
	expect(not dj.transitioning, "DJ: камера не доехала до контроллера")
	expect(dj.control_camera.global_basis.z.dot(dj.face.global_basis.z) > 0.999,
			"DJ: камера смотрит на контроллер не сверху")
	var frame := home.get_viewport().get_visible_rect().grow(-12)
	for x in [-0.5, 0.5]:
		for y in [-0.5, 0.5]:
			var corner := dj.face.to_global(Vector3(x * dj.FACE_SIZE.x, y * dj.FACE_SIZE.y, 0.0))
			expect(frame.has_point(dj.control_camera.unproject_position(corner)),
					"DJ: край контроллера выходит за кадр")
	for control in [dj.transport[0], dj.hardware_dials[0], dj.cross_slider]:
		var motion := InputEventMouseMotion.new()
		var face_size := Vector2(dj.controls_view.size)
		var point: Vector2 = control.get_global_rect().get_center() / face_size - Vector2(0.5, 0.5)
		var world_point := dj.face.to_global(Vector3(point.x * dj.FACE_SIZE.x, -point.y * dj.FACE_SIZE.y, 0))
		motion.position = dj.control_camera.unproject_position(world_point)
		dj._input(motion)
		expect(dj.controller_face.hovered_control == control and dj.controller_face.hover_label.visible,
				"DJ: не подсвечивается элемент под курсором")
	var jog := dj.hardware_dials[0]
	var edge := jog.get_global_rect().get_center() + Vector2(0, jog.size.y * 0.46)
	var uv := edge / Vector2(dj.controls_view.size) - Vector2(0.5, 0.5)
	var raised_point := dj.face.to_global(Vector3(uv.x * dj.FACE_SIZE.x, -uv.y * dj.FACE_SIZE.y,
			dj.controller_face.control_height(jog)))
	var jog_motion := InputEventMouseMotion.new()
	jog_motion.position = dj.control_camera.unproject_position(raised_point)
	dj._input(jog_motion)
	expect(dj.controller_face.hovered_control == jog and dj.controller_face.hover_dashes.size() >= 8,
			"DJ: край 3D-джога не навёлся или не оконтурен")
	var center_uv := jog.get_global_rect().get_center() / Vector2(dj.controls_view.size)
	var rim_radius := dj.controller_face.dial_radius(jog) * 0.99
	for dash in dj.controller_face.hover_dashes:
		var outline_uv := dj.face_pointer(dj.control_camera, dash, dj.controller_face.control_height(jog))
		outline_uv /= Vector2(dj.controls_view.size)
		var radius := ((outline_uv - center_uv) * dj.FACE_SIZE).length()
		expect(radius < rim_radius, "DJ: пунктир выходит за кромку джога")
	var tempo := dj.tempo_faders[1]
	var cap := dj.controller_face.fader_caps[tempo]
	var tempo_motion := InputEventMouseMotion.new()
	tempo_motion.position = dj.control_camera.unproject_position(cap.global_position)
	dj._input(tempo_motion)
	expect(dj.controller_face.hovered_control == tempo, "DJ: крышка правого фейдера не подсвечивается")
	var old_outline := dj.controller_face.hover_dashes.duplicate()
	tempo.value = 0.5
	expect(dj.controller_face.hover_dashes != old_outline, "DJ: пунктир не следует за фейдером")
	tempo.value = 0.0
	for dial in dj.hardware_dials:
		if not dial.get_meta("outline_face_ring", false):
			continue
		var eq_uv := dial.get_global_rect().get_center() / Vector2(dj.controls_view.size)
		var eq_point := (eq_uv - Vector2(0.5, 0.5)) * dj.FACE_SIZE
		var eq_motion := InputEventMouseMotion.new()
		eq_motion.position = dj.control_camera.unproject_position(
				dj.face.to_global(Vector3(eq_point.x, -eq_point.y, dj.controller_face.control_height(dial))))
		dj._input(eq_motion)
		var outline_radius := 0.0
		for dash in dj.controller_face.hover_dashes:
			var on_face := dj.face_pointer(dj.control_camera, dash) / Vector2(dj.controls_view.size)
			outline_radius = maxf(outline_radius, ((on_face - eq_uv) * dj.FACE_SIZE).length())
		expect(dj.controller_face.hovered_control == dial and outline_radius > dj.controller_face.dial_radius(dial),
				"DJ: пунктир EQ должен охватывать внешний круг ручки")
	dj.toggle_echo()
	dj.cycle_beat_fx()
	expect(AudioServer.is_bus_effect_enabled(dj.party.music_bus, dj.reverb_slot)
			and not AudioServer.is_bus_effect_enabled(dj.party.music_bus, dj.echo_slot), "DJ: FX SELECT не включает Reverb")
	dj.toggle_echo()
	dj.cycle_beat_fx()
	dj._input(key_event(KEY_ESCAPE))
	await wait(.6)
	expect(not dj.using_controller and not home.modal, "DJ: Esc не уводит от контроллера")
	expect(not dj.controller_face.hover_label.visible, "DJ: подсказка осталась после выхода")
	expect(home.get_viewport().get_camera_3d() == home.player.camera, "DJ: после выхода не вернулась камера игрока")

func check_house_party() -> void:
	var party := home.party
	var dj := home.night_game.dj
	stand_near_house_deck()
	party.toggle()
	expect(party.starting, "Вечеринка: J у пульта не запускает подготовку")
	party.start()
	expect(party.active, "Вечеринка: не стартует")
	var gestures := home.night_game.gestures
	home._unhandled_input(key_event(KEY_G))
	expect(gestures.visible and home.modal, "Жесты: G не открыла кольцо")
	await wait(0.5)
	expect(dj.has_playback(), "Жесты: музыка остановилась при открытии кольца")
	var fill := home.scene_lighting.get_node("Studio_Fill") as Light3D
	expect(fill.light_energy > party.house_light_energy[fill], "Вечеринка: не усилился мягкий свет спальни")
	for light_name in ["Studio_CloudSpot", "Living_ChandelierSpot", "Kitchen_CeilingSpot",
			"Bath_CeilingSpot", "Hall_CeilingSpot"]:
		var spot := home.scene_lighting.get_node(light_name) as SpotLight3D
		expect(spot.light_energy < party.house_light_energy[spot],
				"Вечеринка: не приглушён потолочный свет %s" % light_name)
	var select := InputEventMouseButton.new()
	select.button_index = MOUSE_BUTTON_LEFT
	select.pressed = true
	select.position = gestures.size * 0.5 + Vector2.UP * gestures.radius() * 0.65
	gestures._gui_input(select)
	expect(not gestures.visible and not home.modal and gestures.gesture == 0,
			"Жесты: выбор не запустил поднятие руки")
	await wait(0.95)
	var player := home.player
	var arm := player.dj_rig.arms[player.drink_arm]
	var skeleton := player.dj_rig.skeleton
	expect(skeleton.get_bone_global_pose(arm.z).origin.y > skeleton.get_bone_global_pose(arm.x).origin.y,
			"Жесты: кисть не поднялась выше плеча")
	for choice in range(4):
		gestures.play_gesture(choice)
		await wait(0.90)
		var visible_area := home.get_viewport().get_visible_rect().grow(-20)
		for index in ([0, 1] if choice == 2 else [player.drink_arm]):
			var wrist := skeleton.to_global(skeleton.get_bone_global_pose(player.dj_rig.arms[index].z).origin)
			expect(not player.camera.is_position_behind(wrist)
					and visible_area.has_point(player.camera.unproject_position(wrist)),
					"Жесты: кисть вне кадра для жеста %d" % choice)
	gestures.gesture = -1
	for entry in party.events.environments:
		expect(entry.node.ambient_light_energy >= 0.55,
				"Вечеринка: окружающий свет слишком низкий")
	expect(fill.light_energy >= 1.72, "Вечеринка: яркость света спальни упала после перехода")
	expect(party.events.lights[0].light_energy >= 0.65 and party.events.beams[0].visible,
			"Вечеринка: цветной свет погас между ударами")
	party.switch_track(1)
	await wait(.8)
	expect(party.track == 1 and party.music[party.playing].playing, "Вечеринка: трек 2 не играет")
	# Taking over the decks manually
	dj.engage()
	expect(dj.manual and not dj.titles[party.playing].is_empty(), "DJ: ручной режим не подхватил текущий трек")
	dj.toggle_deck(party.playing)
	expect(not dj.has_playback(), "DJ: пауза деки не останавливает звук")
	dj.toggle_deck(party.playing)
	expect(dj.has_playback(), "DJ: повторное нажатие не возобновляет деку")
	dj.seek(party.playing, 10.0)
	expect(dj.deck_position(party.playing) >= 9.0, "DJ: перемотка не работает")
	party.switch_track(2)
	expect(not dj.manual and party.track == 2, "Вечеринка: клавиша трека не возвращает встроенный плейлист")
	await wait(4.0)
	expect(not party.guests.is_empty(), "Вечеринка: гости не приходят")
	expect(party.panel.visible and not party.status.text.is_empty(), "Вечеринка: панель статуса пуста")
	var guest := party.guests[0]
	var grid := party.navigation_grid
	var second := PartyGuest.new(21,null,party.psx_assets)
	party.crowd.add_child(second)
	party.guests.append(second)
	second.position = grid.cells[grid.entrance]
	party.invite_to_dance(guest)
	party.invite_to_dance(second)
	expect(not guest.route.is_empty() and not second.route.is_empty() and guest.route[-1].distance_to(second.route[-1])>=PartyNavigation.DANCE_SPACING, "Вечеринка: гости бронируют одно место для танца")
	await check_fight(guest,second)
	party.stop()
	expect(not party.active and is_instance_valid(guest) and party.guests.has(guest), "Вечеринка: гость пропал в момент остановки")
	await wait(.7)
	expect(guest.leaving and guest.route.size()>0, "Вечеринка: гость не получил маршрут на выход")
	expect(not party.music.any(func(p: AudioStreamPlayer): return p.playing), "Вечеринка: музыка играет после остановки")

func check_fight(first: PartyGuest, second: PartyGuest) -> void:
	var party := home.party
	var grid := party.navigation_grid
	var events := party.events
	var placed := false
	for cell in grid.dance_floor:
		var neighbor := cell + Vector2i(ceili(PartyNavigation.DANCE_SPACING/PartyNavigation.CELL),0)
		if grid.dance_floor.has(neighbor):
			first.position = grid.cells[cell]
			second.position = grid.cells[neighbor]
			placed = true
			break
	expect(placed and events.start_fight(first), "Драка: провокация не запустила драку")
	if events.fighters.is_empty():
		return
	var start := first.position
	await wait(4.5)
	expect(events.hit_index>=4 and not events.hit_counts.is_empty(), "Драка: нет нескольких атак и попаданий")
	expect(first.position.distance_to(start)>.04, "Драка: NPC стоят на одном месте")
	events.end_fight(true)
	expect(events.fighters.is_empty() and not first.fighting and not second.fighting, "Драка: вмешательство не прекращает бой")

func check_night_shop() -> void:
	var shop := home.shop
	home.player.velocity = Vector3.ZERO
	home.player.global_position = shop.to_global(Vector3(0, 0, 2))
	expect(shop.can_interact(), "Магазин: у прилавка нельзя взаимодействовать")
	home.party.cash = 100
	var beer := shop.beer
	shop.open()
	expect(shop.is_open() and home.modal, "Магазин: не открывается")
	var item_buttons: Node = shop.panel.get_node("%Items")
	expect(item_buttons.get_child_count() == StreetShop.ITEMS.size(), "Магазин: кнопки товаров не построены")
	(item_buttons.get_child(1) as Button).pressed.emit()
	expect(shop.panel.selected == 1, "Магазин: карточка товара не выбирается")
	(shop.panel.get_node("%BuyButton") as Button).pressed.emit()
	expect(shop.beer == beer + 1 and home.party.cash == 95, "Магазин: покупка пива не работает")
	shop.panel.change_quantity(1)
	(shop.panel.get_node("%BuyButton") as Button).pressed.emit()
	expect(shop.beer == beer + 3 and home.party.cash == 85, "Магазин: покупка нескольких штук не работает")
	shop.buy(0)
	shop.close()
	expect(not shop.is_open() and not home.modal, "Магазин: не закрывается")
	home.player.energy_boost = 0.0
	home.party.extinguish()
	await wait_until(func(): return not home.party.hands_busy(), 4.0)
	shop.drink_energy()
	expect(home.party.hands_busy(), "Энергетик: нет анимации в руках")
	await wait_until(func(): return home.player.energy_boost > 0.0, 5.0)
	expect(home.player.energy_boost > 0.0, "Магазин: энергетик не действует")
	await wait_until(func(): return not home.party.hands_busy(), 5.0)
	expect(FileAccess.file_exists(StreetShop.SAVE), "Магазин: покупки не сохраняются")
	var before := shop.beer
	home.party.consume(true)
	expect(shop.beer == before - 1, "Пиво: B не тратит бутылку")
	await wait(4.0)

func check_cigarette() -> void:
	var party := home.party
	var smokes := party.consumables
	await wait_until(func(): return not is_instance_valid(smokes.hand_prop), 6.0)
	party.cigarettes = 3
	party.consume(false)
	# The cigarette reaches the lips at the end of the hand animation (~1 s).
	await wait_until(func(): return is_instance_valid(smokes.lip_cigarette), 3.0)
	expect(party.cigarettes == 2 and is_instance_valid(smokes.lip_cigarette), "Сигарета: N не зажигает сигарету")
	await wait_until(func(): return not is_instance_valid(smokes.hand_prop), 6.0)
	party.extinguish()
	# K takes the cigarette from the lips and flicks it away (~1 s).
	await wait_until(func(): return not is_instance_valid(smokes.lip_view), 3.0)
	expect(not is_instance_valid(smokes.lip_cigarette) and not is_instance_valid(smokes.lip_view), "Сигарета: K не тушит сигарету")
	await wait_until(func(): return not is_instance_valid(smokes.hand_prop), 3.0)
	await wait(.2)

func check_music_library() -> void:
	var dj := home.night_game.dj
	var library := dj.music_library
	var folder := SavePaths.file("music")
	DirAccess.make_dir_recursive_absolute(folder)
	var clip := AudioStreamWAV.new()
	clip.format = AudioStreamWAV.FORMAT_16_BITS
	clip.mix_rate = 22050
	var silence := PackedByteArray()
	silence.resize(22050 * 2 * 12)
	clip.data = silence
	clip.save_to_wav(ProjectSettings.globalize_path(folder.path_join("test_track.wav")))
	library.folder = ProjectSettings.globalize_path(folder)
	library.scan_folder()
	await wait_until(func(): return not library.scanning, 3.0)
	expect(library.listing.item_count == 1, "Ноутбук: трек в папке не найден")
	if library.listing.item_count == 1:
		library.listing.select(0)
		library.load_selection(1, false)
		expect(dj.titles[1] == "test_track", "Ноутбук: трек не загрузился в деку B")
	dj.use_builtin()

## Waits until condition() is true or the timeout runs out.
func wait_until(condition: Callable, timeout: float) -> void:
	var left := timeout
	while left > 0.0 and not condition.call():
		await home.get_tree().process_frame
		left -= home.get_process_delta_time()

func check_club() -> void:
	var club := home.club
	var shift := club.shift
	home.player.velocity = Vector3.ZERO
	home.player.global_position = club.to_global(Vector3.ZERO)
	expect(shift.nearby(), "Клуб: игрок внутри не считается в клубе")
	expect(home.night_game.current_dj() == home.night_game.club_dj or not club.near_deck(), "Клуб: выбран не тот пульт")
	shift.start()
	expect(shift.active, "Клуб: смена не начинается")
	await wait(1.0)
	expect(shift.active and shift.time > 0.0, "Клуб: смена не идёт")
	expect(shift.panel.visible and not shift.summary.text.is_empty(), "Клуб: панель смены не показывается")
	var club_dj := home.night_game.club_dj
	club_dj.open(true)
	expect(club_dj.panel.visible, "Клуб: ноутбук клубного пульта не открывается")
	club_dj.close()
	shift.active = false

func check_main_menu() -> void:
	var menu := home.night_game.menu
	var intro := home.night_game.intro
	menu.show_menu()
	expect(menu.opened and menu.layer.visible and home.modal, "Меню: не открывается")
	var expected := home.tr("Продолжить") if intro.opening_completed else home.tr("Начать игру")
	expect(menu.screen.continue_button.text == expected, "Меню: неверная подпись главной кнопки")
	menu.screen.continue_button.pressed.emit()
	expect(not menu.opened and not menu.layer.visible, "Меню: кнопка не закрывает меню")
	if intro.active:
		await wait(.2)
		intro.finish()
	expect(not home.modal, "Меню: после выхода игра осталась заблокированной")

## Puts the player on the platform facing a rider, so aimed_person() picks them.
func face_rider(rider: PartyGuest) -> void:
	var subway := home.subway
	var head := rider.global_position + Vector3.UP * 1.43 * rider.body_height
	var eye := subway.to_global(rider.position + Vector3(0, 1.55, 1.4))
	home.player.velocity = Vector3.ZERO
	home.player.move_to(eye, head)
	home.player.camera.force_update_transform()

func check_subway() -> void:
	var subway := home.subway
	expect(subway.people.size() == 3, "Метро: на платформе нет пассажиров")
	expect(not subway.underground(home.club.to_global(Vector3.ZERO)), "Метро: клуб считается подземкой")
	var first := subway.people[0]
	face_rider(first)
	await home.get_tree().physics_frame
	expect(subway.underground(home.player.global_position), "Метро: платформа не считается подземкой")
	expect(subway.aimed_person() == first, "Метро: пассажир перед игроком не в прицеле")
	home.party.cash = 10
	subway.give(first)
	expect(home.party.cash == 10 - Balance.SUBWAY_DONATION and subway.helped.has(first), "Метро: помощь не списывает деньги")
	subway.give(first)
	expect(home.party.cash == 10 - Balance.SUBWAY_DONATION, "Метро: повторная помощь списывает деньги ещё раз")
	var second := subway.people[1]
	home.party.cash = 0
	subway.give(second)
	expect(home.party.cash == 0 and not subway.helped.has(second), "Метро: без денег помощь всё равно засчитана")
	# Real input path: E while looking at the third rider.
	var third := subway.people[2]
	face_rider(third)
	await home.get_tree().physics_frame
	home.party.cash = 5
	home._unhandled_input(key_event(KEY_E))
	expect(subway.encounter == third and home.modal, "Метро: E не открывает разговор с блокировкой движения")
	expect(subway.encounter_choices.text.contains("$%d" % Balance.SUBWAY_DONATION), "Метро: в выборе нет цены")
	home.player.rotation.y += .65
	await wait(.6)
	var gaze := home.player.camera.global_position.direction_to(subway.face_point(third))
	expect(gaze.dot(-home.player.camera.global_basis.z)>.97, "Метро: камера не навелась на собеседника")
	home._unhandled_input(key_event(KEY_1))
	expect(subway.helped.has(third) and home.party.cash == 5 - Balance.SUBWAY_DONATION, "Метро: клавиша 1 не помогает пассажиру")
	await wait(1.95)
	expect(subway.encounter == null and not home.modal, "Метро: камера не отпускает после разговора")
	face_rider(second)
	await home.get_tree().physics_frame
	home._unhandled_input(key_event(KEY_E))
	home._unhandled_input(key_event(KEY_2))
	expect(subway.reacting and not subway.helped.has(second), "Метро: отказ засчитан как помощь")
	await wait(1.95)
	# The train moves while the player is downstairs.
	subway.clock = 0.0
	var start_x := subway.train.position.x
	await wait(1.0)
	expect(not is_equal_approx(subway.train.position.x, start_x), "Метро: поезд не движется")
	home.player.global_position = home.club.to_global(Vector3.ZERO)
	await home.get_tree().physics_frame

func check_intro() -> void:
	var intro := home.night_game.intro
	intro.start(true)
	expect(intro.active and home.modal, "Интро: не запускается")
	await wait(.3)
	expect(intro.layer.visible, "Интро: оверлей не показывается")
	expect(intro.dialogue.size() == intro.LINES.size()-1, "Интро: отсутствуют звуковые дорожки")
	expect(intro.arrival_car.visible and not intro.cabin.visible, "Интро: нет внешнего кадра на трассе")
	var car_start := intro.cabin.position.z
	await wait(.24)
	expect(intro.cabin.position.z-car_start>2.0, "Интро: машина не едет по трассе")
	intro.elapsed = intro.WAKE_CALL-.08
	await wait(.24)
	expect(intro.fade.color.a>.95 and intro.wake_voice.playing, "Интро: Кир не слышен сквозь сон")
	intro.wake_voice.stop()
	intro.elapsed = intro.voice_lead
	await wait(.18)
	expect(intro.cabin.visible and intro.fade.color.a<.05 and intro.voice.playing, "Интро: герой не проснулся")
	intro.advance_line()
	await wait(.35)
	expect(intro.voice.playing and intro.cabin.position.z > car_start, "Интро: реплика или движение машины не начались")
	while intro.line<intro.PHONE_LINE:
		intro.advance_line()
	await wait(1.28)
	expect(intro.cabin.phone.visible and intro.cabin.phone_amount>.8 and intro.ringtone.playing and intro.cabin.phone_ui.page==intro.PhoneUI.Page.CALL, "Интро: входящий звонок не появился")
	for step in range(intro.PHONE_TAPS.size()):
		intro.elapsed = intro.PHONE_TAPS[step][0]-.04
		await wait(.20)
		expect(intro.cabin.phone_ui.page==intro.PHONE_TAPS[step][2], "Интро: не переключился экран телефона")
		expect(intro.cabin.tap_hand.visible, "Интро: не появилась рука для нажатия пальцем")
	await wait(.10)
	expect(intro.voice.playing, "Интро: голосовое не началось после нажатия на запись")
	intro.advance_line()
	await wait(.25)
	expect(intro.line == intro.PHONE_LINE+1, "Интро: реплики не переключаются")
	expect(not intro.subtitle.text.is_empty() and not intro.speaker.text.is_empty(), "Интро: субтитры не показываются")
	while intro.line<intro.EXIT_LINE:
		intro.advance_line()
	expect(intro.LINES[intro.EXIT_LINE-1][0]==1 and intro.LINES[intro.EXIT_LINE+1][4]=="acted_door", "Интро: выход должен быть перед первым разговором снаружи")
	intro.elapsed = 2.24
	await wait(.16)
	expect(intro.cabin.doors[0].rotation.y>1.0 and intro.cabin.visible, "Интро: пассажирская дверь не открылась")
	intro.elapsed = 6.17
	await wait(.16)
	expect(intro.cabin.doors[0].rotation.y<.03 and intro.friend.visible, "Интро: выход из машины не завершился")
	var space := home.get_world_3d().direct_space_state
	var route := [3.47,5.82,7.46]
	for index in range(route.size()-1):
		for height in [-1.2,-.55,0.0]:
			var offset := Vector3.UP*float(height)
			var from := intro.cabin.to_global(intro.exit_eye(route[index]))+offset
			var to := intro.cabin.to_global(intro.exit_eye(route[index+1]))+offset
			var ray := PhysicsRayQueryParameters3D.create(from,to,1,[home.player.get_rid()])
			expect(space.intersect_ray(ray).is_empty(), "Интро: на пути от машины до Кира есть препятствие")
	while intro.line<intro.KEY_LINE:
		intro.advance_line()
	await wait(1.0)
	var kir := intro.friend.imported_model as GuestModel
	var wrist := kir.skeleton.get_bone_global_pose(kir.arms[0].z).origin
	expect(intro.key_prop.visible and intro.key_prop.global_position.distance_to(kir.skeleton.to_global(wrist))<.16, "Интро: ключ не держится у пальцев Кира")
	intro.finish()
	await wait(.2)
	expect(not intro.active and not home.modal, "Интро: не завершается")
	expect(home.hud.root.visible, "Интро: после завершения скрыт HUD")

func check_story_entry() -> void:
	var intro := home.night_game.intro
	var fridge := home.night_game.fridge
	expect(intro.opening_completed and not intro.entry_opened, "История: после приезда дверь должна быть закрыта")
	home._unhandled_input(key_event(KEY_E))
	await wait(.95)
	expect(intro.entry_opened and not intro.entrance_shape.disabled and intro.entrance_leaf.rotation.y>1.3, "История: ключ не открывает дверь")
	home.player.move_to(fridge.to_global(Vector3(.22,1.64,-1.23)),fridge.to_global(Vector3(0,1.15,-.43)))
	await home.get_tree().physics_frame
	home._unhandled_input(key_event(KEY_E))
	expect(intro.note_read and not fridge.opened and intro.follow_up.visible, "История: записка не запускает уборку")
	var saved := ConfigFile.new()
	expect(saved.load(intro.SAVE)==OK and saved.get_value("story","note_read",false), "История: прочитанная записка не сохранилась")

func check_city_retail() -> void:
	var market = home.night_world.retail[0]
	var gear = home.night_world.retail[1]
	var cash := home.party.cash
	home.party.cash = 500
	for store in [market,gear]:
		home.player.global_position = store.to_global(store.counter+Vector3(0,.08,1.0))
		expect(store.can_interact(), "Магазин: касса недоступна")
		home._unhandled_input(key_event(KEY_E))
		expect(store.panel.visible, "Магазин: E не открывает каталог")
		store.buy()
		home._unhandled_input(key_event(KEY_ESCAPE))
		expect(not store.panel.visible, "Магазин: Esc не закрывает каталог")
	home.shop.load_stock()
	expect(home.shop.food_stock.get("Яблоки",0)==1 and gear.owns(0) and home.party.cash==378, "Магазин: покупки не сохранились")
	home.party.cash = cash
	home.shop.food_stock.clear()
	home.shop.owned_controllers = 0
	home.shop.save_stock()

func check_localization() -> void:
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	expect(home.tr("Проект сохранён.") == "Project saved.", "Перевод: английский не подключён")
	expect(home.tr("Я %s. Мой родной город — %s (%s).") % ["A", "B", "C"] == "I'm A. My home town is B (C).", "Перевод: фраза с параметрами переведена неверно")
	await home.get_tree().process_frame
	var resume: Button = home.night_game.pause_panel.get_node("%ResumeButton")
	expect(resume.get_minimum_size().x > 0.0 and resume.tr(resume.text) == "Continue", "Перевод: кнопки сцены паузы не переводятся")
	TranslationServer.set_locale("ru")
	expect(home.tr("Проект сохранён.") == "Проект сохранён.", "Перевод: русский текст не возвращается")
	TranslationServer.set_locale("uk")
	expect(home.tr("Проект сохранён.") == "Проект сохранён.", "Перевод: при украинской системе должен остаться оригинал")
	TranslationServer.set_locale(previous)

func check_home_interactions() -> void:
	var game := home.night_game
	var fridge := game.fridge
	var shop := home.shop
	var player := home.player
	player.move_to(fridge.to_global(Vector3(.22,1.64,-1.23)),fridge.to_global(Vector3(0,1.15,-.43)))
	await home.get_tree().physics_frame
	expect(fridge.aimed() and shop.fridge_beer == 3, "Холодильник: нет доступа или стартовых бутылок")
	home._unhandled_input(key_event(KEY_E))
	expect(fridge.opened, "Холодильник: E не открывает дверцу")
	var carried := shop.beer
	home._unhandled_input(key_event(KEY_1))
	expect(shop.fridge_beer == 2 and shop.beer == carried+1, "Холодильник: не удалось взять бутылку")
	home._unhandled_input(key_event(KEY_2))
	expect(shop.fridge_beer == 3 and shop.beer == carried, "Холодильник: не удалось вернуть бутылку")
	shop.beer += 6
	home._unhandled_input(key_event(KEY_3))
	shop.load_stock()
	expect(shop.fridge_beer == 9 and shop.beer == carried, "Холодильник: упаковка не сохранилась")
	home._unhandled_input(key_event(KEY_4))
	expect(shop.fridge_beer == 3 and shop.beer == carried+6, "Холодильник: не удалось забрать упаковку")
	home._unhandled_input(key_event(KEY_E))
	expect(not fridge.opened, "Холодильник: E не закрывает дверцу")
	var cash := home.party.cash
	for item in game.litter.values():
		var point: Vector3 = item.global_position
		var reachable := false
		for direction in [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT]:
			player.move_to(point+Vector3.UP*1.64+direction*.65,point+Vector3(.20,.28,0))
			await home.get_tree().physics_frame
			if game.aimed_cleanup() == item:
				home._unhandled_input(key_event(KEY_E))
				reachable = true
				break
		expect(reachable, "Уборка: не подбирается мусор возле метки %s" % point)
	expect(game.litter.is_empty() and home.party.cash == cash+game.CLEANUP_REWARD, "Уборка: квест или награда не засчитаны")
	expect(not game.intro.cash_envelope.visible, "История: конверт остался после начисления награды")
	var intro := game.intro
	expect(not intro.home_soundcheck_done and not intro.samir_confirmed, "История: приглашение пришло до проверки трека")
	intro.confirm_booking()
	expect(not intro.samir_confirmed, "История: Самир пропустил проверку трека")
	var deck := home.party.deck.global_position
	player.global_position = deck+Vector3(0,-.9,1.0)
	game.dj.engage()
	game.dj.crossfade = -1.0
	game.dj.gains[game.dj.routing[0]] = 1.0
	home.party.music_gain = .85
	home.party.music[0].stream = AudioStreamGenerator.new()
	home.party.music[0].stream_paused = false
	home.party.music[0].play()
	intro.update_soundcheck(3.1)
	expect(intro.home_soundcheck_done and intro.follow_up.visible, "История: домашний трек не открыл приглашение")
	home.club.speak(home.club.staff[2])
	expect(intro.samir_confirmed, "История: Самир не подтвердил слот")
	var booking_cash := home.party.cash
	intro.first_booking_complete()
	intro.first_booking_complete()
	shop.load_stock()
	expect(home.party.cash==booking_cash+40, "История: оплата сета не сохранилась или выдана дважды")
	home.party.music[0].stop()
	expect(game.intro.first_set_done and game.intro.follow_up_line == 1, "История: после первого сета нет разговора с Киром")

## Picks English in the pause menu, checks it is applied live and saved, then restores.
func check_language_setting() -> void:
	var languages: OptionButton = home.night_game.pause_panel.get_node("%LanguageOption")
	expect(languages.item_count == GameSettings.LANGUAGES.size(), "Язык: в настройках нет списка языков")
	var english := -1
	for index in languages.item_count:
		if languages.get_item_metadata(index) == "en":
			english = index
	languages.select(english)
	languages.item_selected.emit(english)
	await home.get_tree().process_frame
	expect(TranslationServer.get_locale() == "en", "Язык: выбор English не переключает язык")
	expect(GameSettings.language() == "en", "Язык: выбор не сохраняется")
	# A label built in code earlier (in Russian) must follow the switch without a restart.
	var folder_button: Button = home.night_game.dj.panel.get_node("%Toolbar").get_child(0)
	expect(folder_button.atr(folder_button.text) == "Choose folder", "Язык: интерфейс не переводится на лету")
	var guest: PartyGuest = home.club.dancers[0]
	expect(guest.introduction().begins_with("I'm "), "Язык: реплики гостей не переводятся на лету")
	GameSettings.set_language("ru")
	expect(folder_button.atr(folder_button.text) == "Выбрать папку", "Язык: русский не возвращается")

## Every string in the translation template must have an English translation.
func check_translation_coverage() -> void:
	var english := load("res://locale/en.po") as Translation
	var translated := {}
	for message in english.get_message_list():
		translated[message] = true
	var template := FileAccess.get_file_as_string("res://locale/messages.pot")
	var missing := 0
	for raw_line in template.split("\n"):
		var line := raw_line.trim_suffix("\r")
		if line.begins_with("msgid \"") and line.length() > 8:
			var message := line.substr(7, line.length() - 8).c_unescape()
			if not translated.has(message):
				missing += 1
	expect(missing == 0, "Перевод: %d строк без английского перевода (обновите locale/en.po)" % missing)

func check_traffic_spacing() -> void:
	var district := home.night_world.district
	var traffic := district.traffic
	for index in range(traffic.size()):
		traffic[index].distance = [40.0,29.0,15.0][index]
		traffic[index].speed = 0.0
		traffic[index].car.position = district.traffic_point(traffic[index].distance)
	var crossing := district.traffic_point(43.0)
	for frame in range(360):
		district.step_traffic(1.0/60.0,crossing)
	expect(absf(traffic[0].distance-40.0)<.08, "Трафик: машина не остановилась перед игроком")
	expect(traffic[0].distance-traffic[1].distance>=NightDistrict.TRAFFIC_GAP-.02, "Трафик: машина наехала на остановившуюся впереди")
	var nearest := INF
	for frame in range(360):
		district.step_traffic(1.0/60.0,Vector3.UP*100)
		for a in range(traffic.size()):
			for b in range(a+1,traffic.size()):
				nearest = minf(nearest,traffic[a].car.position.distance_to(traffic[b].car.position))
	expect(traffic[0].distance>45.0 and nearest>=4.8, "Трафик: очередь не разъехалась или машины наложились на повороте")

func key_event(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event
