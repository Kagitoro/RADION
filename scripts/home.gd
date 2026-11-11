extends Node3D

const Player = preload("res://scripts/player.gd")
const HUD = preload("res://scripts/hud.gd")
const Openings = preload("res://scripts/openings.gd")
const Construction = preload("res://scripts/construction.gd")
const SceneFinish = preload("res://scripts/scene_finish.gd")
const Party = preload("res://scripts/party.gd")
const Seams = preload("res://scripts/seams.gd")
const NightWorld = preload("res://scripts/night_world.gd")
const NightGame = preload("res://scripts/night_game.gd")
const SAVE_PATH := "user://radion_home.json"
const PICK_MASK := 2

@onready var house: Node3D = $HouseGeometry
var player
var hud
var data: Dictionary = {}
var records: Dictionary = {}
var originals: Dictionary = {}
var nodes: Dictionary = {}
var bodies: Dictionary = {}
var catalog: Dictionary = {}
var room_attachments: Array = []
var room_drag: Dictionary = {}
var room_resize: Dictionary = {}
var inventory: Array = []
var history: Array[String] = []
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
var dirty := false
var modal := false
var aim: Dictionary = {}
var aim_timer := 0.0
var target_frame: MeshInstance3D
var selected_frame: MeshInstance3D
var next_id := 1
var headless := false
var ground_root := Node3D.new()
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

func _ready() -> void:
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
	target_frame = add_target_frame(Color("#f3efdd"))
	selected_frame = add_target_frame(Color("#83f2a6"))
	setup_lighting()
	register_room_details()
	openings.prepare_studio_windows()
	openings.prepare_room_windows()
	openings.install_stock_passages()
	openings.install_studio_windows()
	for id in records:
		apply_item(id)
	scene_finish.sync_ceilings()
	if not "--smoke" in OS.get_cmdline_user_args() and not "--visual-smoke" in OS.get_cmdline_user_args() and FileAccess.file_exists(SAVE_PATH):
		load_project(SAVE_PATH, false)
	add_child(night_world)
	night_world.setup()
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.surface_at = footstep_surface
	scene_finish.setup_mirror()
	hud = HUD.new()
	hud.game = self
	add_child(hud)
	add_child(party)
	party.setup()
	night_world.dress_bar()
	add_child(night_game)
	night_game.setup()
	go_room("hall")
	if "--smoke" in OS.get_cmdline_user_args():
		call_deferred("smoke_test")
	elif "--visual-smoke" in OS.get_cmdline_user_args():
		call_deferred("visual_smoke")
	elif not headless:
		if game_mode and "--skip-menu" not in OS.get_cmdline_user_args():
			get_tree().auto_accept_quit = false
			night_game.menu.show_menu()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_instance_valid(night_game.menu):
		night_game.menu.quit_game()

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
	var surface := StandardMaterial3D.new()
	surface.albedo_color = Color("#647650")
	surface.roughness = 1.0
	var grass_texture := NoiseTexture2D.new()
	grass_texture.seamless = true
	var grass_noise := FastNoiseLite.new()
	grass_noise.frequency = .04
	grass_texture.noise = grass_noise
	var grass_ramp := Gradient.new()
	grass_ramp.colors = PackedColorArray([Color("#a7b7a1"),Color("#f5f6e5")])
	grass_texture.color_ramp = grass_ramp
	surface.albedo_texture = grass_texture
	surface.uv1_scale = Vector3(7,7,1)
	site.mesh = plane
	site.material_override = surface
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
		register_room_attachment(light,light.global_position)

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
		y = floor_surface(s) - 0.0375
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
	held_before = snapshot()
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
		hud.notice("Двери, окна и их стены можно перемещать на плане по Tab.")
		return
	held_before = snapshot()
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
	hud.refresh()

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
	placement_surface = "Пол"
	placement_supported = str(held.kind)=="floor"
	var snap_height := true
	if not aim.is_empty():
		point = aim.position
		var normal: Vector3 = aim.normal
		var target: Dictionary = records.get(aimed_id(),{})
		var name := str(target.get("label","Поверхность"))
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
			placement_surface = "Потолок / нижняя сторона"
			snap_height = false
			placement_supported = true
		else:
			placement_surface = name
			snap_height = false
			placement_supported = true
	var wall := structural_wall(held)
	if wall or not placement_supported:
		var ground := ground_height(Vector2(point.x,point.z))
		placement_supported = is_finite(ground)
		placement_surface = "Пол" if placement_supported else "Нет опоры"
		if placement_supported:
			point.y = ground
			snap_height = false
	if str(held.kind)=="floor":
		var ground := ground_height(Vector2(point.x,point.z))
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
		hud.notice("Наведи на пол или на поверхность, куда хочешь поставить предмет.")
		return
	commit_preview()

