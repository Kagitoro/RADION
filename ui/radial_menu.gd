class_name RadialMenu
extends Control
## GTA-style wheel, open only while Tab is held. Root ring: inventory (top),
## actions (right), cancel (bottom), emotes (left). Inventory, actions and
## emotes open their own page with an animated swap; every entry shows an icon
## with its name underneath. LMB picks, RMB or the centre goes back, releasing
## Tab (or Esc) closes everything.

signal item_chosen(page: String, id: String)

const BG := Color(0.02, 0.03, 0.06)
## One solid disc (no gaps), thin separators, dark hub with a blue rim.
const DISC := Color(0.13, 0.16, 0.21, 0.94)
const DISC_HOVER := Color(0.25, 0.31, 0.40, 0.97)
const SEPARATOR := Color(1, 1, 1, 0.13)
const HUB := Color(0.05, 0.07, 0.10, 0.98)
const HUB_RIM := Color("#6f8fbf")
const TEXT := Color("#eef1ff")
const MUTED := Color("#8f9bc4")
const AMBER := Color("#ffb43c")
const PAGE_TITLES := {"root": "Меню", "inventory": "Инвентарь", "actions": "Действия", "emotes": "Эмоции"}

var game: Node
var page := "root"
## page -> Array of {id, label, icon, count (-1 none), enabled}
var pages := {}
var opened := false
## 0 closed .. 1 open (show / hide animation).
var appear := 0.0
## 0 just switched .. 1 settled (page swap animation).
var swap := 1.0
var hover := -1
var hover_glow: PackedFloat32Array = []
var motion: Tween
var swap_motion: Tween

func _init(night_game: Node) -> void:
	game = night_game
	hide()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func open(content: Dictionary) -> void:
	pages = content
	set_page("root", false)
	opened = true
	show()
	Input.warp_mouse(get_viewport_rect().size * 0.5)
	animate_to(1.0, 0.22, Tween.TRANS_BACK)

func close() -> void:
	if not opened:
		return
	opened = false
	animate_to(0.0, 0.14, Tween.TRANS_CUBIC)

func animate_to(target: float, time: float, transition: Tween.TransitionType) -> void:
	if is_instance_valid(motion):
		motion.kill()
	motion = create_tween().set_trans(transition).set_ease(Tween.EASE_OUT)
	motion.tween_method(func(value: float):
		appear = value
		queue_redraw(), appear, target, time)
	if target <= 0.0:
		motion.tween_callback(hide)

func set_page(name: String, animated := true) -> void:
	page = name
	hover = -1
	hover_glow.resize(items().size())
	hover_glow.fill(0.0)
	Input.warp_mouse(get_viewport_rect().size * 0.5)
	if is_instance_valid(swap_motion):
		swap_motion.kill()
	if not animated:
		swap = 1.0
		return
	swap_motion = create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	swap_motion.tween_method(func(value: float):
		swap = value
		queue_redraw(), 0.0, 1.0, 0.26)

func items() -> Array:
	return pages.get(page, [])

func grid() -> bool:
	return page == "inventory"

# --- geometry -----------------------------------------------------------------

func radius() -> float:
	return minf(240.0, minf(size.x, size.y) * 0.42)

func inner() -> float:
	return radius() * 0.42

func start_angle(count: int) -> float:
	return PI if count == 2 else -PI * 0.5

func sector_center(index: int, count: int) -> float:
	return start_angle(count) + index * TAU / count

func slot_rect(index: int) -> Rect2:
	var columns := 4
	var cell := Vector2(118, 122)
	var count := items().size()
	var rows := ceili(count / float(columns))
	var origin := size * 0.5 - Vector2(columns * cell.x, rows * cell.y) * 0.5
	return Rect2(origin + Vector2(index % columns, index / columns) * cell + Vector2(6, 6), cell - Vector2(12, 12))

func pick(point: Vector2) -> int:
	if grid():
		for index in items().size():
			if slot_rect(index).has_point(point):
				return index
		return -1
	var offset := point - size * 0.5
	var count := items().size()
	if count == 0 or offset.length() < inner():
		return -1
	var step := TAU / count
	return posmod(roundi((offset.angle() - start_angle(count)) / step), count)

