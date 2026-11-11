extends Node3D

const ClubShift = preload("res://scripts/club_shift.gd")
const Guest = preload("res://scripts/party_guest.gd")
const Interior = preload("res://assets/club/radion_club.glb")
const ENTRY_X := -4.2
const ENTRY_Z := 5.08
const FLOOR_WIDTH := 19.10
const WALL_X := FLOOR_WIDTH*.5-.10
const DOOR_HALF_WIDTH := .57
const CYAN := Color("#58def9")
const PINK := Color("#f75ba9")

var world
var interior: Node3D
var dancers: Array[Node3D] = []
var lights: Array[OmniLight3D] = []
const DJStation = preload("res://scripts/dj_station.gd")
const TRACKS := ["DJ Dance"]
const BPM := [128.0]
const STAGE_HEIGHT := .42
const BEAM_SOURCES := [Vector3(-3.3,3.80,-2.95),Vector3(-1.1,3.80,1.05),Vector3(1.1,3.80,-2.95),Vector3(3.3,3.80,1.05)]

var deck := Node3D.new()
var music: Array[AudioStreamPlayer] = []
var music_bus := -1
var music_gain := 1.0
var track := 0
var playing := 0
var track_time := 0.0
var fader: Tween
var dj: DJStation
var shift: Node
var pose_time := 0.0
var show_time := 0.0
var mounted_modules := {}
var beams: Array[MeshInstance3D] = []
var tiles: Array[StandardMaterial3D] = []
var staff: Array[Node3D] = []
var response_time := 0.0
var responding: Node3D
var waiter_target := 0
const COUNTER_X := -6.52
const SHELVES_X := -8.67
const BARTENDER_X := -7.67
const SEATING_SHIFT := 2.77
const SERVICE_ROUTE := [
	Vector3(-4.80,0,2.66),Vector3(-3.62,0,3.20),Vector3(4.35,0,3.20),
	Vector3(5.56,0,1.72),Vector3(5.56,0,-.64),Vector3(4.35,0,2.50),
]

func _init(night_world) -> void:
	world = night_world

func build() -> void:
	name = "Nightclub"
	position = Vector3(-27,0,ENTRY_X)
	rotation.y = PI*.5
	interior = Interior.instantiate() as Node3D
	add_child(interior)
	arrange_interior(interior)
	batch_repeated_meshes()
	build_shell()
	build_mounts()
	for index in range(3):
		var light := OmniLight3D.new()
		light.position = [Vector3(-2.5,2.6,-2),Vector3(2.5,2.7,-2),Vector3(-.5,2.9,2.6)][index]
		light.light_color = [PINK,CYAN,Color("#b38bf7")][index]
		light.omni_range = 7.0
		light.light_energy = 1.4
		add_child(light)
		lights.append(light)
	build_show()
	set_process(false)

func arrange_interior(parent: Node3D) -> void:
	for module in parent.get_children():
		var prefix := str(module.name).get_slice("-",0)
		if prefix.length() != 3 or not prefix.is_valid_int():
			arrange_interior(module)
			continue
		var index := int(prefix)
		if index in [98,99,100,126,128,139,140,141,142]:
			mounted_modules[index] = module
		if index in range(42,57) or index == 127 or index in [115,116,117,118,120,121,133,134,135,136,137,138,143,144]:
			module.hide()
		elif index in [109,110,111]:
			module.position.x += SHELVES_X+5.75
		elif index in range(105,123):
			module.position.x += COUNTER_X+4.60
		elif index in range(123,126):
			module.position.x += SEATING_SHIFT
		elif index == 132:
			module.position.x += .95
		elif index in range(63,73) or index in range(139,143):
			module.position.z -= 1.08
		elif index in range(57,63):
			module.position.y += STAGE_HEIGHT-.4
			if index >= 59:
				module.position.z -= .90
		elif index in range(73,79):
			module.position.y += STAGE_HEIGHT
		elif index == 81:
			module.position = Vector3(-3.05,STAGE_HEIGHT,-4.8)
		elif index in range(101,105):
			module.position.x += signf(module.position.x)*1.65

func batch_repeated_meshes() -> void:
	var batches := {}
	for model in interior.find_children("*","MeshInstance3D",true,false):
		if model.mesh == null or not model.is_visible_in_tree():
			continue
		model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var instances: Array = batches.get_or_add(model.mesh,[])
		instances.append(model)
	var inverse := interior.global_transform.affine_inverse()
	for source in batches:
		var instances: Array = batches[source]
		if instances.size() < 3:
			continue
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = source
		batch.instance_count = instances.size()
		for index in range(instances.size()):
			batch.set_instance_transform(index,inverse*instances[index].global_transform)
			instances[index].hide()
		var model := MultiMeshInstance3D.new()
		model.multimesh = batch
		model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		interior.add_child(model)

