class_name LowPolyEqualizer
extends Control
## A DJ-style level meter made of chamfered blocks; bars bounce to a fake beat.
## Purely decorative (main menu, inventory header).

@export var bars := 16
@export var blocks := 9
@export var low_color := Color("#ffb43c")
@export var high_color := Color("#ff4f9a")
@export var tempo := 124.0
@export_range(0.0, 1.0) var opacity := .9

var levels: PackedFloat32Array = []
var clock := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	levels.resize(bars)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	clock += delta
	var beat := fmod(clock*tempo/60.0,1.0)
	var kick := pow(1.0-beat,3.0)
	for index in bars:
		var wave := .5+.5*sin(clock*(1.3+index*.37)+index*1.7)
		var target := clampf(.18+wave*.5+kick*(.45 if index<bars/3 else .25),0.0,1.0)
		# Fast attack, slow fall, like a real meter.
		levels[index] = target if target>levels[index] else move_toward(levels[index],target,delta*1.6)
	queue_redraw()

func _draw() -> void:
	var gap := 4.0
	var width := (size.x-gap*(bars-1))/bars
	var block := (size.y-gap*(blocks-1))/blocks
	var cut := minf(width,block)*.28
	for index in bars:
		var lit := int(round(levels[index]*blocks))
		for step in blocks:
			var x := index*(width+gap)
			var y := size.y-(step+1)*block-step*gap
			var color := low_color.lerp(high_color,float(step)/maxf(blocks-1,1))
			color.a = opacity if step<lit else opacity*.12
			draw_colored_polygon(PackedVector2Array([
				Vector2(x+cut,y),Vector2(x+width,y),Vector2(x+width,y+block-cut),
				Vector2(x+width-cut,y+block),Vector2(x,y+block),Vector2(x,y+cut),
			]),color)