func secondary_interaction() -> void:
	if not held.is_empty():
		cancel_hold()
		return
	selected = aimed_id()
	hud.refresh()

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
	record_change(before)
	hud.clear_held()
	hud.refresh()

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
		hud.refresh()

func resize_width(value: float) -> void:
	if not held.is_empty():
		held.w = clampf(value, .024, 28.0)
		update_preview()
		hud.refresh_held(held)
	elif records.has(selected) and not plan_only(selected):
		var before := snapshot()
		records[selected].w = clampf(value, .024, 28.0)
		apply_item(selected)
		record_change(before)
	hud.refresh()

func adjust(direction: int, fine: bool) -> void:
	var s: Dictionary = held if not held.is_empty() else records.get(selected, {})
	if s.is_empty() or (held.is_empty() and (str(s.kind)=="floor" or plan_only(selected))):
		return
	var before := snapshot() if held.is_empty() else ""
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
		record_change(before)
	else:
		update_preview()
		hud.refresh_held(s)
	hud.refresh()

func delete_selected() -> void:
	if not held.is_empty() or not records.has(selected):
		return
	var item: Dictionary = records[selected]
	var group := [selected]
	var retained_walls: Array[String] = []
	if str(item.kind)=="floor":
		if not built_room(item):
			return
		for id in room_members(selected):
			if id!=selected and str(records[id].kind)=="item":
				hud.notice("Сначала вынеси мебель из комнаты.")
				return
			if structural_wall(records[id]):
				if construction.serves_neighbor(records[id],selected):
					retained_walls.append(id)
				else:
					group.append(id)
	var before := snapshot()
	for id in retained_walls:
		records[id].erase("room_owner")
	for id in group:
		records[id].deleted = true
		apply_item(id)
	scene_finish.sync_ceilings()
	selected = ""
	record_change(before)
	hud.refresh()

func snapshot() -> String:
	return JSON.stringify({"format":"radion-home-editor","version":5,"compounds":true,"objects":records.values()})

func record_change(before: String) -> void:
	if before == snapshot():
		return
	history.append(before)
	if history.size() > 25:
		history.pop_front()
	dirty = true
	scene_finish.sync_ceilings()
	if party.is_inside_tree():
		party.sync_deck()
		if party.active or party.starting:
			party.stop()
			hud.notice("Планировка изменилась. Вечеринку можно запустить заново у пульта.")
	if hud != null:
		hud.refresh()

func repair_seams(remember: bool = true) -> int:
	if not held.is_empty():
		if remember:
			hud.notice("Сначала поставь предмет из рук.")
		return 0
	var pieces := seams.collect()
	if pieces.is_empty():
		if remember:
			hud.notice("Узких щелей для заделки не найдено.")
		return 0
	if not construction.commit({"pieces":pieces},false,remember):
		return 0
	if remember:
		hud.notice("Заделано стыков: %d" % pieces.size())
	return pieces.size()

func save_project(path: String = SAVE_PATH) -> void:
	finish_room_move()
	finish_room_resize()
	if not held.is_empty():
		hud.notice("Сначала поставь предмет.")
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		hud.notice("Не удалось сохранить проект.")
		return
	file.store_string(snapshot())
	file.close()
	if path == SAVE_PATH:
		dirty = false
	hud.notice("Проект сохранён.")
	hud.refresh()

func load_project(path: String, record: bool = true) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var before := snapshot()
	if not restore_project(parsed):
		if hud != null:
			hud.notice("Этот файл проекта не удалось открыть.")
		return false
	if record:
		record_change(before)
	return true

