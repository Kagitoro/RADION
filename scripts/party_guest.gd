class_name PartyGuest
extends Node3D


const COUNTRIES := ["Украина","Марокко","Бразилия","Южная Корея","Египет","Колумбия","Япония","Великобритания","Канада","Турция","Индия","Тайвань","Португалия","Нигерия","Франция","Польша"]
## [role, story, outdoor interest, dance interest] for the first guests.
const BACKGROUNDS := [
	["Промоутер","Знакомый диджей из Киева посоветовал послушать твой сет.",.08,.76],
	["Подруга хозяина","Мы познакомились на вечеринке в Касабланке. Сегодня привела друзей.",.20,.59],
	["Танцор","Выступал с друзьями из Сан-Паулу. Они прислали мне адрес этой вечеринки.",.04,.90],
	["Фотограф","Снимала клубы в Сеуле. Друг попросил сделать пару кадров твоего сета.",.12,.70],
	["Сосед","Переехал из Александрии и теперь живу рядом. Услышал басы и заглянул.",.44,.30],
	["Танцор","Мои друзья из Боготы уже у колонок. Я к ним.",.05,.88],
	["Друг хозяина","Мы вместе слушали пластинки в Осаке. Помнишь, какой хаус тогда играли?",.22,.60],
	["Промоутер","Организую ночи в Лондоне. Один из гостей сказал, что здесь стоит послушать диджея.",.12,.74],
]
## Story template for every later guest; %s is the guest's home town.
const DEFAULT_BACKGROUND := ["Гость","Друзья из города %s скинули мне адрес. Я зашёл познакомиться.",.17,.55]
const PERSONALITIES := ["любит хаус","любит общение","танцует всю ночь","ценит спокойные треки"]
const GUESTS := [
	["Артём","Киев"],["Амина","Касабланка"],["Матеус","Сан-Паулу"],["Хана","Сеул"],
	["Омар","Александрия"],["Валентина","Богота"],["Кэндзи","Осака"],["Зара","Лондон"],
	["Даниэль","Торонто"],["Лейла","Стамбул"],["Амар","Мумбаи"],["Мэй","Тайбэй"],
	["Лукас","Лиссабон"],["Ниа","Лагос"],["Идрис","Париж"],["София","Варшава"]
]
var hometown := ""
var origin := ""
var party_role := ""
var connection := ""
var outdoor_interest := .14
var dance_interest := .55
var guest_name: String
var female := false
var body_height := 1.0
var personality := ""
var social_cooldown := 0.0
var smoke_timer := 1.0
var smoking_prop: Node3D
var name_tag: Label3D
var speech: Label3D
var partner: Node3D
var knees: Array[Node3D] = []
var elbows: Array[Node3D] = []
var head := Node3D.new()
var route := PackedVector3Array()
var cursor := 0
var preference := 0
var leaving := false
var dancing := false
var fighting := false
var rest := 0.0
var phase := 0.0
var speed := 1.0
var figure := Node3D.new()
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var imported_model: Node3D
var pose_interval := 1.0/30.0
var pose_elapsed := 0.0
var skin_color: Color
var shirt_color: Color
var pants_color: Color

## Translated texts for the conversation UI.
func display_name() -> String:
	return tr(guest_name)

func introduction() -> String:
	return tr("Я %s. Мой родной город — %s (%s).") % [tr(guest_name), tr(hometown), tr(origin)]

func backstory() -> String:
	var story := tr(connection)
	if story.contains("%s"):
		story = story % tr(hometown)
	return "%s. %s" % [tr(party_role), story]

