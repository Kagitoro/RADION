class_name PauseMenu
extends Control
## Pause overlay for the night game. It only reports what the player chose;
## NightGame decides what each choice does.

signal resume_requested
signal intro_requested
signal new_party_requested
signal main_menu_requested
## Player confirmed "Start over" (progress will be wiped).
signal restart_requested
signal music_volume_changed(value: float)
signal steps_volume_changed(value: float)
signal mouse_sensitivity_changed(value: float)
## Locale code from GameSettings.LANGUAGES ("" = system language).
signal language_changed(code: String)
signal graphics_changed(level: int)

## Key, action shown in the controls cheat sheet.
const CONTROLS := [
	["J","Вечеринка"],["E","Ноутбук / разговор"],["C","Контроллер"],["1–3","Треки"],
	["M","Сведение"],["Tab","Инвентарь"],["B","Пиво"],["N","Сигарета"],
	["K","Потушить"],["R","Энергетик"],["F","Фонарь"],["V","Тошнит"],
]

@onready var settings: SettingsBox = $Window/Content/Body/Side/Settings

func _ready() -> void:
	%ResumeButton.pressed.connect(resume_requested.emit)
	%IntroButton.pressed.connect(intro_requested.emit)
	%NewPartyButton.pressed.connect(new_party_requested.emit)
	%MainMenuButton.pressed.connect(main_menu_requested.emit)
	%RestartButton.pressed.connect(func(): %RestartConfirm.popup_centered())
	%RestartConfirm.confirmed.connect(restart_requested.emit)
	settings.level_changed.connect(func(key: String, value: float):
		match key:
			"music": music_volume_changed.emit(value)
			"steps": steps_volume_changed.emit(value)
			"mouse": mouse_sensitivity_changed.emit(value)
	)
	settings.language_changed.connect(language_changed.emit)
	settings.graphics_changed.connect(graphics_changed.emit)
	var grid: GridContainer = %Controls
	for entry in CONTROLS:
		grid.add_child(UIKit.keycap(str(entry[0])))
		var caption := UIKit.label(str(entry[1]),13)
		caption.add_theme_color_override("font_color",UIKit.MUTED)
		grid.add_child(caption)
	for button in [%ResumeButton,%IntroButton,%NewPartyButton,%MainMenuButton]:
		MenuFx.light_on_focus(button)
	visibility_changed.connect(func():
		if visible:
			settings.sync()
			MenuFx.pop_in(%Window)
			%ResumeButton.grab_focus.call_deferred()
	)
