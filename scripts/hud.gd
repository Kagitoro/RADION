extends CanvasLayer

const Plan = preload("res://scripts/plan.gd")
var game
var root: Control
var badge: Label
var hint: Label
var held_panel: PanelContainer
var held_name: Label
var held_view: SubViewport
var held_root: Node3D
var held_copy: Node3D
var menu: PanelContainer
var menu_title: Label
var search: LineEdit
var asset_list: ItemList
var asset_keys: Array[String] = []
var plan
var plan_panel: PanelContainer
var plan_name: Label
var plan_help: Label
var layer_buttons: Dictionary = {}
var build_buttons: Dictionary = {}
var fields: Dictionary = {}
var dialog: FileDialog
var export_dialog: FileDialog
var notice_label: Label
var last_message := 0
var last_badge := ""
var crosshair: Label
var target_card: PanelContainer
var target_title: Label
var target_hint: Label

func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1c2924ed")
	style.border_color = Color("#719480")
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style())
	return p

func label(text: String, font_size: int = 15) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_outline_color",Color("#172019"))
	node.add_theme_constant_override("outline_size",2)
	return node

func button(text: String, action: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.pressed.connect(action)
	return node

func anchor_fill(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _ready() -> void:
	root = Control.new()
	add_child(root)
	anchor_fill(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair = label("+", 27)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position -= Vector2(8,18)
	build_target_card()
	badge = label("", 16)
	root.add_child(badge)
	badge.position = Vector2(20,18)
	hint = label("", 14)
	root.add_child(hint)
	hint.anchor_top = 1
	hint.anchor_bottom = 1
	hint.offset_left = 20
	hint.offset_top = -43
	hint.offset_bottom = -12
	notice_label = label("", 15)
	root.add_child(notice_label)
	notice_label.position = Vector2(20,47)
	notice_label.z_index = 2
	notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_held()
	build_inventory()
	build_plan()
	dialog = FileDialog.new()
	dialog.title = "Открыть сохранённую расстановку"
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; Проект RADION"])
	dialog.file_selected.connect(func(path): game.load_project(path))
	add_child(dialog)
	export_dialog = FileDialog.new()
	export_dialog.title = "Экспорт проекта RADION"
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.current_file = "RADION-home-project.json"
	export_dialog.filters = PackedStringArray(["*.json ; Проект RADION"])
	export_dialog.file_selected.connect(func(path): game.save_project(path))
	add_child(export_dialog)
	refresh()

func build_held() -> void:
	held_panel = panel()
	root.add_child(held_panel)
	held_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	held_panel.offset_left = -234
	held_panel.offset_top = -211
	held_panel.offset_right = -18
	held_panel.offset_bottom = -54
	held_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	held_panel.add_child(column)
	held_name = label("", 13)
	held_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(held_name)
	var carrier := SubViewportContainer.new()
	carrier.custom_minimum_size = Vector2(174,102)
	carrier.stretch = true
	carrier.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(carrier)
	held_view = SubViewport.new()
	held_view.world_3d = World3D.new()
	held_view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	carrier.add_child(held_view)
	held_root = Node3D.new()
	held_view.add_child(held_root)
	var camera := Camera3D.new()
	held_root.add_child(camera)
	camera.position = Vector3(1.67,1.22,2.30)
	camera.look_at(Vector3.ZERO)
	camera.fov = 31
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38, -32, 0)
	light.light_energy = 1.65
	held_root.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35, 145, 0)
	fill.light_energy = .62
	held_root.add_child(fill)
	held_panel.hide()

func build_inventory() -> void:
	menu = panel()
	root.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu.offset_left = -310
	menu.offset_right = 310
	menu.offset_top = -267
	menu.offset_bottom = 267
	var column := VBoxContainer.new()
	menu.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	menu_title = label("Инвентарь дома", 24)
	menu_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(menu_title)
	top.add_child(button("Закрыть", close_inventory))
	search = LineEdit.new()
	search.placeholder_text = "Поиск по названию"
	search.text_changed.connect(func(_value): filter_items())
	column.add_child(search)
	asset_list = ItemList.new()
	asset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	asset_list.item_activated.connect(func(index): take_asset(index))
	column.add_child(asset_list)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	actions.add_child(button("Взять выбранное", func():
		var choice := asset_list.get_selected_items()
		if not choice.is_empty():
			take_asset(choice[0])
	))
	actions.add_child(button("Открыть JSON", func(): dialog.popup_centered_ratio(.70)))
	actions.add_child(button("Сохранить", func(): game.save_project()))
	actions.add_child(button("Экспорт JSON", func(): export_dialog.popup_centered_ratio(.70)))
	menu.hide()

func filter_items() -> void:
	asset_list.clear()
	asset_keys.clear()
	var query := search.text.strip_edges().to_lower().replace("ё","е")
	for item in game.inventory:
		if not query.is_empty() and not str(item.label).to_lower().replace("ё","е").contains(query):
			continue
		asset_keys.append(str(item.key))
		var zone_name := ""
		if game.data.rooms.has(str(item.get("zone",""))):
			zone_name = "   ·   " + str(game.data.rooms[item.zone].name)
		asset_list.add_item(str(item.label) + zone_name)

func toggle_inventory() -> void:
	if menu.visible:
		close_inventory()
	else:
		game.set_modal(true)
		menu.show()
		menu.move_to_front()
		filter_items()
		search.grab_focus()

func close_inventory() -> void:
	menu.hide()
	game.set_modal(plan.visible)
	refresh()

func take_asset(index: int) -> void:
	if index >= 0 and index < asset_keys.size():
		close_inventory()
		var key := asset_keys[index]
		if key in ["window","opening"]:
			game.cancel_hold()
			if not plan.visible:
				toggle_plan()
			plan.set_opening_tool(key)
			refresh()
		else:
			game.take_template(key)

func show_held(key: String, item: Dictionary) -> void:
	clear_held()
	held_copy = game.duplicate_model(key)
	if held_copy != null:
		held_root.add_child(held_copy)
	held_panel.show()
	refresh_held(item)

func refresh_held(item: Dictionary) -> void:
	held_name.text = "В руках · " + str(item.label)
	if held_copy != null:
		var size: Vector3 = game.dimensions(item)
		var ratio := 1.0 / maxf(size.x, maxf(size.y, size.z))
		held_copy.scale = size * ratio / game.vector(item.dimensions)
		held_copy.position.y = -size.y * ratio * 0.5
		held_copy.rotation.y = deg_to_rad(float(item.r))

func clear_held() -> void:
	if is_instance_valid(held_copy):
		held_copy.free()
	held_copy = null
	held_panel.hide()

func notice(text: String) -> void:
	notice_label.text = text
	last_message = Time.get_ticks_msec()

func build_plan() -> void:
	plan = Plan.new()
	plan.game = game
	root.add_child(plan)
	anchor_fill(plan)
	plan.offset_bottom = -164
	plan.hide()
	plan_panel = panel()
	root.add_child(plan_panel)
	plan_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	plan_panel.offset_top = -164
	var column := VBoxContainer.new()
	plan_panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	for pair in [["Всё","all"],["Комнаты","floor"],["Стены","wall"],["Двери и окна","opening"],["Мебель","item"]]:
		var kind := str(pair[1])
		var tab := button(str(pair[0]), func(): plan.set_layer(kind); refresh())
		tab.toggle_mode = true
		tab.focus_mode = Control.FOCUS_NONE
		header.add_child(tab)
		layer_buttons[kind] = tab
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.add_child(button("Инвентарь", toggle_inventory))
	var reference := button("Моя схема",func(): plan.show_reference = not plan.show_reference; plan.queue_redraw())
	reference.toggle_mode = true
	reference.focus_mode = Control.FOCUS_NONE
	header.add_child(reference)
	header.add_child(button("Заделать щели",func(): plan.finish_drag(); plan.cancel_construction(); game.repair_seams(); plan.queue_redraw()))
	header.add_child(button("Весь дом", func(): plan.fit(); plan.queue_redraw()))
	header.add_child(button("Отменить", func(): plan.cancel_construction(); game.undo(); plan.queue_redraw()))
	header.add_child(button("Сохранить", func(): game.save_project()))
	header.add_child(button("В комнату  [Tab]", toggle_plan))
	var actions := HBoxContainer.new()
	column.add_child(actions)
	plan_name = label("Выбери объект",16)
	plan_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(plan_name)
	var magnet := button("Магнит",func(): plan.magnets = not plan.magnets; plan.joint = {}; plan.queue_redraw(); refresh())
	magnet.toggle_mode = true
	magnet.button_pressed = true
	magnet.focus_mode = Control.FOCUS_NONE
	magnet.tooltip_text = "Привязка стен и комнат. Удерживай Shift, чтобы временно отключить."
	actions.add_child(magnet)
	actions.add_child(button("На пол",func(): game.ground_selection(); plan.queue_redraw()))
	for entry in [["Рисовать стену","wall"],["+ Комната","room"]]:
		var tool := str(entry[1])
		var control := button(str(entry[0]),func(): game.cancel_hold(); plan.set_build_tool(tool); refresh())
		control.toggle_mode = true
		control.focus_mode = Control.FOCUS_NONE
		actions.add_child(control)
		build_buttons[tool] = control
	for entry in [["Дверь","door"],["Проём","opening"],["Окно","window"]]:
		var type := str(entry[1])
		actions.add_child(button("+ "+str(entry[0]),func(): game.cancel_hold(); plan.set_opening_tool(type); refresh()))
	actions.add_child(button("Удалить",func(): game.delete_selected(); plan.queue_redraw()))
	var dimensions_row := HBoxContainer.new()
	column.add_child(dimensions_row)
	for entry in [["X","x"],["Z","z"],["От пола","y"],["Ширина","w"],["Высота","h"],["Глубина","d"],["Поворот","r"]]:
		var key := str(entry[1])
		var column2 := VBoxContainer.new()
		dimensions_row.add_child(column2)
		column2.add_child(label(str(entry[0]), 12))
		var field := SpinBox.new()
		field.min_value = -70 if key in ["x","y","z","r"] else .024
		field.max_value = 360 if key == "r" else 70
		field.step = .01 if key != "r" else 1
		field.custom_minimum_size.x = 101
		field.value_changed.connect(func(value): game.plan_property(key,value); plan.queue_redraw())
		column2.add_child(field)
		fields[key] = field
	plan_help = label("",12)
	column.add_child(plan_help)
	plan_panel.hide()

func toggle_plan() -> void:
	if plan.visible:
		plan.finish_drag()
		plan.cancel_construction()
		plan.opening_tool = ""
	if menu.visible:
		menu.hide()
	plan.visible = not plan.visible
	plan_panel.visible = plan.visible
	game.set_modal(plan.visible)
	if plan.visible:
		if not plan.fitted:
			plan.fit()
		plan.queue_redraw()
	refresh()

func refresh() -> void:
	if root == null:
		return
	if game.game_mode:
		badge.text = "НОЧЬ / HOUSE PARTY"
		badge.visible = not game.modal
		hint.visible = not game.modal
		hint.text = "WASD идти · Shift быстрее · E общаться · F фонарь · Esc пауза"
		crosshair.visible = not game.modal and not game.player.collapsed
		target_card.hide()
		held_panel.hide()
		game.update_target_frames()
		if not notice_label.text.is_empty() and Time.get_ticks_msec()-last_message>4200:
			notice_label.text = ""
		return
	if not notice_label.text.is_empty() and Time.get_ticks_msec() - last_message > 3600:
		notice_label.text = ""
	var current: Dictionary = game.held if not game.held.is_empty() else game.records.get(game.selected,{})
	var targeted: Dictionary = game.records.get(game.aimed_id(),{})
	var text := "RADION · Дом"
	if not current.is_empty():
		var prefix := "Выбрано" if game.held.is_empty() else "В руках"
		text = "%s · %s · %.2f × %.2f × %.2f м" % [prefix,current.label,current.w,current.h,current.d]
	update_target_card(targeted)
	game.update_target_frames()
	if game.dirty:
		text += "  •"
	if text != last_badge:
		badge.text = text
		last_badge = text
	var mode := {"rotate":"поворот","size":"размер "+str(game.axis).to_upper(),"lift":"высота"}[game.tool] as String
	hint.text = "E инвентарь · Tab план · ЛКМ взять / поставить · R/T/X/H режим · колесо — %s · Ctrl+S сохранить" % mode
	crosshair.visible = not game.modal
	hint.visible = not plan.visible
	badge.visible = not plan.visible
	held_panel.visible = not current.is_empty() and not game.held.is_empty() and not game.modal
	if plan.visible:
		for kind in layer_buttons:
			layer_buttons[kind].set_pressed_no_signal(plan.layer==kind)
		for tool in build_buttons:
			build_buttons[tool].set_pressed_no_signal(plan.build_tool==tool)
		var placing_opening: bool = not plan.opening_tool.is_empty()
		var drawing: bool = not plan.build_tool.is_empty()
		plan_name.text = "Выбери объект" if current.is_empty() else str(current.label)
		plan_help.text = "Жёлтые — двери и проходы   ·   Голубые — окна   ·   Перетаскивание — переместить   ·   Колесо — масштаб   ·   Средняя кнопка — панорама"
		if drawing:
			plan_name.text = "Строительство · "+("Комната" if plan.build_tool=="room" else "Стена")
			var reason := str(plan.build_preview.get("error",""))
			plan_help.text = reason if not reason.is_empty() else "Зажми ЛКМ и протяни до второй точки · Отпусти для постройки · ПКМ — выйти · Shift — без магнита"
		elif placing_opening:
			plan_name.text = "Установка · "+str(game.openings.draft(plan.opening_tool).label)
			plan_help.text = "Щелчок по стене — установить · ПКМ — отменить"
		elif plan.layer=="floor":
			plan_help.text = "Середина — перенос · Зелёный угол — размер · Магнит совмещает края комнат · Shift — свободное движение"
		elif plan.layer=="wall":
			plan_help.text = "Перетащи стену или потяни за голубой конец · R — повернуть стену в руках · Shift — без магнита"
		var attached := current.has("wall_id")
		for key in fields:
			fields[key].editable = not current.is_empty() and not drawing and not placing_opening and (not attached or key in ["y","w","h"])
			if not current.is_empty() and not fields[key].get_line_edit().has_focus():
				fields[key].set_value_no_signal(float(current[key]))

func build_target_card() -> void:
	target_card=panel()
	root.add_child(target_card)
	target_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	target_card.offset_left=-340
	target_card.offset_right=-20
	target_card.offset_top=18
	target_card.offset_bottom=76
	target_card.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var group := VBoxContainer.new()
	group.mouse_filter=Control.MOUSE_FILTER_IGNORE
	target_card.add_child(group)
	target_title=label("",15)
	target_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	target_title.mouse_filter=Control.MOUSE_FILTER_IGNORE
	group.add_child(target_title)
	target_hint=label("",12)
	target_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	target_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE
	group.add_child(target_hint)
	target_card.hide()

func update_target_card(target: Dictionary) -> void:
	var held_now: bool = not game.held.is_empty()
	var grab_id: String = game.grab_target_id()
	var visible_now: bool = not game.modal and (not target.is_empty() or held_now or not grab_id.is_empty())
	target_card.visible=visible_now
	if not visible_now:
		crosshair.modulate=Color.WHITE
		return
	if held_now:
		target_title.text="Установка · "+str(game.held.label)
		target_hint.text=str(game.placement_surface)+" · ЛКМ поставить · ПКМ отменить" if game.placement_supported else "Нет опоры · Наведи на пол или поверхность"
		crosshair.modulate=Color("#a6f2bd")
	else:
		var marked: Dictionary = target if not target.is_empty() else game.records.get(grab_id,{})
		var marked_id := str(marked.get("id",""))
		var picked: bool = not marked_id.is_empty() and marked_id==game.selected
		target_title.text=("Выбрано · " if picked else "Прицел · ")+str(marked.get("label",""))
		target_hint.text = "Редактирование на плане · Tab" if game.plan_only(marked_id) else ("ЛКМ взять · ПКМ выделить" if not grab_id.is_empty() else "ПКМ выделить")
		crosshair.modulate=Color("#a6f2bd") if picked else Color("#f3efdd")