func _init(index: int, template: Node3D = null, psx_assets: Dictionary = {}, security: bool = false) -> void:
	preference = index%3
	speed = .86+float(index%4)*.12
	phase = float(index)*.74
	add_child(figure)
	var skin := [Color("#c38e67"),Color("#885b45"),Color("#e3ba9c"),Color("#a87955"),Color("#633e32"),Color("#bd875d"),Color("#e7c1aa")][(index*3+2)%7] as Color
	var shirt := [Color("#b85b59"),Color("#54847b"),Color("#625c99"),Color("#ad8b51"),Color("#537caa")][index%5] as Color
	var pants := Color("#363947").lightened(float(index%4)*.05)
	if security:
		skin = Color("#593823")
		shirt = Color("#141519")
		pants = Color("#101114")
	skin_color = skin
	shirt_color = shirt
	pants_color = pants
	# Profile texts are stored as untranslated keys and translated when shown,
	# so switching the language mid-game updates them too.
	var profile_data: Array = GUESTS[index%GUESTS.size()]
	guest_name = profile_data[0]
	hometown = profile_data[1]
	origin = COUNTRIES[index%COUNTRIES.size()]
	var background: Array = BACKGROUNDS[index] if index<BACKGROUNDS.size() else DEFAULT_BACKGROUND
	party_role = background[0]
	connection = background[1]
	outdoor_interest = background[2]
	dance_interest = background[3]
	female = index%2==1
	body_height = .78 if index%7==6 else (.94 if female else 1.0+float(index%3)*.025)
	var width := 1.58 if security else (1.37 if index%5==3 else (1.0 if not female else .93))
	if security:
		body_height = 1.22
	figure.scale = Vector3(width,body_height,width*.96)
	personality = PERSONALITIES[index%PERSONALITIES.size()]
	if not psx_assets.is_empty():
		var rig := GuestModel.new()
		if rig.setup_psx(psx_assets,female,index,body_height,width,skin,shirt,pants,security):
			add_child(rig)
			imported_model = rig
		else:
			rig.free()
	if not is_instance_valid(imported_model) and is_instance_valid(template):
		use_imported_model(template)
	if is_instance_valid(imported_model):
		if index%5==0:
			build_smoking_prop(imported_model)
			imported_model.ember = smoking_prop
		head.free()
		figure.free()
		setup_labels()
		return
	profile(figure,Vector3.ZERO,[
		Vector3(.117,.93,.083),Vector3(.139,1.00,.094),Vector3(.144,1.12,.105),
		Vector3(.183,1.32,.105),Vector3(.159,1.40,.089),Vector3(.060,1.44,.050)
	],shirt)
	oval(figure,Vector3(0,.93,0),Vector3(.275,.23,.183),pants)
	capsule(figure,Vector3(0,1.47,0),.051,.132,skin)
	figure.add_child(head)
	head.position = Vector3(0,1.59,0)
	oval(head,Vector3.ZERO,Vector3(.162,.221,.170),skin)
	oval(head,Vector3(0,-.059,-.014),Vector3(.122,.105,.144),skin)
	var hair_color := [Color("#372820"),Color("#171b21"),Color("#654231"),Color("#43302f")][index%4] as Color
	oval(head,Vector3(0,.076,.014),Vector3(.168,.113+float(index%3)*.025,.177),hair_color)
	oval(head,Vector3(0,-.009,-.081),Vector3(.032,.044,.040),skin.lightened(.065))
	oval(head,Vector3(0,-.046,-.078),Vector3(.047,.007,.012),skin.darkened(.37))
	for side in [-1,1]:
		oval(head,Vector3(side*.081,-.004,.004),Vector3(.027,.047,.034),skin)
		oval(head,Vector3(side*.032,.014,-.076),Vector3(.029,.012,.014),Color("#d9c7b9"))
		oval(head,Vector3(side*.032,.014,-.083),Vector3(.012,.011,.007),Color("#343133"))
		oval(head,Vector3(side*.032,.028,-.077),Vector3(.032,.007,.009),hair_color)
		var leg := Node3D.new()
		leg.position = Vector3(side*.075,.92,0)
		figure.add_child(leg)
		profile(leg,Vector3.ZERO,[Vector3(.052,-.42,.057),Vector3(.070,-.24,.077),Vector3(.083,-.04,.090),Vector3(.070,.03,.077)],pants)
		var knee := Node3D.new()
		knee.position.y = -.40
		leg.add_child(knee)
		profile(knee,Vector3.ZERO,[Vector3(.038,-.43,.046),Vector3(.046,-.32,.055),Vector3(.057,-.15,.061),Vector3(.054,.02,.057)],pants)
		oval(knee,Vector3(0,-.46,-.050),Vector3(.113,.099,.225),Color("#28292c"))
		legs.append(leg)
		knees.append(knee)
		var arm := Node3D.new()
		arm.position = Vector3(side*.157,1.36,0)
		figure.add_child(arm)
		oval(arm,Vector3(0,-.018,0),Vector3(.133,.151,.137),shirt)
		profile(arm,Vector3.ZERO,[Vector3(.042,-.255,.045),Vector3(.055,-.158,.056),Vector3(.071,-.037,.066),Vector3(.052,.035,.051)],shirt)
		var elbow := Node3D.new()
		elbow.position.y = -.237
		arm.add_child(elbow)
		profile(elbow,Vector3.ZERO,[Vector3(.029,-.217,.025),Vector3(.039,-.101,.041),Vector3(.045,.019,.044)],skin)
		oval(elbow,Vector3(0,-.224,-.006),Vector3(.058,.097,.042),skin)
		arms.append(arm)
		elbows.append(elbow)
	if index%4==0:
		build_smoking_prop(head)
	if female:
		oval(head,Vector3(0,.014,.054),Vector3(.175,.27,.14),hair_color)
		oval(figure,Vector3(0,1.28,-.057),Vector3(.28,.17,.16),shirt)
		if index%2==1:
			profile(figure,Vector3.ZERO,[Vector3(.185,.65,.115),Vector3(.17,.76,.112),Vector3(.13,.99,.089)],shirt.darkened(.15))
	if index%4==0:
		oval(head,Vector3(0,.092,-.002),Vector3(.185,.095,.184),Color("#2b3039"))
		oval(head,Vector3(0,.066,-.099),Vector3(.18,.018,.10),Color("#242932"))
	for index_arm in range(arms.size()):
		for stripe in range(2):
			oval(arms[index_arm],Vector3((-.037 if index_arm==0 else .037),-.13,-.031+stripe*.022),Vector3(.008,.20,.007),Color("#c4c4bb"))
	for side in [-1,1]:
		oval(figure,Vector3(side*.12,1.035,-.096),Vector3(.075,.009,.008),shirt.darkened(.30))
	oval(figure,Vector3(0,1.20,-.103),Vector3(.008,.32,.009),Color("#797f84"))
	setup_labels()

