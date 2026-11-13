class_name VisualTour
extends RefCounted
## Developer screenshot tour for art work. Not part of the smoke checks.
##   godot --path . -- --visual-tour                 (all shots)
##   godot --path . -- --visual-tour=rooms,shop      (only some groups)
## Shots land in user://smoke_test/tour-*.png

## Keeps the RefCounted tour alive while its coroutine awaits.
static var running: VisualTour
var home: Home
var groups: PackedStringArray = []

func _init(target: Home) -> void:
	home = target
	running = self
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--visual-tour="):
			groups = arg.trim_prefix("--visual-tour=").split(",")
		if arg=="--no-baked":
			# Shows the code-built clips, to check pose changes before re-baking.
			FPViewModel.use_baked = false

func wants(group: String) -> bool:
	return groups.is_empty() or group in groups

func run() -> void:
	SavePaths.clear_test_files()
	TranslationServer.set_locale("ru")
	var game := home.night_game
	if game.intro.active:
		game.intro.finish()
	await home.get_tree().create_timer(1.0).timeout
	if wants("rooms"):
		for id in home.data.rooms.keys():
			home.go_room(id)
			await snap("room-%s" % id)
	if wants("export"):
		export_sources()
	if "preview" in groups:
		# Opens the editable preview scenes the way the editor would and renders them.
		for action_name in ["beer","energy","light"]:
			var scene := (load("res://assets/fp/preview/%s.tscn" % action_name) as PackedScene).instantiate() as Node3D
			home.add_child(scene)
			scene.global_transform = home.player.camera.global_transform
			(scene.get_node("PlayerCamera") as Camera3D).make_current()
			var actions := scene.get_node("Actions") as AnimationPlayer
			actions.play(action_name)
			actions.seek(1.2,true,true)
			actions.pause()
			await snap("preview-"+action_name)
			scene.queue_free()
		home.player.camera.make_current()
	if "bake" in groups:
		await bake_actions()
	if wants("sounds"):
		# Synthesized sounds only: the recorded ones are already files in assets/sfx.
		for sound_name in FPSounds.LENGTHS:
			if not FPSounds.RECORDED.has(sound_name):
				FPSounds.get_sound(sound_name).save_to_wav(SavePaths.file("sound-%s.wav" % sound_name))
	if wants("plan"):
		for ceiling in home.scene_finish.ceilings.values():
			ceiling.hide()
		var top := Camera3D.new()
		top.projection = Camera3D.PROJECTION_ORTHOGONAL
		top.size = 16.0
		top.near = 17.8
		home.add_child(top)
		var middle := Vector3.ZERO
		for id in home.data.rooms.keys():
			middle += home.rooms.room_point(id,Vector3.ZERO)
		middle /= home.data.rooms.size()
		top.global_position = middle+Vector3.UP*20
		top.rotation_degrees = Vector3(-90,0,0)
		top.make_current()
		await snap("plan")
		top.queue_free()
		home.player.camera.make_current()
		for ceiling in home.scene_finish.ceilings.values():
			ceiling.show()
	if wants("grip"):
		# Close-up orbit around the held bottle to catch fingers clipping through it.
		home.go_room("living")
		await home.get_tree().create_timer(.3).timeout
		home.shop.beer = 5
		var rig := home.player.view_model
		for t in [.4,1.0,1.7]:
			home.player.intoxication = 0.0
			home.party.consume(true)
			await home.get_tree().create_timer(t).timeout
			rig.anim.pause()
			var bottle := home.party.consumables.held_item as Node3D
			var center := bottle.global_transform*Vector3(0,.085,0)
			var close := Camera3D.new()
			close.cull_mask = 0xFFFFF
			close.fov = 40
			close.near = .01
			home.add_child(close)
			close.make_current()
			var basis := rig.global_basis
			for angle in [0,90,180,270]:
				var offset := basis*(Vector3(0,.05,.28).rotated(Vector3.UP,deg_to_rad(angle)))
				close.global_position = center+offset
				close.look_at(center,basis.y)
				await snap("grip-%04d-%03d" % [int(t*1000),angle])
			close.queue_free()
			home.player.camera.make_current()
			rig.anim.play()
			while rig.anim.is_playing():
				await home.get_tree().process_frame
			await home.get_tree().create_timer(.3).timeout
	if wants("street"):
		var door: Vector3 = home.night_world.door_center
		home.player.move_to(door+Vector3(-3.5,1.64,0),door+Vector3(-12,1.2,0))
		await snap("street-out")
		home.player.move_to(door+Vector3(-10,1.64,6),door+Vector3(-20,1.4,-2))
		await snap("street-club")
	if wants("shop"):
		var shop := home.shop
		home.player.move_to(shop.to_global(Vector3(0,1.64,5.5)),shop.to_global(Vector3(0,1.3,0)))
		await snap("shop-front")
		home.player.global_position = shop.to_global(Vector3(0,0,2))
		home.player.move_to(shop.to_global(Vector3(0,1.64,2.2)),shop.to_global(Vector3(0,1.3,0)))
		shop.open()
		await snap("shop-panel")
		if shop.panel.has_method("select"):
			shop.panel.select(1)
			await snap("shop-panel-beer")
		shop.close()
	if wants("club"):
		var club := home.club
		home.player.move_to(club.to_global(Vector3(0,1.64,3)),club.to_global(Vector3(0,1.4,-4)))
		await snap("club")
	if wants("actions"):
		home.go_room("living")
		await home.get_tree().create_timer(.3).timeout
		home.shop.beer = 5
		home.shop.energy = 3
		home.party.cigarettes = 5
		home.player.paused = false
		await action_frames("beer", func(): home.party.consume(true), [.15,.35,.6,.9,1.3,1.8])
		await action_frames("smoke", func(): home.party.consume(false), [.2,.5,.9,1.3,1.8,2.4,3.2])
		await action_frames("puff", func(): home.party.consume(false), [.3,.7,1.1,1.6])
		await action_frames("stub", func(): home.party.extinguish(), [.5,.86,.98,1.1,1.4])
		home.player.energy_boost = 0.0
		await action_frames("energy", func(): home.shop.drink_energy(), [.4,.8,1.4,2.0,2.5,3.0])
		home.player.intoxication = .9
		home.player.nausea_cooldown = 0
		await action_frames("vomit", func(): home.player.vomit(), [.5,1.0,1.95,2.15,2.5,3.6,4.6])
	if "perf" in groups:
		await measure_performance()
	if "body" in groups:
		# The player's own body seen from the eyes: looking down, walking, and during actions.
		home.go_room("living")
		await home.get_tree().create_timer(.3).timeout
		home.shop.beer = 5
		home.shop.energy = 3
		home.party.cigarettes = 5
		home.player.paused = false
		var actor := home.player
		actor.pitch = -1.15
		await snap("body-idle-down")
		actor.pitch = -.7
		await snap("body-idle-low")
		Input.action_press("move_forward")
		await home.get_tree().create_timer(.5).timeout
		actor.pitch = -1.15
		await snap("body-walk-down")
		actor.pitch = -.45
		await snap("body-walk-low")
		Input.action_release("move_forward")
		await home.get_tree().create_timer(.6).timeout
		home.go_room("living")
		await home.get_tree().create_timer(.3).timeout
		actor.pitch = -1.1
		for spec in [["beer",func(): home.party.consume(true),[.3,1.0,1.8,2.7]],
				["energy",func(): home.shop.drink_energy(),[.5,1.6,2.5,3.0]],
				["smoke",func(): home.party.consume(false),[.5,1.2,2.0,3.2]]]:
			actor.intoxication = 0.0
			actor.energy_boost = 0.0
			spec[1].call()
			var elapsed := 0.0
			for t in spec[2]:
				await home.get_tree().create_timer(t-elapsed).timeout
				elapsed = t
				await grab("body-%s-%04d" % [spec[0],int(t*1000)])
			while home.party.hands_busy():
				await home.get_tree().process_frame
			await home.get_tree().create_timer(.3).timeout
		home.party.extinguish()
		await home.get_tree().create_timer(2.2).timeout
		# In front of the bathroom mirror: the reflection must drink with the right hand.
		var mirror: Node3D = home.scene_finish.mirror
		if is_instance_valid(mirror):
			var normal := mirror.global_basis.z.normalized()
			var eye := mirror.global_position+normal*.75
			eye.y = mirror.global_position.y+.05
			actor.move_to(eye,mirror.global_position)
			await home.get_tree().create_timer(.5).timeout
			for spec in [["beer",func(): home.party.consume(true),[.4,.7,1.6,2.6]],
					["energy",func(): home.shop.drink_energy(),[.75,1.6,2.45,3.0]],
					["light",func(): home.party.consume(false),[.55,1.45,2.7]]]:
				actor.intoxication = 0.0
				actor.energy_boost = 0.0
				actor.move_to(eye,mirror.global_position)
				spec[1].call()
				var elapsed := 0.0
				for t in spec[2]:
					await home.get_tree().create_timer(t-elapsed).timeout
					elapsed = t
					await grab("body-mirror-%s-%04d" % [spec[0],int(t*1000)])
				while home.party.hands_busy():
					await home.get_tree().process_frame
				await home.get_tree().create_timer(.3).timeout
			home.party.extinguish()
			await home.get_tree().create_timer(2.2).timeout
	if wants("pose"):
		home.go_room("living")
		await home.get_tree().create_timer(.3).timeout
		home.shop.beer = 5
		home.shop.energy = 3
		home.party.cigarettes = 5
		var rig := home.player.view_model
		for spec in pose_specs():
			var times: Array = spec[2]
			for t in times:
				home.player.energy_boost = 0.0
				# Keep the drunk sway and nausea out of the pose shots.
				home.player.intoxication = 0.0
				spec[1].call()
				await home.get_tree().create_timer(t).timeout
				rig.anim.pause()
				await snap("pose-%s-%04d" % [spec[0],int(t*1000)])
				if rig.anim.assigned_animation!="":
					rig.anim.play()
				while rig.anim.is_playing():
					await home.get_tree().process_frame
				await home.get_tree().create_timer(.3).timeout
				if spec[0]=="light" and t<4.0:
					home.party.consumables.drop_cigarette()
		if wants_pose("puff"):
			home.party.consume(false)
			while rig.anim.is_playing():
				await home.get_tree().process_frame
			for t in [.45,1.0,1.75,2.0]:
				home.party.consume(false)
				await home.get_tree().create_timer(t).timeout
				rig.anim.pause()
				await snap("pose-puff-%04d" % int(t*1000))
				if rig.anim.assigned_animation!="":
					rig.anim.play()
				while rig.anim.is_playing():
					await home.get_tree().process_frame
			home.party.extinguish()
			await home.get_tree().create_timer(.75).timeout
			rig.anim.pause()
			await snap("pose-stub-0750")
			rig.anim.play()
			await home.get_tree().create_timer(2.0).timeout
	print("RADION_TOUR ready")
	home.quit_game()

