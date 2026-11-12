extends Node3D
## Interior set built in car space. The street remains the playable city.

var world: NightWorld
var driver: PartyGuest
var passenger: GuestModel
var column := Node3D.new()
var wheel := Node3D.new()
var phone := Node3D.new()
var progress: MeshInstance3D
var phone_amount := 0.0
var phone_time: Label3D
var cabin_light: OmniLight3D
var screen_light: OmniLight3D
var driver_look := 0.0
const EYE := Vector3(-.43,1.36,-.33)

func build(night_world: NightWorld) -> void:
	world = night_world
	var leather := Color("#29272a")
	var trim := Color("#34343b")
	var paint := Color("#793d26")
	var rubber := Color("#18191d")
	world.box(self,Vector3(0,.39,.25),Vector3(1.87,.14,3.38),rubber)
	world.box(self,Vector3(0,1.77,-.12),Vector3(1.87,.09,1.88),leather)
	world.box(self,Vector3(0,.87,.77),Vector3(1.86,.38,.57),trim)
	world.box(self,Vector3(0,1.045,.73),Vector3(1.86,.095,.64),leather)
	world.box(self,Vector3(0,.90,.472),Vector3(1.83,.028,.018),Color("#78717a"))
	world.box(self,Vector3(0,.84,1.45),Vector3(1.80,.14,.96),paint)
	world.box(self,Vector3(0,1.74,.83),Vector3(1.79,.072,.10),rubber)
	var glass := QuadMesh.new()
	glass.size = Vector2(1.70,.65)
	var windshield := world.mesh(self,glass,Vector3(0,1.398,.849),Color.WHITE)
	windshield.rotation.x = .30
	windshield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tint := StandardMaterial3D.new()
	tint.cull_mode = BaseMaterial3D.CULL_DISABLED
	tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint.albedo_color = Color(.40,.62,.77,.060)
	windshield.material_override = tint
	world.box(self,Vector3(0,.68,-.03),Vector3(.25,.26,.92),trim)
	world.box(self,Vector3(0,.824,.09),Vector3(.18,.027,.36),rubber)
	for side in [-1,1]:
		world.box(self,Vector3(side*.915,.75,-.02),Vector3(.081,.64,1.97),trim)
		world.box(self,Vector3(side*.875,1.047,-.02),Vector3(.10,.048,1.99),rubber)
		world.box(self,Vector3(side*.86,.911,-.24),Vector3(.032,.037,.29),Color("#7d7777"))
		world.box(self,Vector3(side*.45,.61,-.52),Vector3(.60,.19,.70),leather)
		world.box(self,Vector3(side*.45,1.02,-.98),Vector3(.60,.74,.15),leather)
		world.box(self,Vector3(side*.45,1.43,-1.00),Vector3(.29,.23,.16),leather)
		var pillar := world.mesh(self,BoxMesh.new(),Vector3(side*.88,1.40,.83),trim)
		(pillar.mesh as BoxMesh).size = Vector3(.087,.76,.085)
		pillar.rotation.x = .32
		world.box(self,Vector3(side*.90,1.40,-.91),Vector3(.075,.72,.09),trim)
	for x in [-.60,-.43,-.09,.09]:
		world.box(self,Vector3(x,.963,.458),Vector3(.125,.082,.028),rubber)
		for row in range(3):
			world.box(self,Vector3(x,.94+row*.019,.44),Vector3(.107,.004,.006),Color("#767079"))
	world.box(self,Vector3(0,.826,.439),Vector3(.19,.087,.024),rubber)
	var radio := lit_box(self,Vector3(0,.835,.423),Vector3(.114,.031,.008),Color("#527a75"))
	radio.layers = 1
	label(self," FM  98.3 ",Vector3(0,.836,.417),.00063,Color("#a5e1bc"))
	world.box(self,Vector3(.41,1.09,.622),Vector3(.36,.106,.18),rubber)
	label(self,"0    20    40    60",Vector3(.41,1.092,.527),.0008,Color("#b3cfbf"))
	add_child(column)
	column.position = Vector3(.43,1.03,.225)
	column.rotation.x = PI*.42
	column.add_child(wheel)
	var rim := TorusMesh.new()
	rim.inner_radius = .147
	rim.outer_radius = .179
	world.mesh(wheel,rim,Vector3.ZERO,rubber)
	world.box(wheel,Vector3.ZERO,Vector3(.29,.041,.047),rubber)
	world.box(wheel,Vector3(0,.004,0),Vector3(.109,.059,.084),trim)
	world.box(self,Vector3(0,1.635,.756),Vector3(.25,.071,.039),rubber)
	lit_box(self,Vector3(0,1.635,.734),Vector3(.223,.047,.005),Color("#373a49"))
	build_phone()
	driver = PartyGuest.new(12,null,world.home.party.psx_assets)
	add_child(driver)
	driver.position = Vector3(.42,-.26,-.27)
	driver.rotation.y = PI
	driver.name_tag.hide()
	passenger = GuestModel.new()
	if passenger.setup_psx(world.home.party.psx_assets,false,2,1.0,1.0,Color("#c99570"),Color("#454b68"),Color("#303645")):
		add_child(passenger)
		passenger.position = Vector3(EYE.x,-.27,-.32)
		passenger.rotation.y = PI
		passenger.player_body = true
		passenger.make_first_person(PackedStringArray(["LeftForeArm","LeftUpLeg","RightUpLeg"]))
	else:
		passenger.free()
		passenger = null
	cabin_light = OmniLight3D.new()
	add_child(cabin_light)
	cabin_light.position = Vector3(.26,1.58,.48)
	cabin_light.light_color = Color("#ffc695")
	cabin_light.omni_range = 2.4
	screen_light = OmniLight3D.new()
	phone.add_child(screen_light)
	screen_light.position = Vector3(0,0,.10)
	screen_light.light_color = Color("#a6cdff")
	screen_light.omni_range = .43
	screen_light.light_energy = .36