func build_smoking_prop(parent: Node3D) -> void:
	smoking_prop = Node3D.new()
	parent.add_child(smoking_prop)
	smoking_prop.position = Vector3(.012,-.049,-.103)
	smoking_prop.rotation.x = PI*.5
	var paper := CylinderMesh.new()
	paper.top_radius = .004
	paper.bottom_radius = .004
	paper.height = .064
	mesh_part(smoking_prop,Vector3.ZERO,paper,Color("#d6cbbb"))
	var ember := SphereMesh.new()
	ember.radius = .0044
	ember.height = .0088
	mesh_part(smoking_prop,Vector3(0,-.033,0),ember,Color("#bf6941"))
	smoking_prop.hide()

func setup_labels() -> void:
	name_tag = floating_label(guest_name,1.91*body_height,28)
	name_tag.modulate = Color("#ecdfc6")
	speech = floating_label("",2.10*body_height,26)
	speech.visible = false

func use_imported_model(template: Node3D) -> void:
	if not is_instance_valid(template):
		return
	var body := template.duplicate() as Node3D
	var rig := GuestModel.new()
	if not rig.setup(body,body_height,figure.scale.x,skin_color,shirt_color,pants_color):
		body.free()
		rig.free()
		return
	add_child(rig)
	imported_model = rig
	figure.hide()

func floating_label(value: String, height: float, size: int) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.position.y = height
	label.font_size = size
	label.pixel_size = .0019
	label.outline_size = 5
	label.layers = 2
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	return label

func profile(parent: Node3D, point: Vector3, rings: Array, color: Color) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SIDES := 16
	for ring in range(rings.size()-1):
		for side in range(SIDES):
			var low: Vector3 = rings[ring]
			var high: Vector3 = rings[ring+1]
			var a := ring_vertex(low,TAU*float(side)/SIDES)
			var b := ring_vertex(low,TAU*float(side+1)/SIDES)
			var c := ring_vertex(high,TAU*float(side)/SIDES)
			var d := ring_vertex(high,TAU*float(side+1)/SIDES)
			for vertex in [a,b,c,b,d,c]:
				surface.add_vertex(vertex)
	surface.index()
	surface.generate_normals()
	mesh_part(parent,point,surface.commit(),color)

func ring_vertex(ring: Vector3, angle: float) -> Vector3:
	return Vector3(cos(angle)*ring.x,ring.y,sin(angle)*ring.z)

