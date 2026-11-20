class_name ChatBox
extends CanvasLayer
## Co-op walk chat: recent lines in the lower-left corner (they fade after a
## while), Y opens the input line, Enter sends, Esc closes.

const VISIBLE_TIME := 9.0
const FADE_TIME := 1.5
const MAX_LINES := 8

var home: Node
var panel: VBoxContainer
var lines_box: VBoxContainer
var input: LineEdit
var typing := false

func _init(game_home: Node) -> void:
	home = game_home

func _ready() -> void:
	layer = 30
	panel = VBoxContainer.new()
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 16
	panel.offset_right = 476
	panel.offset_top = -330
	panel.offset_bottom = -110
	panel.alignment = BoxContainer.ALIGNMENT_END
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	lines_box = VBoxContainer.new()
	lines_box.alignment = BoxContainer.ALIGNMENT_END
	lines_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lines_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines_box.add_theme_constant_override("separation", 2)
	panel.add_child(lines_box)
	input = LineEdit.new()
	input.max_length = WalkSession.CHAT_LIMIT
	input.placeholder_text = tr("Сообщение… (Enter — отправить, Esc — закрыть)")
	input.hide()
	input.text_submitted.connect(submit)
	panel.add_child(input)
	for line in WalkSession.chat_log:
		add_line(str(line[0]), str(line[1]), bool(line[2]))
	WalkSession.chat_received.connect(add_line)

func _exit_tree() -> void:
	if WalkSession.chat_received.is_connected(add_line):
		WalkSession.chat_received.disconnect(add_line)

func add_line(author: String, text: String, system: bool) -> void:
	var label := RichTextLabel.new()
	label.bbcode_enabled = false
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", 15)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, .9))
	label.add_theme_constant_override("outline_size", 5)
	if system:
		label.push_color(Color("#ffd166"))
		label.add_text("• " + text)
	else:
		label.push_color(Color("#8fd3ff"))
		label.add_text(author + ": ")
		label.pop()
		label.push_color(Color.WHITE)
		label.add_text(text)
	label.pop()
	label.set_meta("age", 0.0)
	lines_box.add_child(label)
	while lines_box.get_child_count() > MAX_LINES:
		lines_box.get_child(0).free()

func _process(delta: float) -> void:
	for label: Control in lines_box.get_children():
		var age: float = label.get_meta("age") + delta
		label.set_meta("age", age)
		label.modulate.a = 1.0 if typing else clampf((VISIBLE_TIME + FADE_TIME - age) / FADE_TIME, 0.0, 1.0)

func _input(event: InputEvent) -> void:
	if typing:
		if event.is_action_pressed("ui_cancel"):
			close()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("chat") and not event.is_echo() and not home.modal:
		open()
		get_viewport().set_input_as_handled()

func open() -> void:
	typing = true
	home.set_modal(true)
	input.text = ""
	input.show()
	input.grab_focus.call_deferred()

func close() -> void:
	typing = false
	input.release_focus()
	input.hide()
	home.set_modal(false)

func submit(text: String) -> void:
	WalkSession.send_chat(text)
	close()