# --- input --------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not opened:
		return
	if event.is_action_released("inventory") or event.is_action_pressed("pause"):
		finish()
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if not opened:
		return
	if event is InputEventMouseMotion:
		var next := pick(event.position)
		if next != hover:
			hover = next
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			choose(pick(event.position), event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			back()
		accept_event()

func choose(index: int, point: Vector2) -> void:
	if index < 0:
		# The hub: back from a page, close on the root ring.
		if grid() or (point - size * 0.5).length() < inner():
			back()
		return
	var item: Dictionary = items()[index]
	if not item.get("enabled", true):
		return
	var id := str(item.id)
	if page == "root":
		if id == "cancel":
			finish()
		elif pages.has(id):
			set_page(id)
		else:
			# A root entry without a page (Инвентарь opens the inventory panel).
			item_chosen.emit(page, id)
			finish()
		return
	item_chosen.emit(page, id)
	finish()

func back() -> void:
	if page == "root":
		finish()
	else:
		set_page("root")

func finish() -> void:
	close()
	game.radial_closed()

# --- drawing ------------------------------------------------------------------

func _process(delta: float) -> void:
	if not visible:
		return
	var changed := false
	for index in hover_glow.size():
		var target := 1.0 if index == hover else 0.0
		var value := move_toward(hover_glow[index], target, delta * 7.0)
		if value != hover_glow[index]:
			hover_glow[index] = value
			changed = true
	if changed:
		queue_redraw()

func _draw() -> void:
	var eased := clampf(appear, 0.0, 1.2)
	var alpha := clampf(appear, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(BG, 0.45 * alpha))
	var center := size * 0.5
	var scale_in := lerpf(0.72, 1.0, eased) * lerpf(0.86, 1.0, swap)
	var spin := lerpf(-0.35, 0.0, swap) if page != "root" else lerpf(0.25, 0.0, swap)
	var fade := alpha * lerpf(0.0, 1.0, swap)
	draw_set_transform(center, spin, Vector2.ONE * scale_in)
	if grid():
		draw_set_transform(center, 0.0, Vector2.ONE * scale_in)
		draw_grid(fade)
	else:
		draw_ring(fade)
	draw_set_transform(Vector2.ZERO)

func draw_ring(alpha: float) -> void:
	var list := items()
	var count := list.size()
	var outer := radius()
	var hole := inner()
	var font := get_theme_default_font()
	var step := TAU / maxf(count, 1)
	# Base disc, then the hovered sector lit on top of it.
	draw_circle(Vector2.ZERO, outer, Color(DISC, DISC.a * alpha))
	for index in count:
		var glow := hover_glow[index] if index < hover_glow.size() else 0.0
		if glow <= 0.01:
			continue
		var mid := sector_center(index, count)
		var points := PackedVector2Array()
		for i in 33:
			points.append(Vector2.from_angle(mid + lerpf(-step * 0.5, step * 0.5, i / 32.0)) * outer)
		for i in range(32, -1, -1):
			points.append(Vector2.from_angle(mid + lerpf(-step * 0.5, step * 0.5, i / 32.0)) * hole)
		draw_colored_polygon(points, Color(DISC_HOVER, DISC_HOVER.a * glow * alpha))
	if count > 1:
		for index in count:
			var edge := sector_center(index, count) + step * 0.5
			draw_line(Vector2.from_angle(edge) * hole, Vector2.from_angle(edge) * outer, Color(SEPARATOR, SEPARATOR.a * alpha), 1.0, true)
	draw_arc(Vector2.ZERO, outer, 0.0, TAU, 96, Color(1, 1, 1, 0.08 * alpha), 2.0, true)
	for index in count:
		var item: Dictionary = list[index]
		var glow := hover_glow[index] if index < hover_glow.size() else 0.0
		var spot := Vector2.from_angle(sector_center(index, count)) * lerpf(hole, outer, 0.56)
		var enabled: bool = item.get("enabled", true)
		var tint := Color(TEXT if enabled else MUTED, alpha * (1.0 if enabled else 0.55))
		var lift := glow * 3.0
		draw_icon(str(item.icon), spot + Vector2(0, -16 - lift), 36.0 + glow * 4.0, tint)
		var label := tr(str(item.label))
		draw_string(font, spot + Vector2(-80, 30 - lift), label, HORIZONTAL_ALIGNMENT_CENTER, 160, 14, tint)
		var count_value := int(item.get("count", -1))
		if count_value >= 0:
			draw_string(font, spot + Vector2(-80, 47 - lift), "× %d" % count_value, HORIZONTAL_ALIGNMENT_CENTER, 160, 12, Color(MUTED, alpha))
	draw_hub(hole, alpha, list)

## Dark centre with a blue rim: page name, and the hovered entry under it.
func draw_hub(hole: float, alpha: float, list: Array) -> void:
	var font := get_theme_default_font()
	draw_circle(Vector2.ZERO, hole, Color(HUB, HUB.a * alpha))
	draw_arc(Vector2.ZERO, hole, 0.0, TAU, 72, Color(HUB_RIM, alpha), 6.0, true)
	var heading := tr(str(PAGE_TITLES.get(page, page))).to_upper()
	draw_string(font, Vector2(-hole, 2), heading, HORIZONTAL_ALIGNMENT_CENTER, hole * 2.0, 19, Color(TEXT, alpha))
	var sub := ""
	if hover >= 0 and hover < list.size():
		sub = tr(str(list[hover].label))
	elif page != "root":
		sub = tr("ПКМ — назад")
	if not sub.is_empty():
		draw_string(font, Vector2(-hole + 8, 26), sub, HORIZONTAL_ALIGNMENT_CENTER, hole * 2.0 - 16, 13, Color(AMBER if hover >= 0 else MUTED, alpha))

func draw_grid(alpha: float) -> void:
	var font := get_theme_default_font()
	var list := items()
	var center := size * 0.5
	var first := slot_rect(0)
	var last := slot_rect(list.size() - 1)
	var panel := Rect2(first.position - center - Vector2(22, 58), Vector2(last.end.x - first.position.x + 44, last.end.y - first.position.y + 104))
	var back := StyleBoxFlat.new()
	back.bg_color = Color(DISC, DISC.a * alpha)
	back.set_corner_radius_all(18)
	back.border_color = Color(HUB_RIM, 0.55 * alpha)
	back.border_width_top = 3
	back.draw(get_canvas_item(), panel)
	draw_string(font, Vector2(panel.position.x, panel.position.y + 36), tr("ИНВЕНТАРЬ"), HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 19, Color(TEXT, alpha))
	for index in list.size():
		var item: Dictionary = list[index]
		var rect := slot_rect(index)
		rect.position -= center
		var glow := hover_glow[index] if index < hover_glow.size() else 0.0
		rect = rect.grow(glow * 3.0)
		var enabled: bool = item.get("enabled", true)
		var slot := StyleBoxFlat.new()
		slot.bg_color = Color(HUB.lerp(DISC_HOVER, glow), 0.95 * alpha)
		slot.set_corner_radius_all(12)
		slot.border_color = Color(HUB_RIM, (0.25 + glow * 0.75) * alpha)
		slot.set_border_width_all(2)
		slot.draw(get_canvas_item(), rect)
		var tint := Color(TEXT if enabled else MUTED, alpha * (1.0 if enabled else 0.55))
		draw_icon(str(item.icon), rect.get_center() + Vector2(0, -14), 38.0, tint)
		draw_string(font, Vector2(rect.position.x, rect.end.y - 14), tr(str(item.label)), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 13, tint)
		var count_value := int(item.get("count", -1))
		if count_value >= 0:
			draw_string(font, rect.position + Vector2(0, 20), "%d " % count_value, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 8, 14, Color(AMBER if count_value > 0 else MUTED, alpha))
	draw_string(font, Vector2(panel.position.x, panel.end.y - 16), tr("ЛКМ — использовать · ПКМ — назад"), HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 12, Color(MUTED, alpha))

## Small line-art icons, so the wheel needs no image files.
func draw_icon(id: String, at: Vector2, side: float, color: Color) -> void:
	var s := side / 32.0
	var w := 2.4 * s
	match id:
		"inventory":
			draw_rect(Rect2(at + Vector2(-12, -6) * s, Vector2(24, 20) * s), color, false, w)
			draw_arc(at + Vector2(0, -6) * s, 7 * s, PI, TAU, 12, color, w)
			draw_line(at + Vector2(-12, 2) * s, at + Vector2(12, 2) * s, color, w)
		"actions":
			draw_polyline(PackedVector2Array([at + Vector2(3, -15) * s, at + Vector2(-7, 2) * s, at + Vector2(1, 2) * s, at + Vector2(-3, 15) * s, at + Vector2(8, -3) * s, at + Vector2(0, -3) * s, at + Vector2(3, -15) * s]), color, w)
		"emotes":
			draw_arc(at, 13 * s, 0, TAU, 32, color, w)
			draw_circle(at + Vector2(-5, -4) * s, 2 * s, color)
			draw_circle(at + Vector2(5, -4) * s, 2 * s, color)
			draw_arc(at + Vector2(0, 1) * s, 7 * s, 0.35, PI - 0.35, 12, color, w)
		"cancel":
			draw_line(at + Vector2(-10, -10) * s, at + Vector2(10, 10) * s, color, w * 1.3)
			draw_line(at + Vector2(10, -10) * s, at + Vector2(-10, 10) * s, color, w * 1.3)
		"back":
			draw_line(at + Vector2(12, 0) * s, at + Vector2(-10, 0) * s, color, w)
			draw_polyline(PackedVector2Array([at + Vector2(-2, -8) * s, at + Vector2(-11, 0) * s, at + Vector2(-2, 8) * s]), color, w)
		"pee":
			draw_arc(at + Vector2(0, 4) * s, 9 * s, -0.2, PI + 0.2, 16, color, w)
			draw_line(at + Vector2(-8.8, 2.2) * s, at + Vector2(0, -14) * s, color, w)
			draw_line(at + Vector2(8.8, 2.2) * s, at + Vector2(0, -14) * s, color, w)
		"party":
			draw_circle(at + Vector2(-6, 9) * s, 5 * s, color)
			draw_line(at + Vector2(-1.5, 9) * s, at + Vector2(-1.5, -13) * s, color, w)
			draw_line(at + Vector2(-1.5, -13) * s, at + Vector2(10, -8) * s, color, w)
			draw_line(at + Vector2(-1.5, -7) * s, at + Vector2(10, -2) * s, color, w)
		"beer":
			draw_rect(Rect2(at + Vector2(-10, -10) * s, Vector2(16, 22) * s), color, false, w)
			draw_arc(at + Vector2(6, 1) * s, 6 * s, -PI * 0.5, PI * 0.5, 10, color, w)
			draw_line(at + Vector2(-10, -5) * s, at + Vector2(6, -5) * s, color, w)
		"energy":
			draw_rect(Rect2(at + Vector2(-8, -13) * s, Vector2(16, 26) * s), color, false, w)
			draw_polyline(PackedVector2Array([at + Vector2(2, -7) * s, at + Vector2(-3, 1) * s, at + Vector2(2, 1) * s, at + Vector2(-2, 8) * s]), color, w)
		"cigarettes":
			draw_rect(Rect2(at + Vector2(-10, -12) * s, Vector2(20, 24) * s), color, false, w)
			draw_rect(Rect2(at + Vector2(-10, -12) * s, Vector2(20, 7) * s), color)
			draw_line(at + Vector2(-4, -12) * s, at + Vector2(-4, -17) * s, color, w)
		"lighter":
			draw_rect(Rect2(at + Vector2(-6, -4) * s, Vector2(12, 18) * s), color, false, w)
			draw_arc(at + Vector2(0, -9) * s, 4 * s, PI * 0.2, PI * 1.8, 10, color, w)
		"hand_up":
			draw_line(at + Vector2(0, 15) * s, at + Vector2(0, -2) * s, color, w * 1.5)
			draw_circle(at + Vector2(0, -7) * s, 6 * s, color)
		"beat":
			draw_arc(at, 12 * s, -PI * 0.8, -PI * 0.2, 12, color, w)
			draw_arc(at, 7 * s, -PI * 0.8, -PI * 0.2, 12, color, w)
			draw_circle(at + Vector2(0, 6) * s, 3 * s, color)
		"clap":
			draw_rect(Rect2(at + Vector2(-11, -10) * s, Vector2(8, 18) * s), color, false, w)
			draw_rect(Rect2(at + Vector2(3, -10) * s, Vector2(8, 18) * s), color, false, w)
			draw_line(at + Vector2(-2, -14) * s, at + Vector2(-5, -18) * s, color, w)
			draw_line(at + Vector2(2, -14) * s, at + Vector2(5, -18) * s, color, w)
		"drop":
			draw_line(at + Vector2(0, -13) * s, at + Vector2(0, 11) * s, color, w)
			draw_polyline(PackedVector2Array([at + Vector2(-8, 3) * s, at + Vector2(0, 12) * s, at + Vector2(8, 3) * s]), color, w)
		_:
			draw_circle(at, 4 * s, color)