func oval(parent: Node3D, point: Vector3, size: Vector3, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radial_segments = 18
	mesh.rings = 9
	mesh_part(parent,point,mesh,color).scale = size

func capsule(parent: Node3D, point: Vector3, radius: float, height: float, color: Color) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height,radius*2)
	mesh.radial_segments = 9
	mesh.rings = 4
	mesh_part(parent,point,mesh,color)

func mesh_part(parent: Node3D, point: Vector3, mesh: Mesh, color: Color) -> MeshInstance3D:
	var model := MeshInstance3D.new()
	model.mesh = mesh
	var paint := StandardMaterial3D.new()
	paint.albedo_color = color
	paint.roughness = .85
	model.material_override = paint
	model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.position = point
	parent.add_child(model)
	return model

func follow(path: PackedVector3Array) -> void:
	route = path
	cursor = 0
	dancing = false
	rest = 0

func advance(delta: float, pulse: float) -> bool:
	if fighting or (is_instance_valid(imported_model) and imported_model.knockdown_time>0):
		pose(delta,pulse,false)
		return true
	var walking := cursor<route.size()
	if walking:
		var target := route[cursor]
		var direction := target-position
		if direction.length()<=speed*delta+.024:
			position = target
			cursor += 1
		else:
			position = position.move_toward(target,speed*delta)
			rotation.y = lerp_angle(rotation.y,atan2(-direction.x,-direction.z),delta*8.0)
	else:
		if is_instance_valid(partner):
			var direction := partner.position-position
			rotation.y = lerp_angle(rotation.y,atan2(-direction.x,-direction.z),delta*6.0)
		else:
			rest += delta
	pose(delta,pulse,walking)
	return cursor>=route.size()

func pose(delta: float, pulse: float, walking: bool) -> void:
	if is_instance_valid(imported_model):
		pose_elapsed += delta
		if pose_elapsed >= pose_interval:
			imported_model.pose(pose_elapsed,walking,speed,dancing,pulse)
			pose_elapsed = 0.0
		return
	phase += delta*(8 if walking else 5)
	var swing := sin(phase)
	figure.position.y = absf(swing)*(.027 if walking else 0.0)
	if dancing and not walking:
		figure.position.y = .025+absf(sin(pulse*PI))*.045
		figure.rotation.z = sin(phase)*.08
	else:
		figure.rotation.z = 0.0
	for index in range(2):
		var side := 1 if index==0 else -1
		legs[index].rotation.x = side*swing*.40 if walking else 0.0
		arms[index].rotation.x = -side*swing*.38 if walking or dancing else 0.0
		arms[index].rotation.z = side*(-.43-absf(swing)*.18) if dancing else side*-.10
		knees[index].rotation.x = maxf(0,side*swing)*.58 if walking else .04
		elbows[index].rotation.x = -.22-absf(swing)*.20 if walking or dancing else -.13
		if speech.visible:
			elbows[index].rotation.x -= .45+absf(swing)*.46
	head.rotation.x = sin(phase*.7)*(.08 if is_instance_valid(partner) else .028)
	for index in range(2):
		pocket_arm(index)

func pocket_arm(index: int) -> void:
	var upper: Node3D = arms[index]
	var lower: Node3D = elbows[index]
	var side := -1.0 if index==0 else 1.0
	var shoulder := upper.position
	var wrist := Vector3(side*.115,1.040,-.040)
	var direction := (wrist-shoulder).normalized()
	var distance := wrist.distance_to(shoulder)
	const UPPER := .237
	const LOWER := .224
	var along := (UPPER*UPPER-LOWER*LOWER+distance*distance)/(2*distance)
	var outward := Vector3(side,-.15,.30)
	var bend := (outward-direction*outward.dot(direction)).normalized()
	var elbow := shoulder+direction*along+bend*sqrt(maxf(0,UPPER*UPPER-along*along))
	upper.basis = limb_basis(elbow-shoulder)
	lower.basis = upper.basis.inverse()*limb_basis(wrist-elbow)

func limb_basis(direction: Vector3) -> Basis:
	var up := -direction.normalized()
	var side := Vector3.RIGHT if absf(up.x)<.95 else Vector3.FORWARD
	var forward := side.cross(up).normalized()
	return Basis(up.cross(forward).normalized(),up,forward)
