class_name PauseMenu
extends PanelContainer
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

func _ready() -> void:
	%ResumeButton.pressed.connect(resume_requested.emit)
	%IntroButton.pressed.connect(intro_requested.emit)
	%NewPartyButton.pressed.connect(new_party_requested.emit)
	%MainMenuButton.pressed.connect(main_menu_requested.emit)
	%RestartButton.pressed.connect(func(): %RestartConfirm.popup_centered())
	%RestartConfirm.confirmed.connect(restart_requested.emit)
	%MusicSlider.value_changed.connect(music_volume_changed.emit)
	%StepsSlider.value_changed.connect(steps_volume_changed.emit)
	%MouseSlider.value_changed.connect(mouse_sensitivity_changed.emit)
	var languages: OptionButton = %LanguageOption
	var current := GameSettings.language()
	for index in GameSettings.LANGUAGES.size():
		var entry: Array = GameSettings.LANGUAGES[index]
		languages.add_item(entry[1])
		languages.set_item_metadata(index, entry[0])
		if entry[0] == current:
			languages.select(index)
	languages.item_selected.connect(func(index: int): language_changed.emit(str(languages.get_item_metadata(index))))