func restore_project(project) -> bool:
	if not project is Dictionary or project.get("format","") != "radion-home-editor" or not project.get("objects") is Array or project.objects.size() > 700:
		return false
	var incoming: Array = []
	for item in project.objects:
		if not item is Dictionary or not item.has("id"):
			return false
		var good := true
		for key in ["x","y","z","w","h","d","r"]:
			if not item.has(key) or not (item[key] is float or item[key] is int) or not is_finite(float(item[key])):
				good = false
		if not good or float(item.w) <= 0.0 or float(item.h) <= 0.0 or float(item.d) <= 0.0:
			return false
		if item.has("wall_id"):
			for key in ["wall_offset","sill"]:
				var value = item.get(key)
				if not (value is float or value is int) or not is_finite(float(value)):
					return false
		if originals.has(str(item.id)) or not make_template(str(item.get("template",""))).is_empty():
			incoming.append(item)
	cancel_room_move()
	cancel_room_resize()
	cancel_hold()
	if party.is_inside_tree():
		party.stop()
	for id in openings.wall_meshes.keys():
		openings.clear_wall(id)
	for id in records.keys():
		if not originals.has(id):
			remove_body(id)
			nodes[id].free()
			nodes.erase(id)
			records.erase(id)
	for id in originals:
		records[id] = originals[id].duplicate(true)
	for item in incoming:
		var id := str(item.id)
		var row: Dictionary = records.get(id, {})
		if row.is_empty():
			var key := str(item.get("template",""))
			row = make_template(key)
			var model := duplicate_model(key)
			if row.is_empty() or model == null:
				continue
			row.id = id
			add_child(model)
			nodes[id] = model
			records[id] = row
		for key in ["x","y","z","w","h","d","r","label","deleted","room_owner","wall_id","wall_offset","sill","opening_kind","managed_wall"]:
			if item.has(key):
				row[key] = item[key]
		if built_room(item):
			row.zone = id
		if int(project.get("version",1))<3 and str(row.get("template",""))=="wall" and is_equal_approx(float(row.h),2.65):
			row.h = SceneFinish.WALL_HEIGHT
		if openings.kind(row)=="door" and str(row.get("template",""))=="opening":
			openings.add_door_leaf(nodes[id],vector(row.dimensions))
	if int(project.get("version",1))<2:
		openings.install_stock_passages()
		openings.install_studio_windows()
	for id in records:
		apply_item(id)
	if int(project.get("version",1))<4:
		repair_seams(false)
	if int(project.get("version",1))<5:
		repair_hallway()
	sync_room_details()
	if night_world.initialized:
		night_world.refresh()
	if party.is_inside_tree():
		party.sync_deck()
	selected = ""
	if hud != null:
		hud.refresh()
	return true

func repair_hallway() -> void:
	var hall: Dictionary = records.get("base-39",{})
	var north: Dictionary = records.get("base-24",{})
	var south: Dictionary = records.get("base-4",{})
	if hall.is_empty() or north.is_empty() or south.is_empty():
		return
	var edge := room_world_bounds(hall).end.x
	var roof_end := room_world_bounds(north).end.x
	if absf(edge+2.35)>.08 or absf(roof_end+.85)>.10 or absf(float(south.z)+.05)>.08:
		return
	hall.x = float(hall.x)+(roof_end-edge)*.5
	hall.w = float(hall.w)+roof_end-edge
	apply_item("base-39")
	var start := room_world_bounds(south).end.x
	var doorway := Vector2(-1.48-.46,-1.48+.46)
	var patches: Array[Dictionary] = []
	for span in [Vector2(start,doorway.x),Vector2(doorway.x,doorway.y),Vector2(doorway.y,roof_end)]:
		if span.y<=span.x+.03:
			continue
		var patch := construction.wall_piece(Vector2(span.x,float(south.z)),Vector2(span.y,float(south.z)),float(south.y))
		patch.label = "Стена прихожей"
		patch.room_owner = "hall"
		if span.x==doorway.x:
			patch.y = float(south.y)+2.10
			patch.h = .60
		patches.append(patch)
	construction.commit({"pieces":patches},false,false)

func undo() -> void:
	if history.is_empty():
		return
	restore_project(JSON.parse_string(history.pop_back()))
	dirty = true
	hud.refresh()

func go_room(id: String) -> void:
	if not data.rooms.has(id):
		return
	var s: Dictionary = data.rooms[id]
	player.move_to(room_point(id,vector(s.p)),room_point(id,vector(s.t)))

func set_modal(open: bool) -> void:
	modal = open
	player.paused = open
	update_target_frames()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if player == null or modal:
		return
	if player.global_position.y < -1.2:
		var safe: Vector3 = player.safe_floor
		if player.has_safe_floor and floor_below(Vector2(safe.x,safe.z)):
			player.return_to_floor()
		else:
			go_room("kitchen")
		hud.notice("Возврат на пол")
	aim_timer -= delta
	if aim_timer > 0:
		return
	aim_timer = 0.036 if not game_mode else .15
	if not game_mode:
		aim = ray_target()
		update_preview()
	hud.refresh()

func floor_below(point: Vector2) -> bool:
	return is_finite(ground_height(point))

func structural_wall(row: Dictionary) -> bool:
	return not row.is_empty() and not bool(row.deleted) and str(row.kind)=="wall" and bool(row.solid) and openings.kind(row).is_empty()