func wants_pose(pose_name: String) -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pose="):
			return arg.trim_prefix("--pose=")==pose_name
	return true

## [name, start action, [times to freeze]]; filtered by --pose=name
func pose_specs() -> Array:
	var all := [
		["beer",func(): home.party.consume(true),[.38,.98,1.65]],
		["energy",func(): home.shop.drink_energy(),[.38,.75,1.6,2.55]],
		["light",func(): home.party.consume(false),[.55,1.0,1.7,4.15]],
	]
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pose="):
			only = arg.trim_prefix("--pose=")
	return all.filter(func(entry): return only=="" or entry[0]==only)

func action_frames(prefix: String, start: Callable, times: Array) -> void:
	start.call()
	var elapsed := 0.0
	for index in times.size():
		var wait: float = times[index]-elapsed
		await home.get_tree().create_timer(wait).timeout
		elapsed = times[index]
		await RenderingServer.frame_post_draw
		home.get_viewport().get_texture().get_image().save_png(SavePaths.file("tour-%s-%d.png" % [prefix,index]))
	# The next action needs free hands, however long this one runs.
	while home.party.hands_busy():
		await home.get_tree().process_frame
	await home.get_tree().create_timer(.5).timeout

## Frame cost per room and per effect, uncapped (no vsync):
##   godot --path . -- --visual-tour=perf
## Prints "PERF ..." lines: GPU/CPU render ms, process/physics ms, draw calls.
func measure_performance() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var viewport := home.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport,true)
	home.player.paused = true
	var shadowed := 0
	var lights := 0
	for light in home.find_children("*","Light3D",true,false):
		if (light as Light3D).is_visible_in_tree():
			lights += 1
			if (light as Light3D).shadow_enabled:
				shadowed += 1
	print("PERF lights=%d shadowed=%d nodes=%d occluders=%d" % [lights,shadowed,Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		home.get_node(HouseOcclusion.NAME).get_child_count() if home.has_node(HouseOcclusion.NAME) else 0])
	for id in home.data.rooms.keys():
		home.go_room(id)
		await sample_frames("room-%s" % id,viewport)
		var casting := VisualQuality.shadow_lamps.filter(func(light): return light.shadow_enabled and light.shadow_opacity>.99).size()
		print("PERF   %s shadow lamps on: %d" % [id,casting])
		visible_breakdown(id)
	home.go_room("living")
	await sample_frames("living-baseline",viewport)
	for quality in [1,0,2]:
		VisualQuality.set_level(quality)
		VisualQuality.update_shadow_budget(home.player.camera)
		await sample_frames("living-graphics-%s" % VisualQuality.LEVEL_NAMES[quality],viewport)
	home.go_room("hall")
	for quality in [1,0,2]:
		VisualQuality.set_level(quality)
		VisualQuality.update_shadow_budget(home.player.camera)
		await sample_frames("hall-graphics-%s" % VisualQuality.LEVEL_NAMES[quality],viewport)
	home.go_room("living")
	var env: Environment = home.get_viewport().world_3d.environment
	if env==null:
		for node in home.find_children("*","WorldEnvironment",true,false):
			env = (node as WorldEnvironment).environment
	for effect in ["ssao_enabled","ssil_enabled","ssr_enabled","volumetric_fog_enabled","glow_enabled"]:
		env.set(effect,false)
		await sample_frames("living-no-"+effect,viewport)
		env.set(effect,true)
	var lamps := VisualQuality.shadow_lamps.duplicate()
	var lit := lamps.filter(func(light): return light.shadow_enabled).size()
	VisualQuality.shadow_lamps.clear()
	for light in lamps:
		light.shadow_enabled = false
	await sample_frames("living-no-lamp-shadows(%d)" % lit,viewport)
	VisualQuality.shadow_lamps.assign(lamps)
	VisualQuality.update_shadow_budget(home.player.camera)
	# Script cost of the outside world while the player is in the house.
	var paused_nodes := []
	for node in home.night_world.street.get_children()+[home.party,home.night_game]:
		if node.is_processing() or node.is_physics_processing():
			paused_nodes.append([node,node.is_processing(),node.is_physics_processing()])
			node.set_process(false)
			node.set_physics_process(false)
	await sample_frames("living-no-world-logic",viewport)
	for entry in paused_nodes:
		entry[0].set_process(entry[1])
		entry[0].set_physics_process(entry[2])
	await sample_frames("living-baseline-again",viewport)
	# Cheaper variants of the same look, one at a time.
	var sizes := {}
	for light in lamps:
		sizes[light] = light.light_size
		light.light_size = 0.0
	await sample_frames("living-shadows-no-pcss",viewport)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	await sample_frames("living-shadows-no-pcss-soft-low",viewport)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	for light in lamps:
		light.light_size = sizes[light]
	var root_viewport := home.get_viewport()
	var msaa := root_viewport.msaa_3d
	root_viewport.msaa_3d = Viewport.MSAA_DISABLED
	await sample_frames("living-no-msaa",viewport)
	root_viewport.msaa_3d = msaa
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_LOW,true,.5,2,50,300)
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_LOW,true,.5,4,50,300)
	await sample_frames("living-ssao-ssil-low",viewport)
	RenderingServer.environment_set_volumetric_fog_volume_size(48,32)
	await sample_frames("living-+fog-small",viewport)
	home.party.toggle()
	await home.get_tree().create_timer(4.0).timeout
	await sample_frames("living-party",viewport)
	home.party.stop()

