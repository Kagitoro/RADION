class_name InteractMenu
extends Control
## Small choice list shown on E next to the crosshair: "Взаимодействовать /
## Отменить", "Поставить / Кинуть / Отменить"… Pick with the mouse, the number
## keys or E (first option); Esc or RMB cancels. Options pop in one by one.

const ROW := Vector2(260, 44)
const BG := Color(0.13, 0.16, 0.21)
const HOVER := Color(0.25, 0.31, 0.40)
const HUB := Color(0.05, 0.07, 0.10)
const RIM := Color("#6f8fbf")
const TEXT := Color("#eef1ff")
const MUTED := Color("#8f9bc4")

var game: Node
var title := ""
## [label, Callable or null]; the last one is always "Отменить".
var options: Array = []
var opened := false
var appear := 0.0
var hover := 0
var motion: Tween

func _init(night_game: Node) -> void:
	game = night_game
	hide()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func open(heading: String, choices: Array) -> void:
	title = heading
	options = choices + [[tr("Отменить"), null]]
	hover = 0
	opened = true
	show()
	Input.warp_mouse(row_rect(0).get_center())
	animate(1.0, 0.2 + options.size() * 0.04)

func close() -> void:
	if not opened:
		return
	opened = false
	animate(0.0, 0.12)
	game.interact_menu_closed()

func animate(target: float, time: float) -> void:
	if is_instance_valid(motion):
		motion.kill()
	motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	motion.tween_method(func(value: float):
		appear = value
		queue_redraw(), appear, target, time)
	if target <= 0.0:
		motion.tween_callback(hide)

func row_rect(index: int) -> Rect2:
	var origin := size * 0.5 + Vector2(46, -ROW.y * 0.5)
	return Rect2(origin + Vector2(0, index * (ROW.y + 8)), ROW)

func pick(point: Vector2) -> int:
	for index in options.size():
		if row_rect(index).has_point(point):
			return index
	return -1

func choose(index: int) -> void:
	if index < 0 or index >= options.size():
		return
	var action = options[index][1]
	close()
	if action is Callable and action.is_valid():
		action.call()

func _input(event: InputEvent) -> void:
	if not opened:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if event.is_action_pressed("pause"):
			close()
		elif event.is_action_pressed("interact"):
			choose(hover)
		elif key.physical_keycode >= KEY_1 and key.physical_keycode < KEY_1 + options.size():
			choose(key.physical_keycode - KEY_1)
		else:
			return
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if not opened:
		return
	if event is InputEventMouseMotion:
		var next := pick(event.position)
		if next >= 0 and next != hover:
			hover = next
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var index := pick(event.position)
			if index >= 0:
				choose(index)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			close()
		accept_event()

func _draw() -> void:
	var font := get_theme_default_font()
	var first := row_rect(0)
	if not title.is_empty():
		var head_alpha := clampf(appear * 1.6, 0.0, 1.0)
		draw_string_outline(font, first.position + Vector2(6, -12), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, ROW.x, 15, 5, Color(0, 0, 0, 0.7 * head_alpha))
		draw_string(font, first.position + Vector2(6, -12), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, ROW.x, 15, Color(TEXT, head_alpha))
	for index in options.size():
		# Staggered pop-in: each row starts a little after the previous one.
		var local := clampf((appear * (1.0 + options.size() * 0.18) - index * 0.18), 0.0, 1.0)
		if local <= 0.0:
			continue
		var rect := row_rect(index)
		rect.position.x += (1.0 - local) * 34.0
		var selected := index == hover
		var cancel := index == options.size() - 1
		var box := StyleBoxFlat.new()
		box.bg_color = Color(HOVER if selected else BG, 0.95 * local)
		box.set_corner_radius_all(10)
		box.border_color = Color(RIM, (0.9 if selected else 0.3) * local)
		box.set_border_width_all(2)
		box.draw(get_canvas_item(), rect)
		var key_box := Rect2(rect.position + Vector2(10, 10), Vector2(24, 24))
		var key := StyleBoxFlat.new()
		key.bg_color = Color(HUB, local)
		key.set_corner_radius_all(6)
		key.draw(get_canvas_item(), key_box)
		draw_string(font, key_box.position + Vector2(0, 17), str(index + 1), HORIZONTAL_ALIGNMENT_CENTER, 24, 13, Color(MUTED, local))
		draw_string(font, rect.position + Vector2(46, 28), str(options[index][0]), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 56, 16, Color(MUTED if cancel and not selected else TEXT, local))
