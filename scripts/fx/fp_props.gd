class_name FPProps
extends RefCounted
## Builders for the consumable props (beer bottle, energy can, cigarette, lighter).
## The shapes are glTF models from tools/blender/build_fp_assets.py; the label
## textures they use are still generated here and exported by the visual tour. Every builder makes either a first-person
## viewmodel copy (`view = true`, drawn over the world) or a normal world copy
## (mirror reflection, fridge, bar shelves).

const VIEW_SHADER := preload("res://assets/fx/viewmodel.gdshader")
const GLASS_SHADER := preload("res://assets/fx/viewmodel_glass.gdshader")
const FLAME_SHADER := preload("res://assets/fx/flame.gdshader")

static var textures := {}

# --- materials -------------------------------------------------------------

static func view_material(color: Color, rough: float, metal := 0.0, texture: Texture2D = null) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = VIEW_SHADER
	material.set_shader_parameter("albedo",color)
	material.set_shader_parameter("roughness",rough)
	material.set_shader_parameter("metallic",metal)
	if texture!=null:
		material.set_shader_parameter("albedo_texture",texture)
	return material

static func material(view: bool, color: Color, rough: float, metal := 0.0, texture: Texture2D = null, glass := false) -> Material:
	if view:
		var shaded := view_material(color,rough,metal,texture)
		if glass:
			shaded.shader = GLASS_SHADER
			shaded.set_shader_parameter("specular",.9)
			shaded.set_shader_parameter("rim_amount",.5)
			shaded.set_shader_parameter("rim_color",Color(color.r,color.g,color.b).lightened(.5))
			shaded.set_shader_parameter("rim_amount",.25)
		return shaded
	var standard := StandardMaterial3D.new()
	standard.albedo_color = color
	standard.roughness = rough
	standard.metallic = metal
	if texture!=null:
		standard.albedo_texture = texture
	if glass:
		standard.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		standard.metallic_specular = .9
		standard.rim_enabled = true
		standard.rim = .4
	return standard

static func set_emission(target: Material, color: Color, energy: float) -> void:
	if target is ShaderMaterial:
		target.set_shader_parameter("emission",color)
		target.set_shader_parameter("emission_energy",energy)
	elif target is StandardMaterial3D:
		target.emission_enabled = true
		target.emission = color
		target.emission_energy_multiplier = energy

# --- glTF models (built by tools/blender/build_fp_assets.py) -------------------

const MODELS := {
	"bottle": preload("res://assets/fp/bottle.glb"),
	"can": preload("res://assets/fp/can.glb"),
	"cigarette": preload("res://assets/fp/cigarette.glb"),
	"lighter": preload("res://assets/fp/lighter.glb"),
	"pack": preload("res://assets/fp/pack.glb"),
	"six_pack": preload("res://assets/fp/six_pack.glb"),
}
## Imported material name -> extra viewmodel shader settings.
const VIEW_TWEAKS := {
	"CanWrap": {"clearcoat_amount": .6},
	"LighterPlastic": {"clearcoat_amount": .8},
	"Glass": {"specular": .9, "rim_amount": .25},
	"Condensation": {"specular": .9, "rim_amount": .25},
}

## Instantiates a prop model. Every mesh gets its own material in
## `material_override` (the ember and liquid are animated per instance):
## the viewmodel shader for `view` copies, the imported material otherwise.
static func model(key: String, root_name: String, view: bool) -> Node3D:
	var root := (MODELS[key] as PackedScene).instantiate() as Node3D
	root.name = root_name
	for node in root.find_children("*","MeshInstance3D",true,false):
		var mesh_node := node as MeshInstance3D
		var source := mesh_node.mesh.surface_get_material(0)
		mesh_node.material_override = convert_material(source,view)
		if view:
			mesh_node.layers = FPViewModel.LAYER
			mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root

