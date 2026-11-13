class_name PartyNavigation
extends RefCounted
## Walkable grid of the house for guests: which cells are indoors, outdoors, on the dance floor, and A* routes between them.

const CELL := .28
const DANCE_SPACING := .90
var navigation := AStarGrid2D.new()
var cells := {}
var connected: Array[Vector2i] = []
var dance_floor: Array[Vector2i] = []
var indoor_cells: Array[Vector2i] = []
var outdoor_cells: Array[Vector2i] = []
var entrance := Vector2i.ZERO
var party: Party

func _init(owner_node: Party) -> void:
	party = owner_node

func rebuild_navigation() -> bool:
	var floors: Array[Dictionary] = []
	var bounds := Rect2()
	for row in party.home.records.values():
		if str(row.kind)=="floor" and not bool(row.deleted):
			floors.append(row)
			var footprint: Rect2 = party.home.rooms.room_world_bounds(row)
			bounds = footprint if not bounds.has_area() else bounds.merge(footprint)
	if not bounds.has_area():
		return false
	var first := Vector2i((bounds.position/CELL).floor())
	var last := Vector2i((bounds.end/CELL).ceil())
	if (last.x-first.x)*(last.y-first.y)>100000:
		return false
	navigation.region = Rect2i(first,last-first+Vector2i.ONE)
	navigation.cell_size = Vector2(CELL,CELL)
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	navigation.update()
	cells.clear()
	connected.clear()
	dance_floor.clear()
	indoor_cells.clear()
	outdoor_cells.clear()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .17
	capsule.height = 1.56
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.exclude = [party.home.player.get_rid()]
	var physics := party.get_world_3d().direct_space_state
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var id := Vector2i(x,y)
			var point := Vector2(id)*CELL
			var height := -INF
			for floor_row in floors:
				if party.home.rooms.inside_room(floor_row,point,.01):
					height = maxf(height,party.home.rooms.floor_surface(floor_row))
			if is_finite(height):
				var at := Vector3(point.x,height,point.y)
				query.transform.origin = at+Vector3.UP*.84
				if physics.intersect_shape(query,1).is_empty():
					cells[id] = at
					continue
			navigation.set_point_solid(id)
	if cells.size()<12:
		return false
	var seed := closest_cell(party.deck.position,cells.keys())
	var seen := {}
	seen[seed] = true
	connected.append(seed)
	var cursor := 0
	while cursor<connected.size():
		var at := connected[cursor]
		cursor += 1
		if party.home.night_world.outside(cells[at]):
			outdoor_cells.append(at)
		else:
			indoor_cells.append(at)
		if Vector3(cells[at]).distance_to(party.deck.position)<3.2:
			dance_floor.append(at)
		for step in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var neighbor: Vector2i = at+step
			if cells.has(neighbor) and not seen.has(neighbor) and absf(float(cells[neighbor].y)-float(cells[at].y))<.14:
				seen[neighbor] = true
				connected.append(neighbor)
	var door_point: Vector3 = party.home.night_world.door_center+Vector3(-5.2,0,-4.9)
	entrance = closest_cell(door_point,connected)
	return connected.size()>=18

func closest_cell(point: Vector3, candidates: Array) -> Vector2i:
	var best := INF
	var result := Vector2i.ZERO
	for id in candidates:
		var distance := point.distance_squared_to(cells[id])
		if distance<best:
			best = distance
			result = id
	return result

func find_destination(guest: PartyGuest, prefer_dance: bool = false) -> void:
	var group := indoor_cells if not indoor_cells.is_empty() else connected
	if not prefer_dance and not outdoor_cells.is_empty() and party.rng.randf()<guest.outdoor_interest:
		group = outdoor_cells
	elif not dance_floor.is_empty() and (prefer_dance or party.rng.randf()<guest.dance_interest):
		group = dance_floor
	if try_destination(guest,group):
		return
	if group!=indoor_cells and try_destination(guest,indoor_cells):
		return
	if group!=outdoor_cells and try_destination(guest,outdoor_cells):
		return
	guest.rest = 3.5

func try_destination(guest: PartyGuest, group: Array[Vector2i]) -> bool:
	if group.is_empty():
		return false
	var offset := party.rng.randi_range(0,group.size()-1)
	var player := party.home.player.global_position
	for step in range(group.size()):
		var cell := group[(offset+step)%group.size()]
		var point: Vector3 = cells[cell]
		if point.distance_squared_to(player)>.70*.70 and space_available(guest,point,true) and route_to(guest,cell):
			return true
	return false

func space_available(guest: PartyGuest, point: Vector3, reserve_destinations: bool) -> bool:
	for other in party.guests:
		if other==guest:
			continue
		if other.position.distance_squared_to(point)<DANCE_SPACING*DANCE_SPACING:
			return false
		if reserve_destinations and other.cursor<other.route.size():
			var goal: Vector3 = other.route[-1]
			if goal.distance_squared_to(point)<DANCE_SPACING*DANCE_SPACING:
				return false
	return true

func route_to(guest: PartyGuest, destination: Vector2i) -> bool:
	if connected.is_empty() or not cells.has(destination):
		return false
	var from := closest_cell(guest.position,connected)
	var ids := navigation.get_id_path(from,destination)
	if ids.is_empty():
		return false
	var path := PackedVector3Array()
	for id in ids:
		path.append(cells[id])
	guest.follow(path)
	return true

func route_out(guest: PartyGuest, side: float) -> bool:
	if outdoor_cells.is_empty():
		return false
	var door := party.home.night_world.door_center
	var gate := closest_cell(door+Vector3(-13.45,0,0),outdoor_cells)
	var gate_position: Vector3 = cells[gate]
	if absf(gate_position.z-door.z)>1.25 or gate_position.x>door.x-12.2 or not route_to(guest,gate):
		return false
	guest.route.append(door+Vector3(-14.8,0,0))
	guest.route.append(door+Vector3(-14.8,.09,2.1*side))
	guest.route.append(door+Vector3(-14.8,.09,26.0*side))
	return true
