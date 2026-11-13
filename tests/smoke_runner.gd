class_name SmokeRunner
extends RefCounted
## Runs every headless test suite and reports one summary line.
##   godot --headless --path . -- --smoke         (exit code 0 = all passed)
##   godot --path . -- --visual-smoke              (screenshots into user://smoke_test/)

var home: Home

func _init(target: Home) -> void:
	home = target

# State carried across the "Start over" scene reload (the old Home and this runner are freed).
static var restart_pending := false
static var carried_errors: Array[String] = []
static var collector: ErrorCollector
static var old_home_id := 0

func run() -> void:
	if restart_pending:
		await finish_restart_check()
		return
	SavePaths.clear_test_files()
	# Source language, so checks do not depend on the machine locale.
	TranslationServer.set_locale("ru")
	collector = ErrorCollector.new()
	OS.add_logger(collector)
	var errors: Array[String] = []
	await HomeSmokeTest.new(home).run(errors)
	await GameplaySmokeTest.new(home).run(errors)
	await start_restart_check(errors)

## Last check: press "Start over" in the pause menu. The scene reloads, a new
## Home starts a new runner, and finish_restart_check() verifies the fresh game.
func start_restart_check(errors: Array[String]) -> void:
	home.night_game.intro.opening_completed = true
	home.night_game.intro.save_story()
	home.shop.save_stock()
	ConfigFile.new().save(MainMenu.CHECKPOINT)
	GameSettings.set_language("ru")
	home.storage.save_project()
	for path in GameReset.progress_files():
		if not FileAccess.file_exists(path):
			errors.append("Рестарт: тест не смог создать файл прогресса " + path.get_file())
	carried_errors = errors
	old_home_id = home.get_instance_id()
	restart_pending = true
	var game := home.night_game
	game.toggle_pause()
	game.pause_panel.get_node("%RestartButton").pressed.emit()
	var confirm: ConfirmationDialog = game.pause_panel.get_node("%RestartConfirm")
	if not confirm.visible:
		errors.append("Рестарт: нет окна подтверждения")
	confirm.confirmed.emit()

func finish_restart_check() -> void:
	restart_pending = false
	var errors := carried_errors
	await home.get_tree().process_frame
	if home.get_instance_id() == old_home_id or home.get_tree().current_scene != home:
		errors.append("Рестарт: сцена не пересоздана")
	for path in GameReset.progress_files():
		if FileAccess.file_exists(path):
			errors.append("Рестарт: не удалён файл прогресса " + path.get_file())
	if not FileAccess.file_exists(GameSettings.FILE) or not FileAccess.file_exists(ProjectStorage.SAVE_PATH):
		errors.append("Рестарт: удалены настройки или расстановка дома")
	if home.night_game.intro.opening_completed or home.modal:
		errors.append("Рестарт: игра не начинается с начала")
	if home.party.cash != Balance.START_CASH:
		errors.append("Рестарт: деньги не сброшены")
	# The rebuilt game must still work: open and close the laptop.
	home.night_game.dj.open(true)
	if not home.night_game.dj.panel.visible:
		errors.append("Рестарт: после перезапуска не работает пульт")
	home.night_game.dj.close()
	OS.remove_logger(collector)
	for problem in collector.take():
		errors.append("Ошибка движка: " + problem)
	print("RADION_SMOKE objects=%d inventory=%d catalog=%d errors=%s" % [home.originals.size(), home.inventory.size(), home.catalog.size(), str(errors)])
	home.quit_game(0 if errors.is_empty() else 1)

func run_visual() -> void:
	SavePaths.clear_test_files()
	TranslationServer.set_locale("ru")
	var game := home.night_game
	game.menu.show_menu()
	await snap("menu")
	game.menu.screen.show_settings(true)
	await snap("menu-settings")
	game.menu.screen.show_settings(false)
	game.menu.screen.continue_pressed.emit()
	if game.intro.active:
		await home.get_tree().create_timer(1.2).timeout
		game.intro.advance_line()
		await snap("intro")
		game.intro.finish()
	game.toggle_pause()
	await snap("pause")
	game.pause_panel.get_node("%RestartConfirm").popup_centered()
	await snap("restart-confirm")
	game.pause_panel.get_node("%RestartConfirm").hide()
	GameSettings.set_language("en")
	await snap("pause-en")
	GameSettings.set_language("ru")
	game.toggle_pause()
	home.shop.beer = 3
	home.shop.energy = 1
	home.party.cigarettes = 4
	game.toggle_backpack()
	await snap("inventory")
	game.close_backpack()
	GameEvents.notify(tr("Энергетик · бег быстрее на 45 с"))
	await snap("hud")
	var shop := home.shop
	home.player.global_position = shop.to_global(Vector3(0, 0, 2))
	shop.open()
	await snap("shop")
	shop.close()
	game.dj.open(true)
	await snap("laptop")
	game.dj.close()
	await home.get_tree().create_timer(.6).timeout
	var rider := home.subway.people[0]
	var eye := home.subway.to_global(rider.position + Vector3(0, 1.55, 1.6))
	home.player.move_to(eye, rider.global_position + Vector3.UP * 1.3)
	home.subway.say(rider, home.subway.REQUESTS[0])
	await snap("subway")
	GameSettings.set_language("en")
	await snap("subway-en")
	GameSettings.set_language("ru")
	print("RADION_VISUAL ready")
	home.quit_game()

func snap(shot_name: String) -> void:
	await home.get_tree().create_timer(.6).timeout
	await RenderingServer.frame_post_draw
	home.get_viewport().get_texture().get_image().save_png(SavePaths.file("ui-%s.png" % shot_name))
