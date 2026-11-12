class_name HomeControls
extends RefCounted
## Keyboard and mouse routing for both the night game and the house editor.

const EDITOR_ROOMS := {"editor_room_kitchen": "kitchen", "editor_room_hall": "hall", "editor_room_bath": "bath", "editor_room_living": "living", "editor_room_studio": "studio"}
const EDITOR_SIZE_AXES := {"editor_size_all": "all", "editor_size_x": "x", "editor_size_y": "y", "editor_size_z": "z"}
var home: Home

func _init(game_home: Home) -> void:
	home = game_home

## Entry point, called from Home._unhandled_input.
func handle(event: InputEvent) -> void:
	if home.player == null:
		return
	if home.game_mode:
		game_input(event)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("editor_plan"):
			home.hud.toggle_plan()
			return
		if event.is_action_pressed("editor_inventory"):
			home.hud.toggle_inventory()
			return
		if event.is_action_pressed("pause"):
			if home.hud.menu.visible:
				home.hud.close_inventory()
			elif home.hud.plan.visible:
				if not home.hud.plan.opening_tool.is_empty() or not home.hud.plan.build_tool.is_empty():
					home.hud.plan.set_layer(home.hud.plan.layer)
					GameEvents.refresh_hud()
				else:
					home.hud.toggle_plan()
			elif not home.held.is_empty():
				home.cancel_hold()
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			return
		if event.ctrl_pressed:
			if event.physical_keycode == KEY_S:
				home.storage.save_project()
			elif event.physical_keycode == KEY_Z:
				if home.hud.plan.visible:
					home.hud.plan.cancel_construction()
				home.storage.undo()
			return
		if event.is_action_pressed("editor_delete") and home.hud.plan.visible and not home.hud.menu.visible:
			home.delete_selected()
			home.hud.plan.queue_redraw()
			return
		if event.is_action_pressed("editor_rotate") and home.hud.plan.visible and not home.hud.menu.visible and home.rooms.structural_wall(home.held):
			home.held.r = fposmod(float(home.held.r)+90.0,360.0)
			home.hud.plan.queue_redraw()
			GameEvents.refresh_hud()
			return
		if home.modal:
			return
		editor_key(event)
		GameEvents.refresh_hud()
	if home.modal:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		home.player.look_motion(event.relative)
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				else:
					home.aim = home.ray_target()
					home.interact()
			MOUSE_BUTTON_RIGHT:
				home.aim = home.ray_target()
				home.secondary_interaction()
			MOUSE_BUTTON_WHEEL_UP: home.adjust(1,event.shift_pressed)
			MOUSE_BUTTON_WHEEL_DOWN: home.adjust(-1,event.shift_pressed)

## House-editor shortcuts (developer mode, game_mode == false).
func editor_key(event: InputEvent) -> void:
	if event.is_action_pressed("start_party"):
		home.party.toggle()
	elif event.is_action_pressed("drink_beer"):
		home.party.consume(true)
	elif event.is_action_pressed("smoke"):
		home.party.consume(false)
	elif event.is_action_pressed("extinguish"):
		home.party.extinguish()
	elif event.is_action_pressed("editor_buy_cigarettes"):
		home.party.buy_cigarettes()
	elif event.is_action_pressed("beat_mix"):
		if home.party.near_deck():
			home.party.beat_mix()
	elif event.is_action_pressed("editor_rotate"):
		home.tool = "rotate"
	elif event.is_action_pressed("editor_lift"):
		home.tool = "lift"
	elif event.is_action_pressed("editor_fly"):
		home.player.airborne = not home.player.airborne
	elif event.is_action_pressed("editor_delete"):
		home.delete_selected()
	else:
		for action in EDITOR_SIZE_AXES:
			if event.is_action_pressed(action):
				home.tool = "size"
				home.axis = EDITOR_SIZE_AXES[action]
				return
		for action in EDITOR_ROOMS:
			if event.is_action_pressed(action):
				home.go_room(EDITOR_ROOMS[action])
				return
		for index in 3:
			if event.is_action_pressed("track_%d" % (index + 1)) and home.party.near_deck():
				home.party.switch_track(index)
				return

func game_input(event: InputEvent) -> void:
	if home.night_game.menu.opened:
		return
	if event is InputEventKey or event is InputEventJoypadButton:
		if event.is_pressed() and not event.is_echo():
			home.night_game.handle_input(event)
	elif event is InputEventMouseMotion and not home.modal and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		home.player.look_motion(event.relative)
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and not home.modal:
		if home.night_game.click_controller():
			return
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
