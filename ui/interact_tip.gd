class_name InteractTip
extends VBoxContainer
## Tip next to the crosshair for what the player looks at: the object's name and,
## under it, the keys that do something ("[E] Открыть", "[ЛКМ] Подойти к пульту").
## NightGame feeds it every hint tick with show_tip(name, "E · Открыть   C · FLX4").

const OFFSET := Vector2(30, -18)

var title: Label
var rows: VBoxContainer
var current := ""
var fade: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	# Pinned to the screen centre, growing right and down from just beside the crosshair.
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = OFFSET.x
	offset_top = OFFSET.y
	offset_right = OFFSET.x
	offset_bottom = OFFSET.y
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_END
	title = UIKit.title("", 17, UIKit.TEXT)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 6)
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(title)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rows)
	modulate.a = 0.0

## name: what it is (may be empty); text: "KEY · action" parts, split by 2+ spaces
## or new lines (the format the old bottom hint used).
func show_tip(name: String, text: String) -> void:
	var key := name + "|" + text
	if key == current:
		return
	current = key
	if name.is_empty() and text.is_empty():
		animate(0.0)
		return
	title.text = name
	title.visible = not name.is_empty()
	for child in rows.get_children():
		child.queue_free()
	for part in split_actions(text):
		rows.add_child(make_row(part))
	animate(1.0)

static func split_actions(text: String) -> Array:
	var parts := []
	for line in text.replace("\n", "   ").split("   ", false):
		if not line.strip_edges().is_empty():
			parts.append(line.strip_edges())
	return parts

func make_row(part: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pieces := part.split(" · ", false, 1)
	if pieces.size() == 2 and KeyHints.is_key(pieces[0].strip_edges()):
		var cap := UIKit.keycap(pieces[0].strip_edges(), 13)
		cap.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		row.add_child(cap)
		row.add_child(caption(pieces[1]))
	else:
		row.add_child(caption(part))
	return row

func caption(text: String) -> Label:
	var label := UIKit.label(text.strip_edges(), 14)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func animate(target: float) -> void:
	if is_instance_valid(fade):
		fade.kill()
	fade = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	fade.tween_property(self, "modulate:a", target, 0.12)
