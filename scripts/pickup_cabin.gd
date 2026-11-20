extends Node3D

const PAINT := Color("#d8d4c8")
const TRIM := Color("#44484a")
const RUBBER := Color("#262930")
const FABRIC := Color("#474956")
const EYES := [
	Vector3(.40,1.69,.38), Vector3(-.40,1.69,.38),
	Vector3(-.40,1.70,-.23), Vector3(.40,1.70,-.23),
]
var view := Camera3D.new()
var wheel := Node3D.new()
var gas_pedal := Node3D.new()
var brake_pedal := Node3D.new()
var speed_label := Label3D.new()
var finishes := {}
var yaw := 0.0
var pitch := -.045

func build(model: Node3D) -> void:
	for old_name in ["flatbed-truck_1", "flatbed-truck_2"]:
		var panel := model.find_child(old_name,true,false) as Node3D
		if panel != null:
			panel.hide()
	var floor_mesh := block(self,Vector3(0,.89,.32),Vector3(1.52,.08,1.47),RUBBER)
	floor_mesh.name = "CabinFloor"
	block(self,Vector3(0,1.11,-.46),Vector3(1.67,.47,.09),PAINT)
	block(self,Vector3(0,1.96,-.44),Vector3(1.63,.11,.11),PAINT)
	block(self,Vector3(0,1.96,1.10),Vector3(1.6,.11,.10),PAINT)
	block(self,Vector3(0,1.34,1.28),Vector3(1.62,.085,.125),PAINT)
	block(self,Vector3(0,1.015,1.22),Vector3(1.64,.58,.11),PAINT)
	block(self,Vector3(0,.73,1.24),Vector3(1.63,.15,.12),TRIM)
	for side in [-1.0,1.0]:
		var x: float = side * .78
		block(self,Vector3(side*.80,.881,.33),Vector3(.11,.33,1.65),PAINT)
		block(self,Vector3(x,1.195,.34),Vector3(.11,.32,1.58),PAINT)
		block(self,Vector3(x,1.95,.32),Vector3(.11,.105,1.60),PAINT)
		block(self,Vector3(x,1.60,-.43),Vector3(.11,.77,.11),PAINT)
		block(self,Vector3(x,1.60,.07),Vector3(.09,.77,.10),PAINT)
		beam(Vector3(x,1.34,1.28),Vector3(x,1.96,1.10),.09,PAINT)
		for handle_z in [-.30,.22]:
			block(self,Vector3(side*.85,1.26,handle_z),Vector3(.033,.034,.125),RUBBER)
		block(self,Vector3(side*.853,1.153,.073),Vector3(.012,.37,.017),TRIM)
		block(self,Vector3(side*.855,.98,.34),Vector3(.013,.067,1.43),TRIM)
		block(self,Vector3(x*.94,1.30,.46),Vector3(.06,.052,.34),RUBBER)
		block(self,Vector3(x*.94,1.30,-.23),Vector3(.06,.052,.26),RUBBER)
		pane(Vector3(x,1.65,.53),Vector2(.85,.55),Vector3(0,PI/2,0))
		pane(Vector3(x,1.65,-.18),Vector2(.40,.55),Vector3(0,PI/2,0))
	pane(Vector3(0,1.65,1.19),Vector2(1.49,.65),Vector3(-.282,0,0))
	pane(Vector3(0,1.65,-.44),Vector2(1.48,.57),Vector3.ZERO)
	detail_dashboard()
	for index in EYES.size():
		var seat: Vector3 = EYES[index]
		build_seat(seat,index<2)
	add_child(wheel)
	wheel.position = Vector3(.40,1.365,.76)
	var ring := TorusMesh.new()
	ring.inner_radius = .135
	ring.outer_radius = .176
	ring.rings = 24
	ring.ring_segments = 9
	var ring_instance := MeshInstance3D.new()
	ring_instance.mesh = ring
	ring_instance.material_override = finish(Color("#535865"))
	ring_instance.rotation.x = PI/2
	wheel.add_child(ring_instance)
	block(wheel,Vector3.ZERO,Vector3(.27,.028,.035),RUBBER)
	block(wheel,Vector3(0,-.06,0),Vector3(.035,.15,.033),RUBBER)
	block(wheel,Vector3.ZERO,Vector3(.099,.085,.054),Color("#454c53"))
	add_child(speed_label)
	speed_label.position = Vector3(.40,1.418,.829)
	speed_label.rotation.y = PI
	speed_label.pixel_size = .00155
	speed_label.font_size = 34
	speed_label.outline_size = 2
	speed_label.modulate = Color("#b5eec2")
	add_child(view)
	view.fov = 78.0
	view.near = .026
	view.set_disable_scale(true)
	view.set_cull_mask_value(3,false)
	var dash_light := OmniLight3D.new()
	dash_light.position = Vector3(0,1.73,.81)
	dash_light.light_color = Color("#b8ceec")
	dash_light.light_energy = .46
	dash_light.omni_range = 1.6
	add_child(dash_light)
	var footwell_light := OmniLight3D.new()
	footwell_light.position = Vector3(.43,1.12,.67)
	footwell_light.light_color = Color("#adb9c9")
	footwell_light.light_energy = .32
	footwell_light.omni_range = .61
	add_child(footwell_light)

