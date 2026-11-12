class_name NightDistrict
extends Node3D

const GROUND_SHADER = preload("res://assets/city/district_ground.gdshader")
const FACADE_DETAILS = preload("res://assets/city/facade_details.glb")
const BRICK = preload("res://assets/city/brick.jpg")
const PAVERS = preload("res://assets/city/pavers.jpg")
const ASPHALT_TEXTURE = preload("res://assets/city/asphalt.jpg")
const CURB_HEIGHT := .09
const WALKS := [
	Rect2(-15.53,-27.8,1.43,25.95), Rect2(-15.53,1.85,1.43,25.35),
	Rect2(-61.5,-17.3,2.8,35.1), Rect2(-52.0,-17.3,2.6,34.6),
	Rect2(-51.6,24.7,28.0,2.45), Rect2(-48.5,17.45,23.0,.60),
]
const VEHICLES := [preload("res://assets/city/street_compact.glb"),preload("res://assets/city/street_pickup.glb")]
const CAR_SIZES := [Vector3(1.84,1.68,3.87),Vector3(2.10,1.89,4.91)]
const BOUNDS := Rect2(-77,-35,63.1,69)
const TRAFFIC_ROUTE := [Vector3(-17.5,0,-22),Vector3(-17.5,0,20),Vector3(-54,0,20),Vector3(-54,0,-22)]

var world: NightWorld
const TRAFFIC_GAP := 7.4

var traffic: Array[Dictionary] = []
var route_length := 0.0
var walkers: Array[Dictionary] = []
var elapsed := 0.0
var facade_meshes := {}
var warm_glass := StandardMaterial3D.new()
var walk_material: StandardMaterial3D
var wall_materials: Array[StandardMaterial3D] = []

func _init(night_world: NightWorld) -> void:
	world = night_world

func build() -> void:
	var center := BOUNDS.get_center()
	build_ground_collision()
	for z in [-34.9,33.9]:
		world.box(self,Vector3(center.x,.65,z),Vector3(63.1,1.3,.22),Color("#383d4c"),true)
	world.box(self,Vector3(-76.9,.65,center.y),Vector3(.22,1.3,69),Color("#383d4c"),true)
	for interval in [Vector2(-35,-1.7),Vector2(1.7,34)]:
		world.box(self,Vector3(-13.91,.65,(interval.x+interval.y)*.5),Vector3(.11,1.3,interval.y-interval.x),Color("#353e4e"),true)
	build_roads()
	build_blocks()
	for index in range(TRAFFIC_ROUTE.size()):
		route_length += TRAFFIC_ROUTE[index].distance_to(TRAFFIC_ROUTE[(index+1)%TRAFFIC_ROUTE.size()])
	for index in range(3):
		var distance := route_length*(float(index)+.18)/3.0
		var car := place_car(self,index%2,traffic_point(distance),true)
		var direction := traffic_point(distance+.7)-car.position
		car.rotation.y = atan2(direction.x,direction.z)
		var wheels := car.find_children("Axle-*","Node3D",true,false)
		traffic.append({"car":car,"distance":distance,"speed":0.0,"cruise":4.3+index*.45,
			"wheels":wheels,"radius":.34 if index%2==0 else .46})
	for index in range(4):
		var car := place_car(self,index%2,Vector3(-45.2+index*4.0,0,14.6))
		car.rotation.y = PI
	set_process(false)

static func place_car(parent: Node3D, index: int, at: Vector3, moving: bool = false) -> Node3D:
	var car := VEHICLES[index].instantiate() as Node3D
	parent.add_child(car)
	car.position = at
	var body: StaticBody3D = AnimatableBody3D.new() if moving else StaticBody3D.new()
	if body is AnimatableBody3D:
		body.sync_to_physics = false
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = CAR_SIZES[index]
	collision.shape = shape
	collision.position.y = shape.size.y*.5
	body.add_child(collision)
	car.add_child(body)
	return car

