class_name Home
extends Node3D

const PICK_MASK := 2

@onready var house: Node3D = $HouseGeometry
var player: Player
var hud: HUD
var data: Dictionary = {}
var records: Dictionary = {}
var originals: Dictionary = {}
var nodes: Dictionary = {}
var bodies: Dictionary = {}
var catalog: Dictionary = {}
var inventory: Array = []
var selected := ""
var held: Dictionary = {}
var preview: Node3D
var held_before := ""
var held_rotated := false
var placement_surface := ""
var placement_supported := false
var grabbed := ""
var tool := "rotate"
var axis := "all"
var modal := false
var aim: Dictionary = {}
var aim_timer := 0.0
var next_id := 1
var headless := false
var ground_root := Node3D.new()
var landscape_surface: ShaderMaterial
var scene_lighting := Node3D.new()
var ghost_materials: Array = []
var openings := Openings.new(self)
var construction := Construction.new(self)
var scene_finish := SceneFinish.new(self)
var party := Party.new(self)
var seams := Seams.new(self)
var game_mode := true
var night_world := NightWorld.new(self)
var night_game := NightGame.new(self)
var controls := HomeControls.new(self)
var frames := TargetFrames.new(self)
var storage := ProjectStorage.new(self)
var rooms := RoomLayout.new(self)
var smoke_runner: SmokeRunner
## Shortcuts to the night-world venues most systems talk to.
var club: Nightclub:
	get: return night_world.nightclub
var shop: StreetShop:
	get: return night_world.shop
var subway: SubwayStation:
	get: return night_world.subway

func _ready() -> void:
	# Build every UI in the source language: controls then translate their text
	# live, so the language can be switched at any moment without a restart.
	TranslationServer.set_locale("ru")
	headless = DisplayServer.get_name() == "headless"
	var payload = JSON.parse_string(FileAccess.get_file_as_string("res://assets/layout.json"))
	if not payload is Dictionary:
		push_error("Не удалось прочитать описание дома.")
		return
	data = payload
	inventory = data.inventory
	add_child(ground_root)
	add_child(scene_lighting)
	add_child(scene_finish)
	for s in data.objects:
		var id := str(s.id)
		var model := house.find_child(str(s.node), true, false) as Node3D
		if model == null:
			push_warning("Нет модели: " + str(s.node))
			continue
		records[id] = s.duplicate(true)
		originals[id] = s.duplicate(true)
		nodes[id] = model
	for name in data.templates:
		var s: Dictionary = data.templates[name]
		var model := house.find_child(str(s.node), true, false) as Node3D
		if model != null:
			catalog[name] = model
	var collection := house.find_child("Catalog", true, false) as Node3D
	if collection != null:
		collection.hide()
	scene_finish.prepare_walls()
	openings.prepare_catalog_window()
	frames.target_frame = frames.add_target_frame(Color("#f3efdd"))
	frames.selected_frame = frames.add_target_frame(Color("#83f2a6"))
	setup_lighting()
	rooms.register_room_details()
	openings.prepare_studio_windows()
	openings.prepare_room_windows()
	openings.install_stock_passages()
	openings.install_studio_windows()
	for id in records:
		apply_item(id)
	scene_finish.sync_ceilings()
	if not SavePaths.is_test_run() and FileAccess.file_exists(storage.SAVE_PATH):
		storage.load_project(storage.SAVE_PATH, false)
	add_child(night_world)
	night_world.setup()
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.surface_at = rooms.footstep_surface
	scene_finish.setup_mirror()
	hud = HUD.new()
	hud.game = self
	add_child(hud)
	add_child(party)
	party.setup()
	night_world.dress_bar()
	add_child(night_game)
	night_game.setup()
	VisualQuality.plaster(scene_finish.paint)
	VisualQuality.apply(self)
	if not SavePaths.is_test_run():
		GameSettings.apply_language(GameSettings.language())
	go_room("hall")
	if "--smoke" in OS.get_cmdline_user_args():
		smoke_runner = SmokeRunner.new(self)
		smoke_runner.run.call_deferred()
	elif "--visual-smoke" in OS.get_cmdline_user_args():
		smoke_runner = SmokeRunner.new(self)
		smoke_runner.run_visual.call_deferred()
	elif Array(OS.get_cmdline_user_args()).any(func(arg: String): return arg.begins_with("--visual-tour")):
		VisualTour.new(self).run.call_deferred()
	elif not headless:
		if game_mode and "--skip-menu" not in OS.get_cmdline_user_args():
			get_tree().auto_accept_quit = false
			night_game.menu.show_menu()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	controls.handle(event)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_instance_valid(night_game.menu):
		night_game.menu.quit_game()

