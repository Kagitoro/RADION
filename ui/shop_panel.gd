class_name ShopPanel
extends PanelContainer
## Night Shop counter window. StreetShop owns the stock and prices.

signal buy_requested(index: int)
signal close_requested

func _ready() -> void:
	%CloseButton.pressed.connect(close_requested.emit)

## items: [[name, price, description], ...] — names are translated here.
func set_items(items: Array) -> void:
	for child in %Items.get_children():
		child.queue_free()
	for index in items.size():
		var item: Array = items[index]
		var button := Button.new()
		button.text = "%s   $%d   ·   %s" % [tr(item[0]), item[1], tr(item[2])]
		button.pressed.connect(buy_requested.emit.bind(index))
		%Items.add_child(button)

func set_stock(text: String) -> void:
	%StockLabel.text = text

func set_message(text: String) -> void:
	%MessageLabel.text = text