func build_ground_collision() -> void:
	var cut := SubwayStation.OPENING
	for section in [
		Rect2(BOUNDS.position,Vector2(cut.position.x-BOUNDS.position.x,BOUNDS.size.y)),
		Rect2(Vector2(cut.end.x,BOUNDS.position.y),Vector2(BOUNDS.end.x-cut.end.x,BOUNDS.size.y)),
		Rect2(Vector2(cut.position.x,BOUNDS.position.y),Vector2(cut.size.x,cut.position.y-BOUNDS.position.y)),
		Rect2(Vector2(cut.position.x,cut.end.y),Vector2(cut.size.x,BOUNDS.end.y-cut.end.y)),
	]:
		var center: Vector2 = section.get_center()
		world.box(self,Vector3(center.x,-.12,center.y),Vector3(section.size.x,.24,section.size.y),Color.TRANSPARENT,true,true)

func build_roads() -> void:
	var surface := PlaneMesh.new()
	surface.size = BOUNDS.size
	var center := BOUNDS.get_center()
	var model: MeshInstance3D = world.mesh(self,surface,Vector3(center.x,0,center.y),Color.WHITE)
	var material := ShaderMaterial.new()
	material.shader = GROUND_SHADER
	material.set_shader_parameter("club_half_width",Nightclub.FLOOR_WIDTH*.5)
	var opening := SubwayStation.OPENING
	material.set_shader_parameter("subway_opening",Vector4(opening.position.x,opening.position.y,opening.end.x,opening.end.y))
	material.set_shader_parameter("asphalt",ASPHALT_TEXTURE)
	material.set_shader_parameter("pavers",PAVERS)
	model.material_override = material
	model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	walk_material = tiled_material(PAVERS,Color("#b4afb2"),.45)
	for walk in WALKS:
		var at: Vector2 = walk.get_center()
		var size := Vector3(walk.size.x,CURB_HEIGHT,walk.size.y)
		var center_3d := Vector3(at.x,CURB_HEIGHT*.5,at.y)
		textured_box(self,center_3d,size,walk_material)
		build_curb_collision(walk)
	for x in [-21.73,-62.1]:
		for z in [-26,-12,9,27]:
			world.lamp(Vector3(x,0,z))
	for z in [-29,28]:
		world.add_sign(self,"RADION DISTRICT",Vector3(-26,2.55,z),Vector3(0,0 if z<0 else PI,0),Color("#8de6ed"),.004)

