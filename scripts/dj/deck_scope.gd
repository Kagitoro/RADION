class_name DeckScope
extends Control
## Waveform strip that shows the last audio samples of a deck.

var samples := PackedVector2Array()

func _ready() -> void:
	custom_minimum_size.y = maxf(68,custom_minimum_size.y)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var middle := size.y*.5
	draw_line(Vector2(0,middle),Vector2(size.x,middle),Color("#24465d"))
	if samples.is_empty():
		return
	for column in range(100):
		var peak := 0.0
		var first := column*samples.size()/100
		var last := (column+1)*samples.size()/100
		for index in range(first,last):
			peak = maxf(peak,maxf(absf(samples[index].x),absf(samples[index].y)))
		var fraction := float(column)/99.0
		var x := fraction*size.x
		var height := clampf(peak*5.5,.01,1)*middle
		var tint := Color("#48cafa").lerp(Color("#e374ff"),fraction)
		draw_line(Vector2(x,middle-height),Vector2(x,middle+height),tint,2,true)
