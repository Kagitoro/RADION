class_name MainMenuScreen
extends Control
## Visual part of the main menu. MainMenu decides what the buttons do.

signal continue_pressed
signal quit_pressed
## Settings changed from the menu's settings panel (see SettingsBox).
signal level_changed(key: String, value: float)
signal language_changed(code: String)
signal graphics_changed(level: int)

const FOOTER := [["Enter","выбрать"],["↑↓","меню"],["Esc","назад"]]

@onready var continue_button: Button = %ContinueButton
@onready var settings: SettingsBox = %Settings

func _ready() -> void:
	var game_name := str(ProjectSettings.get_setting("application/config/name")).to_upper()
	%Title.text = game_name
	%Echo.text = game_name
	var version := str(ProjectSettings.get_setting("application/config/version",""))
	%Version.text = game_name if version.is_empty() else "v%s · %s" % [version,game_name]
	continue_button.pressed.connect(continue_pressed.emit)
	%QuitButton.pressed.connect(quit_pressed.emit)
	%SettingsButton.pressed.connect(func(): show_settings(not %SettingsPanel.visible))
	%BackButton.pressed.connect(func(): show_settings(false))
	settings.level_changed.connect(level_changed.emit)
	settings.language_changed.connect(language_changed.emit)
	settings.graphics_changed.connect(graphics_changed.emit)
	for button in [continue_button,%SettingsButton,%QuitButton,%BackButton]:
		MenuFx.light_on_focus(button)
	var footer: HBoxContainer = %Footer
	for hint in FOOTER:
		var cap := UIKit.keycap(str(hint[0]))
		cap.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		footer.add_child(cap)
		var caption := UIKit.label(str(hint[1]),13)
		caption.add_theme_color_override("font_color",UIKit.MUTED)
		footer.add_child(caption)
		var gap := Control.new()
		gap.custom_minimum_size.x = 10
		footer.add_child(gap)

## "Continue" for a returning player, "Start game" before the intro was seen.
func set_continue_label(has_progress: bool) -> void:
	continue_button.text = tr("Продолжить") if has_progress else tr("Начать игру")

func settings_open() -> bool:
	return %SettingsPanel.visible

func show_settings(open: bool) -> void:
	%SettingsPanel.visible = open
	if open:
		settings.sync()
		MenuFx.pop_in(%SettingsPanel)
		(settings.sliders["music"] as Control).grab_focus.call_deferred()
	else:
		%SettingsButton.grab_focus.call_deferred()

## Entrance: the shard and the column slide in from the left, the logo echo settles.
func play_intro() -> void:
	show_settings(false)
	var column: Control = %Column
	var shard: Control = %Shard
	var echo: Control = %Echo
	column.modulate.a = 0.0
	shard.modulate.a = 0.0
	var start := column.position.x
	column.position.x = start-60
	echo.position = Vector2(18,14)
	var motion := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	motion.tween_property(shard,"modulate:a",1.0,.45)
	motion.tween_property(column,"modulate:a",1.0,.4).set_delay(.1)
	motion.tween_property(column,"position:x",start,.5).set_delay(.1)
	motion.tween_property(echo,"position",Vector2(6,6),.6).set_delay(.25).set_trans(Tween.TRANS_BACK)
	continue_button.grab_focus.call_deferred()