static func convert_material(source: Material, view: bool) -> Material:
	var standard := source as StandardMaterial3D
	if standard==null:
		return source
	var glass := standard.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED
	if not view:
		var copy := standard.duplicate() as StandardMaterial3D
		if glass:
			copy.metallic_specular = .9
			copy.rim_enabled = true
			copy.rim = .4
		return copy
	var shaded := view_material(standard.albedo_color,standard.roughness,standard.metallic,standard.albedo_texture)
	if glass:
		shaded.shader = GLASS_SHADER
		var c := standard.albedo_color
		shaded.set_shader_parameter("rim_color",Color(c.r,c.g,c.b).lightened(.5))
	if standard.emission_enabled:
		set_emission(shaded,standard.emission,standard.emission_energy_multiplier)
	var name := standard.resource_name
	for key in VIEW_TWEAKS.get(name,{}):
		shaded.set_shader_parameter(key,VIEW_TWEAKS[name][key])
	return shaded

# --- meshes ----------------------------------------------------------------

## Surface of revolution around Y. profile: (radius, height) points from bottom to top.
static func lathe(profile: PackedVector2Array, segments := 28, cap_bottom := false, cap_top := false) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lengths := PackedFloat32Array([0.0])
	for index in range(1,profile.size()):
		lengths.append(lengths[index-1]+profile[index].distance_to(profile[index-1]))
	var total := maxf(lengths[lengths.size()-1],.0001)
	var normals := PackedVector2Array()
	for index in range(profile.size()):
		var before := profile[maxi(index-1,0)]
		var after := profile[mini(index+1,profile.size()-1)]
		var along := (after-before).normalized()
		normals.append(Vector2(along.y,-along.x))
	for side in range(segments):
		for index in range(profile.size()-1):
			var corners := [[side,index],[side+1,index],[side,index+1],[side+1,index],[side+1,index+1],[side,index+1]]
			for corner in corners:
				var angle: float = TAU*float(corner[0])/segments
				var point := profile[corner[1]]
				var normal := normals[corner[1]]
				tool.set_normal(Vector3(normal.x*cos(angle),normal.y,normal.x*sin(angle)).normalized())
				tool.set_uv(Vector2(1.0-float(corner[0])/segments,1.0-lengths[corner[1]]/total))
				tool.add_vertex(Vector3(point.x*cos(angle),point.y,point.x*sin(angle)))
	for end in [[cap_bottom,0,-1.0],[cap_top,profile.size()-1,1.0]]:
		if not end[0]:
			continue
		var ring := profile[end[1]]
		for side in range(segments):
			var a := TAU*float(side)/segments
			var b := TAU*float(side+1)/segments
			var points := [Vector3(0,ring.y,0),Vector3(ring.x*cos(a),ring.y,ring.x*sin(a)),Vector3(ring.x*cos(b),ring.y,ring.x*sin(b))]
			if end[2]>0:
				points = [points[0],points[2],points[1]]
			for point in points:
				tool.set_normal(Vector3(0,end[2],0))
				tool.set_uv(Vector2(.5+point.x*6,.5+point.z*6))
				tool.add_vertex(point)
	return tool.commit()

static func add_mesh(parent: Node3D, mesh: Mesh, surface: Material, at := Vector3.ZERO, turn := Vector3.ZERO, size := Vector3.ONE, view := true) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = surface
	node.position = at
	node.rotation = turn
	node.scale = size
	if view:
		node.layers = FPViewModel.LAYER
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

static func cylinder_mesh(radius: float, height: float, segments := 24, top := -1.0) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top<0 else top
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return mesh

# --- beer ------------------------------------------------------------------

const BOTTLE_PROFILE := [
	Vector2(.0,.0),Vector2(.026,.0),Vector2(.031,.003),Vector2(.0325,.010),Vector2(.0325,.128),
	Vector2(.031,.142),Vector2(.025,.160),Vector2(.017,.176),Vector2(.0132,.190),Vector2(.0125,.226),
	Vector2(.0138,.229),Vector2(.0140,.236),Vector2(.0125,.239),
]

