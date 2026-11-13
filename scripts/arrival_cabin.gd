extends Node3D
## Interior set built in car space. The street remains the playable city.

var world: NightWorld
var driver: PartyGuest
var passenger: GuestModel
var column := Node3D.new()
var wheel := Node3D.new()
var phone := Node3D.new()
var phone_amount := 0.0
const PhoneUI = preload("res://scripts/arrival_phone_ui.gd")
const TapHand = preload("res://scripts/arrival_tap_hand.gd")
var phone_ui: PhoneUI
var tap_hand: TapHand
var cabin_light: OmniLight3D
var screen_light: OmniLight3D
var driver_look := 0.0
var phone_press := 0.0
var doors: Array[Node3D] = []
var parked_details := Node3D.new()
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
		var door := Node3D.new()
		add_child(door)
		doors.append(door)
		door.position = Vector3(side*.915,0,.80)
		world.box(door,Vector3(0,.75,-.81),Vector3(.081,.64,1.62),trim)
		world.box(door,Vector3(side*.047,.75,-.81),Vector3(.018,.62,1.60),paint)
		world.box(door,Vector3(-side*.04,1.047,-.81),Vector3(.10,.048,1.64),rubber)
		world.box(door,Vector3(-side*.055,.911,-1.04),Vector3(.032,.037,.29),Color("#7d7777"))
		world.box(self,Vector3(side*.915,.75,-.90),Vector3(.081,.64,.17),trim)
		world.box(self,Vector3(side*.45,.61,-.52),Vector3(.60,.19,.70),leather)
		world.box(self,Vector3(side*.45,1.02,-.98),Vector3(.60,.74,.15),leather)
		world.box(self,Vector3(side*.45,1.43,-1.00),Vector3(.29,.23,.16),leather)
		var pillar := world.mesh(self,BoxMesh.new(),Vector3(side*.88,1.40,.83),trim)
		(pillar.mesh as BoxMesh).size = Vector3(.087,.76,.085)
		pillar.rotation.x = .32
		world.box(self,Vector3(side*.90,1.40,-.91),Vector3(.075,.72,.09),trim)
	add_child(parked_details)
	parked_details.hide()
	world.box(parked_details,Vector3(0,.61,-1.49),Vector3(1.86,.43,1.0),paint)
	world.box(parked_details,Vector3(0,.47,1.93),Vector3(1.87,.12,.11),trim)
	for side in [-1,1]:
		for axle in [-1.44,1.36]:
			var tyre := CylinderMesh.new()
			tyre.height = .23
			tyre.top_radius = .34
			tyre.bottom_radius = .34
			world.mesh(parked_details,tyre,Vector3(side*.88,.34,axle),rubber).rotation.z = PI*.5
		lit_box(parked_details,Vector3(side*.69,.66,-2.0),Vector3(.21,.095,.02),Color("#8c2c28"))
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
		passenger.make_first_person(PackedStringArray(["LeftForeArm","RightForeArm"]),PackedStringArray(["RightHand"]))
		tap_hand = TapHand.new()
		add_child(tap_hand)
		tap_hand.build(world)
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
	screen_light.light_energy = .18

func set_exit_doors(passenger_open: float, driver_open: float) -> void:
	doors[0].rotation.y = passenger_open*1.28
	doors[1].rotation.y = -driver_open*1.28

func reach_exit_handle(amount: float) -> void:
	if passenger == null or amount <= .001:
		return
	passenger.show()
	var arm := passenger.arms[0]
	var handle := passenger.skeleton.to_local(doors[0].to_global(Vector3(.055,.911,-1.04)))
	passenger.point_arm(arm,Vector3(.23,.71,.22).lerp(handle,amount),Vector3.RIGHT+Vector3.DOWN)

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
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360,720)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	phone.add_child(viewport)
	phone_ui = PhoneUI.new()
	viewport.add_child(phone_ui)
	preload("res://scripts/radion_phone_model.gd").build(phone,viewport.get_texture())
	phone.hide()

func sit(rig: GuestModel) -> void:
	for side in ["Left","Right"]:
		rig.rotate_local(side+"UpLeg",Vector3(-1.20,0,0))
		rig.rotate_local(side+"Leg",Vector3(1.52,0,0))

