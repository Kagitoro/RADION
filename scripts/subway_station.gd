class_name SubwayStation
extends Node3D
## Underground 8 Avenue station behind the Night Shop: stairs, platform, a passing
## train and three riders the player can help with a little money.

## Street-level cut-out for the stairs (x, z on the district ground).
const OPENING := Rect2(-31.5,10.47,8.45,2.66)
const PLATFORM_Y := -4.50
const STAIR_Z := 11.80
const STATION := Rect2(-62.4,6.8,31.0,12.6)
const REQUESTS := [
	"Эй, дружище. Есть пару долларов на кофе?",
	"Привет. Не найдётся мелочи на что-нибудь поесть?",
	"Если есть пара баксов, я был бы благодарен.",
]
const NAMES := ["Лео","Мара","Фрэнк"]
## Riders' replies (translation keys).
const THANKS := "Спасибо. Правда, выручил."
const THANKS_AGAIN := "Спасибо ещё раз. Хорошей ночи."
const NO_MONEY_REPLY := "Ничего, бывает. Доброй ночи."
## How long a rider's speech bubble stays up (seconds).
const SPEECH_TIME := 5.0
## A rider counts as "looked at" within this distance and view-direction dot product.
const AIM_REACH := 2.55
const AIM_DOT := .79
## Train cycle (seconds): arrives during [0, ARRIVE], waits, departs during [DEPART_START, DEPART_END].
const TRAIN_CYCLE := 34.0
const TRAIN_ARRIVE := 8.0
const TRAIN_DEPART_START := 17.0
const TRAIN_DEPART_END := 28.0
const TRAIN_START_X := -74.0
const TRAIN_STOP_X := -46.9
const TRAIN_END_X := -18.0

var world: NightWorld
var home: Home
var people: Array[PartyGuest] = []
var helped: Array[PartyGuest] = []
var asked: Array[PartyGuest] = []
var train := Node3D.new()
var train_sound: AudioStreamPlayer3D
var clock := 0.0
var pose_time := 0.0
var welcomed := false
var speaking: PartyGuest
var speech_time := 0.0

func _init(night_world: NightWorld) -> void:
	world = night_world
	home = world.home

func build() -> void:
	name = "8 Avenue Subway"
	build_stairs()
	build_platform()
	build_train()
	set_process(false)

func build_stairs() -> void:
	var center_x := OPENING.get_center().x
	var width := OPENING.size.y
	var length := OPENING.size.x
	var railing := Color("#25463e")
	for side in [-1,1]:
		var z: float = STAIR_Z+side*(width*.5+.04)
		world.box(self,Vector3(center_x,-2.47,z),Vector3(length,4.94,.15),Color("#343740"),true)
		world.box(self,Vector3(center_x,.53,z),Vector3(length,.07,.075),railing)
		world.box(self,Vector3(center_x,.46,z),Vector3(length,.92,.09),Color.TRANSPARENT,true,true)
		for index in range(6):
			world.box(self,Vector3(OPENING.position.x+.16+index*1.6,.45,z),Vector3(.06,.9,.06),railing)
	world.box(self,Vector3(OPENING.position.x,.46,STAIR_Z),Vector3(.12,.92,width+.13),railing,true)
	for side in [-1,1]:
		var z: float = STAIR_Z+side*(width*.5+.08)
		world.box(self,Vector3(OPENING.end.x+.13,1.11,z),Vector3(.08,2.2,.08),railing,true)
		world.sphere(self,Vector3(OPENING.end.x+.13,2.22,z),Vector3(.20,.22,.20),Color("#bcf6c9"))
	world.add_sign(self,"SUBWAY  ·  8 AV",Vector3(OPENING.end.x+.18,1.96,STAIR_Z),Vector3(0,PI*.5,0),Color("#f2f2db"),.005)
	world.point_light(self,Vector3(OPENING.end.x+.4,2.33,STAIR_Z),Color("#b5f3d3"),1.5,5.5)

	var stair := Node3D.new()
	add_child(stair)
	stair.position = Vector3(center_x,PLATFORM_Y*.5,STAIR_Z)
	stair.rotation.z = atan2(-PLATFORM_Y,length)
	world.box(stair,Vector3(0,-.11,0),Vector3(Vector2(length,PLATFORM_Y).length(),.22,width),Color.TRANSPARENT,true,true)
	const STEPS := 28
	for index in range(STEPS):
		var fraction := (float(index)+.5)/STEPS
		var x := lerpf(OPENING.position.x,OPENING.end.x,fraction)
		var y := lerpf(PLATFORM_Y,0,fraction)
		world.box(self,Vector3(x,y-.11,STAIR_Z),Vector3(length/STEPS,.22,width-.08),Color("#62636a"))
		world.box(self,Vector3(x-.105,y+.007,STAIR_Z),Vector3(.034,.014,width-.16),Color("#a49a6f"))
	for index in range(3):
		var fraction := .2+index*.32
		world.point_light(self,Vector3(lerpf(OPENING.position.x,OPENING.end.x,fraction),lerpf(PLATFORM_Y,0,fraction)+1.75,STAIR_Z),Color("#eee1b1"),.9,4.0)

