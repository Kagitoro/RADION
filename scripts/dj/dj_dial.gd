class_name DJDial
extends Control
## Rotary knob (or jog wheel when jog = true) on the controller photo.

signal changed(value: float)
var value := 0.0
var dragging := false
var jog := false

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_DRAG

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if event.double_click and not jog:
				set_value(0.0)
			accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			adjust(.08 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -.08)
			accept_event()
	elif event is InputEventMouseMotion and dragging and event.button_mask&MOUSE_BUTTON_MASK_LEFT:
		adjust((event.relative.x-event.relative.y)*.009)
		accept_event()

func adjust(amount: float) -> void:
	if jog:
		value = wrapf(value+amount,-1.3158,1.3158)
		changed.emit(amount)
		queue_redraw()
	else:
		set_value(clampf(value+amount,-1,1))

func set_value(amount: float) -> void:
	value = amount
	changed.emit(value)
	queue_redraw()