func detail_dashboard() -> void:
	block(self,Vector3(0,1.225,1.06),Vector3(1.54,.16,.42),RUBBER)
	rounded(Vector3(0,1.301,1.115),Vector3(1.52,.115,.398),Color("#343942"))
	rounded(Vector3(.4,1.355,.954),Vector3(.37,.19,.22),RUBBER)
	block(self,Vector3(.4,1.37,.907),Vector3(.275,.113,.035),Color("#192426"))
	block(self,Vector3(0,1.315,.85),Vector3(.29,.18,.055),Color("#333d46"))
	block(self,Vector3(0,1.35,.817),Vector3(.179,.063,.016),Color("#315052"))
	for x in [-.53,-.15,.15,.53]:
		for louver in range(3):
			block(self,Vector3(x,1.29+louver*.014,.848),Vector3(.085,.005,.014),Color("#596069"))
	rounded(Vector3(0,1.04,.44),Vector3(.24,.24,.61),RUBBER)
	rounded(Vector3(0,1.181,.49),Vector3(.14,.055,.19),Color("#474953"))
	var shifter := block(self,Vector3(0,1.223,.49),Vector3(.024,.104,.024),Color("#777d84"))
	shifter.rotation.x = -.23
	rounded(Vector3(0,1.279,.478),Vector3(.073,.048,.057),RUBBER)
	build_pedal(gas_pedal,Vector3(.247,1.131,.877),Vector2(.054,.119))
	build_pedal(brake_pedal,Vector3(.411,1.137,.865),Vector2(.092,.08))
	block(self,Vector3(.43,.940,.796),Vector3(.51,.014,.439),Color("#20262d"))

func build_pedal(pedal: Node3D, mount: Vector3, size: Vector2) -> void:
	add_child(pedal)
	pedal.position = mount
	pedal.rotation.x = -.24
	block(pedal,Vector3(0,-.042,0),Vector3(.026,.112,.023),Color("#717780"))
	block(pedal,Vector3(0,-.103,-.021),Vector3(size.x,size.y,.032),RUBBER)
	for rib in range(4):
		block(pedal,Vector3(0,-.103+size.y*(float(rib)/4-.36),-.039),Vector3(size.x*.84,.008,.008),Color("#646c75"))

func build_seat(eye: Vector3, front: bool) -> void:
	var leather := Color("#363e48")
	var seam := Color("#6a6d75")
	var back := eye.z-.155
	var cushion_length := .45 if front else .35
	rounded(Vector3(eye.x,1.02,eye.z+.041),Vector3(.61,.197,cushion_length),leather)
	rounded(Vector3(eye.x,1.065,eye.z+.035),Vector3(.43,.116,cushion_length*.94),FABRIC)
	var backrest := rounded(Vector3(eye.x,1.288,back),Vector3(.56,.56,.187),leather)
	backrest.rotation.x = -.13
	rounded(Vector3(eye.x,1.278,back+.056),Vector3(.38,.445,.121),FABRIC)
	for side in [-1.0,1.0]:
		rounded(Vector3(eye.x+side*.232,1.078,eye.z+.035),Vector3(.135,.103,cushion_length*.91),leather)
		rounded(Vector3(eye.x+side*.207,1.294,back+.075),Vector3(.101,.38,.145),leather)
		block(self,Vector3(eye.x+side*.064,1.537,back-.043),Vector3(.014,.088,.014),seam)
	rounded(Vector3(eye.x,1.588,back-.043),Vector3(.243,.151,.126),leather)
	if front:
		rounded(Vector3(eye.x,1.219,back-.105),Vector3(.378,.198,.034),RUBBER)
		block(self,Vector3(eye.x- signf(eye.x)*.288,1.103,eye.z-.065),Vector3(.041,.067,.048),Color("#944e48"))

func rounded(at: Vector3, size: Vector3, tint: Color) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = .5
	shape.height = 1.0
	shape.radial_segments = 14
	shape.rings = 7
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.material_override = finish(tint)
	node.position = at
	node.scale = size
	add_child(node)
	return node

func finish(tint: Color) -> StandardMaterial3D:
	if finishes.has(tint):
		return finishes[tint]
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = .84
	finishes[tint] = material
	return material

func block(parent: Node3D, at: Vector3, size: Vector3, tint: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	node.mesh = shape
	node.material_override = finish(tint)
	node.position = at
	parent.add_child(node)
	return node

func beam(start: Vector3, end: Vector3, width: float, tint: Color) -> void:
	var node := block(self,(start+end)/2,Vector3(width,width,start.distance_to(end)),tint)
	node.basis = Basis.looking_at(end-start,Vector3.FORWARD)

func pane(at: Vector3, size: Vector2, angles: Vector3) -> void:
	var shape := QuadMesh.new()
	shape.size = size
	var glass := MeshInstance3D.new()
	glass.mesh = shape
	var material := finish(Color(.49,.74,.78,.035))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.material_override = material
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass.position = at
	glass.rotation = angles
	add_child(glass)

func look_at_seat(seat: int) -> void:
	yaw = 0.0
	pitch = -.045
	view.position = EYES[seat]
	view.rotation = Vector3(pitch,PI,0)
	view.make_current()

func look_motion(seat: int, motion: Vector2, sensitivity: float) -> void:
	var yaw_limit := 1.90 if seat == 0 else 2.36
	yaw = clampf(yaw-motion.x*sensitivity,-yaw_limit,yaw_limit)
	pitch = clampf(pitch-motion.y*sensitivity,-.96,.78)
	view.rotation = Vector3(pitch,PI+yaw,0)

func animate(speed: float, steering: float, delta: float) -> void:
	wheel.rotation.z = lerpf(wheel.rotation.z,-steering*1.17,1.0-exp(-delta*13.0))
	speed_label.text = "%02d" % roundi(absf(speed)*3.6)

func animate_pedals(gas: float, brake: float, delta: float) -> void:
	var blend := 1.0-exp(-delta*17.0)
	gas_pedal.rotation.x = lerpf(gas_pedal.rotation.x,-.24-.32*gas,blend)
	brake_pedal.rotation.x = lerpf(brake_pedal.rotation.x,-.24-.28*brake,blend)
