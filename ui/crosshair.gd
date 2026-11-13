class_name Crosshair
extends Control
## Low-poly crosshair: a small diamond with a dark rim, tinted through `modulate`
## (the HUD greens it over things that can be picked up). It swells briefly when
## the target changes (`pulse`).

const SIZE := 22.0
var swell := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIZE,SIZE)
	size = Vector2(SIZE,SIZE)

func pulse() -> void:
	swell = 1.0
	set_process(true)

func _process(delta: float) -> void:
	swell = move_toward(swell,0.0,delta*5.0)
	queue_redraw()
	if swell<=0.0:
		set_process(false)

func _draw() -> void:
	var center := size*.5
	var outer := 5.0+swell*3.0
	var inner := 3.0+swell*1.5
	draw_colored_polygon(diamond(center,outer),Color(UIKit.INK,.85))
	draw_colored_polygon(diamond(center,inner),Color.WHITE)
	# A brighter top-left facet gives the diamond its low-poly bevel.
	draw_colored_polygon(PackedVector2Array([center+Vector2(0,-inner),center+Vector2(-inner,0),center]),Color(1,1,1,.55).lerp(UIKit.AMBER,.35))

static func diamond(center: Vector2, radius: float) -> PackedVector2Array:
	return PackedVector2Array([center+Vector2(0,-radius),center+Vector2(radius,0),center+Vector2(0,radius),center+Vector2(-radius,0)])