## Long-neck lager bottle (assets/fp/bottle.glb); origin at the bottom centre,
## 0.24 m tall. Children: Glass, Liquid (scale.y = fill, holds Foam), Label, NeckLabel, Cap, Beads.
static func beer_bottle(view: bool) -> Node3D:
	var root := model("bottle","Bottle",view)
	# Condensation beads only on the cold bottle in hand.
	root.get_node("Beads").visible = view
	return root

static func beer_label() -> Texture2D:
	if textures.has("beer_label"):
		return textures.beer_label
	var image := Image.create(256,96,false,Image.FORMAT_RGBA8)
	var paper := Color("#e8d6a8")
	var noise := FastNoiseLite.new()
	noise.frequency = .08
	for y in range(96):
		for x in range(256):
			var grain := noise.get_noise_2d(x,y)*.05
			image.set_pixel(x,y,Color(paper.r+grain,paper.g+grain,paper.b+grain*1.4))
	image.fill_rect(Rect2i(0,0,256,9),Color("#7e2219"))
	image.fill_rect(Rect2i(0,87,256,9),Color("#7e2219"))
	image.fill_rect(Rect2i(0,10,256,2),Color("#b48a3c"))
	image.fill_rect(Rect2i(0,84,256,2),Color("#b48a3c"))
	# Two faces so the brand is visible from any side.
	for face in [0,128]:
		ellipse(image,Vector2(face+64,48),Vector2(46,30),Color("#7e2219"))
		ellipse(image,Vector2(face+64,48),Vector2(43,27),Color("#f1e3bd"))
		stamp(image,"NIGHT",Vector2i(face+64,30),2,Color("#3c1d12"))
		stamp(image,"LAGER",Vector2i(face+64,49),2,Color("#7e2219"))
		image.fill_rect(Rect2i(face+40,46,48,1),Color("#b48a3c"))
		stamp(image,"5.2",Vector2i(face+64,70),1,Color("#3c1d12"))
	image.generate_mipmaps()
	textures.beer_label = ImageTexture.create_from_image(image)
	return textures.beer_label

# --- energy can -------------------------------------------------------------

const CAN_PROFILE := [
	Vector2(.0,.006),Vector2(.020,.006),Vector2(.026,.0),Vector2(.0305,.004),Vector2(.0325,.014),
	Vector2(.0325,.112),Vector2(.0300,.124),Vector2(.0265,.130),Vector2(.0268,.133),
]

## 330 ml slim can (assets/fp/can.glb), 0.133 m tall. Children: Body, Lid, Tab (rotates open), Hole.
static func energy_can(view: bool) -> Node3D:
	var root := model("can","Can",view)
	root.get_node("Hole").visible = false
	return root

static func can_wrap() -> Texture2D:
	if textures.has("can"):
		return textures.can
	var image := Image.create(256,128,false,Image.FORMAT_RGBA8)
	for y in range(128):
		var shade := lerpf(.10,.03,float(y)/127.0)
		for x in range(256):
			image.set_pixel(x,y,Color(shade*.8,shade*.9,shade*1.6))
	image.fill_rect(Rect2i(0,0,256,10),Color("#c9ced6"))
	image.fill_rect(Rect2i(0,118,256,10),Color("#c9ced6"))
	for face in [0,128]:
		# Diagonal acid-green bolt.
		var bolt := PackedVector2Array([Vector2(70,14),Vector2(46,62),Vector2(64,62),Vector2(50,112),Vector2(86,52),Vector2(68,52),Vector2(84,14)])
		polygon(image,bolt,Vector2(face,0),Color("#b6ff2e"))
		stamp(image,"VOLT",Vector2i(face+64,40),3,Color("#f4ffe8"))
		stamp(image,"ENERGY",Vector2i(face+64,78),1,Color("#b6ff2e"))
		image.fill_rect(Rect2i(face+20,94,88,2),Color("#b6ff2e"))
	image.generate_mipmaps()
	textures.can = ImageTexture.create_from_image(image)
	return textures.can