func build_shell() -> void:
	var wall := Color("#252332")
	var facade := Color("#333443")
	world.box(self,Vector3(0,-.12,-.7),Vector3(FLOOR_WIDTH,.24,11.8),Color("#242433"),true)
	world.box(self,Vector3(0,4.54,-.7),Vector3(FLOOR_WIDTH+.20,.25,11.95),wall,true)
	for x in [-WALL_X,WALL_X]:
		world.box(self,Vector3(x,2.23,-.7),Vector3(.20,4.46,11.8),wall,true)
	world.box(self,Vector3(0,2.23,-6.55),Vector3(FLOOR_WIDTH,4.46,.2),wall,true)
	for span in [Vector2(-FLOOR_WIDTH*.5,ENTRY_X-DOOR_HALF_WIDTH),Vector2(ENTRY_X+DOOR_HALF_WIDTH,FLOOR_WIDTH*.5)]:
		world.box(self,Vector3((span.x+span.y)*.5,2.23,ENTRY_Z),Vector3(span.y-span.x,4.46,.22),facade,true)
	world.box(self,Vector3(ENTRY_X,3.38,ENTRY_Z),Vector3(1.14,2.16,.22),facade,true)
	world.box(self,Vector3(0,-.07,5.18),Vector3(FLOOR_WIDTH,.14,.85),facade)
	world.box(self,Vector3(ENTRY_X,2.53,5.35),Vector3(1.8,.16,.73),Color("#222130"))
	world.add_sign(self,"RADION / CLUB",Vector3(ENTRY_X,3.18,5.21),Vector3.ZERO,CYAN,.0046)
	world.add_sign(self,"ВХОД",Vector3(ENTRY_X,2.82,5.21),Vector3.ZERO,Color("#ffb1d2"),.0021)
	world.point_light(self,Vector3(ENTRY_X,2.65,5.40),CYAN,2.0,6.5)
	for x in [-5.5,-3.0,-.5,2.0,4.5]:
		world.box(self,Vector3(x,3.77,5.21),Vector3(1.75,.06,.05),PINK if x<0 else CYAN)
	for x in [-8.95,-8.15,-7.35,-6.55,-1.25,-.45,.35,1.15,1.95,2.75,3.55,4.35,5.15,5.95,6.75,7.55,8.35,9.15]:
		world.box(self,Vector3(x,1.65,5.218),Vector3(.12,2.8,.14),Color("#343445"))
	var trim := BoxMesh.new()
	trim.size = Vector3(FLOOR_WIDTH-.25,.045,.055)
	var neon: MeshInstance3D = world.mesh(self,trim,Vector3(0,4.21,5.26),PINK)
	var finish := StandardMaterial3D.new()
	finish.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	finish.albedo_color = Color("#d664b8")
	neon.material_override = finish
	# Simplified collisions for furnishings leave aisles and the dance floor clear.
	build_stage()
	solid(Vector3(COUNTER_X,.54,-.32),Vector3(.70,1.08,5.2))
	solid(Vector3(SHELVES_X,.84,-.67),Vector3(.62,1.68,3.0))
	for z in [-2.6,0,2.6]:
		solid(Vector3(5+SEATING_SHIFT,.49,z),Vector3(1.75,.98,2.17))
	for x in [-3.9,3.9]:
		solid(Vector3(x,.64+STAGE_HEIGHT,-4.2),Vector3(.78,1.28,.78))
	solid(Vector3(-.25,.48,4.1),Vector3(1.6,.96,.65))

