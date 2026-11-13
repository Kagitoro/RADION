class_name DJLibrary
extends RefCounted
## Laptop music library: folder choice, background scan, search and loading the selection into a deck.

const FORMATS := ["mp3", "wav", "ogg"]
static var CONFIG := SavePaths.file("dj_library.cfg")
var chooser: FileDialog
var listing: ItemList
var search: LineEdit
var folder_label: Label
var folder := ""
var files := PackedStringArray()
var pending := PackedStringArray()
var directory: DirAccess
var scan_path := ""
var scanning := false
var station: DJStation

func _init(owner_node: DJStation) -> void:
	station = owner_node

## Restores the last chosen folder, falling back to the system Music folder.
func load_folder_setting() -> void:
	var config := ConfigFile.new()
	folder = OS.get_system_dir(OS.SYSTEM_DIR_MUSIC)
	if config.load(CONFIG)==OK:
		folder = str(config.get_value("library","folder",folder))
	if not DirAccess.dir_exists_absolute(folder):
		folder = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)

## Builds the search bar, file list and load buttons inside the laptop panel.
func build_ui(toolbar: HBoxContainer, box: VBoxContainer) -> void:
	var hud := station.home.hud
	toolbar.add_child(UIKit.button(tr("Выбрать папку"),choose_folder))
	toolbar.add_child(UIKit.button(tr("Обновить"),scan_folder))
	search = LineEdit.new()
	search.placeholder_text = tr("Поиск по названию и подпапке")
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(_query): refresh_library())
	toolbar.add_child(search)
	folder_label = UIKit.label("",14)
	folder_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(folder_label)
	listing = ItemList.new()
	listing.size_flags_vertical = Control.SIZE_EXPAND_FILL
	listing.item_activated.connect(func(_index): activate_selection())
	box.add_child(listing)
	var load_row := HBoxContainer.new()
	box.add_child(load_row)
	load_row.add_child(UIKit.button(tr("Включить"),play_selection))
	for index in range(2):
		load_row.add_child(UIKit.button(tr("Загрузить в %s") % DJStation.DECK_NAMES[index],load_selection.bind(index,false)))
	chooser = FileDialog.new()
	chooser.title = tr("Папка с музыкой")
	chooser.access = FileDialog.ACCESS_FILESYSTEM
	chooser.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	chooser.dir_selected.connect(func(path: String):
		folder = path
		var config := ConfigFile.new()
		config.set_value("library","folder",folder)
		config.save(CONFIG)
		scan_folder()
	)
	station.add_child(chooser)

func choose_folder() -> void:
	if DirAccess.dir_exists_absolute(folder):
		chooser.current_dir = folder
	chooser.popup_centered_ratio(.72)

func scan_folder() -> void:
	files.clear()
	pending = PackedStringArray([folder])
	directory = null
	scanning = true
	refresh_library()

func scan_step() -> void:
	for index in range(250):
		if directory==null:
			if pending.is_empty():
				scanning = false
				files.sort()
				refresh_library()
				return
			scan_path = pending[-1]
			pending.resize(pending.size()-1)
			directory = DirAccess.open(scan_path)
			if directory==null:
				continue
			directory.list_dir_begin()
		var entry := directory.get_next()
		if entry.is_empty():
			directory = null
			continue
		if directory.is_link(entry):
			continue
		var path := scan_path.path_join(entry)
		if directory.current_is_dir():
			pending.append(path)
		elif entry.get_extension().to_lower() in FORMATS:
			files.append(path)

func refresh_library() -> void:
	var query := search.text.strip_edges().to_lower()
	listing.clear()
	for path in files:
		var label := path.trim_prefix(folder.trim_suffix("/")+"/")
		if query.is_empty() or label.to_lower().contains(query):
			var index := listing.add_item(label)
			listing.set_item_metadata(index,path)
	folder_label.text = "%s   ·   %s" % [folder,tr("Поиск файлов…") if scanning else tr("%d треков") % listing.item_count]

func play_selection() -> void:
	var current := station.audible_deck()
	load_selection(current,true)

func activate_selection() -> void:
	if station.load_target>=0:
		load_selection(station.load_target,false)
	else:
		play_selection()

func load_selection(index: int, play_now: bool) -> void:
	var selected := listing.get_selected_items()
	if selected.is_empty():
		station.info.text = tr("Выбери трек в списке.")
		return
	var path := str(listing.get_item_metadata(selected[0]))
	if not station.load_file(path,index,play_now):
		station.info.text = tr("Не удалось открыть %s") % path.get_file()
