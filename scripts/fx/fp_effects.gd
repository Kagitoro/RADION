class_name FPEffects
extends RefCounted
## Particle effects for the hand actions: smoke, sparks, spray, vomit splashes.

static var soft_texture: Texture2D

## Soft round puff used by every smoke particle.
static func puff_texture() -> Texture2D:
	if soft_texture!=null:
		return soft_texture
	var image := Image.create(64,64,false,Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = .09
	for y in range(64):
		for x in range(64):
			var d := Vector2(x-31.5,y-31.5).length()/31.5
			var wisp := .75+.25*noise.get_noise_2d(x,y)
			var alpha := pow(clampf(1.0-d,0,1),1.8)*wisp
			image.set_pixel(x,y,Color(1,1,1,alpha))
	image.generate_mipmaps()
	soft_texture = ImageTexture.create_from_image(image)
	return soft_texture

static func smoke_material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.vertex_color_use_as_albedo = true
	material.albedo_color = tint
	material.albedo_texture = puff_texture()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.proximity_fade_enabled = true
	material.proximity_fade_distance = .15
	return material

static func fade_ramp(peak: float, points: Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(points.map(func(p): return p[0]))
	gradient.colors = PackedColorArray(points.map(func(p): return Color(p[1].r,p[1].g,p[1].b,p[1].a*peak)))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture

static func grow_curve(start: float, end: float) -> CurveTexture:
	var curve := Curve.new()
	curve.max_value = maxf(start,end)
	curve.add_point(Vector2(0,start),0,0)
	curve.add_point(Vector2(.35,lerpf(start,end,.7)))
	curve.add_point(Vector2(1,end))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture

static func quad(size: float) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size,size)
	return mesh

## A breath of smoke blown forward from the mouth; frees itself.
static func exhale(world: Node3D, origin: Vector3, forward: Vector3, strength := 1.0) -> void:
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = .0
	particles.amount = int(30*strength)
	particles.lifetime = 3.2
	particles.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.direction = forward.normalized()
	process.spread = 16.0
	process.initial_velocity_min = .45*strength
	process.initial_velocity_max = .85*strength
	process.gravity = Vector3(0,.10,0)
	process.damping_min = .55
	process.damping_max = .9
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = .012
	process.scale_min = .8
	process.scale_max = 1.3
	process.scale_curve = grow_curve(.25,1.0)
	process.angle_min = -180
	process.angle_max = 180
	process.angular_velocity_min = -25
	process.angular_velocity_max = 25
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 1.2
	process.turbulence_noise_scale = 2.4
	process.turbulence_influence_min = .04
	process.turbulence_influence_max = .12
	process.color_ramp = fade_ramp(1.0,[[0.0,Color(.86,.88,.9,0)],[.1,Color(.86,.88,.9,.2)],[.5,Color(.8,.82,.85,.08)],[1.0,Color(.8,.82,.85,0)]])
	particles.process_material = process
	particles.draw_pass_1 = quad(.13)
	particles.material_override = smoke_material(Color.WHITE)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-3,-3,-3),Vector3(6,6,6))
	world.add_child(particles)
	particles.global_position = origin
	particles.emitting = true
	# Emit over ~0.9 s like a real exhale, then let the cloud drift away.
	particles.amount_ratio = 1.0
	particles.speed_scale = 1.0
	particles.preprocess = 0.0
	particles.get_tree().create_timer(4.0).timeout.connect(particles.queue_free)

## Thin rising wisp from a burning tip; caller keeps and frees it.
static func ember_wisp() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = 26
	particles.lifetime = 2.6
	particles.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 6.0
	process.initial_velocity_min = .05
	process.initial_velocity_max = .09
	process.gravity = Vector3(0,.07,0)
	process.scale_curve = grow_curve(.15,1.0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = .7
	process.turbulence_noise_scale = 1.6
	process.turbulence_influence_min = .03
	process.turbulence_influence_max = .07
	process.color_ramp = fade_ramp(1.0,[[0.0,Color(.8,.83,.88,0)],[.15,Color(.8,.83,.88,.10)],[1.0,Color(.75,.78,.82,0)]])
	process.angle_min = -180
	process.angle_max = 180
	particles.process_material = process
	particles.draw_pass_1 = quad(.03)
	particles.material_override = smoke_material(Color.WHITE)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-2,-1,-2),Vector3(4,4,4))
	return particles

## Hot sparks from a flint wheel or a flicked butt. Frees itself.
static func sparks(world: Node3D, origin: Vector3, direction: Vector3, count := 14, speed := .7) -> void:
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = .9
	particles.amount = count
	particles.lifetime = .5
	particles.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.direction = direction
	process.spread = 40.0
	process.initial_velocity_min = speed*.5
	process.initial_velocity_max = speed
	process.gravity = Vector3(0,-3.0,0)
	process.scale_min = .5
	process.scale_max = 1.0
	process.color_ramp = fade_ramp(1.0,[[0.0,Color(1,.9,.5,1)],[.5,Color(1,.5,.15,1)],[1.0,Color(.6,.15,.0,0)]])
	particles.process_material = process
	var dot := QuadMesh.new()
	dot.size = Vector2(.004,.004)
	particles.draw_pass_1 = dot
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.vertex_color_use_as_albedo = true
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	glow.albedo_texture = puff_texture()
	particles.material_override = glow
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(particles)
	particles.global_position = origin
	particles.emitting = true
	particles.get_tree().create_timer(1.2).timeout.connect(particles.queue_free)

## Fine fizz spray from a freshly opened can or bottle. Frees itself.
static func fizz(world: Node3D, origin: Vector3, tint := Color(.95,.97,1.0)) -> void:
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = .75
	particles.amount = 24
	particles.lifetime = .55
	particles.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 35.0
	process.initial_velocity_min = .25
	process.initial_velocity_max = .6
	process.gravity = Vector3(0,-2.0,0)
	process.scale_min = .4
	process.scale_max = 1.0
	process.color_ramp = fade_ramp(1.0,[[0.0,Color(tint.r,tint.g,tint.b,.8)],[1.0,Color(tint.r,tint.g,tint.b,0)]])
	particles.process_material = process
	particles.draw_pass_1 = quad(.006)
	particles.material_override = smoke_material(Color.WHITE)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(particles)
	particles.global_position = origin
	particles.emitting = true
	particles.get_tree().create_timer(1.0).timeout.connect(particles.queue_free)

## Chunky wet splash where vomit hits the floor. Frees itself.
static func splatter(world: Node3D, origin: Vector3) -> void:
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = .6
	particles.amount = 34
	particles.lifetime = .7
	particles.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 75.0
	process.initial_velocity_min = .5
	process.initial_velocity_max = 1.3
	process.gravity = Vector3(0,-7.0,0)
	process.scale_min = .5
	process.scale_max = 1.4
	process.color_ramp = fade_ramp(1.0,[[0.0,Color("#8a7a46")],[.6,Color("#6f5d33")],[1.0,Color(.4,.33,.18,0)]])
	process.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	process.collision_bounce = .05
	process.collision_friction = 1.0
	particles.process_material = process
	var drop := SphereMesh.new()
	drop.radius = .006
	drop.height = .009
	drop.radial_segments = 6
	drop.rings = 3
	particles.draw_pass_1 = drop
	var wet := StandardMaterial3D.new()
	wet.vertex_color_use_as_albedo = true
	wet.roughness = .15
	wet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particles.material_override = wet
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(particles)
	particles.global_position = origin+Vector3.UP*.02
	particles.emitting = true
	particles.get_tree().create_timer(1.6).timeout.connect(particles.queue_free)