## Stops every audio player before quitting so no MP3 playback leaks at exit.
func quit_game(code: int = 0) -> void:
	for player_node in get_tree().root.find_children("*", "", true, false):
		if player_node is AudioStreamPlayer or player_node is AudioStreamPlayer3D:
			player_node.stop()
			player_node.bus = &"Master"
			player_node.stream = null
	await get_tree().process_frame
	get_tree().quit(code)

func vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func setup_lighting() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#282f2b")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#e6e6da")
	env.ambient_light_energy = 0.61
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	add_child(world)
	var site := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(180,180)
	landscape_surface = ShaderMaterial.new()
	landscape_surface.shader = preload("res://assets/city/landscape_ground.gdshader")
	landscape_surface.set_shader_parameter("grass_color",Color("#647650"))
	var grass_texture := NoiseTexture2D.new()
	grass_texture.seamless = true
	var grass_noise := FastNoiseLite.new()
	grass_noise.frequency = .04
	grass_texture.noise = grass_noise
	var grass_ramp := Gradient.new()
	grass_ramp.colors = PackedColorArray([Color("#a7b7a1"),Color("#f5f6e5")])
	grass_texture.color_ramp = grass_ramp
	landscape_surface.set_shader_parameter("grass",grass_texture)
	site.mesh = plane
	site.material_override = landscape_surface
	site.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	site.position.y = -.055
	add_child(site)
	scene_finish.landscape(env)
	for entry in data.lights:
		var light: Light3D
		if bool(entry.get("spot",false)):
			var spot := SpotLight3D.new()
			spot.spot_range = 7.5
			spot.spot_angle = minf(82.0, float(entry.angle))
			spot.spot_attenuation = 1.1
			spot.shadow_enabled = false
			light = spot
		else:
			var omni := OmniLight3D.new()
			omni.omni_range = maxf(0.28, float(entry.range))
			omni.omni_attenuation = 1.35
			light = omni
		var rgb := int(entry.color)
		light.light_color = Color8((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255)
		light.light_energy = float(entry.energy) * (0.048 if bool(entry.get("spot",false)) else 0.047)
		scene_lighting.add_child(light)
		light.global_position = vector(entry.p)
		if bool(entry.get("spot",false)):
			var target := vector(entry.target)
			var up := Vector3.FORWARD if absf((target - light.global_position).normalized().dot(Vector3.UP)) > 0.98 else Vector3.UP
			light.look_at(target, up)
		rooms.register_room_attachment(light,light.global_position)

func dimensions(s: Dictionary) -> Vector3:
	return Vector3(float(s.w), float(s.h), float(s.d))

func transform_item(model: Node3D, s: Dictionary) -> void:
	model.position = Vector3(float(s.x), float(s.y), float(s.z))
	model.rotation = Vector3(0, deg_to_rad(float(s.r)), 0)
	model.scale = dimensions(s) / vector(s.dimensions)

func apply_item(id: String) -> void:
	if not records.has(id) or not nodes.has(id):
		return
	var s: Dictionary = records[id]
	var model: Node3D = nodes[id]
	transform_item(model, s)
	model.visible = not bool(s.deleted)
	rebuild_body(id)
	if s.has("wall_id"):
		openings.refresh(str(s.wall_id))
	elif str(s.kind)=="wall":
		openings.refresh(id)

func remove_body(id: String) -> void:
	if not bodies.has(id):
		return
	var body: StaticBody3D = bodies[id]
	var target = aim.get("collider")
	if not is_instance_valid(target) or target == body:
		aim.clear()
	bodies.erase(id)
	body.free()

func rebuild_body(id: String) -> void:
	remove_body(id)
	if id == grabbed or not records.has(id) or bool(records[id].deleted):
		return
	var s: Dictionary = records[id]
	var size := dimensions(s)
	var floor_item := str(s.kind) == "floor"
	var opening := openings.kind(s)
	var body := StaticBody3D.new()
	body.collision_layer = PICK_MASK | (1 if floor_item or s.solid or (opening=="window" and s.has("wall_id")) else 0)
	body.collision_mask = 0
	body.set_meta("item_id", id)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, 0.075 if floor_item else maxf(0.03, size.y), size.z)
	collider.shape = shape
	var y := float(s.y) + size.y * 0.5
	if floor_item:
		y = rooms.floor_surface(s) - 0.0375
	body.add_child(collider)
	ground_root.add_child(body)
	body.position = Vector3(float(s.x), y, float(s.z))
	body.rotation.y = deg_to_rad(float(s.r))
	if opening in ["door","opening"] and (s.has("wall_id") or str(s.get("template",""))=="opening"):
		var threshold := StaticBody3D.new()
		threshold.collision_layer = 1
		threshold.collision_mask = 0
		body.add_child(threshold)
		openings.shape(threshold,Vector3(0,-size.y*.5-.035,0),Vector3(size.x,.07,maxf(size.z,.15)+.35))
	bodies[id] = body

