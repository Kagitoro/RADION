class_name RoomLayout
extends RefCounted
## Room geometry queries plus whole-room move and resize for the house editor.

var room_attachments: Array = []
var room_drag: Dictionary = {}
var room_resize: Dictionary = {}
var home: Home

func _init(game_home: Home) -> void:
	home = game_home

func floor_below(point: Vector2) -> bool:
	return is_finite(ground_height(point))

func structural_wall(row: Dictionary) -> bool:
	return not row.is_empty() and not bool(row.deleted) and str(row.kind)=="wall" and bool(row.solid) and home.openings.kind(row).is_empty()

func wall_in_room(wall: Dictionary, zone: String) -> bool:
	for row in home.records.values():
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
	for row in home.records.values():
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
	var height := home.night_world.club_ground_at(point)
	for row in home.records.values():
		if str(row.kind)=="floor" and not bool(row.deleted) and inside_room(row,point,.085):
			height = maxf(height,floor_surface(row))
	return height

func room_point(id: String, point: Vector3) -> Vector3:
	for key in home.originals:
		var original: Dictionary = home.originals[key]
		if str(original.get("zone","")) != id or str(original.kind) != "floor":
			continue
		var room: Dictionary = home.records[key]
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
	for original in home.originals.values():
		if str(original.kind)=="floor" and str(original.get("zone",""))==id:
			return original
	return {}

func register_room_attachment(node: Node3D, at: Vector3) -> void:
	for id in home.data.rooms:
		var room: Dictionary = home.data.rooms[id]
		var rect: Array = room.rect
		if at.x>=float(rect[0]) and at.x<=float(rect[1]) and at.z>=float(rect[2]) and at.z<=float(rect[3]):
			room_attachments.append({"node":node,"zone":id,"p":node.global_position})
			return

func register_room_details() -> void:
	var editable_nodes := {}
	for node in home.nodes.values():
		editable_nodes[node] = true
	for child in home.house.find_children("*","MeshInstance3D",true,false):
		var current: Node = child
		var editable := false
		while current!=null and current!=home.house:
			if editable_nodes.has(current) or current.name=="Catalog":
				editable = true
				break
			current = current.get_parent()
		if not editable:
			var model := child as MeshInstance3D
			register_room_attachment(model,model.global_transform*model.get_aabb().get_center())

func sync_room_details() -> void:
	home.scene_finish.sync_ceilings()
	for item in room_attachments:
		var original := room_floor(item.zone)
		if original.is_empty():
			continue
		item.node.global_position = room_point(item.zone,item.p)

func room_members(id: String) -> Dictionary:
	var floor_state: Dictionary = home.records[id]
	var zone := str(floor_state.get("zone",""))
	var members := {}
	var neighbors: Array[Dictionary] = []
	for row in home.records.values():
		if str(row.id)!=id and str(row.kind)=="floor" and not bool(row.deleted) and not str(row.get("zone","")).is_empty():
			neighbors.append(row)
	for key in home.records:
		var item: Dictionary = home.records[key]
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
	var floor_state: Dictionary = home.records.get(id,{})
	var zone := str(floor_state.get("zone",""))
	if floor_state.is_empty() or zone.is_empty() or str(floor_state.kind)!="floor":
		return
	room_drag = {"id":id,"zone":zone,"start":Vector2(float(floor_state.x),float(floor_state.z)),
		"members":room_members(id),"before":home.storage.snapshot(),"delta":Vector2.ZERO}

func preview_room_move(to: Vector2) -> void:
	if room_drag.is_empty():
		return
	var delta: Vector2 = to-room_drag.start
	room_drag.delta = delta
	for id in room_drag.members:
		var p: Vector2 = room_drag.members[id]+delta
		home.records[id].x = p.x
		home.records[id].z = p.y
		home.transform_item(home.nodes[id],home.records[id])
	home.openings.sync_positions()
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
		home.records[id].room_owner = operation.zone
		home.apply_item(id)
	sync_room_details()
	home.selected = operation.id
	home.storage.record_change(operation.before)
	GameEvents.refresh_hud()

func cancel_room_move() -> void:
	if room_drag.is_empty():
		return
	preview_room_move(room_drag.start)
	room_drag = {}

func resizable_room(id: String) -> bool:
	var room: Dictionary = home.records.get(id,{})
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
		baseline[member] = home.records[member].duplicate(true)
	var neighbors: Array[Rect2] = []
	for item in home.records.values():
		if str(item.kind)=="floor" and str(item.id)!=id and not bool(item.deleted) and not str(item.get("zone","")).is_empty():
			neighbors.append(room_world_bounds(item))
	room_resize = {"id":id,"source":room_world_bounds(home.records[id]),"before":home.storage.snapshot(),
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
		var live: Dictionary = home.records[id]
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
		home.transform_item(home.nodes[id],live)
	home.openings.sync_positions()
	sync_room_details()

func finish_room_resize() -> void:
	if room_resize.is_empty():
		return
	var operation := room_resize
	room_resize={}
	if not bool(operation.changed):
		return
	for id in operation.baseline:
		home.apply_item(id)
	home.storage.record_change(operation.before)
	GameEvents.refresh_hud()

func cancel_room_resize() -> void:
	if room_resize.is_empty():
		return
	preview_room_resize(room_resize.source)
	room_resize={}
