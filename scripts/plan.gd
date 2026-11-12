class_name FloorPlan
extends Control

const REFERENCE_ROOMS := {
	"living": Rect2(3,8,5,4),
	"hall": Rect2(3,5,8,2.5),
	"bath": Rect2(7.5,8,3.5,3),
	"kitchen": Rect2(11,5,6,5),
	"studio": Rect2(17,6,5,3.5),
}

var game: Home
var layer := "all"
var zoom := 51.0
var center := Vector2.ZERO
var dragging := ""
var offset := Vector2.ZERO
var before := ""
var room_move := false
var resize_corner := Vector2.ZERO
var resize_start := Rect2()
var resize_anchor := Vector2.ZERO
var resizing := false
var opening_tool := ""
var opening_drag := ""
var opening_preview := {}
var opening_start := Vector2.ZERO
var hover := ""
var show_reference := false
var fitted := false
var magnets := true
var joint := {}
var wall_start := {}
var wall_handle := 0
var wall_supported := true
var build_tool := ""
var building := false
var build_start := Vector2.ZERO
var build_end := Vector2.ZERO
var build_preview := {}
var geometry := PlanSnapping.new(self)

func fit() -> void:
	var bounds := Rect2()
	for row in game.records.values():
		if bool(row.deleted) or str(row.kind)!="floor":
			continue
		var rect: Rect2 = game.rooms.room_world_bounds(row)
		bounds = rect if not bounds.has_area() else bounds.merge(rect)
	if not bounds.has_area():
		return
	zoom = clampf(minf((size.x-94)/bounds.size.x,(size.y-94)/bounds.size.y),10.0,100.0)
	center = bounds.get_center()
	fitted = true

func set_layer(kind: String) -> void:
	finish_drag()
	opening_tool = ""
	cancel_construction()
	layer = kind
	queue_redraw()

func set_opening_tool(type: String) -> void:
	set_layer("opening")
	opening_tool = type
	GameEvents.notify(tr("Наведи на стену и щёлкни для установки. ПКМ отменяет."))

func set_build_tool(type: String) -> void:
	var next := "" if build_tool==type else type
	set_layer("floor" if type=="room" else "wall")
	build_tool = next
	queue_redraw()

func cancel_construction() -> void:
	build_tool = ""
	building = false
	build_preview = {}
	queue_redraw()

func start_construction(point: Vector2, snapping: bool) -> void:
	build_start = point.snapped(Vector2(.05,.05))
	if snapping:
		joint = geometry.nearest_joint(build_start,Vector2.ZERO,"",false,build_tool=="room")
		if not joint.is_empty():
			build_start = joint.point
	build_end = build_start
	build_preview = {}
	building = true

func preview_construction(point: Vector2, snapping: bool) -> void:
	build_end = point.snapped(Vector2(.05,.05))
	if build_tool=="wall":
		var delta := build_end-build_start
		var axis := Vector2.RIGHT.rotated(snappedf(delta.angle(),PI*.25))
		build_end = build_start+axis*maxf(0.0,snappedf(delta.dot(axis),.05))
		if snapping:
			joint = geometry.nearest_joint(build_end,axis,"",true)
			if not joint.is_empty():
				build_end = joint.point
	elif snapping:
		var side := (build_end-build_start).sign()
		build_end += geometry.room_snap(Rect2(build_start,build_end-build_start).abs(),"",side)
	build_preview = game.construction.draft(build_tool,build_start,build_end)

func opening_visible(row: Dictionary) -> bool:
	if bool(row.deleted) or game.openings.kind(row).is_empty():
		return false
	var wall_id := str(row.get("wall_id",""))
	return wall_id.is_empty() or game.openings.wall_candidate(game.records.get(wall_id,{}))

func project(point: Vector2) -> Vector2:
	return (point-center)*zoom+size*0.5

func unproject(point: Vector2) -> Vector2:
	return (point-size*0.5)/zoom+center