func lit_box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	var model := world.mesh(parent,shape,at,color)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	model.material_override = material
	return model

func label(parent: Node3D, value: String, at: Vector3, pixel: float, color: Color, angle: float = PI) -> Label3D:
	var text := Label3D.new()
	text.text = value
	text.font_size = 32
	text.pixel_size = pixel
	text.modulate = color
	text.outline_size = 0
	text.rotation.y = angle
	text.position = at
	parent.add_child(text)
	return text

func build_phone() -> void:
	add_child(phone)
	world.box(phone,Vector3.ZERO,Vector3(.084,.156,.013),Color("#17171d"))
	world.box(phone,Vector3(0,0,.006),Vector3(.077,.149,.003),Color("#777d90"))
	lit_box(phone,Vector3(0,0,.008),Vector3(.071,.142,.002),Color("#141d33"))
	lit_box(phone,Vector3(0,.060,.010),Vector3(.032,.009,.002),Color("#0a0d16"))
	label(phone,"VOICEMAIL",Vector3(0,.040,.012),.00030,Color("#dbe6ff"),0)
	label(phone,"LAST MONTH",Vector3(0,.024,.012),.00022,Color("#a3afd1"),0)
	for i in range(16):
		var amplitude := .006 + absf(sin(i*1.37)*sin(i*.62+.3))*.014
		lit_box(phone,Vector3((i-7.5)*.0038,.002,.011),Vector3(.00175,amplitude,.001),Color("#849aff"))
	lit_box(phone,Vector3(0,-.021,.011),Vector3(.061,.002,.001),Color("#414c71"))
	progress = lit_box(phone,Vector3(-.0305,-.021,.012),Vector3(.061,.002,.001),Color("#e2e6ff"))
	phone_time = label(phone,"0:00",Vector3(0,-.038,.012),.00034,Color("#cfd7ed"),0)
	lit_box(phone,Vector3(0,-.064,.011),Vector3(.024,.002,.001),Color("#98a4c8"))
	phone.hide()