func build_stage() -> void:
	var finish := Color("#272b3b")
	world.box(self,Vector3(0,STAGE_HEIGHT*.5,-4.89),Vector3(8.85,STAGE_HEIGHT,3.28),finish,true)
	for index in range(3):
		var height := STAGE_HEIGHT*float(index+1)/3.0
		world.box(self,Vector3(2.60,height*.5,-2.40-index*.34),Vector3(1.55,height,.34),finish)
		world.box(self,Vector3(2.60,height+.006,-2.55-index*.34),Vector3(1.50,.012,.045),CYAN)
	# Match the visible stair run with a walkable slope for the player controller.
	var ramp := Node3D.new()
	add_child(ramp)
	ramp.position = Vector3(2.60,STAGE_HEIGHT*.5,-2.74)
	ramp.rotation.x = atan2(STAGE_HEIGHT,1.02)
	world.box(ramp,Vector3(0,-.065,0),Vector3(1.55,.13,Vector2(1.02,STAGE_HEIGHT).length()),Color.TRANSPARENT,true,true)
	world.box(self,Vector3(0,STAGE_HEIGHT+.49,-4.60),Vector3(1.92,.98,.78),Color("#353648"),true)
	world.box(self,Vector3(0,STAGE_HEIGHT+1.0,-4.60),Vector3(2.0,.07,.87),Color("#171927"))
	world.box(self,Vector3(0,STAGE_HEIGHT+.73,-4.197),Vector3(1.72,.035,.012),PINK)
	add_child(deck)
	deck.position = Vector3(0,STAGE_HEIGHT+1.035,-4.67)
	deck.rotation.y = PI
	DJStation.build_laptop(self)

func build_mounts() -> void:
	var steel := Color("#30313c")
	var wall_back := Color("#32313e")
	world.box(self,Vector3(0,1.10,-6.30),Vector3(5.04,2.20,.32),wall_back)
	for x in [-3.0,3.0]:
		for z in [-4.0,2.0]:
			world.box(self,Vector3(x,4.22,z),Vector3(.12,.45,.12),steel)
	for index in [98,99,100]:
		var module: Node3D = mounted_modules.get(index)
		if module == null:
			continue
		var bounds := module_bounds(module)
		var top := bounds.end.y-.035
		var at := bounds.get_center()
		if top<4.43:
			world.box(self,Vector3(at.x,(top+4.43)*.5,at.z),Vector3(.048,4.43-top,.048),steel)
	for index in [126,128,139,140,141,142]:
		var module: Node3D = mounted_modules.get(index)
		if module == null:
			continue
		var bounds := module_bounds(module)
		var back := bounds.end.z-.04 if index<130 else bounds.position.z+.04
		var wall := ENTRY_Z-.11 if index<130 else -6.45
		var at := bounds.get_center()
		world.box(self,Vector3(at.x,at.y,(back+wall)*.5),
			Vector3(bounds.size.x*.88,bounds.size.y*.84,absf(back-wall)+.04),wall_back)
	for z in [-.62,.62]:
		world.box(self,Vector3(COUNTER_X,1.45,z),Vector3(.045,.72,.045),steel)
	world.box(self,Vector3(COUNTER_X,1.8,0),Vector3(.05,.045,1.27),steel)

func module_bounds(module: Node3D) -> AABB:
	var bounds := AABB()
	var inverse := global_transform.affine_inverse()
	for model in module.find_children("*","MeshInstance3D",true,false):
		var part: AABB = (inverse*model.global_transform)*model.get_aabb()
		bounds = part if not bounds.has_volume() else bounds.merge(part)
	return bounds

func build_show() -> void:
	var colors := [CYAN,PINK,Color("#6d65ff"),Color("#e8a6ff")]
	for index in range(BEAM_SOURCES.size()):
		var source: Vector3 = BEAM_SOURCES[index]
		world.box(self,source+Vector3.UP*.40,Vector3(.10,.53,.10),Color("#272834"))
		world.box(self,source+Vector3.UP*.08,Vector3(.27,.23,.23),Color("#30313e"))
		var shape := CylinderMesh.new()
		shape.height = 1.0
		shape.top_radius = .40
		shape.bottom_radius = .024
		shape.radial_segments = 12
		var beam := MeshInstance3D.new()
		beam.mesh = shape
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = Color(colors[index],.14)
		beam.material_override = material
		interior.add_child(beam)
		beams.append(beam)
	for x in [-1.5,-.5,.5,1.5]:
		for z in [-2.5,-1.5,-.5,.5]:
			var shape := BoxMesh.new()
			shape.size = Vector3(.84,.006,.84)
			var tile: MeshInstance3D = world.mesh(interior,shape,Vector3(x,.017,z),CYAN)
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = Color("#24536d")
			tile.material_override = material
			tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tiles.append(material)
	world.point_light(self,Vector3(COUNTER_X,2.65,.5),Color("#ca86f0"),1.75,5.6)
	world.point_light(self,Vector3(5+SEATING_SHIFT,2.65,.5),Color("#60c4ff"),1.65,6.0)

func box(parent: Node3D, at: Vector3, size: Vector3, tint: Color) -> void:
	world.box(parent,at,size,tint)

func cylinder(parent: Node3D, at: Vector3, radius: float, height: float, tint: Color) -> void:
	world.home.party.cylinder(parent,at,radius,height,tint)