## What the camera can see, grouped by the top two node levels under Home:
## surfaces (≈ draw calls before instancing) and triangles.
func visible_breakdown(label: String) -> void:
	var camera := home.player.camera
	var groups := {}
	for node in home.find_children("*","MeshInstance3D",true,false):
		var model := node as MeshInstance3D
		if model.mesh==null or not model.is_visible_in_tree() or (model.layers & camera.cull_mask)==0:
			continue
		var box := model.global_transform*model.get_aabb()
		var seen := camera.is_position_in_frustum(box.get_center())
		for corner in range(8):
			seen = seen or camera.is_position_in_frustum(box.get_endpoint(corner))
		if not seen:
			continue
		var path := str(home.get_path_to(model)).split("/")
		var key := "/".join(path.slice(0,mini(2,path.size()-1)))
		var entry: Array = groups.get(key,[0,0,0])
		entry[0] += 1
		entry[1] += model.mesh.get_surface_count()
		var triangles := 0
		for surface in model.mesh.get_surface_count():
			var arrays := model.mesh.surface_get_arrays(surface) if model.mesh is ArrayMesh else []
			if not arrays.is_empty():
				var index = arrays[Mesh.ARRAY_INDEX]
				var vertices = arrays[Mesh.ARRAY_VERTEX]
				triangles += ((index as PackedInt32Array).size() if index!=null and not (index as PackedInt32Array).is_empty() else (vertices as PackedVector3Array).size())/3
		entry[2] += triangles
		groups[key] = entry
	var keys := groups.keys()
	keys.sort_custom(func(a,b): return groups[a][1]>groups[b][1])
	for key in keys.slice(0,2):
		var holder := home.get_node(NodePath(key))
		print("PERF   %s %s is %s script=%s parent=%s" % [label,key,holder.get_class(),holder.get_script().resource_path if holder.get_script() else "",holder.get_parent().get_script().resource_path if holder.get_parent().get_script() else holder.get_parent().name])
	for key in keys.slice(0,8):
		print("PERF   %s %-40s meshes=%5d surfaces=%5d tris=%7dk" % [label,key,groups[key][0],groups[key][1],groups[key][2]/1000])