func update_pose(delta: float, clock: float, phone_view: PhoneUI.Page, played: float, tap: Vector2, reach: float, touch: float, talking: bool) -> void:
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
	var raise_phone := phone_view != PhoneUI.Page.OFF
	phone_amount = move_toward(phone_amount,1.0 if raise_phone else 0.0,delta*(1.02 if raise_phone else 1.42))
	if raise_phone:
		phone_ui.show_page(phone_view,played,tap,touch,delta)
	var ease := smoothstep(0,1,phone_amount)
	phone.visible = phone_amount>.08
	phone.position = Vector3(-.62,.72,.05).lerp(Vector3(-.49,1.105,.225),ease)
	phone.position.y += sin(clock*2.5)*.003
	phone.rotation = Vector3(-.08,PI-.035,.024)
	var facing := phone.global_transform.looking_at(to_global(EYE+Vector3(.015,-.055,.045)),global_basis.y,true)
	phone.global_basis = phone.global_basis.slerp(facing.basis,ease).orthonormalized()
	phone_press = move_toward(phone_press,touch,delta*7.0)
	phone.rotate_object_local(Vector3.RIGHT,-.033*phone_press)
	if passenger != null:
		passenger.visible = phone.visible
		tap_hand.visible = phone.visible
		passenger.pose(0.0,false,1.0,false,0.0)
		sit(passenger)
		var contact := Vector3(-.027,-.078,-.082)
		for index in range(passenger.arms.size()):
			var arm := passenger.arms[index]
			var side := 1.0 if index==0 else -1.0
			var rest := Vector3(side*.23,.71,.22)
			var target := passenger.skeleton.to_local(phone.to_global(contact)) if index==0 and phone.visible else rest
			passenger.point_arm(arm,target,Vector3(side*.36,-1.42,-.24))
		if phone.visible:
			var arm := passenger.arms[0]
			var wrist := passenger.skeleton.to_global(passenger.skeleton.get_bone_global_pose(arm.z).origin)
			phone.global_position = wrist - phone.global_basis*contact
			var aligned := phone.global_transform.looking_at(to_global(EYE+Vector3(.015,-.055,.045)),global_basis.y,true)
			phone.global_basis = phone.global_basis.slerp(aligned.basis,ease*.94).orthonormalized()
			phone.global_position = wrist - phone.global_basis*contact
			var fingers := phone.to_global(Vector3(-.015,.040,contact.z-.006))
			orient_hand(passenger,arm.z,wrist,fingers,phone.global_basis.z,.94)
			var tap_arm := passenger.arms[1]
			var local := Vector3((tap.x/360.0-.5)*.074,(.5-tap.y/720.0)*.148,.014)
			var tip := phone.to_global(local)
			var hand := phone.to_global(local+Vector3(.105,-.038,.012))
			var rest := to_global(Vector3(-.72,.54,-.08))
			var path := rest.lerp(hand,reach)
			path += phone.global_basis*Vector3(.075,-.11,-.005)*sin(PI*reach)
			passenger.point_arm(tap_arm,passenger.skeleton.to_local(path),Vector3(-.95,-1.7,-.30))
			var tap_wrist := passenger.skeleton.to_global(passenger.skeleton.get_bone_global_pose(tap_arm.z).origin)
			var pointing := (global_basis*Vector3(.12,.58,.80)).lerp(tap_wrist.direction_to(tip),reach).normalized()
			var across := pointing.cross(phone.global_basis.z).normalized()
			tap_hand.global_transform = Transform3D(Basis(across,pointing,across.cross(pointing)),tap_wrist)
			tap_hand.pose_tip(tip,touch)

func orient_hand(rig: GuestModel, bone: int, wrist: Vector3, fingers: Vector3, palm_normal: Vector3, influence: float) -> void:
	var inverse := rig.skeleton.global_basis.inverse()
	var up := (inverse*(fingers-wrist)).normalized()
	var side := up.cross(inverse*palm_normal).normalized()
	var current := rig.skeleton.get_bone_global_pose(bone).basis.orthonormalized()
	var grip := Basis(side,up,side.cross(up))
	rig.set_joint_rotation(bone,current.slerp(grip,influence))
