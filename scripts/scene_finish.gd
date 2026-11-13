class_name SceneFinish
extends Node

const MIRROR_LAYER := 2
const REFLECTED_HEAD_LAYER := 3
const WALL_HEIGHT := 2.70

var home: Home
var mirror: MeshInstance3D
var mirror_camera: Camera3D
var mirror_view: SubViewport
var ceilings := {}
var paint := StandardMaterial3D.new()

func _init(game_home: Home) -> void:
	home = game_home
	paint.albedo_color = Color("#b7ad9d")
	paint.roughness = .86
	var grain := FastNoiseLite.new()
	grain.frequency = .17
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = grain
	texture.as_normal_map = true
	texture.bump_strength = .12
	paint.normal_enabled = true
	paint.normal_texture = texture
	paint.normal_scale = .14

func prepare_walls() -> void:
	var source: Node3D = home.catalog.get("wall")
	if source!=null:
		var dimensions: Vector3 = home.vector(home.data.templates.wall.dimensions)
		replace_wall_mesh(source,dimensions)
		home.data.templates.wall.h = WALL_HEIGHT
	for row in home.originals.values():
		if home.rooms.structural_wall(row) and str(row.label)=="Стена":
			replace_wall_mesh(home.nodes[row.id],home.vector(row.dimensions))

func replace_wall_mesh(root: Node3D, dimensions: Vector3) -> void:
	for child in root.get_children():
		child.free()
	var model := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	model.mesh = box
	model.material_override = paint
	model.position.y = dimensions.y*.5
	root.add_child(model)

func sync_ceilings() -> void:
	for id in ceilings.keys():
		if not home.records.has(id) or bool(home.records[id].deleted):
			ceilings[id].free()
			ceilings.erase(id)
	for row in home.records.values():
		if str(row.kind)!="floor" or bool(row.deleted) or str(row.id)=="night-courtyard":
			continue
		var model: MeshInstance3D = ceilings.get(row.id)
		if model==null:
			model = MeshInstance3D.new()
			model.mesh = BoxMesh.new()
			var material := StandardMaterial3D.new()
			material.albedo_color = Color("#e1ded3")
			material.roughness = .92
			model.material_override = material
			home.add_child(model)
			ceilings[row.id] = model
		var slab := model.mesh as BoxMesh
		var built: bool = home.rooms.built_room(row)
		slab.size = Vector3(float(row.w)+.024,.05,float(row.d)+.024)
		var top: float = home.rooms.floor_surface(row)+WALL_HEIGHT
		if not built:
			top += .027
			var key := str(row.id)
			if not str(row.get("zone","")).is_empty():
				top = maxf(top,float(row.y)+float(row.h)+.032)
			else:
				top += float(key.hash()%31)*.00055
		model.position = Vector3(float(row.x),top-.025,float(row.z))
		model.rotation.y = deg_to_rad(float(row.r))

func setup_mirror() -> void:
	var frame: Node3D = home.nodes.get("base-74")
	if frame==null:
		return
	var parts := frame.find_children("*","MeshInstance3D",true,false)
	if parts.size()!=2:
		return
	var glass := parts[1] as MeshInstance3D
	var normal := -glass.global_basis.x.normalized()
	var up := glass.global_basis.y.normalized()
	var right := up.cross(normal).normalized()
	var bounds := glass.get_aabb()
	var width := bounds.size.z*glass.global_basis.z.length()
	var height := bounds.size.y*glass.global_basis.y.length()
	var center := glass.global_transform*bounds.get_center()+normal*.027
	glass.hide()
	mirror_view = SubViewport.new()
	mirror_view.world_3d = home.get_world_3d()
	mirror_view.size = Vector2i(clampi(roundi(288.0*width/height),96,576),288)
	mirror_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(mirror_view)
	mirror_camera = Camera3D.new()
	mirror_camera.set_cull_mask_value(MIRROR_LAYER,false)
	mirror_camera.set_cull_mask_value(4,false)
	mirror_camera.set_cull_mask_value(5,false)
	mirror_camera.current = true
	mirror_view.add_child(mirror_camera)
	mirror = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width,height)
	mirror.mesh = quad
	mirror.set_layer_mask_value(1,false)
	mirror.set_layer_mask_value(MIRROR_LAYER,true)
	mirror.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded;
