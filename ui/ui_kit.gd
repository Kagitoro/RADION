class_name UIKit
extends RefCounted
## Small factory for the game's standard widgets. Static, so any system can build
## UI without holding a reference to the HUD. Colours match ui/theme.tres.

static func panel_style() -> StyleBoxFlat:
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

static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style())
	return p

static func label(text: String, font_size: int = 15) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_outline_color",Color("#172019"))
	node.add_theme_constant_override("outline_size",2)
	return node

static func button(text: String, action: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.pressed.connect(action)
	return node

static func anchor_fill(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## Rounded frame with a 1 px border, used by the DJ controller and laptop.
static func frame_style(fill: Color, border: Color, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(margin)
	return style