func wall_in_room(wall: Dictionary, zone: String) -> bool:
	for row in records.values():
		if str(row.kind)=="floor" and not bool(row.deleted) and str(row.get("zone",""))==zone:
			return inside_room(row,Vector2(float(wall.x),float(wall.z)),.14)
	return false

func floor_surface(row: Dictionary) -> float:
	if str(row.get("template",""))=="floor":
		return float(row.y)+float(row.h)
	match str(row.get("zone","")):
		"studio": return float(row.y)+.12
		"": return float(row.y)+float(row.h)
	return float(row.y)

func footstep_surface(point: Vector3) -> String:
	var planar := Vector2(point.x,point.z)
	for row in records.values():
		if bool(row.deleted) or not inside_room(row,planar):
			continue
		if "Ковёр" in str(row.label) and absf(point.y-float(row.y))<.2:
			return "rug"
		if str(row.kind)=="floor" and absf(point.y-floor_surface(row))<.24:
			if str(row.id)=="night-courtyard" or str(row.get("zone","")) in ["hall","bath","kitchen"]:
				return "tile"
	return "wood"

func built_room(row: Dictionary) -> bool:
	var id := str(row.get("id",""))
	return id.begins_with("build-") and str(row.get("template",""))=="floor" and str(row.get("zone",""))==id

func ground_height(point: Vector2) -> float:
	var height := night_world.club_ground_at(point)
	for row in records.values():
		if str(row.kind)=="floor" and not bool(row.deleted) and inside_room(row,point,.085):
			height = maxf(height,floor_surface(row))
	return height

func _unhandled_input(event: InputEvent) -> void:
	if player == null:
		return
	if game_mode:
		game_input(event)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_TAB:
				hud.toggle_plan()
				return
			KEY_E:
				hud.toggle_inventory()
				return
			KEY_ESCAPE:
				if hud.menu.visible:
					hud.close_inventory()
				elif hud.plan.visible:
					if not hud.plan.opening_tool.is_empty() or not hud.plan.build_tool.is_empty():
						hud.plan.set_layer(hud.plan.layer)
						hud.refresh()
					else:
						hud.toggle_plan()
				elif not held.is_empty():
					cancel_hold()
				else:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				return
		if event.ctrl_pressed:
			if event.physical_keycode == KEY_S:
				save_project()
			elif event.physical_keycode == KEY_Z:
				if hud.plan.visible:
					hud.plan.cancel_construction()
				undo()
			return
		if event.physical_keycode==KEY_DELETE and hud.plan.visible and not hud.menu.visible:
			delete_selected()
			hud.plan.queue_redraw()
			return
		if event.physical_keycode==KEY_R and hud.plan.visible and not hud.menu.visible and structural_wall(held):
			held.r = fposmod(float(held.r)+90.0,360.0)
			hud.plan.queue_redraw()
			hud.refresh()
			return
		if modal:
			return
		match event.physical_keycode:
			KEY_J: party.toggle()
			KEY_B: party.consume(true)
			KEY_N: party.consume(false)
			KEY_K: party.extinguish()
			KEY_P: party.buy_cigarettes()
			KEY_1, KEY_2, KEY_3:
				if party.near_deck():
					party.switch_track(event.physical_keycode-KEY_1)
			KEY_M:
				if party.near_deck():
					party.beat_mix()
			KEY_R: tool = "rotate"
			KEY_T:
				tool = "size"
				axis = "all"
			KEY_X:
				tool = "size"
				axis = "x"
			KEY_Y:
				tool = "size"
				axis = "y"
			KEY_Z:
				tool = "size"
				axis = "z"
			KEY_H: tool = "lift"
			KEY_F:
				player.airborne = not player.airborne
			KEY_DELETE: delete_selected()
			KEY_F1: go_room("kitchen")
			KEY_F2: go_room("hall")
			KEY_F3: go_room("bath")
			KEY_F4: go_room("living")
			KEY_F5: go_room("studio")
		hud.refresh()
	if modal:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player.look_motion(event.relative)
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				else:
					aim = ray_target()
					interact()
			MOUSE_BUTTON_RIGHT:
				aim = ray_target()
				secondary_interaction()
			MOUSE_BUTTON_WHEEL_UP: adjust(1,event.shift_pressed)
			MOUSE_BUTTON_WHEEL_DOWN: adjust(-1,event.shift_pressed)

