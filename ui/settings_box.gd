class_name SettingsBox
extends VBoxContainer
## Settings shared by the pause menu and the main menu: music, footsteps, mouse
## sensitivity and language. Values come from and go to GameSettings; the game
## applies them through the signals. The rows are built here and registered as
## unique names (%MusicSlider, %StepsSlider, %MouseSlider, %LanguageOption) in the
## scene that owns this box.

signal level_changed(key: String, value: float)
## Locale code from GameSettings.LANGUAGES ("" = system language).
signal language_changed(code: String)
## 0 low, 1 medium, 2 high (VisualQuality.LEVEL_NAMES).
signal graphics_changed(level: int)

const ROWS := [["music","MusicSlider","Музыка"],["steps","StepsSlider","Шаги"],["mouse","MouseSlider","Чувствительность мыши"]]

var sliders := {}
var language: OptionButton
var graphics: OptionButton

func _ready() -> void:
	add_theme_constant_override("separation",10)
	var heading := UIKit.title(tr("Настройки"),17,UIKit.AMBER)
	add_child(heading)
	for row in ROWS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation",12)
		add_child(line)
		var caption := UIKit.label(str(row[2]),14)
		caption.custom_minimum_size.x = 190
		caption.add_theme_color_override("font_color",UIKit.MUTED)
		line.add_child(caption)
		var slider := HSlider.new()
		slider.name = str(row[1])
		slider.max_value = 1.0
		slider.step = .01
		slider.custom_minimum_size = Vector2(170,22)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(slider)
		var readout := UIKit.label("",13)
		readout.custom_minimum_size.x = 40
		readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(readout)
		var key := str(row[0])
		slider.value_changed.connect(func(value: float):
			readout.text = "%d%%" % roundi(value*100)
			level_changed.emit(key,value)
		)
		sliders[key] = slider
		register(slider)
	var quality_line := HBoxContainer.new()
	quality_line.add_theme_constant_override("separation",12)
	add_child(quality_line)
	var quality_caption := UIKit.label("Графика",14)
	quality_caption.custom_minimum_size.x = 190
	quality_caption.add_theme_color_override("font_color",UIKit.MUTED)
	quality_line.add_child(quality_caption)
	graphics = OptionButton.new()
	graphics.name = "GraphicsOption"
	graphics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quality_line.add_child(graphics)
	register(graphics)
	for index in VisualQuality.LEVEL_NAMES.size():
		graphics.add_item(VisualQuality.LEVEL_NAMES[index])
	graphics.item_selected.connect(graphics_changed.emit)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation",12)
	add_child(line)
	var caption := UIKit.label("Язык / Language",14)
	caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	caption.custom_minimum_size.x = 190
	caption.add_theme_color_override("font_color",UIKit.MUTED)
	line.add_child(caption)
	language = OptionButton.new()
	language.name = "LanguageOption"
	language.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	language.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(language)
	register(language)
	for index in GameSettings.LANGUAGES.size():
		var entry: Array = GameSettings.LANGUAGES[index]
		language.add_item(entry[1])
		language.set_item_metadata(index,entry[0])
	language.item_selected.connect(func(index: int): language_changed.emit(str(language.get_item_metadata(index))))
	sync()

## Shows the saved values (without re-applying them).
func sync() -> void:
	for key in sliders:
		var slider: HSlider = sliders[key]
		slider.set_value_no_signal(GameSettings.level(key))
		(slider.get_parent().get_child(2) as Label).text = "%d%%" % roundi(slider.value*100)
	graphics.select(GameSettings.graphics())
	var current := GameSettings.language()
	for index in language.item_count:
		if language.get_item_metadata(index)==current:
			language.select(index)

## Makes a row reachable as %Name from the scene that owns this box.
func register(control: Control) -> void:
	var scene_root := owner if owner!=null else self
	control.owner = scene_root
	control.unique_name_in_owner = true