func corners(s: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for v in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		var local: Vector2 = v * Vector2(float(s.w)*.5,float(s.d)*.5)
		pts.append(project(Vector2(float(s.x),float(s.z))+local.rotated(-deg_to_rad(float(s.r)))))
	return pts







func move_wall_tip(point: Vector2, enabled: bool) -> void:
	var tips := geometry.wall_tips(wall_start,Vector2(float(wall_start.x),float(wall_start.z)))
	var fixed := tips[0] if wall_handle>0 else tips[1]
	var axis := (tips[1]-tips[0]).normalized()*wall_handle
	var minimum := maxf(.15,float(game.openings.thickness(wall_start))+.01)
	var tip := fixed+axis*maxf(minimum,snappedf((point-fixed).dot(axis),.05))
	joint = geometry.nearest_joint(tip,axis,dragging,true) if enabled else {}
	if not joint.is_empty():
		var target: Vector2 = joint.point
		if (target-fixed).dot(axis)>=minimum:
			tip = fixed+axis*(target-fixed).dot(axis)
		else:
			joint = {}
	var row := wall_start.duplicate()
	var span_key := "w" if game.openings.along_x(row) else "d"
	row[span_key] = fixed.distance_to(tip)
	var middle := (fixed+tip)*.5
	row.x = middle.x
	row.z = middle.y
	if game.wall_cuts_fit(row):
		game.records[dragging] = row
	else:
		joint = {}

func held_point(point: Vector2, enabled: bool) -> Vector2:
	var row: Dictionary = game.held
	joint = geometry.wall_snap(row,point,enabled) if game.rooms.structural_wall(row) else {}
	return point if joint.is_empty() else point+Vector2(joint.delta)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("#152019"))
	var low := unproject(Vector2.ZERO)
	var high := unproject(size)
	for i in range(floori(low.x),ceili(high.x)):
		var x := project(Vector2(i,0)).x
		draw_line(Vector2(x,0),Vector2(x,size.y),Color("#32423a"))
	for i in range(floori(low.y),ceili(high.y)):
		var y := project(Vector2(0,i)).y
		draw_line(Vector2(0,y),Vector2(size.x,y),Color("#32423a"))
	for kind in ["floor","wall","item"]:
		for s in game.records.values():
			if bool(s.deleted) or str(s.kind) != kind or not game.openings.kind(s).is_empty():
				continue
			var pts := corners(s)
			var picked: bool = str(s.id) == game.selected
			var color := Color("#8bc8a7") if picked else Color("#58766a") if kind == "floor" else Color("#b3a68f") if kind == "wall" else Color("#547e8b")
			color.a = 1.0 if kind==layer or picked or (layer=="all" and kind!="item") else .38
			if kind!="wall" or bool(s.solid) or picked:
				draw_colored_polygon(pts,color)
			pts.append(pts[0])
			draw_polyline(pts,Color("#193125"),1.0,true)
	for row in game.records.values():
		if bool(row.deleted) or str(row.kind)!="floor" or str(row.get("zone","")).is_empty():
			continue
		var location := project(Vector2(float(row.x),float(row.z)))
		var title := tr(str(game.data.rooms[row.zone].name)) if game.data.rooms.has(row.zone) else tr(str(row.label))
		var room: Rect2 = game.rooms.room_world_bounds(row)
		var width := room.size.x*zoom
		draw_string(ThemeDB.fallback_font,location+Vector2(-width*.5,5),title,HORIZONTAL_ALIGNMENT_CENTER,width,14,Color("#f4fff8"))
	for row in game.records.values():
		if opening_visible(row):
			draw_opening(row,str(row.id)==game.selected or str(row.id)==hover)
	if show_reference:
		draw_reference()
	if not opening_preview.is_empty():
		draw_opening(opening_preview,true,true)
	if layer in ["all","floor"] and game.rooms.resizable_room(game.selected):
		var active: Dictionary = game.records[game.selected]
		for p in corners(active):
			draw_rect(Rect2(p-Vector2(6,6),Vector2(12,12)),Color("#183426"))
			draw_rect(Rect2(p-Vector2(4,4),Vector2(8,8)),Color("#b6f6c5"))
	var wall: Dictionary = game.records.get(game.selected,{})
	if layer in ["all","wall"] and game.rooms.structural_wall(wall) and game.held.is_empty():
		for tip in geometry.wall_tips(wall,Vector2(float(wall.x),float(wall.z))):
			draw_circle(project(tip),6,Color("#15251f"),true,-1,true)
			draw_circle(project(tip),4,Color("#81dcff"),true,-1,true)
	if not game.held.is_empty():
		var s: Dictionary = game.held.duplicate()
		var point := unproject(get_local_mouse_position()).snapped(Vector2(.05,.05))
		if not joint.is_empty():
			point += Vector2(joint.delta)
		s.x = point.x
		s.z = point.y
		var grounded: bool = str(s.kind)=="floor" or is_finite(game.rooms.ground_height(point))
		draw_colored_polygon(corners(s),Color("#aedabc99") if grounded else Color("#ff807899"))
	if not joint.is_empty():
		draw_arc(project(joint.point),9,0,TAU,24,Color("#83e8ff"),2.0,true)
	if building:
		draw_construction()

