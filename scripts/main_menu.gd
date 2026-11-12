class_name MainMenu
extends Node

static var CHECKPOINT := SavePaths.file("radion_checkpoint.cfg")

var home: Home
var game: NightGame
var layer: CanvasLayer
var camera: Camera3D
const SCREEN := preload("res://ui/main_menu_screen.tscn")
var screen: MainMenuScreen
var opened := false
var entered := false
var loaded_checkpoint := false
var player_was_visible := true
var hud_was_visible := true
var club_was_muted := false

func setup(game_home: Home, night_game: NightGame) -> void:
	home = game_home
	game = night_game
	layer = CanvasLayer.new()
	layer.layer = 25
	add_child(layer)
	screen = SCREEN.instantiate()
	layer.add_child(screen)
	screen.continue_pressed.connect(resume)
	screen.quit_pressed.connect(quit_game)
	layer.hide()

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
	var bus: int = home.club.music_bus
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
	screen.set_continue_label(game.intro.opening_completed)
	layer.show()
	screen.continue_button.grab_focus()

func leave_menu() -> void:
	opened = false
	entered = true
	layer.hide()
	home.player.camera.make_current()
	camera.queue_free()
	camera = null
	home.player.visible = player_was_visible
	home.hud.root.visible = hud_was_visible
	AudioServer.set_bus_mute(home.club.music_bus,club_was_muted)
	restore_checkpoint()
	home.set_modal(false)

func resume() -> void:
	if not opened:
		return
	leave_menu()
	if not game.intro.opening_completed:
		game.intro.start()
	elif not game.intro.entry_opened:
		game.intro.place_at_door()

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
	if not at.is_finite() or not home.rooms.floor_below(Vector2(at.x,at.z)):
		return
	var yaw := float(config.get_value("player","yaw",0.0))
	var pitch := clampf(float(config.get_value("player","pitch",0.0)),-1.5,1.5)
	var aim := Vector3(-sin(yaw)*cos(pitch),sin(pitch),-cos(yaw)*cos(pitch))
	var eye: Vector3 = at+home.player.camera.position+Vector3.UP*.025
	home.player.move_to(eye,eye+aim)

func quit_game() -> void:
	save_checkpoint()
	home.quit_game()

func _input(event: InputEvent) -> void:
	if opened and entered and event.is_action_pressed("pause"):
		resume()
		get_viewport().set_input_as_handled()