func game_input(event: InputEvent) -> void:
	if night_game.menu.opened:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		night_game.key(event.physical_keycode)
	elif event is InputEventMouseMotion and not modal and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		player.look_motion(event.relative)
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and not modal:
		if night_game.click_controller():
			return
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func smoke_test() -> void:
	var errors: Array[String] = []
	var stock_size := records.size()
	if records.size() < 180 or inventory.size() < 35 or catalog.size() < 10:
		errors.append("Неполная сцена или библиотека")
	var stove := ""
	for id in originals:
		if str(originals[id].label) == "Плита и духовой шкаф":
			stove = id
			break
	if stove.is_empty():
		errors.append("Нет плиты")
	else:
		selected = ""
		var stale_collider: StaticBody3D = bodies[stove]
		aim = {"collider":stale_collider}
		interact()
		if grabbed != stove or str(held.get("id","")) != stove or not aimed_id().is_empty():
			errors.append("ЛКМ оставляет старую цель после взятия предмета")
		aim = {"collider":stale_collider}
		if not aimed_id().is_empty():
			errors.append("Удалённая цель всё ещё доступна")
		aim.clear()
		cancel_hold()
		if not bodies.has(stove):
			errors.append("Отмена взятия не восстановила коллизию")
		take_template(stove)
		if held.is_empty():
			errors.append("Не получилось взять предмет")
		else:
			var w := float(held.w)
			resize_width(w + 0.22)
			interact()
			if not records.has(selected) or absf(float(records[selected].w) - w - .22) > .001:
				errors.append("Ошибка установки или ширины")
			undo()
			if records.size() != stock_size:
				errors.append("Отмена не вернула исходные объекты")
	var studio := room_floor("studio")
	var desk_id := ""
	var fridge_id := ""
	for row in originals.values():
		if row.label=="Рабочий стол":
			desk_id=str(row.id)
		elif row.label=="Холодильник":
			fridge_id=str(row.id)
	var origin := Vector2(float(studio.x),float(studio.z))
	var offset := Vector2(2.15,2.70)
	var desk_x := float(records[desk_id].x)
	var fridge_x := float(records[fridge_id].x)
	var item_ids := records.keys()
	var shared_wall: Dictionary = records["base-27"].duplicate(true)
	begin_room_move(str(studio.id))
	if not room_drag.members.has(desk_id):
		errors.append("Не определена мебель комнаты")
	preview_room_move(origin+offset)
	finish_room_move()
	if absf(float(records[desk_id].x)-desk_x-offset.x)>.001 or absf(float(records[fridge_id].x)-fridge_x)>.001:
		errors.append("Комната не перенесла мебель независимо от соседей")
	if records.keys()!=item_ids or records["base-27"]!=shared_wall:
		errors.append("Перенос добавил объекты или изменил общую стену")
	if not restore_project(JSON.parse_string(snapshot())) or absf(float(records[str(studio.id)].z)-origin.y-offset.y)>.001:
		errors.append("Положение перенесённой комнаты не восстановилось")
	undo()
	if absf(float(records[str(studio.id)].x)-origin.x)>.001 or records.size()!=stock_size:
		errors.append("Отмена переноса комнаты не сработала")
	print("ROOM_MOVE furniture and unchanged shared wall verified")






	var smoke_path := "user://radion_smoke_test.json"
	save_project(smoke_path)
	if not load_project(smoke_path, false):
		errors.append("Ручное сохранение не читается")
	if FileAccess.file_exists(smoke_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(smoke_path))
	if not restore_project(JSON.parse_string(snapshot())):
		errors.append("Снимок проекта не читается")
	print("RADION_SMOKE objects=%d inventory=%d catalog=%d errors=%s" % [originals.size(),inventory.size(),catalog.size(),str(errors)])
	get_tree().quit(0 if errors.is_empty() else 1)