func ray_target() -> Dictionary:
	var camera: Camera3D = player.camera
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * 8.0
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, PICK_MASK))

func template_model(key: String) -> Node3D:
	if nodes.has(key):
		return nodes[key]
	return catalog.get(key) as Node3D

func make_template(key: String) -> Dictionary:
	var template: Dictionary = originals.get(key, data.templates.get(key, {}))
	if template.is_empty():
		return {}
	var s := template.duplicate(true)
	s.template = key
	s.zone = ""
	s.deleted = false
	return s

func duplicate_model(key: String) -> Node3D:
	var source := template_model(key)
	if source == null:
		return null
	var clone := source.duplicate(0) as Node3D
	clone.position = Vector3.ZERO
	clone.rotation = Vector3.ZERO
	clone.scale = Vector3.ONE
	clone.show()
	return clone

func make_ghost(model: Node3D) -> void:
	ghost_materials.clear()
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		for i in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(i)
			if not material is BaseMaterial3D:
				continue
			var tint := material.duplicate() as BaseMaterial3D
			var color := tint.albedo_color
			color.a = .56
			tint.albedo_color = color
			tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ghost_materials.append([mesh,i,mesh.get_surface_override_material(i)])
			mesh.set_surface_override_material(i,tint)

func restore_ghost() -> void:
	for entry in ghost_materials:
		if is_instance_valid(entry[0]):
			entry[0].set_surface_override_material(entry[1],entry[2])
	ghost_materials.clear()

func take_template(key: String) -> void:
	cancel_hold()
	var s := make_template(key)
	var model := duplicate_model(key)
	if s.is_empty() or model == null:
		return
	held_before = storage.snapshot()
	held = s
	held.id = "copy-godot-%d-%d" % [Time.get_ticks_msec(), next_id]
	next_id += 1
	held.x = 0.0
	held.z = 0.0
	held.offset = 0.0
	held_rotated = false
	preview = model
	add_child(preview)
	make_ghost(preview)
	hud.show_held(key, held)
	update_preview()