func draw_construction() -> void:
	var valid := build_preview.has("pieces")
	var color := Color("#90f7b8") if valid else Color("#ff928a")
	var a := project(build_start)
	var b := project(build_end)
	var caption := tr("%.2f м") % build_start.distance_to(build_end)
	if build_tool=="room":
		var box := Rect2(a,b-a).abs()
		draw_rect(box,Color(color,.16),true)
		draw_rect(box,color,false,2.0)
		var dimensions := (build_end-build_start).abs()
		caption = tr("%.2f × %.2f м") % [dimensions.x,dimensions.y]
	elif not valid:
		draw_line(a,b,color,3.0,true)
	if valid:
		for piece in build_preview.pieces:
			if str(piece.template)!="wall":
				continue
			var middle := Vector2(float(piece.x),float(piece.z))
			var run := Vector2.RIGHT.rotated(-deg_to_rad(float(piece.r)))*float(piece.w)*.5
			draw_line(project(middle-run),project(middle+run),color,5.0,true)
	draw_circle(a,4,color)
	draw_string(ThemeDB.fallback_font,(a+b)*.5+Vector2(8,-11),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,16,color)

func draw_reference() -> void:
	var color := Color("#d1b1ff")
	for id in REFERENCE_ROOMS:
		var cells: Rect2 = REFERENCE_ROOMS[id]
		var from := project((cells.position-Vector2(12,8))*.87)
		var to := project((cells.end-Vector2(12,8))*.87)
		var top_right := Vector2(to.x,from.y)
		var bottom_left := Vector2(from.x,to.y)
		for side in [[from,top_right],[top_right,to],[to,bottom_left],[bottom_left,from]]:
			draw_dashed_line(side[0],side[1],color,1.5,7.0)
		var title := "%s × %s" % [str(cells.size.x),str(cells.size.y)]
		draw_string(ThemeDB.fallback_font,from+Vector2(5,17),title,HORIZONTAL_ALIGNMENT_LEFT,-1,13,color)

func draw_opening(row: Dictionary, highlighted: bool, preview: bool = false) -> void:
	var type: String = game.openings.kind(row)
	var point := project(Vector2(float(row.x),float(row.z)))
	var direction := geometry.opening_direction(row)
	var across := direction.orthogonal()
	var half := maxf(8.0,geometry.opening_width(row)*zoom*.5)
	var color := Color("#72d6ff") if type=="window" else Color("#ffce72")
	if preview:
		color = Color("#a4ffbf")
	var a := point-direction*half
	var b := point+direction*half
	draw_line(a,b,Color("#15251f"),10 if highlighted else 8,true)
	draw_line(a,b,color,4 if highlighted else 3,true)
	if type=="window":
		draw_line(a+across*4,b+across*4,color,1,true)
	elif type=="door":
		var side := a+across*half*1.35
		draw_line(a,side,color,2,true)
		draw_line(side,b,color.darkened(.28),1,true)
	else:
		draw_line(a-across*5,a+across*5,color,2,true)
		draw_line(b-across*5,b+across*5,color,2,true)
	if highlighted:
		draw_string(ThemeDB.fallback_font,point+Vector2(-95,-12),tr(str(row.label)),HORIZONTAL_ALIGNMENT_CENTER,190,13,color)







