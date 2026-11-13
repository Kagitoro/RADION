class_name PlanSnapping
extends RefCounted
## Floor-plan geometry: what lies under the cursor and where walls, rooms and openings snap to.


var plan: FloorPlan

func _init(owner_node: FloorPlan) -> void:
	plan = owner_node

func snap_radius() -> float:
	return clampf(12.0/plan.zoom,.07,.25)

func wall_tips(row: Dictionary, at: Vector2) -> PackedVector2Array:
	var frame: Transform3D = plan.game.openings.wall_frame(row)
	var run := Vector2(frame.basis.x.x,frame.basis.x.z)*float(plan.game.openings.width(row))*.5
	return PackedVector2Array([at-run,at+run])

func nearest_joint(point: Vector2, axis: Vector2, exclude: String, along_axis: bool = false, floors_only: bool = false) -> Dictionary:
	var radius := snap_radius()
	var best := INF
	var result := {}
	for row in plan.game.records.values():
		if bool(row.deleted) or str(row.id)==exclude:
			continue
		var targets := PackedVector2Array()
		var priority := 0
		if not floors_only and plan.game.rooms.structural_wall(row):
			var tips := wall_tips(row,Vector2(float(row.x),float(row.z)))
			targets.append_array(tips)
			if absf(axis.dot((tips[1]-tips[0]).normalized()))<.85:
				targets.append(Geometry2D.get_closest_point_to_segment(point,tips[0],tips[1]))
		elif str(row.kind)=="floor":
			priority = 1
			var outline := plan.corners(row)
			for index in range(4):
				targets.append(Geometry2D.get_closest_point_to_segment(point,plan.unproject(outline[index]),plan.unproject(outline[(index+1)%4])))
		for target in targets:
			if along_axis and absf(axis.cross(target-point))>.008:
				continue
			var distance := point.distance_to(target)
			var score := distance+priority*radius
			if distance<radius and score<best:
				best = score
				result = {"point":target,"delta":target-point,"score":score}
	return result

func wall_snap(row: Dictionary, point: Vector2, enabled: bool) -> Dictionary:
	if not enabled:
		return {}
	var tips := wall_tips(row,point)
	var axis := (tips[1]-tips[0]).normalized()
	var first := nearest_joint(tips[0],axis,str(row.id))
	var last := nearest_joint(tips[1],axis,str(row.id))
	if first.is_empty() or (not last.is_empty() and float(last.score)<float(first.score)):
		return last
	return first

func room_snap(rect: Rect2, id: String, side: Vector2 = Vector2.ZERO) -> Vector2:
	var radius := snap_radius()
	var best := Vector2(radius,radius)
	var shift := Vector2.ZERO
	for row in plan.game.records.values():
		if str(row.id)==id or str(row.kind)!="floor" or bool(row.deleted) or str(row.get("zone","")).is_empty():
			continue
		var neighbor: Rect2 = plan.game.rooms.room_world_bounds(row)
		for axis in range(2):
			var across := 1-axis
			if rect.position[across]>neighbor.end[across]+radius or rect.end[across]<neighbor.position[across]-radius:
				continue
			var edges := [rect.position[axis],rect.end[axis]]
			if side[axis]!=0:
				edges = [edges[0] if side[axis]<0 else edges[1]]
			for from in edges:
				for target in [neighbor.position[axis],neighbor.end[axis]]:
					var delta := float(target)-float(from)
					if absf(delta)<best[axis]:
						best[axis] = absf(delta)
						shift[axis] = delta
	return shift

func wall_tip_at(pixel: Vector2) -> int:
	var row: Dictionary = plan.game.records.get(plan.game.selected,{})
	if plan.layer not in ["all","wall"] or not plan.game.rooms.structural_wall(row):
		return 0
	var tips := wall_tips(row,Vector2(float(row.x),float(row.z)))
	for index in range(2):
		if plan.project(tips[index]).distance_to(pixel)<=10.0:
			return index*2-1
	return 0

func opening_at(pixel: Vector2) -> String:
	var best := 10.0
	var result := ""
	for row in plan.game.records.values():
		if not plan.opening_visible(row):
			continue
		var center_pixel := plan.project(Vector2(float(row.x),float(row.z)))
		var run := opening_direction(row)*maxf(8.0,opening_width(row)*plan.zoom*.5)
		var distance := pixel.distance_to(Geometry2D.get_closest_point_to_segment(pixel,center_pixel-run,center_pixel+run))
		if distance<best:
			best = distance
			result = str(row.id)
	return result

func opening_direction(row: Dictionary) -> Vector2:
	var angle := float(row.r)
	if not row.has("opening_kind") and float(row.d)>float(row.w):
		angle -= 90.0
	return Vector2.RIGHT.rotated(-deg_to_rad(angle))

func opening_width(row: Dictionary) -> float:
	return float(row.w) if row.has("opening_kind") else maxf(float(row.w),float(row.d))

func hit(point: Vector2) -> String:
	if plan.layer in ["all","opening"]:
		var id := opening_at(plan.project(point))
		if not id.is_empty() or plan.layer=="opening":
			return id
	for kind in (["item","wall","floor"] if plan.layer=="all" else [plan.layer]):
		var id := hit_layer(point,kind)
		if not id.is_empty():
			return id
	return ""

func hit_layer(point: Vector2, kind: String) -> String:
	var result := ""
	var smallest := INF
	for s in plan.game.records.values():
		if bool(s.deleted) or str(s.kind)!=kind or not plan.game.openings.kind(s).is_empty():
			continue
		var local := (point-Vector2(float(s.x),float(s.z))).rotated(deg_to_rad(float(s.r)))
		if absf(local.x)<=float(s.w)*.5+.07 and absf(local.y)<=float(s.d)*.5+.07:
			var area := float(s.w)*float(s.d)
			if area<smallest:
				result = str(s.id)
				smallest = area
	return result

func room_corner_at(point: Vector2) -> Vector2:
	if plan.layer not in ["all","floor"] or not plan.game.rooms.resizable_room(plan.game.selected):
		return Vector2.ZERO
	var rect: Rect2 = plan.game.rooms.room_world_bounds(plan.game.records[plan.game.selected])
	for dir in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		var world := rect.get_center()+Vector2(dir)*rect.size*.5
		if plan.project(world).distance_to(point)<=11.0:
			return dir
	return Vector2.ZERO
