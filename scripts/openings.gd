class_name Openings
extends RefCounted

const WALL_COLOR := Color("#b7ad9d")
const STOCK_PASSAGES := [
	["base-4", ["base-5","base-6","base-10","base-11","base-12"], -5.8725, 0.0, 3.915, 0.0, -5.64, 1.51],
	["base-7", ["base-8","base-9","base-13","base-14","base-15"], -2.3925, 0.0, 3.045, 0.0, -2.39, .82],
	["base-18", ["base-19","base-20","base-23"], -.87, -1.0875, 2.175, -90.0, -1.39, .96],
	["base-27", ["base-28","base-29","base-31","base-32","base-33"], 4.35, -.2175, 3.045, -90.0, .60, .89],
]
const STOCK_WINDOWS := [
	["kitchen","Окно кухни",Vector3(5.335,1.55,-.14),Vector2(1.212,1.421)],
	["bath","Окно ванной",Vector3(-3.394,1.86,.79),Vector2(.532,.671)],
	["living","Окно комнаты с ковром",Vector3(-5.895,1.58,-2.02),Vector2(1.582,1.661)],
]

var home: Home
var wall_meshes := {}
var wall_finish := StandardMaterial3D.new()
var door_finish := StandardMaterial3D.new()
var brass := StandardMaterial3D.new()
var studio_rod: Node3D
var glazing := StandardMaterial3D.new()

func _init(game_home: Home) -> void:
	home = game_home
	wall_finish.albedo_color = WALL_COLOR
	wall_finish.roughness = .86
	door_finish.albedo_color = Color("#e2dace")
	door_finish.roughness = .48
	brass.albedo_color = Color("#a88750")
	brass.metallic = .72
	glazing.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glazing.albedo_color = Color(.67,.86,.95,.09)
	glazing.roughness = .14

func prepare_catalog_window() -> void:
	var model: Node3D = home.catalog.get("window")
	if model==null:
		return
	var pieces := model.find_children("*","MeshInstance3D",true,false)
	if pieces.size()==19:
		set_glass(pieces[0])

func set_glass(part: MeshInstance3D) -> void:
	part.material_override = glazing
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func kind(row: Dictionary) -> String:
	var type := str(row.get("opening_kind",row.get("template","")))
	if type in ["door","opening","window"]:
		return type
	match str(row.get("label","")):
		"Входная дверь": return "door"
		"Окна и шторы спальни": return "window"
		"Кухонная арка": return "opening"
	return ""

func wall_candidate(row: Dictionary) -> bool:
	return not row.is_empty() and not bool(row.deleted) and str(row.kind)=="wall" and bool(row.solid) and kind(row).is_empty() and float(row.h)>=1.8

func wall_frame(row: Dictionary) -> Transform3D:
	var angle := float(row.r) + (0.0 if along_x(row) else -90.0)
	return Transform3D(Basis(Vector3.UP,deg_to_rad(angle)),Vector3(float(row.x),float(row.y),float(row.z)))

func width(row: Dictionary) -> float:
	return float(row.w) if along_x(row) else float(row.d)

func along_x(row: Dictionary) -> bool:
	return str(row.get("template",""))=="wall" or float(row.w)>=float(row.d)

func thickness(row: Dictionary) -> float:
	return float(row.d) if along_x(row) else float(row.w)

func pose(row: Dictionary, wall: Dictionary) -> void:
	var frame := wall_frame(wall)
	var at := frame * Vector3(float(row.wall_offset)*width(wall),float(row.sill),0)
	row.x = at.x
	row.y = at.y
	row.z = at.z
	row.r = float(wall.r) + (0.0 if along_x(wall) else -90.0)

func sync_positions() -> void:
	for row in home.records.values():
		var host: Dictionary = home.records.get(str(row.get("wall_id","")), {})
		if not host.is_empty():
			pose(row,host)

