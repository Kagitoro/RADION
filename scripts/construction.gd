extends RefCounted

const EDGE_TOLERANCE := .02
const MIN_ROOM := 1.10

var home

func _init(editor) -> void:
	home = editor

func draft(mode: String, start: Vector2, end: Vector2) -> Dictionary:
	if absf(start.x)>70 or absf(start.y)>70 or absf(end.x)>70 or absf(end.y)>70:
		return {"error":"Строй в пределах плана."}
	if mode=="room":
		return draft_room(Rect2(start,end-start).abs())
	return draft_wall(start,end)

func draft_room(rect: Rect2) -> Dictionary:
	if minf(rect.size.x,rect.size.y)<MIN_ROOM:
		return {"error":"Минимальный размер комнаты — 1,1 × 1,1 м."}
	if maxf(rect.size.x,rect.size.y)>70:
		return {"error":"Сторона комнаты должна быть не длиннее 70 м."}
	for row in home.records.values():
		if bool(row.deleted) or str(row.kind)!="floor":
			continue
		var bounds: Rect2 = home.room_world_bounds(row)
		var overlap := bounds.intersection(rect)
		if overlap.size.x>.002 and overlap.size.y>.002:
			return {"error":"Здесь уже есть пол. Состыкуй комнаты по краю."}
	var middle := rect.get_center()
	var pieces: Array[Dictionary] = [{"template":"floor","x":middle.x,"z":middle.y,
		"y":-float(home.data.templates.floor.h),"w":rect.size.x,"d":rect.size.y}]
	var corners := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
	for index in range(4):
		pieces.append_array(uncovered_wall(corners[index],corners[(index+1)%4],0.0))
	return {"pieces":pieces}

func draft_wall(start: Vector2, end: Vector2) -> Dictionary:
	var length := start.distance_to(end)
	if length<.20 or length>70:
		return {"error":"Длина стены должна быть от 0,2 до 70 м."}
	var floors: Array[Dictionary] = []
	for row in home.records.values():
		if str(row.kind)=="floor" and not bool(row.deleted):
			floors.append(row)
	var level: float = home.ground_height(start)
	var steps := ceili(length/.20)
	for i in range(steps+1):
		var point := start.lerp(end,float(i)/steps)
		if not is_finite(level) or not floors.any(func(floor_row):
			return home.inside_room(floor_row,point,.085) and absf(float(home.floor_surface(floor_row))-level)<.025):
			return {"error":"Под всей стеной нужен пол одного уровня. Можно сначала нарисовать комнату."}
	var pieces := uncovered_wall(start,end,level)
	if pieces.is_empty():
		return {"error":"На этом отрезке уже есть стена."}
	return {"pieces":pieces}

func uncovered_wall(start: Vector2, end: Vector2, level: float) -> Array[Dictionary]:
	var axis := (end-start).normalized()
	var length := start.distance_to(end)
	var covered: Array[Vector2] = []
	for row in home.records.values():
		if not home.structural_wall(row) or absf(float(row.y)-level)>.025:
			continue
		var frame: Transform3D = home.openings.wall_frame(row)
		var run := Vector2(frame.basis.x.x,frame.basis.x.z)
		var center := Vector2(float(row.x),float(row.z))-start
		if absf(axis.cross(run))>.002 or absf(axis.cross(center))>EDGE_TOLERANCE:
			continue
		var half := float(home.openings.width(row))*.5
		var a := maxf(0,center.dot(axis)-half)
		var b := minf(length,center.dot(axis)+half)
		if b>a:
			covered.append(Vector2(a,b))
	covered.sort_custom(func(a,b): return a.x<b.x)
	var pieces: Array[Dictionary] = []
	var edge := 0.0
	for span in covered:
		if span.x>edge+EDGE_TOLERANCE:
			pieces.append(wall_piece(start+axis*edge,start+axis*span.x,level))
		edge = maxf(edge,span.y)
	if length>edge+EDGE_TOLERANCE:
		pieces.append(wall_piece(start+axis*edge,end,level))
	return pieces

func wall_piece(start: Vector2, end: Vector2, level: float) -> Dictionary:
	var middle := (start+end)*.5
	return {"template":"wall","x":middle.x,"y":level,"z":middle.y,
		"w":start.distance_to(end),"r":fposmod(rad_to_deg(-(end-start).angle()),360)}

func serves_neighbor(wall: Dictionary, excluded_room: String) -> bool:
	var frame: Transform3D = home.openings.wall_frame(wall)
	var axis := Vector2(frame.basis.x.x,frame.basis.x.z)
	if maxf(absf(axis.x),absf(axis.y))<.999:
		return false
	var along := 0 if absf(axis.x)>absf(axis.y) else 1
	var across := 1-along
	var center := Vector2(float(wall.x),float(wall.z))
	var half := float(home.openings.width(wall))*.5
	for row in home.records.values():
		if str(row.id)==excluded_room or str(row.kind)!="floor" or bool(row.deleted):
			continue
		var bounds: Rect2 = home.room_world_bounds(row)
		if absf(float(home.floor_surface(row))-float(wall.y))>.025:
			continue
		if minf(absf(center[across]-bounds.position[across]),absf(center[across]-bounds.end[across]))>EDGE_TOLERANCE:
			continue
		if minf(center[along]+half,bounds.end[along])-maxf(center[along]-half,bounds.position[along])>EDGE_TOLERANCE:
			return true
	return false

func commit(result: Dictionary, make_room: bool = true, remember: bool = true) -> bool:
	if result.has("error"):
		if home.hud!=null:
			home.hud.notice(str(result.error))
		return false
	var pieces: Array = result.pieces
	if home.records.size()+pieces.size()>700:
		if home.hud!=null:
			home.hud.notice("Достигнут предел в 700 элементов.")
		return false
	var models: Array[Node3D] = []
	for piece in pieces:
		var model: Node3D = home.duplicate_model(str(piece.template))
		if model==null:
			for pending in models:
				pending.free()
			return false
		models.append(model)
	var before: String = home.snapshot() if remember else ""
	var room_id := ""
	for index in range(pieces.size()):
		var piece: Dictionary = pieces[index]
		var row: Dictionary = home.make_template(str(piece.template))
		row.merge(piece,true)
		var id := "build-%d-%d" % [Time.get_ticks_msec(),home.next_id]
		home.next_id += 1
		row.id = id
		if make_room and str(piece.template)=="floor":
			room_id = id
			row.zone = id
			row.label = "Новая комната"
		elif not room_id.is_empty():
			row.room_owner = room_id
		home.records[id] = row
		home.nodes[id] = models[index]
		home.add_child(models[index])
		home.apply_item(id)
		if index==0 and make_room:
			home.selected = id
	if remember:
		home.record_change(before)
	home.scene_finish.sync_ceilings()
	if home.hud!=null:
		home.hud.refresh()
	return true