# --- cigarette ---------------------------------------------------------------

## Cigarette pointing along -Z, filter at the origin. Children: Filter, Paper, Ember, Ash.
## Paper and Ash shorten with `set_cigarette_burn`.
static func cigarette(view: bool) -> Node3D:
	return model("cigarette","Cigarette",view)

static func set_cigarette_burn(item: Node3D, burn: float, glow: float) -> void:
	var remaining := 1.0-clampf(burn,0.0,1.0)*.85
	var paper := item.get_node_or_null("Paper") as Node3D
	if paper==null:
		return
	paper.scale.z = remaining
	var tip := -.022-.062*remaining
	var ash := item.get_node("Ash") as Node3D
	var ember := item.get_node("Ember") as MeshInstance3D
	ember.position.z = tip-.0006
	ash.position.z = tip-.0035
	ash.visible = burn>.03
	var surface := ember.material_override
	set_emission(surface,Color("#ff5a1a").lerp(Color("#ffc46a"),glow*.6),.6+glow*5.5)

static func cork_texture() -> Texture2D:
	return noise_texture("cork",Color("#a8692c"),Color("#e2a965"),.35,64)

static func paper_texture() -> Texture2D:
	return noise_texture("paper",Color("#d9d3c6"),Color("#fbf8f1"),.5,64)

static func ash_texture() -> Texture2D:
	return noise_texture("ash",Color("#3c3a38"),Color("#c2bdb5"),.6,32)

static func skin_texture() -> Texture2D:
	return noise_texture("skin",Color("#e2d0c4"),Color("#ffffff"),.09,128)

