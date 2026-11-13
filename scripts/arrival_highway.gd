extends Node3D

const START_Z := -208.0
const LANE_X := -56.60
const EXIT_Z := -27.8

func build(world: NightWorld) -> void:
	var center := (START_Z+EXIT_Z)*.5
	var length := EXIT_Z-START_Z+25.0
	center -= 12.5
	world.box(self,Vector3(-55.30,-.14,center),Vector3(40,.22,length),Color("#222728"))
	var road := PlaneMesh.new()
	road.size = Vector2(7.30,length)
	var asphalt := world.mesh(self,road,Vector3(-55.30,.026,center),Color.WHITE)
	var finish := StandardMaterial3D.new()
	finish.albedo_texture = preload("res://assets/city/asphalt.jpg")
	finish.albedo_color = Color("#737680")
	finish.uv1_scale = Vector3(2,length/3.7,1)
	finish.roughness = .96
	asphalt.material_override = finish
	for side in [-1,1]:
		world.box(self,Vector3(-55.30+side*3.11,.033,center),Vector3(.10,.009,length),Color("#9fa2a5"))
		for i in range(13):
			var z := -37.5-i*14.3
			var at := Vector3(-55.30+side*3.82,0,z)
			world.box(self,at+Vector3.UP*.42,Vector3(.075,.84,.077),Color("#787d82"))
			world.box(self,at+Vector3(0,.69,-.041),Vector3(.074,.13,.009),Color("#c6bda1"))
			if i%3==0:
				world.box(self,at+Vector3(side*.77,2.37,0),Vector3(.10,4.74,.11),Color("#343842"))
				world.box(self,at+Vector3(side*.21,4.68,0),Vector3(1.18,.11,.19),Color("#4b5156"))
				world.point_light(self,at+Vector3(side*.02,4.48,0),Color("#ffd9a4"),1.15,10.0)
			for tree in range(2):
				var x: float = side*(6.6+tree*4.3+sin(i*7.0)*1.6)
				var foot := Vector3(-55.3+x,0,z+tree*3.4)
				world.box(self,foot+Vector3.UP*1.15,Vector3(.27,2.30,.28),Color("#252824"))
				world.sphere(self,foot+Vector3.UP*3.18,Vector3(2.35,3.50,2.55),Color("#252d2c"))
	for i in range(34):
		world.box(self,Vector3(-55.30,.033,-30.0-i*5.85),Vector3(.105,.009,2.10),Color("#a9a18a"))
	var sign := Node3D.new()
	add_child(sign)
	sign.position = Vector3(-55.30,0,-39.5)
	var steel := Color("#565e63")
	for side in [-1,1]:
		world.box(sign,Vector3(side*3.77,1.59,0),Vector3(.09,3.18,.09),steel)
	world.box(sign,Vector3(0,3.14,0),Vector3(7.62,.09,.09),steel)
	world.box(sign,Vector3(-1.20,2.76,0),Vector3(1.75,.72,.075),Color("#315046"))
	world.add_sign(sign,"CITY EXIT",Vector3(-1.20,2.88,-.042),Vector3(0,PI,0),Color("#f2edce"),.0042)
	world.add_sign(sign,"8 AVENUE",Vector3(-1.20,2.64,-.042),Vector3(0,PI,0),Color("#cadfcb"),.0028)
	world.point_light(sign,Vector3(-1.20,3.13,-.52),Color("#ffe7c0"),.55,4.0)

static func speed(z: float) -> float:
	var highway_speed := lerpf(4.9,21.8,1.0-smoothstep(-106,-33,z))
	return highway_speed-2.15*smoothstep(EXIT_Z,-11,z)