func build_curb_collision(walk: Rect2) -> void:
	var body := StaticBody3D.new()
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	var bottom := walk.grow(.17)
	shape.points = PackedVector3Array([
		Vector3(bottom.position.x,-.035,bottom.position.y),Vector3(bottom.end.x,-.035,bottom.position.y),
		Vector3(bottom.end.x,-.035,bottom.end.y),Vector3(bottom.position.x,-.035,bottom.end.y),
		Vector3(walk.position.x,CURB_HEIGHT,walk.position.y),Vector3(walk.end.x,CURB_HEIGHT,walk.position.y),
		Vector3(walk.end.x,CURB_HEIGHT,walk.end.y),Vector3(walk.position.x,CURB_HEIGHT,walk.end.y),
	])
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func tiled_material(texture: Texture2D, tint: Color, repeats: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = tint
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE*repeats
	material.roughness = .92
	return material

func textured_box(parent: Node3D, at: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var shape := BoxMesh.new()
	shape.size = size
	var model: MeshInstance3D = world.mesh(parent,shape,at,Color.WHITE)
	model.material_override = material
	model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func build_blocks() -> void:
	warm_glass.albedo_color = Color("#ad8865")
	warm_glass.emission_enabled = true
	warm_glass.emission = Color("#cb9c70")
	warm_glass.emission_energy_multiplier = .53
	warm_glass.roughness = .78
	var samples := FACADE_DETAILS.instantiate()
	for model in samples.find_children("*","MeshInstance3D",true,false):
		facade_meshes[str(model.name)] = model.mesh
	samples.free()
	for color in [Color("#a78c84"),Color("#c6aba1"),Color("#827b7c")]:
		wall_materials.append(tiled_material(BRICK,color,.43))
	build_house(Vector3(-43,0,-10.6),PI*.5,Vector2(10.9,11.4),3,0,"NORTHSIDE COFFEE")
	build_house(Vector3(-43.1,0,5.5),-PI*.5,Vector2(10.7,11.3),4,1,"")
	build_house(Vector3(-68,0,-10.8),PI*.5,Vector2(11.1,11.6),3,2,"CORNER MARKET")
	build_house(Vector3(-68,0,7.2),PI*.5,Vector2(10.4,12.1),4,0,"")
	build_house(Vector3(-66.5,0,-28.4),0,Vector2(12,8.8),2,1,"")
	build_house(Vector3(-44.5,0,30.4),PI,Vector2(11.8,5.6),3,2,"")
	for index in range(9):
		var height := 6.0+float((index*7)%6)*2
		world.box(self,Vector3(-86-index%2*6,height*.5,-39+index*9),Vector3(8,height,5.7),Color("#202735"))
		for row in range(int(height/2.7)):
			if (index+row)%3!=0:
				glow(self,Vector3(-81.99-index%2*6,1.8+row*2.6,-39+index*9),Vector3(.03,.60,1.7),Color("#696183"))

func build_house(at: Vector3, yaw: float, footprint: Vector2, floors: int, palette: int, storefront: String) -> void:
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.position = at
	pivot.rotation.y = yaw
	var height := 3.1*floors
	var dimensions := Vector3(footprint.x,height,footprint.y)
	textured_box(pivot,Vector3.UP*height*.5,dimensions,wall_materials[palette])
	world.box(pivot,Vector3.UP*height*.5,dimensions,Color.TRANSPARENT,true,true)
	var stone := Color("#928984")
	world.box(pivot,Vector3(0,.19,0),Vector3(footprint.x+.10,.38,footprint.y+.10),stone)
	world.box(pivot,Vector3(0,height-.04,0),Vector3(footprint.x+.28,.26,footprint.y+.28),stone)
	world.box(pivot,Vector3(0,height+.20,0),Vector3(footprint.x+.16,.25,footprint.y+.16),Color("#48454a"))
	for side in range(4):
		var face := Node3D.new()
		pivot.add_child(face)
		face.rotation.y = side*PI*.5
		var width := footprint.x if side%2==0 else footprint.y
		var depth := footprint.y if side%2==0 else footprint.x
		face.position = Vector3(0,0,depth*.5).rotated(Vector3.UP,face.rotation.y)
		for level in range(1,floors):
			for bay in range(4):
				var x := (float(bay)-1.5)*width*.227
				var lit := (bay+level*3+palette+side)%4==0
				build_window(face,Vector3(x,level*3.1+1.43,0),Vector2(1.20,1.67),lit)
		if side!=0:
			for bay in [-1,0,1]:
				build_window(face,Vector3(float(bay)*width*.24,1.62,0),Vector2(1.1,1.36),false)
			continue
		for x in [-width*.29,width*.29]:
			build_window(face,Vector3(x,1.49,0),Vector2(2.2 if storefront!="" else 1.35,1.68),storefront!="")
		place_facade_detail(face,"Door",Vector3(0,1.17,.015),Vector3(1.46,2.34,.23))
		if storefront!="":
			world.box(face,Vector3(0,2.65,.086),Vector3(5.35,.52,.17),Color("#23323a"))
			world.add_sign(face,storefront,Vector3(0,2.65,.185),Vector3.ZERO,Color("#ffe3ad"),.0038)
		world.point_light(face,Vector3(0,2.70,.47),Color("#ffd1a2"),.85,4.2)

func build_window(face: Node3D, at: Vector3, size: Vector2, lit: bool) -> void:
	place_facade_detail(face,"WideWindow" if size.x>2.0 else "Window",at,Vector3(size.x+.12,size.y+.16,.19),lit)
	world.box(face,at+Vector3(0,-size.y*.5-.08,.08),Vector3(size.x+.25,.105,.22),Color("#aaa09a"))

func place_facade_detail(parent: Node3D, key: String, at: Vector3, size: Vector3, lit: bool = false) -> void:
	var source: Mesh = facade_meshes[key]
	var bounds := source.get_aabb()
	var model := MeshInstance3D.new()
	model.mesh = source
	if lit:
		for surface in range(source.get_surface_count()):
			var material := source.surface_get_material(surface)
			if material != null and "glass" in material.resource_name.to_lower():
				model.set_surface_override_material(surface,warm_glass)
	model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.scale = size/bounds.size
	var anchor := Vector3(bounds.get_center().x,bounds.get_center().y,bounds.position.z)
	model.position = at-anchor*model.scale
	parent.add_child(model)

func glow(parent: Node3D, at: Vector3, size: Vector3, tint: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var light: MeshInstance3D = world.mesh(parent,mesh,at,tint)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = tint
	light.material_override = material
	light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func populate() -> void:
	var routes: Array[PackedVector3Array] = []
	for walk in WALKS:
		var center: Vector2 = walk.get_center()
		var margin := .58
		var vertical: bool = walk.size.y>walk.size.x
		var length: float = (walk.size.y if vertical else walk.size.x)*.5-margin
		var along := Vector3(0,0,length) if vertical else Vector3(length,0,0)
		var midpoint := Vector3(center.x,CURB_HEIGHT,center.y)
		routes.append(PackedVector3Array([midpoint-along,midpoint+along]))
	for index in range(routes.size()):
		var person := PartyGuest.new(index+9,null,world.home.party.psx_assets)
		add_child(person)
		person.name_tag.hide()
		person.position = routes[index][0].lerp(routes[index][1],.17+.11*(index%4))
		walkers.append({"person":person,"points":routes[index],"next":1})
	set_process(true)

func _process(delta: float) -> void:
	var player: Node3D = world.home.player
	if not is_instance_valid(player):
		return
	var observer := to_local(player.global_position)
	var view := get_viewport().get_camera_3d()
	var viewer := to_local(view.global_position) if view!=null else observer
	step_traffic(delta,observer)
	elapsed += delta
	if elapsed<.05:
		return
	for route in walkers:
		var person: Node3D = route.person
		var destination: Vector3 = route.points[route.next]
		if person.position.distance_to(destination)<.08:
			route.next = 1-route.next
		else:
			var direction := person.position.direction_to(destination)
			person.rotation.y = lerp_angle(person.rotation.y,atan2(-direction.x,-direction.z),minf(1.0,elapsed*8))
			person.position = person.position.move_toward(destination,elapsed*person.speed)
		if person.position.distance_squared_to(viewer)<32.0*32.0:
			person.pose(elapsed,0.0,true)
	elapsed = 0.0

func traffic_point(distance: float) -> Vector3:
	var remaining := fposmod(distance,route_length)
	for index in range(TRAFFIC_ROUTE.size()):
		var start: Vector3 = TRAFFIC_ROUTE[index]
		var end: Vector3 = TRAFFIC_ROUTE[(index+1)%TRAFFIC_ROUTE.size()]
		var length := start.distance_to(end)
		if remaining<length:
			return start.lerp(end,remaining/length)
		remaining -= length
	return TRAFFIC_ROUTE[0]

func step_traffic(delta: float, observer: Vector3) -> void:
	var previous := PackedFloat64Array()
	for route in traffic:
		previous.append(route.distance)
	for index in range(traffic.size()):
		var route := traffic[index]
		var distance := previous[index]
		var gap := route_length
		for other in range(previous.size()):
			if other!=index:
				gap = minf(gap,fposmod(previous[other]-distance,route_length))
		var room := maxf(0.0,gap-TRAFFIC_GAP)
		var target_speed := minf(float(route.cruise),room*1.2)
		var car: Node3D = route.car
		if traffic_point(distance+2.4).distance_to(observer)<3.25:
			target_speed = 0.0
		var acceleration := 2.6 if target_speed>float(route.speed) else 8.0
		route.speed = move_toward(float(route.speed),target_speed,delta*acceleration)
		var step := minf(float(route.speed)*delta,room)
		distance = fposmod(distance+step,route_length)
		route.distance = distance
		car.position = traffic_point(distance)
		var direction := traffic_point(distance+.65)-traffic_point(distance-.65)
		car.rotation.y = lerp_angle(car.rotation.y,atan2(direction.x,direction.z),minf(1.0,delta*6.0))
		for wheel in route.wheels:
			wheel.rotate_x(step/float(route.radius))