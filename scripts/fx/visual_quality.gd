class_name VisualQuality
extends RefCounted
## One pass that lifts the whole scene out of the flat "untextured box" look:
## Forward+ post effects (SSAO, SSIL, SSR, glow, fog, grading), shadows on the
## room lamps and a subtle procedural surface detail on every plain material.
## On the Compatibility fallback renderer the unsupported effects are skipped.

## House lamps that may cast shadows; only the nearest few do at any moment.
static var shadow_lamps: Array[Light3D] = []
## Omni shadows render the scene six times each: twelve lamps cost ~11 ms of GPU
## time on a GTX 1650. Four nearest is where the difference stops being visible.
const SHADOW_RANGE := 14.0
## A lamp hidden behind a wall counts as this much farther away (metres).
const WALL_PENALTY := 7.0
## Lamps that already cast a shadow keep it unless another is clearly better.
const KEEP_BONUS := 1.5
const SHADOW_FADE := .35
## Graphics quality (pause/main menu): 0 low, 1 medium, 2 high.
## Low: no SSAO/SSIL/SSR/fog, no lamp shadows. Medium: SSAO + fog, 2 shadows. High: everything, 4 shadows.
const SHADOW_BUDGETS := [0,3,5]
const LEVEL_NAMES := ["Низкая","Средняя","Высокая"]
static var level := 2
static var environments: Array[Environment] = []

static func forward_plus() -> bool:
	return str(ProjectSettings.get_setting("rendering/renderer/rendering_method","")) == "forward_plus" \
		and RenderingServer.get_current_rendering_method() == "forward_plus"

static func apply(home: Node) -> void:
	environments.clear()
	for node in home.find_children("*","WorldEnvironment",true,false):
		environment((node as WorldEnvironment).environment)
		environments.append((node as WorldEnvironment).environment)
	set_level(level)
	lamp_shadows(home)
	surfaces(home)

static func environment(env: Environment) -> void:
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.08
	env.glow_enabled = true
	env.glow_intensity = .55
	env.glow_strength = .9
	env.glow_bloom = .02
	env.glow_hdr_threshold = .95
	env.glow_hdr_scale = 1.6
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for level in range(7):
		env.set_glow_level(level,[0.0,.6,1.0,.8,.5,.3,0.0][level])
	if not forward_plus():
		return
	env.ssao_enabled = true
	env.ssao_radius = .9
	env.ssao_intensity = 1.7
	env.ssao_power = 1.4
	env.ssao_detail = .6
	env.ssao_light_affect = .05
	env.ssil_enabled = true
	env.ssil_radius = 3.0
	env.ssil_intensity = .55
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = .2
	env.ssr_fade_out = 2.5
	env.ssr_depth_tolerance = .25
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = .006
	env.volumetric_fog_albedo = Color("#c9d3e6")
	env.volumetric_fog_emission = Color("#06080d")
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_anisotropy = .45
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_ambient_inject = .15

## Soft shadows on the house lamps; street and club lights stay cheap.
static func lamp_shadows(home: Node) -> void:
	var lighting: Node = home.get("scene_lighting")
	if lighting==null:
		return
	shadow_lamps.clear()
	for light in lighting.get_children():
		if light is Light3D and light.light_energy>.08:
			shadow_lamps.append(light)
			light.shadow_enabled = false
			light.shadow_blur = 1.6
			light.shadow_bias = .04
			light.shadow_normal_bias = 1.2
			light.light_volumetric_fog_energy = .6
			# No PCSS (light_size 0): soft enough with the blur, ~25% cheaper on the GPU.
			light.light_size = 0.0

## Switches the costly effects for a quality level (see LEVEL_NAMES).
static func set_level(value: int) -> void:
	level = clampi(value,0,2)
	var rich := forward_plus()
	for env in environments:
		if env==null:
			continue
		env.ssao_enabled = rich and level>=1
		env.ssil_enabled = rich and level>=2
		env.ssr_enabled = rich and level>=2
		env.volumetric_fog_enabled = rich and level>=1
	# Lower shadow filtering on medium/low: fewer samples per shadowed pixel.
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if level==2 else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	if level==0:
		for light in shadow_lamps:
			if is_instance_valid(light):
				fade_shadow(light,false)

## Gives shadows to the budget's lamps nearest to `eye` (called a few
## times a second); the rest keep lighting the room without a shadow map.
static func update_shadow_budget(camera: Camera3D) -> void:
	if camera==null or not camera.is_inside_tree():
		return
	var eye := camera.global_position
	var frustum := camera.get_frustum()
	var space := camera.get_world_3d().direct_space_state
	var scored := []
	for light in shadow_lamps:
		if not is_instance_valid(light) or not light.is_visible_in_tree():
			continue
		var reach := light_range(light)
		var distance := light.global_position.distance_to(eye)
		# Only lamps whose light reaches into the view: the shadow must be seen to matter.
		if distance>SHADOW_RANGE+reach*.5 or not sphere_in_view(frustum,light.global_position,reach):
			continue
		var score := distance
		var ray := PhysicsRayQueryParameters3D.create(eye,light.global_position,1)
		if not space.intersect_ray(ray).is_empty():
			score += WALL_PENALTY
		if light.has_meta("shadow_on") and bool(light.get_meta("shadow_on")):
			score -= KEEP_BONUS
		scored.append([score,light])
	scored.sort_custom(func(a,b): return a[0]<b[0])
	var chosen := {}
	for entry in scored.slice(0,SHADOW_BUDGETS[level]):
		chosen[entry[1]] = true
	for light in shadow_lamps:
		if is_instance_valid(light):
			fade_shadow(light,chosen.has(light))