uniform sampler2D reflection_view : filter_linear;
void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	if (dot(centered, centered) > 1.0) { discard; }
	vec3 reflected = texture(reflection_view, vec2(1.0 - UV.x, UV.y)).rgb;
	ALBEDO = reflected * vec3(0.90, 0.94, 0.97) + vec3(0.022, 0.025, 0.029);
}"""
	material.shader = shader
	material.set_shader_parameter("reflection_view",mirror_view.get_texture())
	mirror.material_override = material
	frame.add_child(mirror)
	mirror.global_transform = Transform3D(Basis(right,up,normal),center)
	home.player.camera.set_cull_mask_value(REFLECTED_HEAD_LAYER,false)

func _process(_delta: float) -> void:
	if mirror==null:
		return
	var player_camera: Camera3D = home.player.camera
	var normal := mirror.global_basis.z.normalized()
	var center := mirror.global_position
	var eye := player_camera.global_position
	var distance := (eye-center).dot(normal)
	if home.modal or not mirror.is_visible_in_tree() or distance<=.04 or eye.distance_squared_to(center)>36:
		mirror_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var up := mirror.global_basis.y.normalized()
	var right := normal.cross(up).normalized()
	var quad := mirror.mesh as QuadMesh
	var width := quad.size.x*mirror.global_basis.x.length()
	var height := quad.size.y*mirror.global_basis.y.length()
	var visible := player_camera.is_position_in_frustum(center)
	for side in [-1.0,1.0]:
		for vertical in [-1.0,1.0]:
			visible = visible or player_camera.is_position_in_frustum(center+right*width*.5*side+up*height*.5*vertical)
	if not visible:
		mirror_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var reflected_eye := eye-2.0*normal*distance
	var shift := center-reflected_eye
	mirror_camera.global_transform = Transform3D(Basis(right,up,-normal),reflected_eye)
	var near := distance+.004
	var factor := near/distance
	mirror_camera.set_frustum(height*factor,Vector2(shift.dot(right),shift.dot(up))*factor,near,22.0)
	mirror_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func landscape(env: Environment) -> void:
	var sky := Sky.new()
	var atmosphere := ProceduralSkyMaterial.new()
	atmosphere.sky_top_color = Color("#6b9bc2")
	atmosphere.sky_horizon_color = Color("#e0e4cf")
	atmosphere.ground_horizon_color = Color("#b5c2a0")
	atmosphere.ground_bottom_color = Color("#667451")
	atmosphere.sun_angle_max = 12
	sky.sky_material = atmosphere
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#fff0d8")
	sun.light_energy = .39
	sun.rotation_degrees = Vector3(-37,-58,0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 22
	home.add_child(sun)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6147
	var leaves: Array[Transform3D] = []
	var colors: Array[Color] = []
	var trunks: Array[Transform3D] = []
	for i in range(65):
		var angle := TAU*float(i)/65.0+rng.randf_range(-.12,.12)
		var radius := rng.randf_range(13.5,52.0)
		var base := Vector3(cos(angle)*radius,-.06,sin(angle)*radius)
		var height := rng.randf_range(3.4,8.0)
		var trunk_width := height*.028
		trunks.append(Transform3D(Basis.from_scale(Vector3(trunk_width,height*.72,trunk_width)),base+Vector3.UP*height*.36))
		var tint := Color("#365c42").lerp(Color("#819450"),rng.randf_range(.05,.9))
		for tier in range(5):
			var crown_radius := height*rng.randf_range(.15,.25)*(1.0-.095*tier)
			var offset := Vector3(rng.randf_range(-.55,.55),height*(.49+.10*tier),rng.randf_range(-.55,.55))
			var basis := Basis(Vector3.UP,rng.randf_range(0,TAU)).scaled_local(Vector3(crown_radius,crown_radius*1.25,crown_radius))
			leaves.append(Transform3D(basis,base+offset))
			colors.append(tint.lightened(.04*tier))
	var trunk := CylinderMesh.new()
	trunk.top_radius = .52
	trunk.bottom_radius = 1.0
	trunk.height = 1.0
	trunk.radial_segments = 7
	trunk.rings = 0
	scatter(trunk,trunks,[],Color("#6b5340"))
	var crown := SphereMesh.new()
	crown.radius = 1.0
	crown.height = 2.0
	crown.radial_segments = 13
	crown.rings = 7
	scatter(crown,leaves,colors,Color.WHITE)

func scatter(mesh: Mesh, transforms: Array[Transform3D], colors: Array[Color], tint: Color) -> void:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = not colors.is_empty()
	batch.mesh = mesh
	batch.instance_count = transforms.size()
	for index in range(transforms.size()):
		batch.set_instance_transform(index,transforms[index])
		if batch.use_colors:
			batch.set_instance_color(index,colors[index])
	var grove := MultiMeshInstance3D.new()
	grove.multimesh = batch
	var finish := StandardMaterial3D.new()
	finish.albedo_color = tint
	finish.vertex_color_use_as_albedo = batch.use_colors
	finish.vertex_color_is_srgb = batch.use_colors
	finish.roughness = 1.0
	grove.material_override = finish
	home.add_child(grove)