func sit(rig: GuestModel) -> void:
	for side in ["Left","Right"]:
		rig.rotate_local(side+"UpLeg",Vector3(-1.20,0,0))
		rig.rotate_local(side+"Leg",Vector3(1.52,0,0))

func update_pose(delta: float, clock: float, raise_phone: bool, duration: float, clip_time: float, talking: bool) -> void:
	wheel.rotation.y = sin(clock*.81)*.062 + sin(clock*1.48)*.017
	cabin_light.light_energy = .29 + .21*pow(maxf(0,sin(clock*1.20)),4)
	var rig := driver.imported_model as GuestModel
	if rig != null:
		# Reset to the same seated base on every frame before applying IK.
		rig.pose(0.0,false,1.0,false,0.0)
		sit(rig)
		driver_look = move_toward(driver_look,.16 if talking else 0.0,delta*.48)
		rig.rotate_local("Head",Vector3(.018*sin(clock*1.15),driver_look,.008*sin(clock*.8)))
		for index in range(rig.arms.size()):
			var side := 1.0 if index==0 else -1.0
			var arm := rig.arms[index]
			var rim := wheel.to_global(Vector3(side*.145,.0,-.075))
			var wrist := rim+global_basis*Vector3(side*.027,-.025,-.074)
			rig.point_arm(arm,rig.skeleton.to_local(wrist),Vector3(side,-.76,-.31))
			var solved := rig.skeleton.to_global(rig.skeleton.get_bone_global_pose(arm.z).origin)
			orient_hand(rig,arm.z,solved,rim,global_basis*Vector3(side*.34,1,0),.86)
	phone_amount = move_toward(phone_amount,1.0 if raise_phone else 0.0,delta*(1.75 if raise_phone else 2.4))
	var ease := smoothstep(0,1,phone_amount)
	phone.visible = phone_amount>.08
	phone.position = Vector3(-.61,.76,.04).lerp(Vector3(-.53,1.194,.238),ease)
	phone.position.y += sin(clock*2.5)*.003
	phone.rotation = Vector3(.42*(1.0-ease)-.12*ease,PI-.045,.012)
	var played := clampf(clip_time/maxf(.1,duration),.002,1.0)
	progress.scale.x = played
	progress.position.x = -.0305+.0305*played
	phone_time.text = "0:%02d" % floori(clip_time)
	if passenger != null:
		passenger.visible = phone.visible
		passenger.pose(0.0,false,1.0,false,0.0)
		sit(passenger)
		var contact := Vector3(-.027,-.085,-.078)
		for index in range(passenger.arms.size()):
			var arm := passenger.arms[index]
			var side := 1.0 if index==0 else -1.0
			var rest := Vector3(side*.19,.88,.23)
			var target := passenger.skeleton.to_local(phone.to_global(contact)) if index==0 and phone.visible else rest
			passenger.point_arm(arm,target,Vector3(side,-.7,-.20))
		if phone.visible:
			var arm := passenger.arms[0]
			var wrist := passenger.skeleton.to_global(passenger.skeleton.get_bone_global_pose(arm.z).origin)
			phone.global_position = wrist - phone.global_basis*contact
			var fingers := phone.to_global(Vector3(-.017,.025,contact.z))
			orient_hand(passenger,arm.z,wrist,fingers,phone.global_basis.z,.94)

func orient_hand(rig: GuestModel, bone: int, wrist: Vector3, fingers: Vector3, palm_normal: Vector3, influence: float) -> void:
	var inverse := rig.skeleton.global_basis.inverse()
	var up := (inverse*(fingers-wrist)).normalized()
	var side := up.cross(inverse*palm_normal).normalized()
	var current := rig.skeleton.get_bone_global_pose(bone).basis.orthonormalized()
	var grip := Basis(side,up,side.cross(up))
	rig.set_joint_rotation(bone,current.slerp(grip,influence))