func build_platform() -> void:
	var center_x := -46.95
	var length := 31.10
	var tile_color := Color("#a5a296")
	var concrete := Color("#37383d")
	var floor_at := Vector3(center_x,PLATFORM_Y-.18,11.27)
	var floor_size := Vector3(length,.36,8.88)
	world.box(self,floor_at,floor_size,Color.TRANSPARENT,true,true)
	var floor_shape := BoxMesh.new()
	floor_shape.size = floor_size
	var floor_mesh: MeshInstance3D = world.mesh(self,floor_shape,floor_at,Color.WHITE)
	var floor_finish := StandardMaterial3D.new()
	floor_finish.albedo_texture = preload("res://assets/city/pavers.jpg")
	floor_finish.albedo_color = Color("#898485")
	floor_finish.uv1_triplanar = true
	floor_finish.uv1_world_triplanar = true
	floor_finish.uv1_scale = Vector3.ONE*.43
	floor_finish.roughness = .88
	floor_mesh.material_override = floor_finish
	world.box(self,Vector3(center_x,-.56,13.23),Vector3(length,.25,12.83),concrete,true)
	world.box(self,Vector3(center_x,-2.54,6.87),Vector3(length,3.92,.23),concrete,true)
	world.box(self,Vector3(center_x,-2.75,19.47),Vector3(length,4.45,.22),concrete,true)
	world.box(self,Vector3(-62.51,-2.52,13.20),Vector3(.22,4.0,12.7),concrete,true)
	for span in [Vector2(6.8,OPENING.position.y),Vector2(OPENING.end.y,19.55)]:
		world.box(self,Vector3(-31.48,-2.52,(span.x+span.y)*.5),Vector3(.20,4.0,span.y-span.x),concrete,true)
	wall_tiles(center_x,6.995,1,tile_color)
	wall_tiles(center_x,19.34,-1,Color("#787a72"))
	world.box(self,Vector3(center_x,-1.37,7.035),Vector3(30.9,.23,.12),Color("#2a544d"))
	world.box(self,Vector3(center_x,-1.37,19.26),Vector3(30.9,.23,.12),Color("#2a544d"))
	world.box(self,Vector3(center_x,PLATFORM_Y+.017,15.43),Vector3(31.0,.034,.45),Color("#c6a13b"))
	build_tactile_strip(center_x)
	world.box(self,Vector3(center_x,PLATFORM_Y-.85,17.45),Vector3(31.05,.24,4.0),Color("#202127"),true)
	world.box(self,Vector3(center_x,PLATFORM_Y+.68,15.72),Vector3(31.0,1.36,.09),Color.TRANSPARENT,true,true)
	for z in [16.75,18.04]:
		world.box(self,Vector3(center_x,PLATFORM_Y-.63,z),Vector3(30.95,.09,.08),Color("#83858b"))
	for index in range(40):
		world.box(self,Vector3(-62.1+index*.77,PLATFORM_Y-.69,17.4),Vector3(.22,.08,1.66),Color("#3d332f"))
	for x in [-35.1,-40.7,-46.3,-51.9,-57.5]:
		world.box(self,Vector3(x,-2.53,14.39),Vector3(.27,3.96,.20),Color("#294a44"),true)
		world.box(self,Vector3(x,-2.53,14.39),Vector3(.15,3.96,.44),Color("#355954"))
		world.box(self,Vector3(x,-.79,11.0),Vector3(.22,.24,8.0),Color("#3a4b49"))
		world.box(self,Vector3(x,-.93,11.11),Vector3(2.05,.09,.23),Color("#eef0cf"))
		world.point_light(self,Vector3(x,-1.03,11.11),Color("#e9eec9"),1.5,6.2)
	for x in [-38.8,-48.6,-57.1]:
		world.place_prop(self,"furniture/bench",Vector3(x,PLATFORM_Y,8.04),Vector3(1.95,.88,.52))
		world.box(self,Vector3(x,PLATFORM_Y+.27,8.04),Vector3(1.90,.54,.51),Color.TRANSPARENT,true,true)
	for x in [-36.5,-46.5,-56.5]:
		world.box(self,Vector3(x,-2.16,7.08),Vector3(4.3,.49,.18),Color("#263a39"))
		world.add_sign(self,"8 AV  •  NIGHT DISTRICT",Vector3(x,-2.15,7.18),Vector3.ZERO,Color("#e8e5c6"),.0045)
	build_route_map(-42.3)
	build_route_map(-52.4)
	world.box(self,Vector3(-34.0,-1.10,11.82),Vector3(.12,.48,2.23),Color("#202c30"))
	world.add_sign(self,"EXIT  →  STREET",Vector3(-34.08,-1.10,11.82),Vector3(0,-PI*.5,0),Color("#e8e7d0"),.0035)

