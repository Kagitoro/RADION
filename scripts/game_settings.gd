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

## Slider settings (0..1) shown in the pause menu and the main menu.
const DEFAULTS := {"music": .85, "steps": .63, "mouse": .45}

## Graphics quality: 0 low, 1 medium, 2 high (VisualQuality.LEVEL_NAMES).
static func graphics() -> int:
	var config := ConfigFile.new()
	if config.load(FILE) != OK:
		return 2
	return clampi(int(config.get_value("video", "graphics", 2)), 0, 2)

static func set_graphics(value: int) -> void:
	var config := ConfigFile.new()
	config.load(FILE)
	config.set_value("video", "graphics", clampi(value, 0, 2))
	if config.save(FILE) != OK:
		push_warning("Не удалось сохранить настройки")

static func level(key: String) -> float:
	var config := ConfigFile.new()
	if config.load(FILE) != OK:
		return float(DEFAULTS[key])
	return float(config.get_value("levels", key, DEFAULTS[key]))

static func set_level(key: String, value: float) -> void:
	var config := ConfigFile.new()
	config.load(FILE)
	config.set_value("levels", key, clampf(value, 0.0, 1.0))
	if config.save(FILE) != OK:
		push_warning("Не удалось сохранить настройки")
