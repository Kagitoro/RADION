extends Node3D
## The passenger's tapping hand has separate finger segments.

var index_base: MeshInstance3D
var index_tip: MeshInstance3D
var knuckle: MeshInstance3D
const INDEX_ROOT := Vector3(-.016,.049,.003)

func build(world: NightWorld) -> void:
	var skin := Color("#a77553")
	var palm := BoxMesh.new()
	palm.size = Vector3(.048,.056,.022)
	world.mesh(self,palm,Vector3(.003,.024,0),skin)
	var wrist := SphereMesh.new()
	wrist.radius = .018
	wrist.height = .035
	wrist.radial_segments = 8
	wrist.rings = 4
	world.mesh(self,wrist,Vector3(0,.005,0),skin).scale = Vector3(1.08,1.2,.69)
	for index in range(3):
		var start := Vector3(-.004+index*.013,.048-index*.002,0)
		var bend := start+Vector3(.001,.019,-.008)
		set_segment(segment(world,skin,.0068),start,bend)
		set_segment(segment(world,skin,.0057),bend,bend+Vector3(0,-.006,-.013))
	set_segment(segment(world,skin,.008),Vector3(-.018,.023,-.002),Vector3(-.031,.040,-.012))
	set_segment(segment(world,skin,.0068),Vector3(-.031,.040,-.012),Vector3(-.024,.048,-.019))
	index_base = segment(world,skin,.0074)
	index_tip = segment(world,skin,.0060)
	var joint := SphereMesh.new()
	joint.radius = .0069
	joint.height = .0138
	joint.radial_segments = 8
	joint.rings = 4
	knuckle = world.mesh(self,joint,Vector3.ZERO,skin)
	hide()

func segment(world: NightWorld, tint: Color, radius: float) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.height = 1
	shape.top_radius = radius*.81
	shape.bottom_radius = radius
	shape.radial_segments = 7
	return world.mesh(self,shape,Vector3.ZERO,tint)

func set_segment(part: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var axis := to-from
	part.position = (from+to)*.5
	part.basis = Basis(Quaternion(Vector3.UP,axis.normalized())).scaled_local(Vector3(1,axis.length(),1))

func pose_tip(target: Vector3, pressed: float) -> void:
	var contact := to_local(target)
	var curl := Vector3(-.010,.080,-.023)
	var tip := curl.lerp(contact,pressed)
	var bend := INDEX_ROOT.lerp(tip,.54)+Vector3(0,0,.010*(1.0-pressed))
	knuckle.position = bend
	set_segment(index_base,INDEX_ROOT,bend)
	set_segment(index_tip,bend,tip)
