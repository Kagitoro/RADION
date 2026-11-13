class_name InventoryWindow
extends PanelContainer
## House-editor inventory: searchable list of objects plus project file actions.

signal close_requested
signal take_requested(index: int)
signal open_requested
signal save_requested
signal export_requested
signal search_changed(query: String)

@onready var search: LineEdit = %Search
@onready var asset_list: ItemList = %AssetList

func _ready() -> void:
	%CloseButton.pressed.connect(close_requested.emit)
	%OpenButton.pressed.connect(open_requested.emit)
	%SaveButton.pressed.connect(save_requested.emit)
	%ExportButton.pressed.connect(export_requested.emit)
	%TakeButton.pressed.connect(func():
		var choice := asset_list.get_selected_items()
		if not choice.is_empty():
			take_requested.emit(choice[0])
	)
	asset_list.item_activated.connect(take_requested.emit)
	search.text_changed.connect(search_changed.emit)