func near_deck() -> bool:
	var player := to_local(world.home.player.global_position)
	return player.y >= STAGE_HEIGHT-.12 and Vector2(player.x,player.z).distance_to(Vector2(0,-4.67)) < 1.85

func setup_dj() -> DJStation:
	var bus_name := "Club music"
	music_bus = AudioServer.get_bus_index(bus_name)
	if music_bus < 0:
		AudioServer.add_bus()
		music_bus = AudioServer.bus_count-1
		AudioServer.set_bus_name(music_bus,bus_name)
	AudioServer.set_bus_volume_db(music_bus,-60)
	for index in range(2):
		var channel := AudioStreamPlayer.new()
		channel.bus = bus_name
		add_child(channel)
		music.append(channel)
	var stream := AudioStreamMP3.load_from_file("res://assets/party/DJ Dance.mp3")
	if stream != null:
		stream.loop = true
		music[0].stream = stream
		music[0].volume_db = -13
	dj = DJStation.new(world.home,self)
	add_child(dj)
	dj.setup()
	dj.bpm_fields[0].value = BPM[0]
	if stream != null:
		music[0].play()
	shift = ClubShift.new()
	add_child(shift)
	shift.setup(self)
	return dj

func solid(at: Vector3, size: Vector3) -> void:
	world.box(self,at,size,Color.TRANSPARENT,true,true)

func open_venue() -> void:
	var positions := [
		Vector3(-1.85,.015,-1.85),Vector3(-.62,.015,-2.5),Vector3(.65,.015,-1.95),
		Vector3(1.85,.015,-.8),Vector3(-1.35,.015,.05),Vector3(.23,.015,.25),
		Vector3(1.65,.015,.95),Vector3(-2.65,.015,.8),Vector3(2.9,.015,.2),Vector3(-.9,.015,1.58),
	]
	for index in range(positions.size()):
		var guest := Guest.new(index+2,null,world.home.party.psx_assets)
		interior.add_child(guest)
		guest.position = positions[index]
		guest.rotation.y = (float(index%3)-1.0)*.62
		guest.dancing = true
		guest.name_tag.hide()
		dancers.append(guest)

	var roles := ["Бармен · Лина","Официант · Макс","Охрана · Самир"]
	var starts := [Vector3(BARTENDER_X,0,-.45),SERVICE_ROUTE[0],Vector3(-5.65,0,5.78)]
	for index in range(roles.size()):
		var worker := Guest.new([3,8,2][index],null,world.home.party.psx_assets,index==2)
		add_child(worker)
		worker.position = starts[index]
		worker.rotation.y = -PI*.5 if index==0 else PI
		worker.name_tag.text = roles[index]
		staff.append(worker)
	var waiter = staff[1]
	if is_instance_valid(waiter.imported_model):
		var tray_shape := CylinderMesh.new()
		tray_shape.top_radius = .165
		tray_shape.bottom_radius = .155
		tray_shape.height = .016
		var tray: MeshInstance3D = world.mesh(waiter,tray_shape,Vector3.ZERO,Color("#30343c"))
		tray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var clear_glass := StandardMaterial3D.new()
		clear_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		clear_glass.albedo_color = Color(.68,.82,.90,.23)
		clear_glass.roughness = .17
		for x in [-.055,.062]:
			var glass := CylinderMesh.new()
			glass.top_radius = .029
			glass.bottom_radius = .023
			glass.height = .10
			var cup: MeshInstance3D = world.mesh(tray,glass,Vector3(x,.058,0),Color.WHITE)
			cup.material_override = clear_glass
			var liquid := CylinderMesh.new()
			liquid.top_radius = .024
			liquid.bottom_radius = .019
			liquid.height = .064
			world.mesh(tray,liquid,Vector3(x,.043,0),Color("#9e5932"))
		waiter.imported_model.service_tray = tray
	set_process(true)

