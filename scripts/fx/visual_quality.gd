class_name VisualQuality
extends RefCounted
## One pass that lifts the whole scene out of the flat "untextured box" look:
## Forward+ post effects (SSAO, SSIL, SSR, glow, fog, grading), shadows on the
## room lamps and a subtle procedural surface detail on every plain material.
## On the Compatibility fallback renderer the unsupported effects are skipped.

static var detail_textures := {}

static func forward_plus() -> bool:
	return str(ProjectSettings.get_setting("rendering/renderer/rendering_method","")) == "forward_plus" \
		and RenderingServer.get_current_rendering_method() == "forward_plus"

static func apply(home: Node) -> void:
	for node in home.find_children("*","WorldEnvironment",true,false):
		environment((node as WorldEnvironment).environment)
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
	for light in lighting.get_children():
		if light is Light3D and light.light_energy>.08:
			light.shadow_enabled = true
			light.shadow_blur = 1.6
			light.shadow_bias = .04
			light.shadow_normal_bias = 1.2
			light.light_volumetric_fog_energy = .6
			if light is OmniLight3D:
				light.light_size = .06
			elif light is SpotLight3D:
				light.light_size = .05

## Adds grime/plaster micro detail to plain coloured materials (shared ones once).
static func surfaces(root: Node) -> void:
	var done := {}
	for node in root.find_children("*","MeshInstance3D",true,false):
		var model := node as MeshInstance3D
		if model.layers & FPViewModel.LAYER:
			continue
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
	var tint := material.albedo_color
	var luma := tint.get_luminance()
	material.albedo_texture = grime_texture()
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE*.9
	material.uv1_triplanar_sharpness = 2.0
	material.normal_enabled = true
	material.normal_texture = bump_texture()
	material.normal_scale = .2
	# Dark paving reads as damp asphalt at night; mid greys as painted metal.
	if luma<.09 and tint.s<.35:
		material.roughness = .42
	elif tint.s<.25 and luma<.35:
		material.metallic = maxf(material.metallic,.25)
		material.roughness = minf(material.roughness,.55)

static func grime_texture() -> Texture2D:
	if detail_textures.has("grime"):
		return detail_textures.grime
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = .012
	noise.fractal_octaves = 5
	noise.fractal_gain = .55
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0,.45,1.0])
	ramp.colors = PackedColorArray([Color(.86,.85,.83),Color(.96,.96,.95),Color(1.02,1.02,1.01)])
	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 512
	texture.seamless = true
	texture.noise = noise
	texture.color_ramp = ramp
	texture.generate_mipmaps = true
	detail_textures.grime = texture
	return texture

static func bump_texture() -> Texture2D:
	if detail_textures.has("bump"):
		return detail_textures.bump
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = .05
	noise.fractal_octaves = 3
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	texture.as_normal_map = true
	texture.bump_strength = 2.0
	texture.generate_mipmaps = true
	detail_textures.bump = texture
	return texture

## Plaster for house walls and ceilings: fine, even paint texture.
static func plaster(material: StandardMaterial3D) -> void:
	if not detail_textures.has("plaster"):
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.frequency = .09
		noise.fractal_octaves = 3
		var ramp := Gradient.new()
		ramp.colors = PackedColorArray([Color(.95,.95,.94),Color(1.01,1.01,1.0)])
		var texture := NoiseTexture2D.new()
		texture.width = 256
		texture.height = 256
		texture.seamless = true
		texture.noise = noise
		texture.color_ramp = ramp
		texture.generate_mipmaps = true
		detail_textures.plaster = texture
	material.albedo_texture = detail_textures.plaster
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE*1.5
	material.normal_enabled = true
	material.normal_texture = bump_texture()
	material.normal_scale = .12
