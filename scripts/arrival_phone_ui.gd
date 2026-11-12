extends Node2D

enum Page { OFF, CALL, DECLINED, INBOX, THREAD, PLAYBACK }
const WIDTH := 360.0
const HEIGHT := 720.0
const PAPER := Color("#f6f7fb")
const INK := Color("#182033")
const SUBTLE := Color("#627086")
const BLUE := Color("#1c68dc")
const CONTACT := "Maya Chen"
var page := Page.OFF
var progress := 0.0
var transition := 0.0
var touch_point := Vector2.ZERO
var touch_amount := 0.0
var font := ThemeDB.fallback_font

func show_page(next: Page, played: float, tap: Vector2, touch: float, delta: float) -> void:
	if page != next:
		page = next
		transition = 1.0
	transition = move_toward(transition,0,delta*5.5)
	progress = played
	touch_point = tap
	touch_amount = touch
	queue_redraw()

func rounded(rect: Rect2, color: Color, radius: int) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	draw_style_box(style,rect)

func text_at(at: Vector2, value: String, size: int, color: Color, centered := false) -> void:
	if centered:
		at.x -= font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x*.5
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func avatar(at: Vector2, radius: float) -> void:
	draw_circle(at,radius,Color("#4963ad"),true,-1,true)
	text_at(at+Vector2(0,radius*.30),"MC",roundi(radius*.8),Color.WHITE,true)

func status_bar(dark: bool) -> void:
	var shade := Color("#f7f8ff") if dark else INK
	text_at(Vector2(27,42),"11:48",22,shade)
	rounded(Rect2(133,20,94,25),Color("#08090d"),13)
	for index in range(4):
		draw_rect(Rect2(276+index*6,41-index*4,4,4+index*4),shade)
	draw_rect(Rect2(308,26,25,14),shade,false,2)
	draw_rect(Rect2(311,29,18,8),shade)
	draw_rect(Rect2(334,30,3,6),shade)
	rounded(Rect2(120,693,120,6),shade,3)

func _draw() -> void:
	var dark := page in [Page.OFF,Page.CALL,Page.DECLINED]
	draw_rect(Rect2(0,0,WIDTH,HEIGHT),Color("#11192f") if dark else PAPER)
	status_bar(dark)
	if page == Page.OFF:
		return
	draw_set_transform(Vector2(15.0*transition*transition,0))
	match page:
		Page.CALL, Page.DECLINED:
			draw_call()
		Page.INBOX:
			draw_inbox()
		_:
			draw_thread()
	if touch_amount>.86:
		draw_set_transform(Vector2.ZERO)
		draw_arc(touch_point,23.0,0,TAU,30,Color(.48,.67,1,.42),3.0,true)

func draw_call() -> void:
	avatar(Vector2(180,151),49)
	text_at(Vector2(180,240),CONTACT,38,Color.WHITE,true)
	text_at(Vector2(180,276),"Booking · old club",23,Color("#b7c5e8"),true)
	text_at(Vector2(180,337),"Incoming call" if page==Page.CALL else "Call declined",25,Color("#d9e2fa"),true)
	if page==Page.DECLINED:
		rounded(Rect2(227,493,74,74),Color("#30b96b"),18)
		rounded(Rect2(244,514,40,26),Color.WHITE,10)
		draw_colored_polygon(PackedVector2Array([Vector2(250,534),Vector2(250,545),Vector2(263,535)]),Color.WHITE)
		text_at(Vector2(264,599),"Messages",21,Color.WHITE,true)
		return
	for x in [96,264]:
		var red: bool = x==264
		draw_circle(Vector2(x,550),40,Color("#f24753") if red else Color("#30b96b"),true,-1,true)
		handset(Vector2(x,550),red)
		text_at(Vector2(x,614),"Decline" if red else "Accept",21,Color.WHITE,true)

func handset(at: Vector2, down: bool) -> void:
	var points := PackedVector2Array()
	for point in [Vector2(-20,6),Vector2(-15,-3),Vector2(-7,-8),Vector2(7,-8),Vector2(15,-3),Vector2(20,6)]:
		points.append(at+point.rotated(0.0 if down else -.92))
	draw_polyline(points,Color.WHITE,7,true)
	for index in [0,points.size()-1]:
		draw_circle(points[index],6,Color.WHITE,true,-1,true)

func draw_inbox() -> void:
	text_at(Vector2(24,113),"Messages",43,INK)
	rounded(Rect2(24,139,312,43),Color("#e8ebf2"),14)
	text_at(Vector2(43,169),"Search",22,SUBTLE)
	rounded(Rect2(15,205,330,110),Color.WHITE,18)
	avatar(Vector2(55,258),25)
	text_at(Vector2(93,245),CONTACT,26,INK)
	text_at(Vector2(93,277),"Voice message · 0:06",21,SUBTLE)
	text_at(Vector2(302,247),"›",30,SUBTLE)
	draw_circle(Vector2(306,271),5,BLUE,true,-1,true)

func draw_thread() -> void:
	text_at(Vector2(23,110),"‹",40,BLUE)
	avatar(Vector2(180,104),26)
	text_at(Vector2(180,155),CONTACT,24,INK,true)
	text_at(Vector2(180,181),"Booking · old club",19,SUBTLE,true)
	draw_line(Vector2(22,199),Vector2(338,199),Color("#d8ddea"),1,true)
	text_at(Vector2(180,239),"Last month · 10:04 PM",19,SUBTLE,true)
	rounded(Rect2(23,263,291,83),Color("#e5e9f1"),17)
	text_at(Vector2(38,294),"You're on at eleven.",24,INK)
	text_at(Vector2(38,322),"Text me when you get here.",19,INK)
	rounded(Rect2(23,367,307,117),Color("#e5e9f1"),17)
	draw_circle(Vector2(282,413),23,BLUE,true,-1,true)
	if page==Page.PLAYBACK:
		draw_rect(Rect2(275,404,5,18),Color.WHITE)
		draw_rect(Rect2(284,404,5,18),Color.WHITE)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(276,403),Vector2(276,423),Vector2(293,413)]),Color.WHITE)
	for index in range(28):
		var height := 5.0+26.0*absf(sin(index*1.71)*cos(index*.57))
		var at := Vector2(44+index*7.1,413)
		var shade := BLUE if float(index)/27.0<=progress else Color("#9eaac0")
		draw_line(at-Vector2(0,height*.5),at+Vector2(0,height*.5),shade,3,true)
	text_at(Vector2(44,455),"Voice message" if page==Page.THREAD else "Playing",20,SUBTLE)
	rounded(Rect2(26,630,308,39),Color("#e8ebf2"),17)
	text_at(Vector2(43,657),"Message",21,SUBTLE)
