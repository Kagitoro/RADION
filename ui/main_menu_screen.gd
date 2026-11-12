class_name MainMenuScreen
extends Control
## Visual part of the main menu. MainMenu decides what the buttons do.

signal continue_pressed
signal quit_pressed

@onready var continue_button: Button = %ContinueButton

func _ready() -> void:
	%Title.text = str(ProjectSettings.get_setting("application/config/name"))
	continue_button.pressed.connect(continue_pressed.emit)
	%QuitButton.pressed.connect(quit_pressed.emit)

## "Continue" for a returning player, "Start game" before the intro was seen.
func set_continue_label(has_progress: bool) -> void:
	continue_button.text = tr("Продолжить") if has_progress else tr("Начать игру")