func slot(point: Vector2, row: Dictionary, radius: float) -> Dictionary:
	var best := radius
	var result := {}
	for host in home.records.values():
		if not wall_candidate(host):
			continue
		var span := width(host)
		var half := float(row.w)*.5
		if span < float(row.w)+.12 or float(row.sill)+float(row.h)>float(host.h)+.001:
			continue
		var inverse := wall_frame(host).affine_inverse()
		var local := inverse * Vector3(point.x,float(host.y),point.y)
		var run := clampf(snappedf(local.x,.05),-span*.5+half+.06,span*.5-half-.06)
		var distance := Vector2(local.x-run,local.z).length()
		if distance >= best:
			continue
		var proposed := row.duplicate()
		proposed.wall_id = str(host.id)
		proposed.wall_offset = run/span
		if not fits(proposed,host):
			continue
		pose(proposed,host)
		result = proposed
		best = distance
	return result

func fits(row: Dictionary, host: Dictionary) -> bool:
	if not wall_candidate(host):
		return false
	var span := width(host)
	var run := float(row.wall_offset)*span
	if absf(run)+float(row.w)*.5>span*.5-.059 or float(row.sill)<0 or float(row.sill)+float(row.h)>float(host.h)+.001:
		return false
	for other in home.records.values():
		if bool(other.deleted) or str(other.id)==str(row.get("id","")) or str(other.get("wall_id",""))!=str(host.id):
			continue
		var sum_half := (float(row.w)+float(other.w))*.5
		if absf(run-float(other.wall_offset)*span)<sum_half+.06:
			return false
	return true

func draft(type: String) -> Dictionary:
	var row: Dictionary = home.make_template("window" if type=="window" else "opening")
	row.opening_kind = type
	row.label = {"opening":"Дверной проём","door":"Дверь","window":"Окно"}[type]
	row.w = 1.18 if type=="window" else .90
	row.h = 1.25 if type=="window" else 2.10
	row.sill = .88 if type=="window" else 0.0
	return row

func place(row: Dictionary) -> void:
	var prior: String = home.storage.snapshot()
	var id := str(row.get("id",""))
	var old: Dictionary = home.records.get(id,{})
	var old_wall := str(old.get("wall_id",""))
	if old.is_empty():
		id = insert(row)
		if id.is_empty():
			return
	else:
		home.records[id] = row
	home.selected = id
	if old_wall!=str(row.wall_id):
		refresh(old_wall)
	home.apply_item(id)
	home.storage.record_change(prior)
	GameEvents.refresh_hud()

func insert(row: Dictionary, id: String = "") -> String:
	var model: Node3D = home.duplicate_model(str(row.template))
	if model==null:
		return ""
	if id.is_empty():
		id = "copy-godot-%d-%d" % [Time.get_ticks_msec(),home.next_id]
		home.next_id += 1
	row.id = id
	home.records[id] = row
	home.nodes[id] = model
	home.add_child(model)
	if kind(row)=="door" and str(row.template)=="opening":
		add_door_leaf(model,home.vector(row.dimensions))
	return id

func add_door_leaf(model: Node3D, dimensions: Vector3) -> void:
	var leaf := Node3D.new()
	model.add_child(leaf)
	leaf.position.x = -dimensions.x*.42
	leaf.rotation.y = 1.42
	var span := dimensions.x*.84
	box(leaf,Vector3(span*.5,dimensions.y*.46,0),Vector3(span,dimensions.y*.90,.044),door_finish)
	box(leaf,Vector3(span*.5,dimensions.y*.59,.023),Vector3(span*.69,dimensions.y*.40,.008),wall_finish)
	box(leaf,Vector3(span*.89,dimensions.y*.46,.044),Vector3(.105,.027,.045),brass)

func box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.material_override = material
	parent.add_child(part)
	part.position = at

func shape(body: StaticBody3D, at: Vector3, size: Vector3) -> void:
	var collider := CollisionShape3D.new()
	var volume := BoxShape3D.new()
	volume.size = size
	collider.shape = volume
	body.add_child(collider)
	collider.position = at

