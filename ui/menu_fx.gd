class_name MenuFx
extends RefCounted
## Small motion helpers shared by the menus.

## A focused button looks exactly like a hovered one, and hovering moves the focus,
## so mouse and keyboard/gamepad always agree on which entry is lit.
static func light_on_focus(button: Button) -> void:
	button.focus_entered.connect(func():
		for state in ["normal","hover"]:
			button.add_theme_stylebox_override(state,button.get_theme_stylebox("hover"))
		button.add_theme_color_override("font_color",button.get_theme_color("font_hover_color"))
		button.add_theme_color_override("font_focus_color",button.get_theme_color("font_hover_color"))
		nudge(button)
	)
	button.focus_exited.connect(func():
		for state in ["normal","hover"]:
			button.remove_theme_stylebox_override(state)
		button.remove_theme_color_override("font_color")
		button.remove_theme_color_override("font_focus_color")
	)
	button.mouse_entered.connect(func():
		if not button.disabled:
			button.grab_focus()
	)

## A short sideways kick when an entry lights up.
static func nudge(control: Control) -> void:
	var motion := control.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	control.pivot_offset = control.size*Vector2(0,.5)
	control.scale = Vector2(1.035,1.035)
	motion.tween_property(control,"scale",Vector2.ONE,.22)

## Window appears: fades in and settles from a slightly smaller, lower position.
static func pop_in(control: Control) -> void:
	control.pivot_offset = control.size*.5
	control.modulate.a = 0.0
	control.scale = Vector2(.96,.96)
	var motion := control.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	motion.tween_property(control,"modulate:a",1.0,.18)
	motion.tween_property(control,"scale",Vector2.ONE,.26)
