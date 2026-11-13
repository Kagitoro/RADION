class_name BackpackPanel
extends Control
## Player inventory (Tab): what the player carries, with low-poly 3D icons, counts
## and the key that uses each item. NightGame fills it and decides what "use" does.

signal close_requested
signal use_requested(id: String)

const SLOT_SIZE := Vector2(196,176)
const FOOTER := [["Tab","закрыть"],["Esc","закрыть"],["ЛКМ","выбрать"],["Enter","использовать"]]

## [id, name, count, key, description, model] — see NightGame.backpack_items().
var items: Array = []
var slots: Array[Button] = []
var selected := 0
var thumbnails := {}
var preview_world: SubViewport
var preview_pivot: Node3D

func _ready() -> void:
	%Detail.add_theme_stylebox_override("panel",UIKit.facet(Color(UIKit.INK,.75),UIKit.EDGE,UIKit.CUT,3))
	%UseButton.pressed.connect(func(): use(selected))
	MenuFx.light_on_focus(%UseButton)
	preview_world = ShopPanel.make_stage(Vector2i(360,170))
	preview_world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	%Preview.add_child(preview_world)
	var footer: HBoxContainer = %Footer
	for hint in FOOTER:
		footer.add_child(UIKit.keycap(str(hint[0])))
		var caption := UIKit.label(str(hint[1]),13)
		caption.add_theme_color_override("font_color",UIKit.MUTED)
		footer.add_child(caption)
		var gap := Control.new()
		gap.custom_minimum_size.x = 10
		footer.add_child(gap)
	set_process(false)

func open(new_items: Array, cash: int) -> void:
	items = new_items
	%Cash.text = "$%d" % cash
	build_slots()
	show()
	MenuFx.pop_in(%Window)
	preview_world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	set_process(true)
	# Start on the first thing the player actually has.
	var first := 0
	for index in items.size():
		if int(items[index][2])>0:
			first = index
			break
	select(first)
	slots[first].grab_focus.call_deferred()

func close() -> void:
	hide()
	preview_world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(false)

func build_slots() -> void:
	for slot in slots:
		slot.queue_free()
	slots.clear()
	for index in items.size():
		var slot := make_slot(index)
		%Slots.add_child(slot)
		slots.append(slot)

func make_slot(index: int) -> Button:
	var item: Array = items[index]
	var count := int(item[2])
	var slot := Button.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.toggle_mode = true
	slot.focus_mode = Control.FOCUS_ALL
	var rest := UIKit.facet(Color(UIKit.DUSK,.9),UIKit.EDGE,UIKit.CUT,4)
	var lit := UIKit.facet(UIKit.RAISED,UIKit.AMBER,UIKit.CUT,4)
	for state in ["normal","disabled"]:
		slot.add_theme_stylebox_override(state,rest)
	for state in ["hover","pressed","hover_pressed","focus"]:
		slot.add_theme_stylebox_override(state,lit)
	var icon := TextureRect.new()
	icon.texture = thumbnail(str(item[5]))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(8,10)
	icon.size = Vector2(SLOT_SIZE.x-16,112)
	slot.add_child(icon)
	var name_label := UIKit.title(tr(str(item[1])),16)
	name_label.position = Vector2(14,128)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(name_label)
	var amount := UIKit.title("×%d" % count,18,UIKit.AMBER if count>0 else UIKit.MUTED)
	amount.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	amount.position = Vector2(SLOT_SIZE.x-58,126)
	amount.size = Vector2(46,24)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(amount)
	if not str(item[3]).is_empty():
		var key := UIKit.keycap(str(item[3]),12)
		key.position = Vector2(10,10)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(key)
	if count<=0:
		icon.modulate = Color(1,1,1,.3)
		name_label.modulate = Color(1,1,1,.5)
	slot.pressed.connect(func(): select(index))
	slot.focus_entered.connect(func(): select(index))
	slot.mouse_entered.connect(func(): slot.grab_focus())
	slot.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.double_click:
			use(index)
		elif event.is_action_pressed("ui_accept"):
			use(index)
			slot.accept_event()
	)
	return slot

func select(index: int) -> void:
	if index<0 or index>=items.size():
		return
	var changed := index!=selected or preview_pivot==null
	selected = index
	for slot_index in slots.size():
		slots[slot_index].set_pressed_no_signal(slot_index==index)
	var item: Array = items[index]
	var count := int(item[2])
	%Name.text = tr(str(item[1]))
	%Count.text = tr("В кармане: %d") % count if count>0 else tr("Нет в кармане · купи в Night Shop")
	%Count.add_theme_color_override("font_color",UIKit.AMBER if count>0 else UIKit.BAD)
	%Description.text = tr(str(item[4]))
	var usable := count>0 and not str(item[3]).is_empty()
	%UseButton.disabled = not usable
	%UseButton.text = tr("Использовать · %s") % str(item[3]) if not str(item[3]).is_empty() else tr("Всегда с собой")
	if changed:
		show_model(str(item[5]))

func use(index: int) -> void:
	if index<0 or index>=items.size():
		return
	var item: Array = items[index]
	if int(item[2])<=0 or str(item[3]).is_empty():
		MenuFx.nudge(slots[index])
		return
	use_requested.emit(str(item[0]))

func thumbnail(model: String) -> Texture2D:
	if thumbnails.has(model):
		return thumbnails[model]
	var view := ShopPanel.make_stage(Vector2i(300,170))
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(view)
	ShopPanel.stage_model(view,model)
	thumbnails[model] = view.get_texture()
	return thumbnails[model]

func show_model(model: String) -> void:
	if preview_pivot!=null:
		preview_world.remove_child(preview_pivot)
		preview_pivot.queue_free()
	preview_pivot = ShopPanel.stage_model(preview_world,model)
	preview_pivot.scale = Vector3.ONE*.7
	preview_pivot.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(preview_pivot,"scale",Vector3.ONE,.3)

func _process(delta: float) -> void:
	if preview_pivot!=null:
		preview_pivot.rotate_y(delta*.9)

func _unhandled_key_input(event: InputEvent) -> void:
	# Number keys pick slots while the inventory is open.
	if not visible or not event.is_pressed():
		return
	var key := (event as InputEventKey).physical_keycode
	if key>=KEY_1 and key<=KEY_9:
		var index := int(key-KEY_1)
		if index<slots.size():
			slots[index].grab_focus()
			get_viewport().set_input_as_handled()
