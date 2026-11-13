class_name ProjectStorage
extends RefCounted
## Saving, loading, validation and undo history for the house layout.

static var SAVE_PATH := SavePaths.file("radion_home.json")
var history: Array[String] = []
var dirty := false
var home: Home

func _init(game_home: Home) -> void:
	home = game_home

func snapshot() -> String:
	return JSON.stringify({"format":"radion-home-editor","version":5,"compounds":true,"objects":home.records.values()})

func record_change(before: String) -> void:
	if before == snapshot():
		return
	history.append(before)
	if history.size() > 25:
		history.pop_front()
	dirty = true
	home.scene_finish.sync_ceilings()
	if home.party.is_inside_tree():
		home.party.sync_deck()
		if home.party.active or home.party.starting:
			home.party.stop()
			GameEvents.notify(tr("Планировка изменилась. Вечеринку можно запустить заново у пульта."))
	GameEvents.refresh_hud()

func repair_seams(remember: bool = true) -> int:
	if not home.held.is_empty():
		if remember:
			GameEvents.notify(tr("Сначала поставь предмет из рук."))
		return 0
	var pieces := home.seams.collect()
	if pieces.is_empty():
		if remember:
			GameEvents.notify(tr("Узких щелей для заделки не найдено."))
		return 0
	if not home.construction.commit({"pieces":pieces},false,remember):
		return 0
	if remember:
		GameEvents.notify(tr("Заделано стыков: %d") % pieces.size())
	return pieces.size()

func save_project(path: String = SAVE_PATH) -> void:
	home.rooms.finish_room_move()
	home.rooms.finish_room_resize()
	if not home.held.is_empty():
		GameEvents.notify(tr("Сначала поставь предмет."))
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		GameEvents.notify(tr("Не удалось сохранить проект."))
		return
	file.store_string(snapshot())
	file.close()
	if path == SAVE_PATH:
		dirty = false
	GameEvents.notify(tr("Проект сохранён."))
	GameEvents.refresh_hud()

func load_project(path: String, record: bool = true) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var before := snapshot()
	if not restore_project(parsed):
		GameEvents.notify(tr("Этот файл проекта не удалось открыть."))
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
		if home.originals.has(str(item.id)) or not home.make_template(str(item.get("template",""))).is_empty():
			incoming.append(item)
	home.rooms.cancel_room_move()
	home.rooms.cancel_room_resize()
	home.cancel_hold()
	if home.party.is_inside_tree():
		home.party.stop()
	for id in home.openings.wall_meshes.keys():
		home.openings.clear_wall(id)
	for id in home.records.keys():
		if not home.originals.has(id):
			home.remove_body(id)
			home.nodes[id].free()
			home.nodes.erase(id)
			home.records.erase(id)
	for id in home.originals:
		home.records[id] = home.originals[id].duplicate(true)
	for item in incoming:
		var id := str(item.id)
		var row: Dictionary = home.records.get(id, {})
		if row.is_empty():
			var key := str(item.get("template",""))
			row = home.make_template(key)
			var model := home.duplicate_model(key)
			if row.is_empty() or model == null:
				continue
			row.id = id
			home.add_child(model)
			home.nodes[id] = model
			home.records[id] = row
		for key in ["x","y","z","w","h","d","r","label","deleted","room_owner","wall_id","wall_offset","sill","opening_kind","managed_wall"]:
			if item.has(key):
				row[key] = item[key]
		if home.rooms.built_room(item):
			row.zone = id
		if int(project.get("version",1))<3 and str(row.get("template",""))=="wall" and is_equal_approx(float(row.h),2.65):
			row.h = SceneFinish.WALL_HEIGHT
		if home.openings.kind(row)=="door" and str(row.get("template",""))=="opening":
			home.openings.add_door_leaf(home.nodes[id],home.vector(row.dimensions))
	if int(project.get("version",1))<2:
		home.openings.install_stock_passages()
		home.openings.install_studio_windows()
	for id in home.records:
		home.apply_item(id)
	if int(project.get("version",1))<4:
		repair_seams(false)
	if int(project.get("version",1))<5:
		repair_hallway()
	home.rooms.sync_room_details()
	if home.night_world.initialized:
		home.night_world.refresh()
	if home.party.is_inside_tree():
		home.party.sync_deck()
	home.selected = ""
	GameEvents.refresh_hud()
	return true

func repair_hallway() -> void:
	var hall: Dictionary = home.records.get("base-39",{})
	var north: Dictionary = home.records.get("base-24",{})
	var south: Dictionary = home.records.get("base-4",{})
	if hall.is_empty() or north.is_empty() or south.is_empty():
		return
	var edge := home.rooms.room_world_bounds(hall).end.x
	var roof_end := home.rooms.room_world_bounds(north).end.x
	if absf(edge+2.35)>.08 or absf(roof_end+.85)>.10 or absf(float(south.z)+.05)>.08:
		return
	hall.x = float(hall.x)+(roof_end-edge)*.5
	hall.w = float(hall.w)+roof_end-edge
	home.apply_item("base-39")
	var start := home.rooms.room_world_bounds(south).end.x
	var doorway := Vector2(-1.48-.46,-1.48+.46)
	var patches: Array[Dictionary] = []
	for span in [Vector2(start,doorway.x),Vector2(doorway.x,doorway.y),Vector2(doorway.y,roof_end)]:
		if span.y<=span.x+.03:
			continue
		var patch := home.construction.wall_piece(Vector2(span.x,float(south.z)),Vector2(span.y,float(south.z)),float(south.y))
		patch.label = "Стена прихожей"
		patch.room_owner = "hall"
		if span.x==doorway.x:
			patch.y = float(south.y)+2.10
			patch.h = .60
		patches.append(patch)
	home.construction.commit({"pieces":patches},false,false)

func undo() -> void:
	if history.is_empty():
		return
	restore_project(JSON.parse_string(history.pop_back()))
	dirty = true
	GameEvents.refresh_hud()
