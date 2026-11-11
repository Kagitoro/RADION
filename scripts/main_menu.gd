extends Node

const CHECKPOINT := "user://radion_checkpoint.cfg"

var home
var game
var layer: CanvasLayer
var camera: Camera3D
var continue_button: Button
var opened := false
var entered := false
var loaded_checkpoint := false
var player_was_visible := true
var hud_was_visible := true
var club_was_muted := false

func setup(editor, night_game) -> void:
	home = editor
	game = night_game
	layer = CanvasLayer.new()
	layer.layer = 25
	add_child(layer)
	var root := Control.new()
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var tint := TextureRect.new()
	root.add_child(tint)
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var shading := Gradient.new()
	shading.offsets = PackedFloat32Array([0.0,.48,1.0])
	shading.colors = PackedColorArray([Color("#0b101b"),Color(.038,.062,.105,.86),Color(.03,.05,.09,.10)])
	var gradient := GradientTexture2D.new()
	gradient.gradient = shading
	gradient.width = 512
	gradient.height = 4
	tint.texture = gradient

	var column := VBoxContainer.new()
	root.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	column.offset_left = 76
	column.offset_right = 397
	column.offset_top = -162
	column.add_theme_constant_override("separation",12)
	var title: Label = home.hud.label("RADION",64)
	title.modulate = Color("#dcf2fa")
	column.add_child(title)
	var subtitle: Label = home.hud.label("DJ SIMULATOR",17)
	subtitle.modulate = Color("#87dce7")
	column.add_child(subtitle)
	var gap := Control.new()
	gap.custom_minimum_size.y = 13
	column.add_child(gap)
	continue_button = menu_button("Продолжить",resume)
	column.add_child(continue_button)
	column.add_child(menu_button("Выход",quit_game))
	layer.hide()

func menu_button(title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 49
	button.add_theme_font_size_override("font_size",20)
	for state in ["normal","hover","pressed","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#182333") if state=="normal" else Color("#264254")
		style.border_color = Color("#416071") if state=="normal" else Color("#80d7e3")
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		style.content_margin_left = 16
		style.content_margin_right = 12
		button.add_theme_stylebox_override(state,style)
	button.pressed.connect(action)
	return button

func show_menu() -> void:
	if opened:
		return
	if entered:
		save_checkpoint()
	opened = true
	game.pause_panel.hide()
	player_was_visible = home.player.visible
	hud_was_visible = home.hud.root.visible
	home.player.hide()
	home.hud.root.hide()
	home.set_modal(true)
	var bus: int = home.night_world.nightclub.music_bus
	club_was_muted = AudioServer.is_bus_mute(bus)
	AudioServer.set_bus_mute(bus,true)
	camera = Camera3D.new()
	camera.cull_mask = home.player.camera.cull_mask
	camera.fov = 59.0
	home.add_child(camera)
	var at: Vector3 = home.night_world.door_center
	camera.global_position = at+Vector3(-15.9,2.35,13.6)
	camera.look_at(at+Vector3(-28,2.65,-2.25))
	camera.make_current()
	continue_button.text = "Продолжить" if game.intro.opening_completed else "Начать игру"
	layer.show()
	continue_button.grab_focus()

func leave_menu() -> void:
	opened = false
	entered = true
	layer.hide()
	home.player.camera.make_current()
	camera.queue_free()
	camera = null
	home.player.visible = player_was_visible
	home.hud.root.visible = hud_was_visible
	AudioServer.set_bus_mute(home.night_world.nightclub.music_bus,club_was_muted)
	restore_checkpoint()
	home.set_modal(false)

func resume() -> void:
	if not opened:
		return
	leave_menu()
	if not game.intro.opening_completed:
		game.intro.start()

func save_checkpoint() -> void:
	if not entered or game.intro.active or home.player.collapsed or home.player.vomiting:
		return
	var player: CharacterBody3D = home.player
	if not player.has_safe_floor:
		return
	var config := ConfigFile.new()
	var at: Vector3 = player.safe_floor
	config.set_value("player","position",at)
	config.set_value("player","yaw",player.rotation.y)
	config.set_value("player","pitch",player.pitch)
	if config.save(CHECKPOINT)!=OK:
		push_warning("Не удалось сохранить точку продолжения")

func restore_checkpoint() -> void:
	if loaded_checkpoint:
		return
	loaded_checkpoint = true
	var config := ConfigFile.new()
	if config.load(CHECKPOINT)!=OK:
		return
	var at: Vector3 = config.get_value("player","position",Vector3.INF)
	if not at.is_finite() or not home.floor_below(Vector2(at.x,at.z)):
		return
	var yaw := float(config.get_value("player","yaw",0.0))
	var pitch := clampf(float(config.get_value("player","pitch",0.0)),-1.5,1.5)
	var aim := Vector3(-sin(yaw)*cos(pitch),sin(pitch),-cos(yaw)*cos(pitch))
	var eye: Vector3 = at+home.player.camera.position+Vector3.UP*.025
	home.player.move_to(eye,eye+aim)

func quit_game() -> void:
	save_checkpoint()
	get_tree().quit()

func _input(event: InputEvent) -> void:
	if opened and entered and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_ESCAPE:
		resume()
		get_viewport().set_input_as_handled()