func move_resize_handle(pixel: Vector2, enabled: bool) -> void:
	var delta := (unproject(pixel)-resize_anchor).snapped(Vector2(.05,.05))
	var first := resize_start.position
	var last := resize_start.end
	if resize_corner.x<0:
		first.x=minf(first.x+delta.x,last.x-1.1)
	else:
		last.x=maxf(last.x+delta.x,first.x+1.1)
	if resize_corner.y<0:
		first.y=minf(first.y+delta.y,last.y-1.1)
	else:
		last.y=maxf(last.y+delta.y,first.y+1.1)
	if enabled:
		var shift := geometry.room_snap(Rect2(first,last-first),game.selected,resize_corner)
		for axis in range(2):
			if resize_corner[axis]<0:
				first[axis] = minf(first[axis]+shift[axis],last[axis]-1.1)
			else:
				last[axis] = maxf(last[axis]+shift[axis],first[axis]+1.1)
	game.rooms.preview_room_resize(Rect2(first,last-first))
	GameEvents.refresh_hud()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		joint = {}
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			center -= event.relative/zoom
			queue_redraw()
			return
		hover = geometry.opening_at(event.position)
		var draft := {}
		if not opening_tool.is_empty():
			draft = game.openings.draft(opening_tool)
		elif not opening_drag.is_empty() and event.position.distance_to(opening_start)>4:
			draft = game.records[opening_drag]
		opening_preview = game.openings.slot(unproject(event.position),draft,26.0/zoom) if not draft.is_empty() else {}
		var snapping: bool = magnets and not event.shift_pressed
		var over_handle := geometry.room_corner_at(event.position)!=Vector2.ZERO or geometry.wall_tip_at(event.position)!=0
		mouse_default_cursor_shape = CURSOR_CROSS if not build_tool.is_empty() else (CURSOR_FDIAGSIZE if resizing or over_handle else CURSOR_ARROW)
		if building:
			preview_construction(unproject(event.position),snapping)
			GameEvents.refresh_hud()
		elif resizing:
			move_resize_handle(event.position,snapping)
		elif not dragging.is_empty():
			var point := unproject(event.position)-offset
			point = point.snapped(Vector2(.05,.05))
			if room_move:
				if snapping:
					var rect: Rect2 = game.rooms.room_world_bounds(game.records[dragging])
					rect.position += point-rect.get_center()
					point += geometry.room_snap(rect,dragging)
				game.rooms.preview_room_move(point)
			else:
				preview_object_drag(point,snapping)
				game.openings.sync_positions()
			GameEvents.refresh_hud()
		elif not game.held.is_empty():
			held_point(unproject(event.position).snapped(Vector2(.05,.05)),snapping)
		queue_redraw()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				joint = {}
				var point := unproject(event.position)
				zoom = clampf(zoom*(1.12 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.12),10.0,180.0)
				center += point-unproject(event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if not build_tool.is_empty():
				var point := unproject(event.position)
				var snapping: bool = magnets and not event.shift_pressed
				if event.pressed:
					start_construction(point,snapping)
				elif building:
					preview_construction(point,snapping)
					game.construction.commit(build_preview)
					building = false
					build_preview = {}
					joint = {}
			elif event.pressed:
				var point := unproject(event.position)
				if not opening_tool.is_empty():
					var slot: Dictionary = game.openings.slot(point,game.openings.draft(opening_tool),26.0/zoom)
					if not slot.is_empty():
						game.openings.place(slot)
						opening_tool = ""
						opening_preview = {}
					else:
						GameEvents.notify(tr("Нужна стена с достаточным свободным местом."))
				elif not game.held.is_empty():
					game.place_on_plan(held_point(point.snapped(Vector2(.05,.05)),magnets and not event.shift_pressed))
					joint = {}
				elif geometry.room_corner_at(event.position)!=Vector2.ZERO:
					resize_corner=geometry.room_corner_at(event.position)
					resize_start=game.rooms.room_world_bounds(game.records[game.selected])
					resize_anchor=point
					resizing=true
					game.rooms.begin_room_resize(game.selected)
				elif geometry.wall_tip_at(event.position)!=0:
					wall_handle = geometry.wall_tip_at(event.position)
					dragging = game.selected
					wall_start = game.records[dragging].duplicate()
					wall_supported = true
					offset = Vector2.ZERO
					before = game.storage.snapshot()
				else:
					game.selected = geometry.hit(point)
					if not game.selected.is_empty():
						dragging = game.selected
						var s: Dictionary = game.records[dragging]
						if s.has("wall_id") or (s.has("opening_kind") and s.has("sill")):
							opening_drag = dragging
							opening_start = event.position
							dragging = ""
						elif str(s.kind)=="floor" and not str(s.get("zone","")).is_empty():
							offset = point-Vector2(float(s.x),float(s.z))
							room_move = true
							game.rooms.begin_room_move(dragging)
						else:
							offset = point-Vector2(float(s.x),float(s.z))
							before = game.storage.snapshot()
							wall_start = s.duplicate() if game.rooms.structural_wall(s) else {}
							wall_supported = true
			elif not opening_drag.is_empty():
				if event.position.distance_to(opening_start)>4:
					var slot: Dictionary = game.openings.slot(unproject(event.position),game.records[opening_drag],26.0/zoom)
					if not slot.is_empty():
						game.openings.place(slot)
					else:
						GameEvents.notify(tr("Перетащи на подходящую стену. Старый проём сохранён."))
				opening_drag = ""
				opening_preview = {}
			elif resizing:
				game.rooms.finish_room_resize()
				resizing=false
			elif not dragging.is_empty():
				finish_drag()
		elif event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_construction()
			opening_tool = ""
			opening_drag = ""
			opening_preview = {}
		queue_redraw()
		GameEvents.refresh_hud()
		accept_event()


func finish_drag() -> void:
	opening_drag = ""
	opening_preview = {}
	joint = {}
	if resizing:
		game.rooms.finish_room_resize()
		resizing=false
	if dragging.is_empty():
		return
	if room_move:
		game.rooms.finish_room_move()
	else:
		if not wall_start.is_empty() and not wall_supported:
			game.records[dragging] = wall_start
			GameEvents.notify(tr("Стена должна опираться на пол."))
		elif not wall_start.is_empty() and wall_handle==0:
			var wall: Dictionary = game.records[dragging]
			if wall.x!=wall_start.x or wall.z!=wall_start.z:
				var owner := str(wall.get("room_owner",""))
				if not owner.is_empty() and not game.rooms.wall_in_room(wall,owner):
					wall.erase("room_owner")
		game.apply_item(dragging)
		game.openings.sync_positions()
		game.storage.record_change(before)
	dragging=""
	room_move=false
	wall_start={}
	wall_handle=0

func preview_object_drag(point: Vector2, snapping: bool) -> void:
	var row: Dictionary = game.records[dragging]
	if not wall_start.is_empty():
		if wall_handle!=0:
			move_wall_tip(point,snapping)
			row = game.records[dragging]
			point = Vector2(float(row.x),float(row.z))
		else:
			joint = geometry.wall_snap(row,point,snapping)
			if not joint.is_empty():
				point += Vector2(joint.delta)
		var ground: float = game.rooms.ground_height(point)
		wall_supported = is_finite(ground)
		if wall_supported:
			row.y = ground
	row.x = point.x
	row.z = point.y
	game.transform_item(game.nodes[dragging],row)
