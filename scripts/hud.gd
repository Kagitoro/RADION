class_name HUD
extends CanvasLayer

const HELD_CARD := preload("res://ui/held_card.tscn")
const INVENTORY := preload("res://ui/inventory_window.tscn")
const TARGET_CARD := preload("res://ui/target_card.tscn")

var game: Home
var root: Control
var badge: Label
var hint: KeyHints
var held_panel: PanelContainer
var held_name: Label
var held_view: SubViewport
var held_root: Node3D
var held_copy: Node3D
var menu: InventoryWindow
var search: LineEdit
var asset_list: ItemList
var asset_keys: Array[String] = []
var plan: FloorPlan
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
var crosshair: Crosshair
var target_card: PanelContainer
var target_title: Label
var target_hint: Label

func _ready() -> void:
	GameEvents.notice_requested.connect(notice)
	GameEvents.hud_refresh_requested.connect(refresh)
	root = Control.new()
	root.theme = preload("res://ui/theme.tres")
	add_child(root)
	UIKit.anchor_fill(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair = Crosshair.new()
	root.add_child(crosshair)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER,Control.PRESET_MODE_KEEP_SIZE)
	build_target_card()
	badge = UIKit.label("", 15)
	badge.theme_type_variation = &"HudBadge"
	root.add_child(badge)
	badge.position = Vector2(20,18)
	hint = KeyHints.new()
	root.add_child(hint)
	hint.anchor_top = 1
	hint.anchor_bottom = 1
	hint.offset_left = 20
	hint.offset_top = -44
	hint.offset_bottom = -16
	notice_label = UIKit.label("", 14)
	notice_label.theme_type_variation = &"HudNotice"
	root.add_child(notice_label)
	notice_label.position = Vector2(20,56)
	notice_label.z_index = 2
	notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_label.hide()
	build_held()
	build_inventory()
	build_plan()
	dialog = FileDialog.new()
	dialog.title = tr("Открыть сохранённую расстановку")
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray([tr("*.json ; Проект RADION")])
	dialog.file_selected.connect(func(path): game.storage.load_project(path))
	add_child(dialog)
	export_dialog = FileDialog.new()
	export_dialog.title = tr("Экспорт проекта RADION")
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.current_file = "RADION-home-project.json"
	export_dialog.filters = PackedStringArray([tr("*.json ; Проект RADION")])
	export_dialog.file_selected.connect(func(path): game.storage.save_project(path))
	add_child(export_dialog)
	refresh()

func build_held() -> void:
	held_panel = HELD_CARD.instantiate()
	root.add_child(held_panel)
	held_name = held_panel.get_node("%Name")
	held_view = held_panel.get_node("%Preview")
	held_root = held_panel.get_node("%Stage")
	(held_panel.get_node("%Camera") as Camera3D).look_at(Vector3.ZERO)
	held_panel.hide()

func build_inventory() -> void:
	menu = INVENTORY.instantiate()
	root.add_child(menu)
	search = menu.search
	asset_list = menu.asset_list
	menu.close_requested.connect(close_inventory)
	menu.take_requested.connect(take_asset)
	menu.search_changed.connect(func(_query: String): filter_items())
	menu.open_requested.connect(func(): dialog.popup_centered_ratio(.70))
	menu.save_requested.connect(func(): game.storage.save_project())
	menu.export_requested.connect(func(): export_dialog.popup_centered_ratio(.70))
	menu.hide()

func filter_items() -> void:
	asset_list.clear()
	asset_keys.clear()
	var query := search.text.strip_edges().to_lower().replace("ё","е")
	for item in game.inventory:
		if not query.is_empty() and not tr(str(item.label)).to_lower().replace("ё","е").contains(query):
			continue
		asset_keys.append(str(item.key))
		var zone_name := ""
		if game.data.rooms.has(str(item.get("zone",""))):
			zone_name = "   ·   " + tr(str(game.data.rooms[item.zone].name))
		asset_list.add_item(tr(str(item.label)) + zone_name)

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
	held_name.text = tr("В руках · %s") % tr(str(item.label))
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
	var fresh := text!=notice_label.text or not notice_label.visible
	notice_label.text = text
	notice_label.visible = not text.is_empty()
	notice_label.reset_size()
	last_message = Time.get_ticks_msec()
	if fresh and notice_label.visible:
		# Slides in from the left edge and fades up.
		notice_label.modulate.a = 0.0
		notice_label.position.x = 0
		var motion := notice_label.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		motion.tween_property(notice_label,"modulate:a",1.0,.18)
		motion.tween_property(notice_label,"position:x",20.0,.25)

