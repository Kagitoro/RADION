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
	await check_dj_station()
	await check_house_party()
	await check_night_shop()
	await check_cigarette()
	await check_music_library()
	await check_club()
	await check_subway()
	await check_main_menu()
	await check_intro()
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
	dj._input(key_event(KEY_ESCAPE))
	await wait(.6)
	expect(not dj.using_controller and not home.modal, "DJ: Esc не уводит от контроллера")
	expect(home.get_viewport().get_camera_3d() == home.player.camera, "DJ: после выхода не вернулась камера игрока")

func check_house_party() -> void:
	var party := home.party
	var dj := home.night_game.dj
	stand_near_house_deck()
	party.toggle()
	expect(party.starting, "Вечеринка: J у пульта не запускает подготовку")
	party.start()
	expect(party.active, "Вечеринка: не стартует")
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
	party.stop()
	expect(not party.active and party.guests.is_empty(), "Вечеринка: остановка не убирает гостей")
	expect(not party.music.any(func(p: AudioStreamPlayer): return p.playing), "Вечеринка: музыка играет после остановки")

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
	expect(shop.beer == beer + 1 and home.party.cash == 95, "Магазин: покупка пива не работает")
	shop.buy(0)
	shop.close()
	expect(not shop.is_open() and not home.modal, "Магазин: не закрывается")
	home.player.energy_boost = 0.0
	shop.drink_energy()
	expect(home.player.energy_boost > 0.0, "Магазин: энергетик не действует")
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
	expect(not is_instance_valid(smokes.lip_cigarette), "Сигарета: K не тушит сигарету")
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
	expect(subway.hint_for(first).contains("$%d" % Balance.SUBWAY_DONATION), "Метро: в подсказке нет цены")
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
	expect(subway.helped.has(third), "Метро: клавиша E не помогает пассажиру")
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
	for step in 3:
		intro.advance_line()
		await wait(.15)
	expect(intro.line == 3, "Интро: реплики не переключаются")
	expect(not intro.subtitle.text.is_empty() and not intro.speaker.text.is_empty(), "Интро: субтитры не показываются")
	intro.finish()
	await wait(.2)
	expect(not intro.active and not home.modal, "Интро: не завершается")
	expect(home.hud.root.visible, "Интро: после завершения скрыт HUD")

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

func key_event(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event