func clear_wall(id: String) -> void:
	if wall_meshes.has(id):
		wall_meshes[id].free()
		wall_meshes.erase(id)

func refresh(id: String) -> void:
	if id.is_empty() or not home.records.has(id):
		return
	var had_visual := wall_meshes.has(id)
	clear_wall(id)
	var wall: Dictionary = home.records[id]
	if id=="base-148" and is_instance_valid(studio_rod):
		studio_rod.visible = bool(wall.get("managed_wall",false)) and not bool(wall.deleted)
	var cuts: Array[Dictionary] = []
	var can_cut: bool = wall_candidate(wall) and home.grabbed!=id
	for row in home.records.values():
		if str(row.get("wall_id",""))!=id:
			continue
		var active := can_cut and not bool(row.deleted)
		home.nodes[row.id].visible = active
		home.remove_body(row.id)
		if not active:
			continue
		pose(row,wall)
		home.transform_item(home.nodes[row.id],row)
		cuts.append(row)
		home.rebuild_body(row.id)
	if not can_cut:
		return
	if cuts.is_empty() and not bool(wall.get("managed_wall",false)):
		if had_visual:
			home.nodes[id].show()
			home.rebuild_body(id)
		return
	home.nodes[id].hide()
	home.remove_body(id)
	var visual := Node3D.new()
	home.ground_root.add_child(visual)
	var body := StaticBody3D.new()
	body.collision_layer = 3
	body.collision_mask = 0
	body.set_meta("item_id",id)
	home.ground_root.add_child(body)
	visual.transform = wall_frame(wall)
	body.transform = visual.transform
	wall_meshes[id] = visual
	home.bodies[id] = body
	var span := width(wall)
	var height := float(wall.h)
	var depth := thickness(wall)
	var edge := -span*.5
	cuts.sort_custom(func(a,b): return float(a.wall_offset)<float(b.wall_offset))
	for row in cuts:
		var center := float(row.wall_offset)*span
		var left := clampf(center-float(row.w)*.5,edge,span*.5)
		var right := clampf(center+float(row.w)*.5,left,span*.5)
		var bottom := clampf(float(row.sill),0,height)
		var top := clampf(bottom+float(row.h),bottom,height)
		segment(visual,body,edge,left,0,height,depth)
		segment(visual,body,left,right,0,bottom,depth)
		segment(visual,body,left,right,top,height,depth)
		edge = right
	segment(visual,body,edge,span*.5,0,height,depth)

func segment(visual: Node3D, body: StaticBody3D, left: float, right: float, bottom: float, top: float, depth: float) -> void:
	if right-left<.005 or top-bottom<.005:
		return
	var at := Vector3((left+right)*.5,(bottom+top)*.5,0)
	var size := Vector3(right-left,top-bottom,depth)
	box(visual,at,size,wall_finish)
	shape(body,at,size)

func install_stock_passages() -> void:
	for entry in STOCK_PASSAGES:
		var id := str(entry[0])
		var pieces: Array = [id] + entry[1]
		var intact := true
		for piece in pieces:
			var current: Dictionary = home.records[piece]
			var stock: Dictionary = home.originals[piece]
			for key in ["x","y","z","w","h","d","r"]:
				if not is_equal_approx(float(current[key]),float(stock[key])):
					intact = false
			if bool(current.deleted):
				intact = false
		if not intact:
			continue
		var wall: Dictionary = home.records[id]
		wall.merge({"x":entry[2],"z":entry[3],"w":entry[4],"d":.15,"r":entry[5],"managed_wall":true},true)
		for piece in entry[1]:
			home.records[piece].deleted = true
		var door := draft("opening")
		door.w = entry[7]
		door.wall_id = id
		door.wall_offset = (float(entry[6])-float(entry[2] if float(entry[5])==0 else entry[3]))/float(entry[4])
		pose(door,wall)
		insert(door,"passage-"+id)

