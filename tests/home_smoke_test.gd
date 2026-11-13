class_name HomeSmokeTest
extends RefCounted
## House-editor checks: library, pick-up, resize, undo, save/load, room move, input map, pause.

var home: Home

func _init(target: Home) -> void:
	home = target

func run(errors: Array[String]) -> void:
	var stock_size := home.records.size()
	if home.records.size() < 180 or home.inventory.size() < 35 or home.catalog.size() < 10:
		errors.append("Неполная сцена или библиотека")
	check_house_lights(errors)
	var stove := ""
	for id in home.originals:
		if str(home.originals[id].label) == "Плита и духовой шкаф":
			stove = id
			break
	if stove.is_empty():
		errors.append("Нет плиты")
	else:
		home.selected = ""
		var stale_collider: StaticBody3D = home.bodies[stove]
		home.aim = {"collider":stale_collider}
		home.interact()
		if home.grabbed != stove or str(home.held.get("id","")) != stove or not home.aimed_id().is_empty():
			errors.append("ЛКМ оставляет старую цель после взятия предмета")
		home.aim = {"collider":stale_collider}
		if not home.aimed_id().is_empty():
			errors.append("Удалённая цель всё ещё доступна")
		home.aim.clear()
		home.cancel_hold()
		if not home.bodies.has(stove):
			errors.append("Отмена взятия не восстановила коллизию")
		home.take_template(stove)
		if home.held.is_empty():
			errors.append("Не получилось взять предмет")
		else:
			var w := float(home.held.w)
			home.resize_width(w + 0.22)
			home.interact()
			if not home.records.has(home.selected) or absf(float(home.records[home.selected].w) - w - .22) > .001:
				errors.append("Ошибка установки или ширины")
			home.storage.undo()
			if home.records.size() != stock_size:
				errors.append("Отмена не вернула исходные объекты")
	var studio := home.rooms.room_floor("studio")
	var desk_id := ""
	var fridge_id := ""
	for row in home.originals.values():
		if row.label=="Рабочий стол":
			desk_id=str(row.id)
		elif row.label=="Холодильник":
			fridge_id=str(row.id)
	var origin := Vector2(float(studio.x),float(studio.z))
	var offset := Vector2(2.15,2.70)
	var desk_x := float(home.records[desk_id].x)
	var fridge_x := float(home.records[fridge_id].x)
	var item_ids := home.records.keys()
	var shared_wall: Dictionary = home.records["base-27"].duplicate(true)
	home.rooms.begin_room_move(str(studio.id))
	if not home.rooms.room_drag.members.has(desk_id):
		errors.append("Не определена мебель комнаты")
	home.rooms.preview_room_move(origin+offset)
	home.rooms.finish_room_move()
	if absf(float(home.records[desk_id].x)-desk_x-offset.x)>.001 or absf(float(home.records[fridge_id].x)-fridge_x)>.001:
		errors.append("Комната не перенесла мебель независимо от соседей")
	if home.records.keys()!=item_ids or home.records["base-27"]!=shared_wall:
		errors.append("Перенос добавил объекты или изменил общую стену")
	if not home.storage.restore_project(JSON.parse_string(home.storage.snapshot())) or absf(float(home.records[str(studio.id)].z)-origin.y-offset.y)>.001:
		errors.append("Положение перенесённой комнаты не восстановилось")
	home.storage.undo()
	if absf(float(home.records[str(studio.id)].x)-origin.x)>.001 or home.records.size()!=stock_size:
		errors.append("Отмена переноса комнаты не сработала")
	print("ROOM_MOVE furniture and unchanged shared wall verified")






	var smoke_path := SavePaths.file("radion_smoke_test.json")
	home.storage.save_project(smoke_path)
	if not home.storage.load_project(smoke_path, false):
		errors.append("Ручное сохранение не читается")
	if FileAccess.file_exists(smoke_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(smoke_path))
	if not home.storage.restore_project(JSON.parse_string(home.storage.snapshot())):
		errors.append("Снимок проекта не читается")
	await check_floor_plan(errors)
	check_inventory(errors)
	check_input_actions(errors)

## Lamps come from assets/house_lights.tscn, where they are placed by hand, and
## the ones tied to a fixture ride on it.
func check_house_lights(errors: Array[String]) -> void:
	var source := (load("res://assets/house_lights.tscn") as PackedScene).instantiate() as Node3D
	var placed := home.scene_lighting.get_children()
	var lamps := source.get_children().filter(func(node): return node is Light3D)
	if placed.size() != lamps.size():
		errors.append("Свет дома: %d ламп вместо %d из house_lights.tscn" % [placed.size(), lamps.size()])
	for lamp in lamps:
		var light := home.scene_lighting.get_node_or_null(NodePath(lamp.name)) as Light3D
		if light == null:
			errors.append("Свет дома: нет лампы " + lamp.name)
			continue
		if light.global_position.distance_to((lamp as Node3D).position) > .01:
			errors.append("Свет дома: %s не там, где в сцене" % lamp.name)
		var fixture := str(lamp.get_meta("fixture", ""))
		if not fixture.is_empty() and home.nodes[fixture].get_node_or_null("Light_" + lamp.name) == null:
			errors.append("Свет дома: %s не привязан к светильнику %s" % [lamp.name, fixture])
	source.free()