func staff_target() -> Node3D:
	var camera: Camera3D = world.home.player.camera
	var best := .88
	var result: Node3D
	for worker in staff:
		var point := worker.global_position+Vector3.UP*1.43*float(worker.body_height)
		var offset := point-camera.global_position
		if offset.length()>2.75:
			continue
		var alignment := offset.normalized().dot(-camera.global_basis.z)
		if alignment<=best:
			continue
		var query := PhysicsRayQueryParameters3D.create(camera.global_position,point,1,[world.home.player.get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		best = alignment
		result = worker
	return result

func speak(worker: Node3D) -> void:
	if is_instance_valid(responding):
		responding.speech.hide()
	responding = worker
	response_time = 4.5
	var index := staff.find(worker)
	var replies := [
		"Привет! Если надо освежиться, у бара есть вода.",
		"Сейчас разнесу напитки. У диванов есть свободные места.",
		"Заходи. DJ на сцене, ступени справа.",
	]
	worker.speech.text = replies[index]
	worker.speech.show()

func animate_staff(delta: float, beat: float) -> void:
	if response_time>0.0:
		response_time -= delta
		if response_time<=0.0 and is_instance_valid(responding):
			responding.speech.hide()
	for index in range(staff.size()):
		var worker := staff[index]
		var walking := false
		if index==0:
			var goal := -.42+sin(show_time*.42)*.70
			worker.position.z = move_toward(worker.position.z,goal,delta*.38)
			walking = absf(worker.position.z-goal)>.035
		if index==1 and not (responding==worker and response_time>0.0):
			var target: Vector3 = SERVICE_ROUTE[waiter_target]
			var direction := worker.position.direction_to(target)
			if worker.position.distance_to(target)<.07:
				waiter_target = (waiter_target+1)%SERVICE_ROUTE.size()
			else:
				worker.rotation.y = lerp_angle(worker.rotation.y,atan2(-direction.x,-direction.z),minf(1.0,delta*8))
				worker.position = worker.position.move_toward(target,delta*.94)
				walking = true
		worker.pose(delta,beat,walking)

func animate_show(pulse: float) -> void:
	var palette := [CYAN,PINK,Color("#8774ff"),Color("#fcb97c")]
	var phrase := int(show_time/7.5)
	for index in range(beams.size()):
		var source: Vector3 = BEAM_SOURCES[index]
		var target := Vector3(sin(show_time*(.58+index*.075)+index*1.7)*4.1,.075,
			cos(show_time*.58+index*1.9)*3.55-.65)
		var difference := target-source
		var beam := beams[index]
		beam.position = (source+target)*.5
		beam.transform.basis = Basis(Quaternion(Vector3.UP,difference.normalized())).scaled_local(Vector3(1,difference.length(),1))
		beam.material_override.albedo_color = Color(palette[(index+phrase)%4],.064+pulse*.095)
	for index in range(tiles.size()):
		var wave := .5+.5*cos(float(index%4)*1.15+float(index/4)*.6-show_time*3.4)
		tiles[index].albedo_color = palette[(index+phrase)%4].darkened(.68-wave*.29-pulse*.12)

func _process(delta: float) -> void:
	var player: Node3D = world.home.player
	if not is_instance_valid(player):
		return
	var view := get_viewport().get_camera_3d()
	var observer := view.global_position if view!=null else player.global_position
	var nearby := global_position.distance_squared_to(observer) < 24.0*24.0
	interior.visible = nearby
	for light in lights:
		light.visible = nearby
	if music_bus >= 0:
		var local := to_local(player.global_position)
		var distance := maxf(0.0,local.z-ENTRY_Z)
		if absf(local.x) > WALL_X or local.z < -6.55:
			distance = maxf(distance,8.0)
		var volume := linear_to_db(maxf(.001,music_gain))-minf(60.0,distance*6.0)
		var previous := AudioServer.get_bus_volume_db(music_bus)
		AudioServer.set_bus_volume_db(music_bus,lerpf(previous,volume,minf(1.0,delta*5.0)))
	if not nearby:
		return
	pose_time += delta
	if pose_time < 1.0/24.0:
		return
	var beat := 0.0
	if is_instance_valid(dj) and dj.has_playback():
		beat = dj.dance_phase() if dj.manual else fposmod(music[0].get_playback_position()*BPM[0]/60.0,1.0)
	show_time += pose_time
	var pulse := exp(-5.0*beat) if dj.has_playback() else .12
	animate_show(maxf(pulse,dj.bass*.85))
	animate_staff(pose_time,beat)
	for person in shift.incident_guests:
		person.pose(pose_time,beat,false)
	for index in range(lights.size()):
		lights[index].light_energy = 1.15+pulse*(.80-float(index)*.18)
	for index in range(dancers.size()):
		var guest := dancers[index]
		if not guest.visible:
			continue
		if guest.dancing:
			var accent := 1.0+dj.bass*.24
			guest.rotation.y = (float(index%3)-1.0)*.62+sin(show_time*1.25+index*.85)*.20*accent
		var walking: bool = shift.active and not shift.paths[index].is_empty()
		guest.pose(pose_time,beat,walking)
	pose_time = 0.0