func grab_current() -> void:
	if not held.is_empty():
		return
	var id := grab_target_id()
	if not records.has(id) or bool(records[id].deleted) or str(records[id].kind) == "floor":
		return
	if plan_only(id):
		GameEvents.notify(tr("Двери, окна и их стены можно перемещать на плане по Tab."))
		return
	held_before = storage.snapshot()
	grabbed = id
	selected = id
	held = records[id].duplicate(true)
	held.offset = 0.0
	held_rotated = false
	preview = nodes[id]
	rebuild_body(id)
	hud.show_held(str(held.get("template", id)), held)
	make_ghost(preview)
	update_preview()
	GameEvents.refresh_hud()

func plan_only(id: String) -> bool:
	var row: Dictionary = records.get(id,{})
	return row.has("opening_kind") or row.has("wall_id") or openings.wall_meshes.has(id)

func aimed_id() -> String:
	var collider = aim.get("collider")
	if not is_instance_valid(collider):
		return ""
	return str(collider.get_meta("item_id", ""))

func grab_target_id() -> String:
	var id := aimed_id()
	var item: Dictionary = records.get(id,{})
	if item.is_empty() or bool(item.deleted) or str(item.kind)=="floor":
		return ""
	return id

func update_preview() -> void:
	if held.is_empty() or preview == null:
		return
	var camera: Camera3D = player.camera
	var point := camera.global_position - camera.global_transform.basis.z * 2.6
	point.y = 0.0
	placement_surface = tr("Пол")
	placement_supported = str(held.kind)=="floor"
	var snap_height := true
	if not aim.is_empty():
		point = aim.position
		var normal: Vector3 = aim.normal
		var target: Dictionary = records.get(aimed_id(),{})
		var name := str(target.get("label",tr("Поверхность")))
		if absf(normal.y) < .45:
			var width := float(held.w)
			var depth := float(held.d)
			var height := float(held.h)
			var flat := minf(width,depth)<maxf(width,depth)*.37 and height>.24
			if flat and not held_rotated:
				var aligned := atan2(normal.x,normal.z) - (PI*.5 if width<depth else 0.0)
				held.r = fposmod(rad_to_deg(aligned),360.0)
			var angle := deg_to_rad(float(held.r))
			var local_normal := normal.rotated(Vector3.UP,-angle)
			var extents := (absf(local_normal.x)*width + absf(local_normal.z)*depth)*.5
			point += normal * (extents+.04)
			point.y = maxf(0.0,point.y-height*.5)
			placement_surface = name
			placement_supported = flat and str(target.get("kind",""))=="wall"
		elif normal.y < -.45:
			point.y -= float(held.h)+.014
			placement_surface = tr("Потолок / нижняя сторона")
			snap_height = false
			placement_supported = true
		else:
			placement_surface = name
			snap_height = false
			placement_supported = true
	var wall := rooms.structural_wall(held)
	if wall or not placement_supported:
		var ground := rooms.ground_height(Vector2(point.x,point.z))
		placement_supported = is_finite(ground)
		placement_surface = tr("Пол") if placement_supported else tr("Нет опоры")
		if placement_supported:
			point.y = ground
			snap_height = false
	if str(held.kind)=="floor":
		var ground := rooms.ground_height(Vector2(point.x,point.z))
		point.y = (ground if is_finite(ground) else 0.0)-float(held.h)
		snap_height = false
	held.x = snappedf(point.x,.05)
	held.z = snappedf(point.z,.05)
	var y := point.y if wall else clampf(point.y+float(held.offset),-.05,8.0)
	held.y = snappedf(y,.025) if snap_height else y
	transform_item(preview,held)
	hud.refresh_held(held)

func interact() -> void:
	if held.is_empty():
		grab_current()
		return
	update_preview()
	if not placement_supported:
		GameEvents.notify(tr("Наведи на пол или на поверхность, куда хочешь поставить предмет."))
		return
	commit_preview()

func secondary_interaction() -> void:
	if not held.is_empty():
		cancel_hold()
		return
	selected = aimed_id()
	GameEvents.refresh_hud()