func sample_frames(label: String, viewport: RID) -> void:
	await home.get_tree().create_timer(1.2).timeout
	var gpu := 0.0
	var cpu := 0.0
	var process := 0.0
	var physics := 0.0
	var draws := 0.0
	var primitives := 0.0
	var count := 0
	var started := Time.get_ticks_usec()
	while Time.get_ticks_usec()-started<1500000:
		await RenderingServer.frame_post_draw
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(viewport)
		process += Performance.get_monitor(Performance.TIME_PROCESS)*1000.0
		physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		count += 1
	var seconds := (Time.get_ticks_usec()-started)/1000000.0
	count = maxi(count,1)
	print("PERF %-34s fps=%5.1f gpu=%6.2fms render_cpu=%5.2fms process=%5.2fms physics=%5.2fms draws=%5d prims=%7dk" % [
		label,count/seconds,gpu/count,cpu/count,process/count,physics/count,int(draws/count),int(primitives/count/1000.0)])

## Saves the next drawn frame right away (snap waits first, for things to settle).
func grab(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	home.get_viewport().get_texture().get_image().save_png(SavePaths.file("tour-%s.png" % shot_name))

func snap(shot_name: String) -> void:
	await home.get_tree().create_timer(.7).timeout
	await RenderingServer.frame_post_draw
	home.get_viewport().get_texture().get_image().save_png(SavePaths.file("tour-%s.png" % shot_name))

## Dumps the procedural hand skeleton (straight rest pose) and the generated
## prop textures for the Blender build script (tools/blender/build_fp_assets.py).
func export_sources() -> void:
	var folder := "res://assets/fp/source/"
	DirAccess.make_dir_recursive_absolute(folder)
	var hand := FPHand.new(false)
	home.add_child(hand)
	for finger in FPHand.FINGERS:
		for joint in hand.joints[finger]:
			(joint as Node3D).rotation = Vector3.ZERO
	hand.set_thumb_swing(0.0)
	for joint in hand.joints.thumb:
		(joint as Node3D).rotation = Vector3.ZERO
	hand.forearm.rotation = Vector3.ZERO
	var bones := []
	bones.append({"name":"hand","parent":"","head":[0,0,0],"tail":[0,0,-.06],"up":[0,1,0]})
	bones.append({"name":"forearm","parent":"hand","head":vec(hand.forearm.position),"tail":vec(hand.forearm.position+Vector3(0,0,.42)),"up":[0,1,0]})
	var chains := {}
	for finger in FPHand.FINGERS:
		chains[finger] = [FPHand.FINGERS[finger][1],FPHand.FINGERS[finger][2]]
	chains["thumb"] = [[.036,.030,.024],.0115]
	for finger in chains:
		var lengths: Array = chains[finger][0]
		for index in range(3):
			var joint := hand.joints[finger][index] as Node3D
			var frame := hand.global_transform.affine_inverse()*joint.global_transform
			var tail: Vector3 = frame*Vector3(0,0,-float(lengths[index]))
			bones.append({
				"name":"%s_%d" % [finger,index+1],
				"parent":"hand" if index==0 else "%s_%d" % [finger,index],
				"head":vec(frame.origin),"tail":vec(tail),"up":vec(frame.basis.y),
				"radius":float(chains[finger][1])*(1.0-index*.09) if finger!="thumb" else .0115-index*.0012,
			})
	var file := FileAccess.open(folder+"hand_rig.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"bones":bones},"\t"))
	file.close()
	hand.queue_free()
	var images := {
		"beer_label":FPProps.beer_label(),"can_wrap":FPProps.can_wrap(),"pack":FPProps.pack_texture(),
		"cork":FPProps.cork_texture(),"paper":FPProps.paper_texture(),"ash":FPProps.ash_texture(),
		"skin":FPProps.skin_texture(),"fabric":FPProps.fabric_texture(),
		"card":FPProps.noise_texture("card",Color("#7a4c22"),Color("#9b6a37"),.3,64),
	}
	for key in images:
		(images[key] as Texture2D).get_image().save_png(folder+key+".png")
	print("RADION_EXPORT done")

func vec(v: Vector3) -> Array:
	return [v.x,v.y,v.z]


## Plays every hand action from code and records it into editable resources:
##   assets/fp/anims/<action>.tres   the clip plus rotation keys for every hand bone
##   assets/fp/preview/<action>.tscn the hands and prop at the start, for the animation editor
## Run: godot --path . -- --visual-tour=bake
func bake_actions() -> void:
	FPViewModel.use_baked = false
	DirAccess.make_dir_recursive_absolute("res://assets/fp/anims")
	DirAccess.make_dir_recursive_absolute("res://assets/fp/preview")
	home.go_room("living")
	await home.get_tree().create_timer(.3).timeout
	home.shop.beer = 5
	home.shop.energy = 3
	home.party.cigarettes = 5
	var actions := [
		["beer",func(): home.party.consume(true)],
		["energy",func():
			home.player.energy_boost = 0.0
			home.shop.drink_energy()],
		["light",func(): home.party.consume(false)],
		["puff",func(): home.party.consume(false)],
		["stub",func(): home.party.extinguish()],
	]
	for action in actions:
		await bake_action(action[0],action[1])
	FPViewModel.use_baked = true
	print("RADION_BAKE done")

func bake_action(action_name: String, start: Callable) -> void:
	var rig := home.player.view_model
	while rig.anim.is_playing():
		await home.get_tree().process_frame
	await home.get_tree().create_timer(.3).timeout
	start.call()
	if rig.anim.assigned_animation!=action_name:
		push_error("bake: %s did not start" % action_name)
		return
	var clip := rig.anim.get_animation(action_name).duplicate(true) as Animation
	var preview := preview_copy(rig,action_name)
	Engine.time_scale = .3
	var keys := {}
	var last := -1.0
	while rig.anim.is_playing() and rig.anim.assigned_animation==action_name:
		var t := rig.anim.current_animation_position
		if last<0.0 or t-last>=1.0/30.0:
			sample_hands(rig,keys,t)
			last = t
		await home.get_tree().process_frame
	Engine.time_scale = 1.0
	sample_hands(rig,keys,clip.length)
	# Pose switches become bone keys, so the code-side pose calls go away.
	for index in range(clip.get_track_count()-1,-1,-1):
		if clip.track_get_type(index)==Animation.TYPE_METHOD and str(clip.track_get_path(index)).ends_with("Hand"):
			clip.remove_track(index)
	for path in keys:
		var entries: Array = keys[path]
		var index: int
		if entries[0][1] is Quaternion:
			index = clip.add_track(Animation.TYPE_ROTATION_3D)
			clip.track_set_path(index,NodePath(path))
			for entry in entries:
				clip.rotation_track_insert_key(index,entry[0],entry[1])
		else:
			index = clip.add_track(Animation.TYPE_VALUE)
			clip.track_set_path(index,NodePath(path))
			clip.value_track_set_update_mode(index,Animation.UPDATE_CONTINUOUS)
			for entry in entries:
				clip.track_insert_key(index,entry[0],entry[1])
		clip.track_set_interpolation_type(index,Animation.INTERPOLATION_LINEAR)
	# Keep only the keys that shape the motion, so a bone can be re-posed by
	# editing a handful of keys instead of one per frame.
	clip.optimize(.002,.6,3)
	clip.resource_name = action_name
	var path := FPViewModel.BAKED_FOLDER+action_name+".tres"
	ResourceSaver.save(clip,path)
	save_preview(preview,action_name,load(path))
	print("baked ",path," tracks=",clip.get_track_count())

func sample_hands(rig: FPViewModel, keys: Dictionary, t: float) -> void:
	for hand in [rig.right,rig.left]:
		var hand_path := str(rig.get_path_to(hand))
		add_key(keys,hand_path+":position",t,hand.position)
		add_key(keys,hand_path+":rotation",t,hand.rotation)
		var skeleton: Skeleton3D = hand.skeleton
		var skeleton_path := str(rig.get_path_to(skeleton))
		for bone in skeleton.get_bone_count():
			add_key(keys,skeleton_path+":"+skeleton.get_bone_name(bone),t,skeleton.get_bone_pose_rotation(bone))

func add_key(keys: Dictionary, path: String, t: float, value) -> void:
	if not keys.has(path):
		keys[path] = []
	keys[path].append([t,value])

## A script-free copy of the rig (hands, props) with a camera, a light and an
## AnimationPlayer holding the baked clip: open it to edit the action visually.
func preview_copy(rig: FPViewModel, action_name: String) -> Node3D:
	var copy := rig.duplicate(Node.DUPLICATE_USE_INSTANTIATION) as Node3D
	copy.name = "Preview_"+action_name
	copy.transform = Transform3D.IDENTITY
	(copy.get_node("Sway") as Node3D).transform = Transform3D.IDENTITY
	# Only the skinned arm matters here; the code-side joint drivers would just confuse.
	for hand_name in ["Sway/Right/RightHand","Sway/Left/LeftHand"]:
		for child in copy.get_node(hand_name).get_children():
			if child.name!="Arm":
				child.get_parent().remove_child(child)
				child.free()
	for node in copy.find_children("*","AnimationPlayer",true,false):
		node.get_parent().remove_child(node)
		node.free()
	var camera := Camera3D.new()
	camera.name = "PlayerCamera"
	camera.fov = home.player.camera.fov
	camera.near = .01
	copy.add_child(camera)
	var light := DirectionalLight3D.new()
	light.name = "Light"
	light.rotation = Vector3(-.7,.5,0)
	copy.add_child(light)
	return copy

func save_preview(copy: Node3D, action_name: String, clip: Animation) -> void:
	var player := AnimationPlayer.new()
	player.name = "Actions"
	copy.add_child(player)
	var library := AnimationLibrary.new()
	library.add_animation(action_name,clip)
	player.add_animation_library("",library)
	player.assigned_animation = action_name
	set_owners(copy,copy)
	var path := "res://assets/fp/preview/%s.tscn" % action_name
	var packed := PackedScene.new()
	packed.pack(copy)
	ResourceSaver.save(packed,path)
	copy.free()

func set_owners(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		if child.scene_file_path=="":
			set_owners(child,root)