func place_on_plan(point: Vector2) -> void:
	if held.is_empty():
		return
	var ground := ground_height(point)
	if str(held.kind)!="floor" and not is_finite(ground):
		hud.notice("Под точкой установки нет пола.")
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
		plan_property("y",float(item.y)-floor_surface(item))
		return
	var ground := ground_height(Vector2(float(item.x),float(item.z)))
	if not is_finite(ground):
		hud.notice("Под выбранным объектом нет пола.")
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
			hud.notice("Размер выходит за границы стены или пересекает соседний проём.")
		return
	if str(item.kind)=="floor" and not str(item.get("zone","")).is_empty() and key in ["x","z"]:
		var p := Vector2(float(item.x),float(item.z))
		if key=="x":
			p.x=value
		else:
			p.y=value
		begin_room_move(selected)
		preview_room_move(p)
		finish_room_move()
		return
	if str(item.kind)=="floor" and not str(item.get("zone","")).is_empty() and key=="y":
		var prior := snapshot()
		var delta := value-float(item.y)
		for id in room_members(selected):
			records[id].y = float(records[id].y)+delta
			apply_item(id)
		sync_room_details()
		record_change(prior)
		return
	if resizable_room(selected) and key in ["w","d"]:
		var next := room_world_bounds(item)
		var rotated := absf(sin(deg_to_rad(float(item.r))))>.9999
		if (key=="w")!=rotated:
			next.size.x=maxf(1.10,value)
		else:
			next.size.y=maxf(1.10,value)
		begin_room_resize(selected)
		preview_room_resize(next)
		finish_room_resize()
		return
	var before := snapshot()
	if key in ["w","h","d"] and openings.wall_meshes.has(selected):
		var next := item.duplicate()
		next[key] = value
		if not wall_cuts_fit(next):
			hud.notice("Стена слишком мала для установленных дверей или окон.")
			return
	item[key] = value
	apply_item(selected)
	if built_room(item):
		scene_finish.sync_ceilings()
	record_change(before)
	hud.refresh()

func visual_smoke() -> void:
	await get_tree().create_timer(.7).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://kitchen-test.png")
	go_room("studio")
	await get_tree().create_timer(.55).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://studio-test.png")
	take_template("chair")
	await get_tree().create_timer(.55).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://held-test.png")
	print("RADION_VISUAL ready")
	get_tree().quit()


func room_point(id: String, point: Vector3) -> Vector3:
	for key in originals:
		var original: Dictionary = originals[key]
		if str(original.get("zone","")) != id or str(original.kind) != "floor":
			continue
		var room: Dictionary = records[key]
		var local := Vector3((point.x-float(original.x))*float(room.w)/float(original.w),
			point.y-float(original.y),(point.z-float(original.z))*float(room.d)/float(original.d))
		return local.rotated(Vector3.UP,deg_to_rad(float(room.r)))+Vector3(float(room.x),float(room.y),float(room.z))
	return point

func inside_room(s: Dictionary, at: Vector2, margin: float = 0.0) -> bool:
	var local := (at-Vector2(float(s.x),float(s.z))).rotated(deg_to_rad(float(s.r)))
	return absf(local.x)<=float(s.w)*.5+margin and absf(local.y)<=float(s.d)*.5+margin

func edge_of_room(s: Dictionary, at: Vector2, tolerance: float = .17) -> bool:
	var local := (at-Vector2(float(s.x),float(s.z))).rotated(deg_to_rad(float(s.r)))
	var dx := absf(local.x)-float(s.w)*.5
	var dz := absf(local.y)-float(s.d)*.5
	return (absf(dx)<=tolerance and dz<=tolerance) or (absf(dz)<=tolerance and dx<=tolerance)

func room_floor(id: String) -> Dictionary:
	for original in originals.values():
		if str(original.kind)=="floor" and str(original.get("zone",""))==id:
			return original
	return {}

func register_room_attachment(node: Node3D, at: Vector3) -> void:
	for id in data.rooms:
		var room: Dictionary = data.rooms[id]
		var rect: Array = room.rect
		if at.x>=float(rect[0]) and at.x<=float(rect[1]) and at.z>=float(rect[2]) and at.z<=float(rect[3]):
			room_attachments.append({"node":node,"zone":id,"p":node.global_position})
			return

func register_room_details() -> void:
	var editable_nodes := {}
	for node in nodes.values():
		editable_nodes[node] = true
	for child in house.find_children("*","MeshInstance3D",true,false):
		var current: Node = child
		var editable := false
		while current!=null and current!=house:
			if editable_nodes.has(current) or current.name=="Catalog":
				editable = true
				break
			current = current.get_parent()
		if not editable:
			var model := child as MeshInstance3D
			register_room_attachment(model,model.global_transform*model.get_aabb().get_center())

func sync_room_details() -> void:
	scene_finish.sync_ceilings()
	for item in room_attachments:
		var original := room_floor(item.zone)
		if original.is_empty():
			continue
		item.node.global_position = room_point(item.zone,item.p)

func room_members(id: String) -> Dictionary:
	var floor_state: Dictionary = records[id]
	var zone := str(floor_state.get("zone",""))
	var members := {}
	var neighbors: Array[Dictionary] = []
	for row in records.values():
		if str(row.id)!=id and str(row.kind)=="floor" and not bool(row.deleted) and not str(row.get("zone","")).is_empty():
			neighbors.append(row)
	for key in records:
		var item: Dictionary = records[key]
		if bool(item.deleted) or item.has("wall_id") or (str(item.kind)=="floor" and key!=id):
			continue
		var point := Vector2(float(item.x),float(item.z))
		var owner := str(item.get("room_owner",""))
		if not owner.is_empty() and owner!=zone:
			continue
		if key!=id and owner!=zone and not inside_room(floor_state,point,.14 if str(item.kind)=="wall" else .025):
			continue
		if owner.is_empty() and str(item.kind)=="wall" and edge_of_room(floor_state,point):
			if neighbors.any(func(neighbor): return edge_of_room(neighbor,point)):
				continue
		members[key] = point
	return members