func commit_preview() -> void:
	var id := str(held.id)
	var before := held_before
	held.erase("offset")
	restore_ghost()
	records[id] = held
	nodes[id] = preview
	preview.name = "E_" + id.replace("-", "_")
	held = {}
	preview = null
	grabbed = ""
	selected = id
	apply_item(id)
	storage.record_change(before)
	hud.clear_held()
	GameEvents.refresh_hud()

func cancel_hold() -> void:
	if held.is_empty():
		return
	restore_ghost()
	if grabbed.is_empty():
		preview.free()
	else:
		var id := grabbed
		grabbed = ""
		apply_item(id)
	held = {}
	preview = null
	if hud != null:
		hud.clear_held()
		GameEvents.refresh_hud()

func resize_width(value: float) -> void:
	if not held.is_empty():
		held.w = clampf(value, .024, 28.0)
		update_preview()
		hud.refresh_held(held)
	elif records.has(selected) and not plan_only(selected):
		var before := storage.snapshot()
		records[selected].w = clampf(value, .024, 28.0)
		apply_item(selected)
		storage.record_change(before)
	GameEvents.refresh_hud()

func adjust(direction: int, fine: bool) -> void:
	var s: Dictionary = held if not held.is_empty() else records.get(selected, {})
	if s.is_empty() or (held.is_empty() and (str(s.kind)=="floor" or plan_only(selected))):
		return
	var before := storage.snapshot() if held.is_empty() else ""
	match tool:
		"rotate":
			if not held.is_empty():
				held_rotated = true
			s.r = fposmod(float(s.r) + direction * (5.0 if fine else 15.0), 360.0)
		"size":
			var factor := exp(direction * (0.035 if fine else 0.105))
			for key in ["w","h","d"]:
				if axis == "all" or {"w":"x","h":"y","d":"z"}[key] == axis:
					s[key] = clampf(float(s[key]) * factor, 0.024, 28.0)
		"lift":
			var amount := direction * (0.025 if fine else 0.10)
			if held.is_empty():
				s.y = clampf(float(s.y) + amount, -5.0, 12.0)
			else:
				s.offset = clampf(float(s.offset) + amount, -5.0, 8.0)
	if held.is_empty():
		apply_item(selected)
		storage.record_change(before)
	else:
		update_preview()
		hud.refresh_held(s)
	GameEvents.refresh_hud()

func delete_selected() -> void:
	if not held.is_empty() or not records.has(selected):
		return
	var item: Dictionary = records[selected]
	var group := [selected]
	var retained_walls: Array[String] = []
	if str(item.kind)=="floor":
		if not rooms.built_room(item):
			return
		for id in rooms.room_members(selected):
			if id!=selected and str(records[id].kind)=="item":
				GameEvents.notify(tr("Сначала вынеси мебель из комнаты."))
				return
			if rooms.structural_wall(records[id]):
				if construction.serves_neighbor(records[id],selected):
					retained_walls.append(id)
				else:
					group.append(id)
	var before := storage.snapshot()
	for id in retained_walls:
		records[id].erase("room_owner")
	for id in group:
		records[id].deleted = true
		apply_item(id)
	scene_finish.sync_ceilings()
	selected = ""
	storage.record_change(before)
	GameEvents.refresh_hud()









func go_room(id: String) -> void:
	if not data.rooms.has(id):
		return
	var s: Dictionary = data.rooms[id]
	player.move_to(rooms.room_point(id,vector(s.p)),rooms.room_point(id,vector(s.t)))

func set_modal(open: bool) -> void:
	modal = open
	player.paused = open
	frames.update_target_frames()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if player == null or modal:
		return
	var below_street: bool = subway.underground(player.global_position)
	if below_street and player.is_on_floor():
		player.safe_floor = player.global_position
		player.has_safe_floor = true
	if player.global_position.y < -1.2 and not below_street:
		var safe: Vector3 = player.safe_floor
		if player.has_safe_floor and rooms.floor_below(Vector2(safe.x,safe.z)):
			player.return_to_floor()
		else:
			go_room("kitchen")
		GameEvents.notify(tr("Возврат на пол"))
	aim_timer -= delta
	if aim_timer > 0:
		return
	aim_timer = 0.036 if not game_mode else .15
	if not game_mode:
		aim = ray_target()
		update_preview()
	GameEvents.refresh_hud()












