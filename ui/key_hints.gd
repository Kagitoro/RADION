class_name KeyHints
extends HBoxContainer
## Control hints as key caps: "WASD идти · Shift быстрее · Esc пауза" becomes
## [WASD] идти  [Shift] быстрее  [Esc] пауза. A part whose first word looks like a
## key (see is_key) is read as "key + action"; anything else stays plain text.
## Set `text` like on a Label (already translated).

var text := "":
	set(value):
		if value==text:
			return
		text = value
		rebuild()

func _ready() -> void:
	add_theme_constant_override("separation",6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	var first := true
	for part in text.split(" · ",false):
		if not first:
			var gap := Control.new()
			gap.custom_minimum_size.x = 8
			add_child(gap)
		first = false
		var words := part.strip_edges().split(" ",false,1)
		if words.size()==2 and is_key(words[0]):
			var cap := UIKit.keycap(words[0],12)
			cap.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			add_child(cap)
			add_child(caption(words[1]))
		else:
			add_child(caption(part.strip_edges()))

## "E", "WASD", "Shift", "Ctrl+S", "R/T/X/H", "ЛКМ", "1–3": starts with a capital
## or a digit and has no lowercase Cyrillic (Russian words are actions, not keys).
static func is_key(word: String) -> bool:
	if word.is_empty() or word.length()>12:
		return false
	var head := word.substr(0,1)
	if head!=head.to_upper() and not head.is_valid_int():
		return false
	for letter in word:
		if letter>="а" and letter<="я" or letter=="ё":
			return false
	return true

func caption(value: String) -> Label:
	var label := UIKit.label(value,13)
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_color_override("font_color",UIKit.TEXT)
	label.add_theme_constant_override("outline_size",4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
