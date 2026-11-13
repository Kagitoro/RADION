class_name GameSettings
extends RefCounted
## Player preferences kept between runs. Currently: interface language.

## [locale code, label]. An empty code follows the operating system language
## (languages without a translation fall back to the Russian original).
const LANGUAGES := [["", "Системный / System"], ["ru", "Русский"], ["en", "English"]]
static var FILE := SavePaths.file("settings.cfg")

static func language() -> String:
	var config := ConfigFile.new()
	if config.load(FILE) != OK:
		return ""
	return str(config.get_value("interface", "language", ""))

## Saves the choice and switches the game to it immediately.
static func set_language(code: String) -> void:
	var config := ConfigFile.new()
	config.load(FILE)
	config.set_value("interface", "language", code)
	if config.save(FILE) != OK:
		push_warning("Не удалось сохранить настройки")
	apply_language(code)

static func apply_language(code: String) -> void:
	TranslationServer.set_locale(code if not code.is_empty() else OS.get_locale())