func place_on_plan(point: Vector2) -> void:
	if held.is_empty():
		return
	var ground := rooms.ground_height(point)
	if str(held.kind)!="floor" and not is_finite(ground):
		GameEvents.notify(tr("Под точкой установки нет пола."))
		return
	held.x = point.x
	held.z = point.y
	held.y = ground if is_finite(ground) else 0.0
	if str(held.kind)=="floor":
		held.y -= float(held.h)
	commit_preview()

func ground_selection() -> void:
	var item: Dictionary = records.get(selected,{})
	if not held.is_empty() or item.is_empty() or not openings.kind(item).is_empty():
		return
	if str(item.kind)=="floor":
		plan_property("y",float(item.y)-rooms.floor_surface(item))
		return
	var ground := rooms.ground_height(Vector2(float(item.x),float(item.z)))
	if not is_finite(ground):
		GameEvents.notify(tr("Под выбранным объектом нет пола."))
		return
	plan_property("y",ground)

func wall_cuts_fit(wall: Dictionary) -> bool:
	for cut in records.values():
		if not bool(cut.deleted) and str(cut.get("wall_id",""))==str(wall.id) and not openings.fits(cut,wall):
			return false
	return true

func plan_property(key: String, value: float) -> void:
	if not held.is_empty():
		if key in ["w","h","d","r"]:
			if key=="r":
				held_rotated = true
			held[key] = value
			hud.refresh_held(held)
		return
	if not records.has(selected):
		return
	var item: Dictionary = records[selected]
	if item.has("wall_id"):
		var next := item.duplicate(true)
		match key:
			"w","h": next[key] = maxf(.28,value)
			"y": next.sill = maxf(0,value-float(records[item.wall_id].y))
			_: return
		if openings.fits(next,records[item.wall_id]):
			openings.place(next)
		else:
			GameEvents.notify(tr("Размер выходит за границы стены или пересекает соседний проём."))
		return
	if str(item.kind)=="floor" and not str(item.get("zone","")).is_empty() and key in ["x","z"]:
		var p := Vector2(float(item.x),float(item.z))
		if key=="x":
			p.x=value
		else:
			p.y=value
		rooms.begin_room_move(selected)
		rooms.preview_room_move(p)
		rooms.finish_room_move()
		return
	if str(item.kind)=="floor" and not str(item.get("zone","")).is_empty() and key=="y":
		var prior := storage.snapshot()
		var delta := value-float(item.y)
		for id in rooms.room_members(selected):
			records[id].y = float(records[id].y)+delta
			apply_item(id)
		rooms.sync_room_details()
		storage.record_change(prior)
		return
	if rooms.resizable_room(selected) and key in ["w","d"]:
		var next := rooms.room_world_bounds(item)
		var rotated := absf(sin(deg_to_rad(float(item.r))))>.9999
		if (key=="w")!=rotated:
			next.size.x=maxf(1.10,value)
		else:
			next.size.y=maxf(1.10,value)
		rooms.begin_room_resize(selected)
		rooms.preview_room_resize(next)
		rooms.finish_room_resize()
		return
	var before := storage.snapshot()
	if key in ["w","h","d"] and openings.wall_meshes.has(selected):
		var next := item.duplicate()
		next[key] = value
		if not wall_cuts_fit(next):
			GameEvents.notify(tr("Стена слишком мала для установленных дверей или окон."))
			return
	item[key] = value
	apply_item(selected)
	if rooms.built_room(item):
		scene_finish.sync_ceilings()
	storage.record_change(before)
	GameEvents.refresh_hud()