static func light_range(light: Light3D) -> float:
	if light is OmniLight3D:
		return (light as OmniLight3D).omni_range
	if light is SpotLight3D:
		return (light as SpotLight3D).spot_range
	return 0.0

static func sphere_in_view(frustum: Array[Plane], center: Vector3, radius: float) -> bool:
	for plane in frustum:
		if plane.distance_to(center)>radius:
			return false
	return true

## Shadows fade in and out instead of popping when the chosen lamps change.
static func fade_shadow(light: Light3D, on: bool) -> void:
	var was := light.has_meta("shadow_on") and bool(light.get_meta("shadow_on"))
	if was==on:
		return
	light.set_meta("shadow_on",on)
	if light.has_meta("shadow_tween"):
		var old: Tween = light.get_meta("shadow_tween")
		if old!=null and old.is_valid():
			old.kill()
	var tween := light.create_tween()
	light.set_meta("shadow_tween",tween)
	if on:
		light.shadow_enabled = true
		tween.tween_property(light,"shadow_opacity",1.0,SHADOW_FADE).from(0.0)
	else:
		tween.tween_property(light,"shadow_opacity",0.0,SHADOW_FADE)
		tween.tween_callback(func(): light.shadow_enabled = false)

## Low-poly finish for everything built in code: plain materials become clean,
## matte flat colour (no noise or bump maps), and smooth primitives are rebuilt
## with few segments and one normal per facet, like the imported models
## (addons/lowpoly_import) and the first-person props.
static func surfaces(root: Node) -> void:
	var done := {}
	for node in root.find_children("*","MeshInstance3D",true,false):
		var model := node as MeshInstance3D
		if model.layers & FPViewModel.LAYER:
			continue
		facet_primitive(model)
		var material := model.material_override as StandardMaterial3D
		if material==null or done.has(material):
			continue
		done[material] = true
		dress(material)

static func dress(material: StandardMaterial3D) -> void:
	if material.albedo_texture!=null or material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:
		return
	if material.emission_enabled or material.shading_mode!=BaseMaterial3D.SHADING_MODE_PER_PIXEL:
		return
	if material.billboard_mode!=BaseMaterial3D.BILLBOARD_DISABLED or material.vertex_color_use_as_albedo:
		return
	material.normal_enabled = false
	material.roughness = maxf(material.roughness,.62)
	material.metallic_specular = minf(material.metallic_specular,.35)
	# Dark paving keeps a little sheen at night; everything else is matte.
	var tint := material.albedo_color
	if tint.get_luminance()<.09 and tint.s<.35:
		material.roughness = .5
	elif material.metallic<.5:
		material.metallic = 0.0

## Walls: flat paint (the facets and the lamps do the shading).
static func plaster(material: StandardMaterial3D) -> void:
	material.albedo_texture = null
	material.normal_enabled = false
	material.roughness = maxf(material.roughness,.85)
	material.metallic = 0.0

## Segment counts of the faceted primitives.
const SPHERE_SIDES := 10
const SPHERE_RINGS := 6
const ROUND_SIDES := 10
static var faceted := {}

## Replaces a smooth primitive (sphere, cylinder, capsule, torus) with a few-sided,
## flat-shaded copy; identical primitives share one faceted mesh.
static func facet_primitive(model: MeshInstance3D) -> void:
	var source := model.mesh as PrimitiveMesh
	if source==null or not (source is SphereMesh or source is CylinderMesh or source is CapsuleMesh or source is TorusMesh):
		return
	if faceted.has(source):
		model.mesh = faceted[source]
		return
	var simple := source.duplicate() as PrimitiveMesh
	if simple is SphereMesh:
		simple.radial_segments = mini(simple.radial_segments,SPHERE_SIDES)
		simple.rings = mini(simple.rings,SPHERE_RINGS)
	elif simple is CylinderMesh:
		simple.radial_segments = mini(simple.radial_segments,ROUND_SIDES)
		simple.rings = 0
	elif simple is CapsuleMesh:
		simple.radial_segments = mini(simple.radial_segments,8)
		simple.rings = mini(simple.rings,2)
	elif simple is TorusMesh:
		simple.rings = mini(simple.rings,12)
		simple.ring_segments = mini(simple.ring_segments,6)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,flat_arrays(simple.get_mesh_arrays()))
	mesh.surface_set_material(0,source.material)
	faceted[source] = mesh
	model.mesh = mesh

## One normal per triangle (corners unshared).
static func flat_arrays(arrays: Array) -> Array:
	var tool := SurfaceTool.new()
	tool.create_from_arrays(arrays,Mesh.PRIMITIVE_TRIANGLES)
	tool.deindex()
	var flat := tool.commit_to_arrays()
	var vertices: PackedVector3Array = flat[Mesh.ARRAY_VERTEX]
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for corner in range(0,vertices.size()-2,3):
		var normal := (vertices[corner+2]-vertices[corner]).cross(vertices[corner+1]-vertices[corner])
		normal = normal.normalized() if normal.length_squared()>1e-20 else Vector3.UP
		normals[corner] = normal
		normals[corner+1] = normal
		normals[corner+2] = normal
	flat[Mesh.ARRAY_NORMAL] = normals
	flat[Mesh.ARRAY_TANGENT] = null
	return flat