func begin_room_move(id: String) -> void:
	var floor_state: Dictionary = records.get(id,{})
	var zone := str(floor_state.get("zone",""))
	if floor_state.is_empty() or zone.is_empty() or str(floor_state.kind)!="floor":
		return
	room_drag = {"id":id,"zone":zone,"start":Vector2(float(floor_state.x),float(floor_state.z)),
		"members":room_members(id),"before":snapshot(),"delta":Vector2.ZERO}

func preview_room_move(to: Vector2) -> void:
	if room_drag.is_empty():
		return
	var delta: Vector2 = to-room_drag.start
	room_drag.delta = delta
	for id in room_drag.members:
		var p: Vector2 = room_drag.members[id]+delta
		records[id].x = p.x
		records[id].z = p.y
		transform_item(nodes[id],records[id])
	openings.sync_positions()
	sync_room_details()

func finish_room_move() -> void:
	if room_drag.is_empty():
		return
	var operation := room_drag
	room_drag = {}
	var delta: Vector2 = operation.delta
	if delta.length_squared()<.000001:
		return
	for id in operation.members:
		records[id].room_owner = operation.zone
		apply_item(id)
	sync_room_details()
	selected = operation.id
	record_change(operation.before)
	hud.refresh()

func cancel_room_move() -> void:
	if room_drag.is_empty():
		return
	preview_room_move(room_drag.start)
	room_drag = {}



const FRAME_EDGES = [[0,1],[0,2],[0,4],[1,3],[1,5],[2,3],[2,6],[3,7],[4,5],[4,6],[5,7],[6,7]]

func add_target_frame(color: Color) -> MeshInstance3D:
	var frame := MeshInstance3D.new()
	frame.mesh = ImmediateMesh.new()
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	frame.material_override = material
	add_child(frame)
	frame.hide()
	return frame

func frame_state(frame: MeshInstance3D, item: Dictionary) -> void:
	if item.is_empty() or bool(item.get("deleted",false)) or str(item.kind)=="floor":
		frame.hide()
		return
	var size := dimensions(item)
	var padding := .015
	if frame.get_meta("size", Vector3.ZERO) != size:
		var lines := frame.mesh as ImmediateMesh
		lines.clear_surfaces()
		var corners: Array[Vector3] = []
		for i in range(8):
			corners.append(Vector3(
				(size.x*.5+padding)*(-1.0 if (i&1)==0 else 1.0),
				-padding if (i&2)==0 else size.y+padding,
				(size.z*.5+padding)*(-1.0 if (i&4)==0 else 1.0)))
		lines.surface_begin(Mesh.PRIMITIVE_LINES)
		for edge in FRAME_EDGES:
			lines.surface_add_vertex(corners[edge[0]])
			lines.surface_add_vertex(corners[edge[1]])
		lines.surface_end()
		frame.set_meta("size",size)
	frame.position = Vector3(float(item.x),float(item.y),float(item.z))
	frame.rotation.y = deg_to_rad(float(item.r))
	frame.show()

func update_target_frames() -> void:
	if target_frame == null or selected_frame == null:
		return
	if game_mode:
		target_frame.hide()
		selected_frame.hide()
		return
	if modal:
		target_frame.hide()
		selected_frame.hide()
		return
	var hit_id := aimed_id()
	if not held.is_empty():
		target_frame.hide()
		frame_state(selected_frame,held)
		return
	frame_state(selected_frame,records.get(selected,{}))
	frame_state(target_frame,records.get(hit_id,{}) if hit_id!=selected else {})


func resizable_room(id: String) -> bool:
	var room: Dictionary = records.get(id,{})
	if room.is_empty() or str(room.kind)!="floor" or str(room.get("zone","")).is_empty() or bool(room.deleted):
		return false
	var a := deg_to_rad(float(room.r))
	return absf(cos(a))>.9999 or absf(sin(a))>.9999

func room_world_bounds(item: Dictionary) -> Rect2:
	var a := deg_to_rad(float(item.r))
	var c := absf(cos(a))
	var s := absf(sin(a))
	var size := Vector2(c*float(item.w)+s*float(item.d),s*float(item.w)+c*float(item.d))
	return Rect2(Vector2(float(item.x),float(item.z))-size*.5,size)