static func fabric_texture() -> Texture2D:
	if textures.has("fabric"):
		return textures.fabric
	var image := Image.create(64,64,false,Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = .2
	for y in range(64):
		for x in range(64):
			var weave := .9+.1*float((x+y)%4<2)
			var grain := .92+noise.get_noise_2d(x,y)*.12
			var value := weave*grain
			image.set_pixel(x,y,Color(value,value,value))
	image.generate_mipmaps()
	textures.fabric = ImageTexture.create_from_image(image)
	return textures.fabric

static func noise_texture(key: String, dark: Color, light: Color, frequency: float, size: int) -> Texture2D:
	if textures.has(key):
		return textures[key]
	var image := Image.create(size,size,false,Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = frequency
	noise.seed = key.hash()
	for y in range(size):
		for x in range(size):
			image.set_pixel(x,y,dark.lerp(light,clampf(noise.get_noise_2d(x,y)*.5+.5,0,1)))
	image.generate_mipmaps()
	textures[key] = ImageTexture.create_from_image(image)
	return textures[key]

# --- lighter -------------------------------------------------------------------

## Disposable lighter, origin at the bottom, flame nozzle up. Children: Wheel, Flame, Light.
static func lighter(view: bool) -> Node3D:
	var root := model("lighter","Lighter",view)
	var flame := MeshInstance3D.new()
	flame.name = "Flame"
	var quad := QuadMesh.new()
	quad.size = Vector2(.014,.03)
	flame.mesh = quad
	var fire := ShaderMaterial.new()
	fire.shader = FLAME_SHADER
	flame.material_override = fire
	flame.position = Vector3(-.004,.094,0)
	flame.visible = false
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if view:
		flame.layers = FPViewModel.LAYER
	root.add_child(flame)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color("#ffa24a")
	light.light_energy = 0.0
	light.omni_range = 2.5
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.position = Vector3(0,.11,.0)
	root.add_child(light)
	return root

# --- shop-only props ------------------------------------------------------------

## Soft pack of cigarettes with an open lid; origin at the bottom centre.
static func cigarette_pack(view: bool) -> Node3D:
	return model("pack","Pack",view)

static func pack_texture() -> Texture2D:
	if textures.has("pack"):
		return textures.pack
	var image := Image.create(112,172,false,Image.FORMAT_RGBA8)
	image.fill(Color("#f4efe6"))
	image.fill_rect(Rect2i(0,70,112,102),Color("#b0231c"))
	image.fill_rect(Rect2i(0,66,112,4),Color("#c8a34f"))
	polygon(image,PackedVector2Array([Vector2(0,70),Vector2(56,40),Vector2(112,70)]),Vector2.ZERO,Color("#b0231c"))
	stamp(image,"ORION",Vector2i(56,96),3,Color("#f4efe6"))
	ellipse(image,Vector2(56,22),Vector2(12,12),Color("#c8a34f"))
	ellipse(image,Vector2(56,22),Vector2(9,9),Color("#f4efe6"))
	image.generate_mipmaps()
	textures.pack = ImageTexture.create_from_image(image)
	return textures.pack

## Cardboard six-pack carrier with six Night Lager bottles.
static func six_pack(view: bool) -> Node3D:
	var root := model("six_pack","SixPack",view)
	for index in range(6):
		var bottle := beer_bottle(view)
		bottle.position = Vector3(-.07+(index%3)*.07,.006,-.037 if index<3 else .037)
		root.add_child(bottle)
	return root

# --- tiny 5x7 bitmap font for printed labels -------------------------------------

const GLYPHS := {
	"A": ["01110","10001","10001","11111","10001","10001","10001"],
	"E": ["11111","10000","10000","11110","10000","10000","11111"],
	"G": ["01110","10001","10000","10111","10001","10001","01111"],
	"H": ["10001","10001","10001","11111","10001","10001","10001"],
	"I": ["11111","00100","00100","00100","00100","00100","11111"],
	"L": ["10000","10000","10000","10000","10000","10000","11111"],
	"N": ["10001","11001","10101","10011","10001","10001","10001"],
	"O": ["01110","10001","10001","10001","10001","10001","01110"],
	"R": ["11110","10001","10001","11110","10100","10010","10001"],
	"T": ["11111","00100","00100","00100","00100","00100","00100"],
	"V": ["10001","10001","10001","10001","10001","01010","00100"],
	"Y": ["10001","10001","01010","00100","00100","00100","00100"],
	"2": ["01110","10001","00001","00110","01000","10000","11111"],
	"5": ["11111","10000","11110","00001","00001","10001","01110"],
	".": ["00000","00000","00000","00000","00000","01100","01100"],
}

## Prints text centred on `center` (top of the glyphs) with `scale` px per dot.
static func stamp(image: Image, text: String, center: Vector2i, scale: int, color: Color) -> void:
	var width := text.length()*6*scale-scale
	var x := center.x-width/2
	for letter in text:
		var rows: Array = GLYPHS.get(letter,[])
		for row in range(rows.size()):
			for column in range(5):
				if rows[row][column]=="1":
					image.fill_rect(Rect2i(x+column*scale,center.y+row*scale,scale,scale),color)
		x += 6*scale

static func ellipse(image: Image, center: Vector2, radius: Vector2, color: Color) -> void:
	for y in range(int(center.y-radius.y),int(center.y+radius.y)+1):
		for x in range(int(center.x-radius.x),int(center.x+radius.x)+1):
			var d := Vector2((x-center.x)/radius.x,(y-center.y)/radius.y)
			if d.length_squared()<=1.0 and x>=0 and y>=0 and x<image.get_width() and y<image.get_height():
				image.set_pixel(x,y,color)

static func polygon(image: Image, points: PackedVector2Array, offset: Vector2, color: Color) -> void:
	var moved := PackedVector2Array()
	for point in points:
		moved.append(point+offset)
	var bounds := Rect2(moved[0],Vector2.ZERO)
	for point in moved:
		bounds = bounds.expand(point)
	for y in range(int(bounds.position.y),int(bounds.end.y)+1):
		for x in range(int(bounds.position.x),int(bounds.end.x)+1):
			if x>=0 and y>=0 and x<image.get_width() and y<image.get_height() and Geometry2D.is_point_in_polygon(Vector2(x,y),moved):
				image.set_pixel(x,y,color)
