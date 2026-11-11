extends RefCounted

const MAX_FLOOR_GAP := .24
const MAX_WALL_GAP := .26
const MIN_WALL_GAP := .075

var home

func _init(editor) -> void:
	home = editor

func collect() -> Array[Dictionary]:
	var floors: Array[Dictionary] = []
	var walls: Array[Dictionary] = []
	for row in home.records.values():
		if bool(row.deleted):
			continue
		if str(row.kind)=="floor" and home.resizable_room(str(row.id)):
			floors.append(row)
		elif home.structural_wall(row):
			walls.append(row)
	var pieces: Array[Dictionary] = []
	for first in range(floors.size()):
		for second in range(first+1,floors.size()):
			floor_seam(floors[first],floors[second],pieces)
	var wall_keys := {}
	for wall in walls:
		var segment := wall_segment(wall)
		var axis := (segment[1]-segment[0]).normalized()
		for side in [-1,1]:
			var tip := segment[0] if side<0 else segment[1]
			var closest := MAX_WALL_GAP
			var destination := tip
			for other in walls:
				if other.id==wall.id or absf(float(other.y)-float(wall.y))>.025:
					continue
				var target := wall_segment(other)
				var nearest := Geometry2D.get_closest_point_to_segment(tip,target[0],target[1])
				var offset := nearest-tip
				var distance := offset.length()
				if distance>=MIN_WALL_GAP and distance<closest and absf(axis.cross(offset))<.012 and offset.dot(axis)*side>0:
					if intersects_opening(tip,nearest,float(wall.y)):
						continue
					closest = distance
					destination = nearest
			if not destination.is_equal_approx(tip):
				var middle := (destination+tip)*.5
				var key := str(middle.snapped(Vector2(.025,.025)))
				if not wall_keys.has(key):
					wall_keys[key] = true
					var piece: Dictionary = home.construction.wall_piece(tip,destination,float(wall.y))
					piece.h = float(wall.h)
					piece.d = home.openings.thickness(wall)
					piece.label = "Заделка стены"
					var owner := str(wall.get("room_owner",""))
					if not owner.is_empty():
						piece.room_owner = owner
					pieces.append(piece)
	return pieces

func floor_seam(a: Dictionary, b: Dictionary, pieces: Array[Dictionary]) -> void:
	var level: float = home.floor_surface(a)
	if absf(level-float(home.floor_surface(b)))>.025:
		return
	var first: Rect2 = home.room_world_bounds(a)
	var last: Rect2 = home.room_world_bounds(b)
	for axis in range(2):
		var across := 1-axis
		var lower := minf(first.end[axis],last.end[axis])
		var upper := maxf(first.position[axis],last.position[axis])
		var width := upper-lower
		var start := maxf(first.position[across],last.position[across])
		var end := minf(first.end[across],last.end[across])
		if width<.006 or width>MAX_FLOOR_GAP or end-start<.3:
			continue
		var center := Vector2.ZERO
		center[axis] = (lower+upper)*.5
		center[across] = (start+end)*.5
		var covered := 0
		for i in range(5):
			var sample := center
			sample[across] = lerpf(start,end,(float(i)+.5)/5.0)
			for floor_row in home.records.values():
				if str(floor_row.kind)=="floor" and not bool(floor_row.deleted) and home.inside_room(floor_row,sample):
					covered += 1
					break
		if covered==5:
			continue
		var size := Vector2.ZERO
		size[axis] = width+.008
		size[across] = end-start
		var thickness := float(home.data.templates.floor.h)
		pieces.append({"template":"floor","label":"Заделка пола","x":center.x,"z":center.y,
			"y":minf(level,float(home.floor_surface(b)))-thickness-.001,"w":size.x,"d":size.y})

func wall_segment(row: Dictionary) -> PackedVector2Array:
	var frame: Transform3D = home.openings.wall_frame(row)
	var run := Vector2(frame.basis.x.x,frame.basis.x.z)*float(home.openings.width(row))*.5
	var center := Vector2(float(row.x),float(row.z))
	return PackedVector2Array([center-run,center+run])

func intersects_opening(from: Vector2, to: Vector2, level: float) -> bool:
	for row in home.records.values():
		if bool(row.deleted) or home.openings.kind(row).is_empty() or float(row.y)>level+2.3:
			continue
		var center := Vector2(float(row.x),float(row.z))
		var closest := Geometry2D.get_closest_point_to_segment(center,from,to)
		var direction := Vector2.RIGHT.rotated(-deg_to_rad(float(row.r)))
		if not row.has("opening_kind") and float(row.d)>float(row.w):
			direction = direction.orthogonal()
		var relative := closest-center
		if absf(relative.cross(direction))<.19 and absf(relative.dot(direction))<maxf(float(row.w),float(row.d))*.5+.06:
			return true
	return false
