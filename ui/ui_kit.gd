class_name UIKit
extends RefCounted
## The game's low-poly UI kit: palette, faceted styles, fonts and small widget
## factories. Static, so any system can build UI without holding the HUD.
## `build_theme()` produces ui/theme.tres (run tools/build_ui_theme.gd after edits);
## the theme is the project default, so plain Controls already look right.

# --- palette ---------------------------------------------------------------------
# Night-club colours: inky blues for surfaces, warm amber as the main accent,
# neon pink and cyan for highlights. Facets are drawn with darker "under" tones.
const INK := Color("#090c17")
const NIGHT := Color("#121829")
const DUSK := Color("#1b2340")
const RAISED := Color("#25305a")
const EDGE := Color("#34427a")
const AMBER := Color("#ffb43c")
const AMBER_DEEP := Color("#c97a12")
const PINK := Color("#ff4f9a")
const CYAN := Color("#43e0ff")
const TEXT := Color("#eef1ff")
const MUTED := Color("#8f9bc4")
const GOOD := Color("#6fe39a")
const BAD := Color("#ff5d6c")

## Chamfer size (px) of panels and buttons: corners are cut at 45°, never rounded.
const CUT := 10
const CUT_SMALL := 6

const DISPLAY_FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")

# --- styles ----------------------------------------------------------------------