func clear_notice() -> void:
	notice_label.text = ""
	notice_label.hide()

func build_plan() -> void:
	plan = FloorPlan.new()
	plan.game = game
	root.add_child(plan)
	UIKit.anchor_fill(plan)
	plan.offset_bottom = -164
	plan.hide()
	plan_panel = UIKit.panel()
	root.add_child(plan_panel)
	plan_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	plan_panel.offset_top = -164
	var column := VBoxContainer.new()
	plan_panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	for pair in [[tr("Всё"),"all"],[tr("Комнаты"),"floor"],[tr("Стены"),"wall"],[tr("Двери и окна"),"opening"],[tr("Мебель"),"item"]]:
		var kind := str(pair[1])
		var tab := UIKit.button(str(pair[0]), func(): plan.set_layer(kind); refresh())
		tab.toggle_mode = true
		tab.focus_mode = Control.FOCUS_NONE
		header.add_child(tab)
		layer_buttons[kind] = tab
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.add_child(UIKit.button(tr("Инвентарь"), toggle_inventory))
	var reference := UIKit.button(tr("Моя схема"),func(): plan.show_reference = not plan.show_reference; plan.queue_redraw())
	reference.toggle_mode = true
	reference.focus_mode = Control.FOCUS_NONE
	header.add_child(reference)
	header.add_child(UIKit.button(tr("Заделать щели"),func(): plan.finish_drag(); plan.cancel_construction(); game.storage.repair_seams(); plan.queue_redraw()))
	header.add_child(UIKit.button(tr("Весь дом"), func(): plan.fit(); plan.queue_redraw()))
	header.add_child(UIKit.button(tr("Отменить"), func(): plan.cancel_construction(); game.storage.undo(); plan.queue_redraw()))
	header.add_child(UIKit.button(tr("Сохранить"), func(): game.storage.save_project()))
	header.add_child(UIKit.button(tr("В комнату  [Tab]"), toggle_plan))
	var actions := HBoxContainer.new()
	column.add_child(actions)
	plan_name = UIKit.label(tr("Выбери объект"),16)
	plan_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(plan_name)
	var magnet := UIKit.button(tr("Магнит"),func(): plan.magnets = not plan.magnets; plan.joint = {}; plan.queue_redraw(); refresh())
	magnet.toggle_mode = true
	magnet.button_pressed = true
	magnet.focus_mode = Control.FOCUS_NONE
	magnet.tooltip_text = tr("Привязка стен и комнат. Удерживай Shift, чтобы временно отключить.")
	actions.add_child(magnet)
	actions.add_child(UIKit.button(tr("На пол"),func(): game.ground_selection(); plan.queue_redraw()))
	for entry in [[tr("Рисовать стену"),"wall"],[tr("+ Комната"),"room"]]:
		var tool := str(entry[1])
		var control := UIKit.button(str(entry[0]),func(): game.cancel_hold(); plan.set_build_tool(tool); refresh())
		control.toggle_mode = true
		control.focus_mode = Control.FOCUS_NONE
		actions.add_child(control)
		build_buttons[tool] = control
	for entry in [[tr("Дверь"),"door"],[tr("Проём"),"opening"],[tr("Окно"),"window"]]:
		var type := str(entry[1])
		actions.add_child(UIKit.button("+ "+str(entry[0]),func(): game.cancel_hold(); plan.set_opening_tool(type); refresh()))
	actions.add_child(UIKit.button(tr("Удалить"),func(): game.delete_selected(); plan.queue_redraw()))
	var dimensions_row := HBoxContainer.new()
	column.add_child(dimensions_row)
	for entry in [["X","x"],["Z","z"],[tr("От пола"),"y"],[tr("Ширина"),"w"],[tr("Высота"),"h"],[tr("Глубина"),"d"],[tr("Поворот"),"r"]]:
		var key := str(entry[1])
		var column2 := VBoxContainer.new()
		dimensions_row.add_child(column2)
		column2.add_child(UIKit.label(str(entry[0]), 12))
		var field := SpinBox.new()
		field.min_value = -70 if key in ["x","y","z","r"] else .024
		field.max_value = 360 if key == "r" else 70
		field.step = .01 if key != "r" else 1
		field.custom_minimum_size.x = 101
		field.value_changed.connect(func(value): game.plan_property(key,value); plan.queue_redraw())
		column2.add_child(field)
		fields[key] = field
	plan_help = UIKit.label("",12)
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
		badge.text = tr("НОЧЬ / HOUSE PARTY")
		badge.visible = not game.modal
		hint.visible = not game.modal
		hint.text = tr("WASD идти · Shift быстрее · E общаться · Tab инвентарь · F фонарь · Esc пауза")
		crosshair.visible = not game.modal and not game.player.collapsed
		target_card.hide()
		held_panel.hide()
		game.frames.update_target_frames()
		if not notice_label.text.is_empty() and Time.get_ticks_msec()-last_message>4200:
			clear_notice()
		return
	if not notice_label.text.is_empty() and Time.get_ticks_msec() - last_message > 3600:
		clear_notice()
	var current: Dictionary = game.held if not game.held.is_empty() else game.records.get(game.selected,{})
	var targeted: Dictionary = game.records.get(game.aimed_id(),{})
	var text := tr("RADION · Дом")
	if not current.is_empty():
		var prefix := tr("Выбрано") if game.held.is_empty() else tr("В руках")
		text = tr("%s · %s · %.2f × %.2f × %.2f м") % [prefix,tr(str(current.label)),current.w,current.h,current.d]
	update_target_card(targeted)
	game.frames.update_target_frames()
	if game.storage.dirty:
		text += "  •"
	if text != last_badge:
		badge.text = text
		last_badge = text
	var mode := {"rotate":tr("поворот"),"size":tr("размер %s") % str(game.axis).to_upper(),"lift":tr("высота")}[game.tool] as String
	hint.text = tr("E инвентарь · Tab план · ЛКМ взять / поставить · R/T/X/H режим · колесо — %s · Ctrl+S сохранить") % mode
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
		plan_name.text = tr("Выбери объект") if current.is_empty() else tr(str(current.label))
		plan_help.text = tr("Жёлтые — двери и проходы   ·   Голубые — окна   ·   Перетаскивание — переместить   ·   Колесо — масштаб   ·   Средняя кнопка — панорама")
		if drawing:
			plan_name.text = tr("Строительство · Комната") if plan.build_tool=="room" else tr("Строительство · Стена")
			var reason := str(plan.build_preview.get("error",""))
			plan_help.text = reason if not reason.is_empty() else tr("Зажми ЛКМ и протяни до второй точки · Отпусти для постройки · ПКМ — выйти · Shift — без магнита")
		elif placing_opening:
			plan_name.text = tr("Установка · %s") % tr(str(game.openings.draft(plan.opening_tool).label))
			plan_help.text = tr("Щелчок по стене — установить · ПКМ — отменить")
		elif plan.layer=="floor":
			plan_help.text = tr("Середина — перенос · Зелёный угол — размер · Магнит совмещает края комнат · Shift — свободное движение")
		elif plan.layer=="wall":
			plan_help.text = tr("Перетащи стену или потяни за голубой конец · R — повернуть стену в руках · Shift — без магнита")
		var attached := current.has("wall_id")
		for key in fields:
			fields[key].editable = not current.is_empty() and not drawing and not placing_opening and (not attached or key in ["y","w","h"])
			if not current.is_empty() and not fields[key].get_line_edit().has_focus():
				fields[key].set_value_no_signal(float(current[key]))

func build_target_card() -> void:
	target_card = TARGET_CARD.instantiate()
	root.add_child(target_card)
	target_title = target_card.get_node("%Title")
	target_hint = target_card.get_node("%Hint")
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
		target_title.text=tr("Установка · %s") % tr(str(game.held.label))
		target_hint.text=tr("%s · ЛКМ поставить · ПКМ отменить") % str(game.placement_surface) if game.placement_supported else tr("Нет опоры · Наведи на пол или поверхность")
		crosshair.modulate=Color("#a6f2bd")
	else:
		var marked: Dictionary = target if not target.is_empty() else game.records.get(grab_id,{})
		var marked_id := str(marked.get("id",""))
		var picked: bool = not marked_id.is_empty() and marked_id==game.selected
		target_title.text=(tr("Выбрано · %s") if picked else tr("Прицел · %s")) % tr(str(marked.get("label","")))
		target_hint.text = tr("Редактирование на плане · Tab") if game.plan_only(marked_id) else (tr("ЛКМ взять · ПКМ выделить") if not grab_id.is_empty() else tr("ПКМ выделить"))
		crosshair.modulate=Color("#a6f2bd") if picked else Color("#f3efdd")