func build_route_map(x: float) -> void:
	world.box(self,Vector3(x,-2.50,7.06),Vector3(1.35,1.12,.16),Color("#29433e"))
	world.box(self,Vector3(x,-2.50,7.15),Vector3(1.19,.98,.03),Color("#bdc0af"))
	world.add_sign(self,"NIGHT LINE",Vector3(x,-2.16,7.18),Vector3.ZERO,Color("#232c33"),.002)
	world.box(self,Vector3(x,-2.53,7.17),Vector3(.86,.035,.018),Color("#4b7799"))
	world.box(self,Vector3(x-.12,-2.67,7.17),Vector3(.50,.027,.016),Color("#bb8055"))
	for dot in range(5):
		world.sphere(self,Vector3(x-.39+dot*.19,-2.53,7.19),Vector3(.050,.050,.020),Color("#edf0dd"))

func build_tactile_strip(center_x: float) -> void:
	var bump := CylinderMesh.new()
	bump.top_radius = .026
	bump.bottom_radius = .030
	bump.height = .012
	bump.radial_segments = 7
	bump.rings = 1
	var finish := StandardMaterial3D.new()
	finish.albedo_color = Color("#cba947")
	finish.roughness = .77
	bump.material = finish
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = bump
	const COLUMNS := 206
	batch.instance_count = COLUMNS*3
	for row in range(3):
		for column in range(COLUMNS):
			var at := Vector3(center_x-15.36+column*.149,PLATFORM_Y+.038,15.29+row*.14)
			batch.set_instance_transform(row*COLUMNS+column,Transform3D(Basis.IDENTITY,at))
	var dots := MultiMeshInstance3D.new()
	dots.multimesh = batch
	dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dots)

func wall_tiles(center_x: float, z: float, face: float, tint: Color) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	var tile := BoxMesh.new()
	tile.size = Vector3(.52,.28,.035)
	multimesh.mesh = tile
	multimesh.instance_count = 59*12
	for row in range(12):
		for col in range(59):
			var x := center_x-15.35+float(col)*.523
			var y := PLATFORM_Y+.22+row*.288
			var index := row*59+col
			multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY,Vector3(x,y,z+face*.012)))
			multimesh.set_instance_color(index,tint.darkened(float((row*17+col*13)%11)*.011))
	var tiles := MultiMeshInstance3D.new()
	tiles.multimesh = multimesh
	var finish := StandardMaterial3D.new()
	finish.vertex_color_use_as_albedo = true
	finish.roughness = .52
	tiles.material_override = finish
	tiles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tiles)

func build_train() -> void:
	add_child(train)
	train.position = Vector3(-72,PLATFORM_Y,17.55)
	for offset in [-5.30,5.30]:
		var car := Node3D.new()
		train.add_child(car)
		car.position.x = offset
		world.box(car,Vector3(0,1.21,0),Vector3(10.15,2.65,2.56),Color("#747981"))
		world.box(car,Vector3(0,2.55,0),Vector3(9.90,.21,2.42),Color("#555962"))
		world.box(car,Vector3(0,.22,-1.29),Vector3(10.15,.15,.055),Color("#454d53"))
		world.box(car,Vector3(0,1.86,-1.29),Vector3(10.15,.10,.06),Color("#42766c"))
		for slot in [-3.9,-2.6,-1.3,0.0,1.3,2.6,3.9]:
			world.box(car,Vector3(slot,1.46,-1.31),Vector3(1.00,.60,.045),Color("#28383d"))
			world.box(car,Vector3(slot,1.47,-1.34),Vector3(.86,.44,.028),Color("#66786d"))
		for x in [-3.20,0.0,3.20]:
			world.box(car,Vector3(x,1.03,-1.35),Vector3(.048,1.90,.035),Color("#25292f"))
		world.add_sign(car,"S  ·  8 AV",Vector3(-4.28,2.09,-1.33),Vector3(0,PI,0),Color("#efe2ab"),.0027)
	train_sound = AudioStreamPlayer3D.new()
	train_sound.stream = preload("res://assets/story/ambience/engine.mp3").duplicate()
	train_sound.stream.loop = true
	train_sound.pitch_scale = .70
	train_sound.volume_db = -17
	train_sound.unit_size = 7
	train_sound.max_distance = 24
	train.add_child(train_sound)