## A flat faceted box: chamfered corners and a thicker darker bottom edge, like
## the lit top and shaded side of a low-poly slab.
static func facet(fill: Color, edge: Color, cut := CUT, under := 0, margin := Vector4(14,10,14,10)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(2)
	if under>0:
		style.border_width_bottom = under
	style.set_corner_radius_all(cut)
	# One segment per corner: a straight cut instead of a curve.
	style.corner_detail = 1
	style.anti_aliasing = true
	style.content_margin_left = margin.x
	style.content_margin_top = margin.y
	style.content_margin_right = margin.z
	style.content_margin_bottom = margin.w
	return style

static func panel_style() -> StyleBoxFlat:
	var style := facet(Color(NIGHT,.95),EDGE,CUT,4)
	style.border_color = EDGE
	return style

## Accent-edged panel for windows that need attention (shop, inventory, pause).
static func window_style() -> StyleBoxFlat:
	var style := facet(Color(NIGHT,.97),EDGE,14,5,Vector4(22,18,22,18))
	style.border_width_top = 3
	style.border_color = EDGE
	return style

static func button_style(fill: Color, edge: Color, under := 4, cut := CUT_SMALL) -> StyleBoxFlat:
	return facet(fill,edge,cut,under,Vector4(16,7,16,7))

## Small chip used by HUD labels: dark fill with a coloured bar on the left.
static func chip_style(accent: Color, alpha := .82) -> StyleBoxFlat:
	var style := facet(Color(INK,alpha),Color(accent,.0),CUT_SMALL,0,Vector4(14,5,14,6))
	style.set_border_width_all(0)
	style.border_width_left = 4
	style.border_color = accent
	return style

## Keyboard key cap for hints: light top facet, deep bottom edge.
static func keycap_style() -> StyleBoxFlat:
	var style := facet(RAISED,EDGE,4,4,Vector4(7,1,7,3))
	style.border_color = Color("#0d1122")
	style.border_width_top = 1
	style.border_width_left = 1
	style.border_width_right = 1
	return style

## Rounded frame with a 1 px border, used by the DJ controller and laptop.
static func frame_style(fill: Color, border: Color, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.corner_detail = 1
	style.set_content_margin_all(margin)
	return style

# --- widgets ---------------------------------------------------------------------

static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style())
	return p

static func label(text: String, font_size: int = 15) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	return node

## Heading in the display font.
static func title(text: String, font_size: int = 26, color := TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.theme_type_variation = &"DisplayLabel"
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	return node

static func button(text: String, action: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.pressed.connect(action)
	return node

## A key cap ("E", "Tab", "ЛКМ") for control hints.
static func keycap(key: String, font_size := 13) -> Label:
	var cap := Label.new()
	cap.text = key
	cap.theme_type_variation = &"KeyCap"
	cap.add_theme_font_size_override("font_size", font_size)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.custom_minimum_size.x = 26
	return cap

static func anchor_fill(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## Tiny diamond (a low-poly "dot") used for slider grabbers and bullets.
static func diamond_texture(size: int, fill: Color, edge: Color) -> ImageTexture:
	var image := Image.create(size,size,false,Image.FORMAT_RGBA8)
	var half := (size-1)*.5
	for y in range(size):
		for x in range(size):
			var d := absf(x-half)+absf(y-half)
			if d<=half-1.5:
				image.set_pixel(x,y,fill if x+y<size else fill.darkened(.25))
			elif d<=half:
				image.set_pixel(x,y,edge)
	return ImageTexture.create_from_image(image)

# --- theme -----------------------------------------------------------------------

static func build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 15
	var display := DISPLAY_FONT

	theme.set_stylebox("panel","PanelContainer",panel_style())
	theme.set_stylebox("panel","Panel",panel_style())

	theme.set_color("font_color","Label",TEXT)
	theme.set_color("font_outline_color","Label",INK)
	theme.set_constant("outline_size","Label",3)

	theme.add_type("DisplayLabel")
	theme.set_type_variation("DisplayLabel","Label")
	theme.set_font("font","DisplayLabel",display)
	theme.set_constant("outline_size","DisplayLabel",0)
	theme.set_color("font_shadow_color","DisplayLabel",Color(INK,.9))
	theme.set_constant("shadow_offset_x","DisplayLabel",0)
	theme.set_constant("shadow_offset_y","DisplayLabel",3)

	theme.add_type("KeyCap")
	theme.set_type_variation("KeyCap","Label")
	theme.set_font("font","KeyCap",display)
	theme.set_stylebox("normal","KeyCap",keycap_style())
	theme.set_color("font_color","KeyCap",TEXT)
	theme.set_constant("outline_size","KeyCap",0)

	theme.add_type("HudBadge")
	theme.set_type_variation("HudBadge","Label")
	theme.set_font("font","HudBadge",display)
	theme.set_stylebox("normal","HudBadge",chip_style(AMBER))
	theme.set_constant("outline_size","HudBadge",0)
	theme.add_type("HudNotice")
	theme.set_type_variation("HudNotice","Label")
	theme.set_stylebox("normal","HudNotice",chip_style(PINK,.88))
	theme.set_constant("outline_size","HudNotice",0)
	theme.add_type("HudObjective")
	theme.set_type_variation("HudObjective","Label")
	theme.set_stylebox("normal","HudObjective",chip_style(CYAN,.7))
	theme.set_constant("outline_size","HudObjective",0)

	# Buttons: slab on the dark side, flipping to amber when hovered or focused.
	var normal := button_style(DUSK,EDGE)
	var hover := button_style(AMBER,AMBER_DEEP)
	var pressed := button_style(AMBER_DEEP,AMBER_DEEP,2)
	pressed.content_margin_top += 2
	var disabled := button_style(Color(NIGHT,.8),Color(EDGE,.5))
	var focus := button_style(Color(0,0,0,0),AMBER,2)
	focus.draw_center = false
	focus.expand_margin_left = 2
	focus.expand_margin_right = 2
	focus.expand_margin_top = 2
	focus.expand_margin_bottom = 2
	for type in ["Button","OptionButton","MenuButton"]:
		theme.set_stylebox("normal",type,normal)
		theme.set_stylebox("hover",type,hover)
		theme.set_stylebox("pressed",type,pressed)
		theme.set_stylebox("hover_pressed",type,pressed)
		theme.set_stylebox("disabled",type,disabled)
		theme.set_stylebox("focus",type,focus)
		theme.set_font("font",type,display)
		theme.set_font_size("font_size",type,15)
		theme.set_color("font_color",type,TEXT)
		theme.set_color("font_hover_color",type,INK)
		theme.set_color("font_focus_color",type,TEXT)
		theme.set_color("font_pressed_color",type,INK)
		theme.set_color("font_hover_pressed_color",type,INK)
		theme.set_color("font_disabled_color",type,MUTED.darkened(.3))
		theme.set_color("icon_hover_color",type,INK)
		theme.set_constant("outline_size",type,0)
	# Big menu buttons (main menu, pause): taller, left-aligned, slanted.
	theme.add_type("MenuButtonBig")
	theme.set_type_variation("MenuButtonBig","Button")
	# A thick left facet (slate at rest, deep amber when lit) reads as an extruded edge.
	for state in ["normal","hover","pressed","hover_pressed","disabled"]:
		var base := theme.get_stylebox(state,"Button").duplicate() as StyleBoxFlat
		base.skew = Vector2(-.2,0)
		base.content_margin_left = 30
		base.content_margin_top = 10
		base.content_margin_bottom = 12
		base.border_width_left = 7
		if state=="normal":
			base.bg_color = Color(DUSK,.92)
			base.border_color = EDGE
		theme.set_stylebox(state,"MenuButtonBig",base)
	theme.set_font_size("font_size","MenuButtonBig",21)
	# A focused big button looks hovered, so the keyboard/gamepad cursor is obvious.
	theme.set_stylebox("focus","MenuButtonBig",StyleBoxEmpty.new())
	theme.set_color("font_focus_color","MenuButtonBig",TEXT)

	# Text fields and lists.
	var field := facet(INK,EDGE,CUT_SMALL,2,Vector4(10,6,10,6))
	var field_focus := facet(INK,AMBER,CUT_SMALL,2,Vector4(10,6,10,6))
	theme.set_stylebox("normal","LineEdit",field)
	theme.set_stylebox("focus","LineEdit",field_focus)
	theme.set_stylebox("read_only","LineEdit",field)
	theme.set_color("font_color","LineEdit",TEXT)
	theme.set_color("caret_color","LineEdit",AMBER)
	theme.set_color("selection_color","LineEdit",Color(AMBER,.35))
	theme.set_stylebox("panel","ItemList",field)
	theme.set_stylebox("focus","ItemList",StyleBoxEmpty.new())
	theme.set_stylebox("selected","ItemList",facet(Color(AMBER,.85),AMBER,4,0,Vector4(4,2,4,2)))
	theme.set_stylebox("selected_focus","ItemList",facet(AMBER,AMBER,4,0,Vector4(4,2,4,2)))
	theme.set_stylebox("hovered","ItemList",facet(RAISED,RAISED,4,0,Vector4(4,2,4,2)))
	theme.set_color("font_selected_color","ItemList",INK)
	theme.set_color("font_hovered_color","ItemList",TEXT)

	# Popups (option lists, confirm dialogs) and tooltips.
	var popup := facet(Color(NIGHT,.98),EDGE,CUT_SMALL,3,Vector4(8,8,8,8))
	theme.set_stylebox("panel","PopupMenu",popup)
	theme.set_stylebox("hover","PopupMenu",facet(AMBER,AMBER,4,0,Vector4(6,2,6,2)))
	theme.set_color("font_hover_color","PopupMenu",INK)
	theme.set_color("font_color","PopupMenu",TEXT)
	theme.set_stylebox("panel","PopupPanel",popup)
	theme.set_stylebox("panel","TooltipPanel",facet(INK,AMBER,4,2,Vector4(8,4,8,5)))
	theme.set_stylebox("embedded_border","Window",window_style())
	theme.set_stylebox("embedded_unfocused_border","Window",window_style())
	theme.set_color("title_color","Window",AMBER)
	theme.set_font("title_font","Window",display)
	theme.set_stylebox("panel","AcceptDialog",facet(Color(NIGHT,.98),EDGE,CUT,0,Vector4(14,12,14,12)))

	# Sliders: a cut groove filled with amber and a diamond grabber.
	var groove := facet(INK,EDGE,3,1,Vector4(0,3,0,3))
	var filled := facet(AMBER,AMBER_DEEP,3,1,Vector4(0,3,0,3))
	theme.set_stylebox("slider","HSlider",groove)
	theme.set_stylebox("grabber_area","HSlider",filled)
	theme.set_stylebox("grabber_area_highlight","HSlider",filled)
	theme.set_icon("grabber","HSlider",diamond_texture(18,TEXT,INK))
	theme.set_icon("grabber_highlight","HSlider",diamond_texture(18,AMBER,INK))
	theme.set_stylebox("background","ProgressBar",groove)
	theme.set_stylebox("fill","ProgressBar",filled)
	theme.set_color("font_color","ProgressBar",TEXT)

	# Scroll bars: thin slabs.
	for type in ["VScrollBar","HScrollBar"]:
		theme.set_stylebox("scroll",type,facet(Color(INK,.6),Color(INK,0),3,0,Vector4(3,3,3,3)))
		theme.set_stylebox("grabber",type,facet(EDGE,EDGE,3,0,Vector4(3,3,3,3)))
		theme.set_stylebox("grabber_highlight",type,facet(AMBER,AMBER,3,0,Vector4(3,3,3,3)))
		theme.set_stylebox("grabber_pressed",type,facet(AMBER_DEEP,AMBER_DEEP,3,0,Vector4(3,3,3,3)))

	# Tabs.
	theme.set_stylebox("tab_selected","TabBar",button_style(AMBER,AMBER_DEEP,3,4))
	theme.set_stylebox("tab_unselected","TabBar",button_style(DUSK,EDGE,3,4))
	theme.set_stylebox("tab_hovered","TabBar",button_style(RAISED,EDGE,3,4))
	theme.set_color("font_selected_color","TabBar",INK)
	theme.set_color("font_unselected_color","TabBar",TEXT)
	theme.set_font("font","TabBar",display)
	theme.set_stylebox("tab_selected","TabContainer",button_style(AMBER,AMBER_DEEP,3,4))
	theme.set_stylebox("tab_unselected","TabContainer",button_style(DUSK,EDGE,3,4))
	theme.set_stylebox("tab_hovered","TabContainer",button_style(RAISED,EDGE,3,4))
	theme.set_stylebox("panel","TabContainer",panel_style())
	theme.set_color("font_selected_color","TabContainer",INK)
	theme.set_font("font","TabContainer",display)

	# Check boxes and buttons keep the default icons, coloured to match.
	for type in ["CheckBox","CheckButton"]:
		theme.set_stylebox("normal",type,StyleBoxEmpty.new())
		theme.set_stylebox("hover",type,facet(Color(RAISED,.6),Color(0,0,0,0),4,0,Vector4(4,2,4,2)))
		theme.set_stylebox("pressed",type,StyleBoxEmpty.new())
		theme.set_stylebox("focus",type,StyleBoxEmpty.new())
		theme.set_color("font_color",type,TEXT)
		theme.set_color("font_hover_color",type,AMBER)
		theme.set_color("font_pressed_color",type,TEXT)
	return theme
