class_name DJLaptopView
extends RefCounted
## Builds the laptop: the deck displays in the library panel and the live screen rendered onto the 3D laptop.


var station: DJStation

func _init(owner_node: DJStation) -> void:
	station = owner_node

func build_track_display(parent: HBoxContainer, index: int) -> void:
	var display := PanelContainer.new()
	display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display.add_theme_stylebox_override("panel",UIKit.frame_style(Color("#080d16"),Color("#315a73"),11))
	parent.add_child(display)
	var screen := VBoxContainer.new()
	display.add_child(screen)
	var screen_header := HBoxContainer.new()
	screen.add_child(screen_header)
	var title: Label = UIKit.label("",16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	screen_header.add_child(title)
	screen_header.add_child(UIKit.label(station.DECK_NAMES[index],14))
	station.deck_labels.append(title)
	var scope := DeckScope.new()
	station.scopes.append(scope)
	screen.add_child(scope)
	var position := HSlider.new()
	position.step = .01
	position.value_changed.connect(func(value): station.seek(index,value))
	screen.add_child(position)
	station.positions.append(position)
	var clock: Label = UIKit.label("",14)
	screen.add_child(clock)
	station.time_labels.append(clock)
	var bpm := SpinBox.new()
	bpm.min_value = 40
	bpm.max_value = 250
	bpm.value = 124
	bpm.suffix = "BPM"
	station.bpm_fields.append(bpm)
	screen.add_child(bpm)

func build_laptop_display() -> void:
	station.laptop_view = SubViewport.new()
	station.laptop_view.size = Vector2i(768,432)
	station.laptop_view.disable_3d = true
	station.laptop_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	station.add_child(station.laptop_view)
	var frame := PanelContainer.new()
	station.laptop_view.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_stylebox_override("panel",UIKit.frame_style(Color("#090f1a"),Color("#344865"),16))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation",10)
	frame.add_child(rows)
	for index in range(2):
		var title: Label = UIKit.label("DECK "+station.DECK_NAMES[index],26)
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		rows.add_child(title)
		station.laptop_titles.append(title)
		var scope := DeckScope.new()
		scope.custom_minimum_size.y = 104
		rows.add_child(scope)
		station.laptop_scopes.append(scope)
		var clock: Label = UIKit.label("",21)
		rows.add_child(clock)
		station.laptop_times.append(clock)
	var screen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(.333,.200)
	screen.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = station.laptop_view.get_texture()
	screen.material_override = material
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	station.party.deck.get_node("LaptopScreen").add_child(screen)
	screen.position.z = .003
