extends RefCounted

const SIZE := Vector2(.078,.163)
const DISPLAY := Vector2(.073,.156)

static func build(parent: Node3D, texture: Texture2D) -> void:
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color("#35232d")
	frame.metallic = .36
	frame.roughness = .53
	plate(parent,SIZE,.012,Vector3.ZERO,frame)
	var rear := StandardMaterial3D.new()
	rear.albedo_color = Color("#4b2531")
	rear.roughness = .4
	plate(parent,Vector2(.074,.158),.001,Vector3(0,0,-.006),rear)
	plate(parent,Vector2(.072,.044),.004,Vector3(0,.054,-.008),frame)
	for point in [Vector2(-.021,.061),Vector2(.002,.060),Vector2(-.021,.041)]:
		lens(parent,Vector3(point.x,point.y,-.012),.009,frame)
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color("#13192b")
		glass.metallic = .36
		glass.roughness = .12
		lens(parent,Vector3(point.x,point.y,-.0135),.007,glass)
	for at in [Vector3(-.039,.033,0),Vector3(-.039,.01,0),Vector3(.039,.026,0)]:
		plate(parent,Vector2(.003,.012),.004,at,frame)
	var glass_front := StandardMaterial3D.new()
	glass_front.albedo_color = Color("#08070a")
	glass_front.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	plate(parent,Vector2(.075,.159),.001,Vector3(0,0,.0065),glass_front)
	var screen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = DISPLAY
	screen.mesh = quad
	var surface := StandardMaterial3D.new()
	surface.albedo_texture = texture
	surface.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen.material_override = surface
	screen.position.z = .0071
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(screen)

static func plate(parent: Node3D, size: Vector2, depth: float, at: Vector3, material: Material) -> void:
	var outline := PackedVector2Array()
	var radius := minf(.009,minf(size.x,size.y)*.36)
	for corner in range(4):
		var start := float(corner)*PI*.5
		var middle := start+PI*.25
		var center := Vector2(signf(cos(middle)),signf(sin(middle)))*(size*.5-Vector2.ONE*radius)
		for step in range(6):
			var angle := start+PI*.5*step/5.0
			outline.append(center+Vector2(cos(angle),sin(angle))*radius)
	var shape := CSGPolygon3D.new()
	shape.polygon = outline
	shape.depth = depth
	shape.material = material
	shape.position = at+Vector3.BACK*depth*.5
	parent.add_child(shape)

static func lens(parent: Node3D, at: Vector3, radius: float, material: Material) -> void:
	var model := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = .0025
	model.mesh = cylinder
	model.material_override = material
	model.rotation.x = PI*.5
	model.position = at
	parent.add_child(model)