func check_inventory(errors: Array[String]) -> void:
	var hud := home.hud
	hud.toggle_inventory()
	if not hud.menu.visible:
		errors.append("Инвентарь: не открывается")
	var everything := hud.asset_list.item_count
	if everything < 10:
		errors.append("Инвентарь: список предметов пуст")
	hud.search.text = "Стул"
	hud.search.text_changed.emit(hud.search.text)
	if hud.asset_list.item_count == 0 or hud.asset_list.item_count >= everything:
		errors.append("Инвентарь: поиск не фильтрует список")
	hud.search.text = ""
	hud.search.text_changed.emit("")
	hud.menu.close_requested.emit()
	if hud.menu.visible:
		errors.append("Инвентарь: кнопка «Закрыть» не работает")

## Opens the floor plan, hit-tests a known object and draws one frame of it.
func check_floor_plan(errors: Array[String]) -> void:
	var hud := home.hud
	var plan := hud.plan
	hud.toggle_plan()
	if not plan.visible or not home.modal:
		errors.append("План: не открывается")
	await home.get_tree().process_frame
	await home.get_tree().process_frame
	var stove := ""
	for id in home.records:
		if str(home.records[id].label) == "Плита и духовой шкаф" and not bool(home.records[id].deleted):
			stove = id
	if stove.is_empty():
		errors.append("План: нет плиты для проверки")
	else:
		var row: Dictionary = home.records[stove]
		var point := Vector2(float(row.x), float(row.z))
		# The smallest object under the point wins, so a pan on the stove is also fine.
		if plan.geometry.hit_layer(point, "item").is_empty():
			errors.append("План: под курсором на плите нет предмета")
		if not plan.geometry.hit(Vector2(500, 500)).is_empty():
			errors.append("План: пустое место за домом что-то выделяет")
		if plan.geometry.hit_layer(point, "floor").is_empty():
			errors.append("План: под плитой нет пола")
		if not plan.unproject(plan.project(point)).is_equal_approx(point):
			errors.append("План: project/unproject не обратимы")
	plan.set_layer("wall")
	plan.queue_redraw()
	await home.get_tree().process_frame
	await home.get_tree().process_frame
	plan.set_layer("all")
	hud.toggle_plan()
	if plan.visible or home.modal:
		errors.append("План: не закрывается")

## Feeds synthetic key presses through the real input path and checks the InputMap wiring.
func check_input_actions(errors: Array[String]) -> void:
	var game := home.night_game
	var flash := game.flashlight.visible
	home._unhandled_input(key_event(KEY_F))
	if game.flashlight.visible == flash:
		errors.append("F (flashlight) не переключает фонарик")
	home._unhandled_input(key_event(KEY_F))
	var mode := game.light_mode
	home._unhandled_input(key_event(KEY_L))
	if game.light_mode != (mode + 1) % game.LIGHT_COLORS.size():
		errors.append("L (cycle_lights) не меняет свет")
	Input.action_press("move_forward")
	Input.action_press("move_right")
	var stick := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	Input.action_release("move_forward")
	Input.action_release("move_right")
	if stick.y <= 0.0 or stick.x <= 0.0:
		errors.append("Оси движения настроены неверно")
	home._unhandled_input(key_event(KEY_ESCAPE))
	if not game.pause_panel.visible or not home.modal:
		errors.append("Esc (pause) не открывает меню паузы")
	var slider: HSlider = game.pause_panel.get_node("%MusicSlider")
	slider.value = .5
	if not is_equal_approx(home.party.music_gain, .5):
		errors.append("Ползунок музыки в меню паузы не меняет громкость")
	home._unhandled_input(key_event(KEY_ESCAPE))
	if game.pause_panel.visible or home.modal:
		errors.append("Повторный Esc не закрывает паузу")
	home._unhandled_input(key_event(KEY_TAB))
	if not game.backpack_open() or not home.modal:
		errors.append("Tab не открывает инвентарь")
	elif game.backpack.slots.size() != game.backpack_items().size():
		errors.append("Инвентарь: не все предметы показаны")
	home._unhandled_input(key_event(KEY_TAB))
	if game.backpack_open() or home.modal:
		errors.append("Повторный Tab не закрывает инвентарь")
	for action in ["interact", "pause", "jump", "run", "open_mixer", "track_1", "talk_6"]:
		if not InputMap.has_action(action) or InputMap.action_get_events(action).is_empty():
			errors.append("Нет привязки для " + action)

func key_event(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event