func prepare_studio_windows() -> bool:
	var group: Node3D = home.nodes.get("base-148")
	while group!=null and group.get_child_count()==1:
		group = group.get_child(0) as Node3D
	if group==null or group.get_child_count()!=221:
		return false
	for index in range(2):
		var center := -.87 if index==0 else .87
		var anchor := group.global_transform * Vector3(center,.59,0)
		var inverse := Transform3D(Basis(Vector3.UP,-PI*.5),anchor).affine_inverse()
		var model := Node3D.new()
		for child_index in range(7+102*index,109+102*index):
			var relative := child_index-7-102*index
			var source := group.get_child(child_index) as MeshInstance3D
			if relative>=7 and relative<=92:
				source.hide()
				continue
			var part := copy_window_part(source,model,inverse)
			if relative==0:
				set_glass(part as MeshInstance3D)
				set_glass(source)
		if index==0:
			for child_index in range(212,221):
				copy_window_part(group.get_child(child_index),model,inverse)
		var key := "studio-window-"+str(index)
		home.add_child(model)
		model.hide()
		home.catalog[key] = model
		var template: Dictionary = home.make_template("window")
		template.dimensions = [.63945,1.79,.43]
		template.w = .63945
		template.h = 1.79
		template.d = .43
		template.sill = .59
		template.wall_offset = center/3.0
		home.data.templates[key] = template
	var rod := group.get_child(211) as Node3D
	studio_rod = rod.duplicate(0) as Node3D
	home.add_child(studio_rod)
	studio_rod.global_transform = rod.global_transform
	home.rooms.register_room_attachment(studio_rod,rod.global_position)
	return true

func copy_window_part(source: Node3D, model: Node3D, inverse: Transform3D) -> Node3D:
	var part := source.duplicate(0) as Node3D
	model.add_child(part)
	part.transform = inverse * source.global_transform
	return part

func install_studio_windows() -> void:
	if not home.catalog.has("studio-window-0"):
		return
	var wall: Dictionary = home.records["base-148"]
	var stock: Dictionary = home.originals["base-148"]
	for key in ["x","y","z","w","h","d","r"]:
		if not is_equal_approx(float(wall[key]),float(stock[key])):
			return
	if bool(wall.deleted):
		return
	wall.merge({"x":8.7,"w":3.045,"d":.0783,"r":-90.0,"managed_wall":true,"label":"Стена спальни"},true)
	for index in range(2):
		var row: Dictionary = home.make_template("studio-window-"+str(index))
		row.wall_id = "base-148"
		row.opening_kind = "window"
		row.label = "Окно спальни "+str(index+1)
		pose(row,wall)
		insert(row,"window-studio-"+str(index))

func prepare_room_windows() -> void:
	for node in home.house.find_children("*","Node3D",true,false):
		var source := node as Node3D
		if source.get_child_count()!=19:
			continue
		for entry in STOCK_WINDOWS:
			if source.position.distance_to(entry[2])>.002:
				continue
			var scale_x := source.global_basis.x.length()
			var angle := atan2(-source.global_basis.x.z,source.global_basis.x.x)
			var span := float(entry[3].x)*scale_x
			var height := float(entry[3].y)
			var anchor := source.global_position-Vector3.UP*height*.5
			var inverse := Transform3D(Basis(Vector3.UP,angle),anchor).affine_inverse()
			var model := Node3D.new()
			for part in source.get_children():
				copy_window_part(part,model,inverse)
			var key := "baked-window-"+str(entry[0])
			home.add_child(model)
			model.hide()
			home.catalog[key] = model
			var row := draft("window")
			row.merge({"template":key,"label":entry[1],"opening_kind":"window","room_owner":entry[0],
				"x":anchor.x,"y":anchor.y,"z":anchor.z,"r":rad_to_deg(angle),"sill":anchor.y,
				"w":span,"h":height,"d":.09,"dimensions":[span,height,.09]},true)
			home.data.templates[key] = row.duplicate(true)
			var id := insert(row,"window-"+str(entry[0]))
			if not id.is_empty():
				home.originals[id] = row.duplicate(true)
				source.hide()