func setup() -> void:
	var positions := [Vector3(-35.5,PLATFORM_Y,9.00),Vector3(-45.6,PLATFORM_Y,8.76),Vector3(-55.55,PLATFORM_Y,8.93)]
	for index in range(positions.size()):
		var person := PartyGuest.new([10,15,14][index],null,home.party.psx_assets)
		add_child(person)
		person.position = positions[index]
		person.rotation.y = PI
		person.name_tag.text = NAMES[index]  # key; the 3D label translates it
		people.append(person)
	set_process(true)

func underground(point: Vector3) -> bool:
	var at := to_local(point)
	var planar := Vector2(at.x,at.z)
	return at.y>=-5.2 and at.y<-.25 and (OPENING.grow(.28).has_point(planar) or STATION.has_point(planar))

## Rider the player is looking at on the platform, or null.
func aimed_person() -> PartyGuest:
	var player: Node3D = home.player
	if not underground(player.global_position):
		return null
	var camera: Camera3D = home.player.camera
	var best := AIM_DOT
	var result: PartyGuest
	for person in people:
		var head := person.global_position+Vector3.UP*1.43*float(person.body_height)
		var direction := head-camera.global_position
		var score := direction.normalized().dot(-camera.global_basis.z)
		if direction.length()>AIM_REACH or score<=best:
			continue
		var query := PhysicsRayQueryParameters3D.create(camera.global_position,head,1,[home.player.get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		result = person
		best = score
	return result

## E on a rider: gives Balance.SUBWAY_DONATION dollars once, then just thanks again.
func give(person: PartyGuest) -> void:
	var price := Balance.SUBWAY_DONATION
	if helped.has(person):
		say(person,THANKS_AGAIN)
	elif home.party.cash<price:
		GameEvents.notify(tr("Для помощи нужно $%d") % price)
		say(person,NO_MONEY_REPLY)
	else:
		home.party.cash -= price
		helped.append(person)
		world.shop.save_stock()
		GameEvents.notify(tr("Ты дал $%d · осталось $%d") % [price,home.party.cash])
		say(person,THANKS)

## Hint shown by NightGame when the player looks at a rider.
func hint_for(person: PartyGuest) -> String:
	if helped.has(person):
		return tr("E · Поговорить")
	return tr("E · Дать $%d · %s") % [Balance.SUBWAY_DONATION, tr(person.name_tag.text)]

## text is a translation key; the speech label translates it (also after a language switch).
func say(person: PartyGuest, text: String) -> void:
	if is_instance_valid(speaking):
		speaking.speech.hide()
	speaking = person
	person.speech.text = text
	person.speech.show()
	speech_time = SPEECH_TIME

func _process(delta: float) -> void:
	var player := home.player
	if not is_instance_valid(player):
		return
	var downstairs := underground(player.global_position)
	var at := to_local(player.global_position)
	if downstairs and at.x < -32.9 and not welcomed:
		welcomed = true
		var person := people[0]
		if not helped.has(person):
			asked.append(person)
			say(person,REQUESTS[0])
	elif not downstairs:
		welcomed = false
		asked.clear()
	if speech_time>0.0:
		speech_time -= delta
		if speech_time<=0.0 and is_instance_valid(speaking):
			speaking.speech.hide()
	if not downstairs:
		if train_sound.playing:
			train_sound.stop()
		return
	clock = fposmod(clock+delta,TRAIN_CYCLE)
	var approaching := clock<TRAIN_ARRIVE
	var departing := clock>TRAIN_DEPART_START and clock<TRAIN_DEPART_END
	if approaching:
		train.position.x = lerpf(TRAIN_START_X,TRAIN_STOP_X,smoothstep(0.0,TRAIN_ARRIVE,clock))
	elif departing:
		train.position.x = lerpf(TRAIN_STOP_X,TRAIN_END_X,smoothstep(TRAIN_DEPART_START,TRAIN_DEPART_END,clock))
	else:
		train.position.x = TRAIN_STOP_X if clock<=TRAIN_DEPART_START else TRAIN_END_X
	if approaching or departing:
		if not train_sound.playing:
			train_sound.play()
	elif train_sound.playing:
		train_sound.stop()
	pose_time += delta
	if pose_time<.05:
		return
	if speech_time<=0.0:
		var listener := aimed_person()
		if listener!=null and not asked.has(listener) and not helped.has(listener):
			asked.append(listener)
			say(listener,REQUESTS[people.find(listener)])
	for person in people:
		var direction := person.global_position.direction_to(player.global_position)
		if person.global_position.distance_to(player.global_position)<5.5:
			person.rotation.y = lerp_angle(person.rotation.y,atan2(-direction.x,-direction.z),pose_time*3.0)
		person.pose(pose_time,0.0,false)
	pose_time = 0.0