func begin_room_resize(id: String) -> void:
	if not resizable_room(id):
		return
	var baseline := {}
	for member in room_members(id):
		baseline[member] = records[member].duplicate(true)
	var neighbors: Array[Rect2] = []
	for item in records.values():
		if str(item.kind)=="floor" and str(item.id)!=id and not bool(item.deleted) and not str(item.get("zone","")).is_empty():
			neighbors.append(room_world_bounds(item))
	room_resize = {"id":id,"source":room_world_bounds(records[id]),"before":snapshot(),
		"baseline":baseline,"neighbors":neighbors,"changed":false}

func limit_room_resize(old: Rect2, requested: Rect2) -> Rect2:
	var first := requested.position
	var last := requested.end
	const TOLERANCE := .002
	for neighbor: Rect2 in room_resize.neighbors:
		if first.y<neighbor.end.y-TOLERANCE and last.y>neighbor.position.y+TOLERANCE:
			if neighbor.end.x<=old.position.x+TOLERANCE and first.x<old.position.x:
				first.x = maxf(first.x,minf(old.position.x,neighbor.end.x))
			if neighbor.position.x>=old.end.x-TOLERANCE and last.x>old.end.x:
				last.x = minf(last.x,maxf(old.end.x,neighbor.position.x))
		if first.x<neighbor.end.x-TOLERANCE and last.x>neighbor.position.x+TOLERANCE:
			if neighbor.end.y<=old.position.y+TOLERANCE and first.y<old.position.y:
				first.y = maxf(first.y,minf(old.position.y,neighbor.end.y))
			if neighbor.position.y>=old.end.y-TOLERANCE and last.y>old.end.y:
				last.y = minf(last.y,maxf(old.end.y,neighbor.position.y))
	return Rect2(first,last-first)

func resize_axis(value: float, low: float, high: float, next_low: float, next_high: float) -> float:
	if value <= low:
		return value + next_low-low
	if value >= high:
		return value + next_high-high
	return lerpf(next_low,next_high,(value-low)/(high-low))

func preview_room_resize(requested: Rect2) -> void:
	if room_resize.is_empty():
		return
	var old: Rect2 = room_resize.source
	var next := limit_room_resize(old,requested)
	room_resize.changed = not old.is_equal_approx(next)
	for id in room_resize.baseline:
		var base: Dictionary = room_resize.baseline[id]
		var live: Dictionary = records[id]
		var bx := float(base.x)
		var bz := float(base.z)
		var bounds := room_world_bounds(base)
		live.x = resize_axis(bx,old.position.x,old.end.x,next.position.x,next.end.x)
		live.z = resize_axis(bz,old.position.y,old.end.y,next.position.y,next.end.y)
		if str(base.kind) in ["floor","wall"]:
			var size := bounds.size
			var left := resize_axis(bx-size.x*.5,old.position.x,old.end.x,next.position.x,next.end.x)
			var right := resize_axis(bx+size.x*.5,old.position.x,old.end.x,next.position.x,next.end.x)
			var top := resize_axis(bz-size.y*.5,old.position.y,old.end.y,next.position.y,next.end.y)
			var bottom := resize_axis(bz+size.y*.5,old.position.y,old.end.y,next.position.y,next.end.y)
			var a := deg_to_rad(float(base.r))
			var c := absf(cos(a))
			var sn := absf(sin(a))
			if c>.9999 or sn>.9999:
				live.w = maxf(.024,right-left if c>.9999 else bottom-top)
				live.d = maxf(.024,bottom-top if c>.9999 else right-left)
			else:
				var dx := (right-left)/maxf(.024,size.x)
				var dz := (bottom-top)/maxf(.024,size.y)
				live.w = maxf(.024,float(base.w)*Vector2(c*dx,sn*dz).length())
				live.d = maxf(.024,float(base.d)*Vector2(sn*dx,c*dz).length())
			live.x = (left+right)*.5
			live.z = (top+bottom)*.5
		transform_item(nodes[id],live)
	openings.sync_positions()
	sync_room_details()

func finish_room_resize() -> void:
	if room_resize.is_empty():
		return
	var operation := room_resize
	room_resize={}
	if not bool(operation.changed):
		return
	for id in operation.baseline:
		apply_item(id)
	record_change(operation.before)
	hud.refresh()

func cancel_room_resize() -> void:
	if room_resize.is_empty():
		return
	preview_room_resize(room_resize.source)
	room_resize={}
