class_name PartyEvents
extends Node3D

var home: Home
var lights: Array[OmniLight3D] = []
var fighters: Array[Node3D] = []
var fight_time := 0.0
var next_hit := 0.0
var hit_index := 0
var event_wait := 28.0
var sounds := AudioStreamPlayer3D.new()
var puddles: Array[Node3D] = []
var vomit_count := 0
var room_lights: Array[Dictionary] = []
var environments: Array[Dictionary] = []
var beams: Array[MeshInstance3D] = []
var grunt := AudioStreamPlayer3D.new()
var retching := AudioStreamPlayer3D.new()
var retch_variants: Array[AudioStreamMP3] = []
var impact_target: Node3D
var impact_attacker: Node3D
var exchange_time := 0.0
var exchange_length := .60
var impact_done := false
var fight_volume := PhysicsShapeQueryParameters3D.new()
var hit_counts := {}
var fight_ending := 0.0
var streams: Array[Dictionary] = []
const SHOUTS := ["Ты охуел? Руки убрал!","Какого хуя ты толкаешься?!","Пошёл нахуй со своими понтами!","Не трогай меня, блядь!","Сейчас получишь, сука!"]

func _init(game_home: Home) -> void:
	home = game_home

func setup() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = .18
	capsule.height = 1.56
	fight_volume.shape = capsule
	fight_volume.collision_mask = 1
	add_child(sounds)
	add_child(grunt)
	grunt.volume_db = -18
	grunt.max_distance = 9
	grunt.stream = load("res://assets/sfx/hurt.mp3")
	add_child(retching)
	retching.volume_db = -16
	retching.max_distance = 7
	for filename in ["gagging","retching"]:
		retch_variants.append(load("res://assets/sfx/"+filename+".mp3"))
	for light in home.scene_lighting.get_children():
		if light is Light3D:
			room_lights.append({"node":light,"energy":light.light_energy})
	for world in home.find_children("*","WorldEnvironment",true,false):
		var environment: Environment = world.environment
		environments.append({"node":environment,"energy":environment.ambient_light_energy})
	sounds.volume_db = -21
	sounds.max_distance = 9
	var data := PackedByteArray()
	data.resize(3600)
	var random := RandomNumberGenerator.new()
	random.seed = 291
	for index in range(1800):
		var t := float(index)/24000.0
		var sample := (sin(TAU*92*t)*.38+random.randf_range(-.14,.14))*exp(-t*52)
		data.encode_s16(index*2,roundi(sample*32767))
	var sound := AudioStreamWAV.new()
	sound.mix_rate = 24000
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.data = data
	sounds.stream = sound
	for row in home.records.values():
		if str(row.kind)!="floor" or str(row.id)==home.night_world.floor_id or bool(row.deleted) or lights.size()>=6:
			continue
		var area: Rect2 = home.rooms.room_world_bounds(row)
		if area.get_area()<4.0:
			continue
		if lights.any(func(other): return Vector2(other.position.x,other.position.z).distance_to(area.get_center())<1.5):
			continue
		var light := OmniLight3D.new()
		light.position = Vector3(area.get_center().x,home.rooms.floor_surface(row)+2.15,area.get_center().y)
		light.omni_range = clampf(maxf(area.size.x,area.size.y)*.8,2.4,5.2)
		light.omni_attenuation = 1.6
		light.light_energy = 0
		light.shadow_enabled = false
		add_child(light)
		lights.append(light)
		var beam := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = .035
		cone.bottom_radius = .80
		cone.height = 2.1
		cone.radial_segments = 16
		beam.mesh = cone
		beam.position = light.position-Vector3.UP*1.0
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow.cull_mode = BaseMaterial3D.CULL_DISABLED
		glow.albedo_color = Color(1,1,1,.025)
		beam.material_override = glow
		beam.hide()
		add_child(beam)
		beams.append(beam)

func _process(delta: float) -> void:
	if home.modal and not home.night_game.dj.is_open():
		return
	var party = home.party
	update_streams(delta)
	for entry in room_lights:
		entry.node.light_energy = lerpf(entry.node.light_energy,entry.energy*(.055 if party.active else 1.0),minf(1,delta*3))
	for entry in environments:
		entry.node.ambient_light_energy = lerpf(entry.node.ambient_light_energy,.025 if party.active else entry.energy,minf(1,delta*3))
	for index in range(lights.size()):
		var light := lights[index]
		var phase := fposmod(party.beat+index*.15,1.0)
		var pulse := pow(maxf(0,cos(phase*TAU)),10)
		var dj = home.night_game.dj
		if is_instance_valid(dj) and dj.manual:
			pulse = (1.0-dj.bass_phase)*dj.bass
		light.light_energy = (.04+pulse*2.3) if party.active else 0.0
		light.light_color = Color.from_hsv(fposmod(floor(party.track_time*.55)*.16+index*.22,.999),.85,1.0)
		var beam := beams[index]
		beam.visible = party.active
		beam.rotation = Vector3(.16*sin(party.track_time*.72+index),0,.14*cos(party.track_time*.5+index))
		var glow := beam.material_override as StandardMaterial3D
		glow.albedo_color = Color(light.light_color,.012+pulse*.055)
	if not party.active:
		if not fighters.is_empty():
			end_fight(false)
		return
	if not fighters.is_empty():
		update_fight(delta)
		return
	event_wait -= delta
	if event_wait<=0:
		event_wait = 3.0
		start_fight()

func start_fight(preferred: Node3D = null) -> bool:
	if not fighters.is_empty() or not home.party.active:
		return false
	for first in home.party.guests:
		if first.leaving or not is_instance_valid(first.imported_model) or (preferred!=null and first!=preferred) or (is_instance_valid(first.partner) and first.partner!=home.player):
			continue
		for second in home.party.guests:
			if second==first or second.leaving or not is_instance_valid(second.imported_model) or is_instance_valid(second.partner):
				continue
			var distance: float = first.global_position.distance_to(second.global_position)
			if distance<.56 or distance>(2.15 if preferred!=null else 1.35):
				continue
			var query := PhysicsRayQueryParameters3D.create(first.global_position+Vector3.UP,second.global_position+Vector3.UP,1)
			if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
				continue
			if home.night_game.guest==first:
				home.night_game.close_talk(false)
			fighters.assign([first,second])
			fight_time = 16.0
			fight_ending = 0.0
			hit_counts.clear()
			next_hit = .85
			hit_index = 0
			for person in fighters:
				person.follow(PackedVector3Array())
				person.fighting = true
				person.imported_model.combat = true
				person.imported_model.combat_swing = 0.0
				person.imported_model.combat_guard = 0.0
				person.imported_model.combat_recoil = 0.0
				person.dancing = false
				person.speech.text = tr(SHOUTS[0] if person==first else SHOUTS[3])
				person.speech.show()
			GameEvents.notify(tr("Гости сцепились! Подойди и нажми E, чтобы разнять."))
			return true
	return false

func update_fight(delta: float) -> void:
	if fighters.any(func(person): return not is_instance_valid(person) or person.leaving):
		end_fight(false)
		return
	fight_time -= delta
	next_hit -= delta
	if fight_ending>0:
		fight_ending -= delta
		if fight_ending<=0:
			end_fight(false)
		return
	for index in range(2):
		var person := fighters[index] as PartyGuest
		var other := fighters[1-index] as PartyGuest
		var rig := person.imported_model as GuestModel
		rig.combat_clock += delta
		rig.combat_recoil = move_toward(rig.combat_recoil,0,delta*3.7)
		var direction := other.global_position-person.global_position
		direction.y = 0
		person.rotation.y = lerp_angle(person.rotation.y,atan2(-direction.x,-direction.z),minf(1,delta*10))
		var axis := direction.normalized()
		var side := axis.cross(Vector3.UP)
		var defending := person == impact_target and hit_index%4 == 2
		rig.combat_guard = move_toward(rig.combat_guard,1.0 if defending else .16,delta*5)
		var gap := direction.length()
		var drift := clampf((gap-.73)*2.7,-.75,1.35)
		var step := axis*drift + side*sin(rig.combat_clock*3.1)*.30
		if person == impact_attacker:
			step = axis*clampf((gap-.68)*3.9,-.5,1.65)
		elif rig.combat_recoil>.05 or defending:
			step = -axis*(.58*rig.combat_recoil)+side*(.56 if defending else 0.0)
		if gap<.61:
			step -= axis*.7
		fight_step(person,step*delta)
	if is_instance_valid(impact_attacker):
		var rig := impact_attacker.imported_model as GuestModel
		var defender := impact_target.imported_model as GuestModel
		exchange_time += delta
		rig.combat_swing = clampf(exchange_time/exchange_length,0,1)
		rig.combat_target = defender.mouth_transform().origin - Vector3.UP*(.36 if rig.combat_style==2 else .02)
		if not impact_done and rig.combat_swing >= .54:
			impact_done = true
			land_punch()
		if rig.combat_swing >= 1.0:
			rig.combat_swing = 0.0
			impact_attacker = null
			impact_target = null
	home.party.bonus = maxf(-18,home.party.bonus-delta*1.1)
	if next_hit<=0 and impact_attacker == null and fight_ending <= 0:
		var attacker_index: int = [0,0,1,1,0,1][hit_index%6]
		impact_attacker = fighters[attacker_index]
		impact_target = fighters[1-attacker_index]
		var rig := impact_attacker.imported_model as GuestModel
		rig.punch_side = hit_index%2
		rig.combat_style = hit_index%3
		exchange_length = [.48,.61,.54][rig.combat_style]
		exchange_time = 0.0
		impact_done = false
		next_hit = exchange_length + (.12 if hit_index%3==0 else .40)
		impact_attacker.speech.text = tr(SHOUTS[hit_index%SHOUTS.size()])
		hit_index += 1
	if fight_time<=0:
		end_fight(false)

func fight_step(person: PartyGuest, step: Vector3) -> void:
	var next := person.global_position+step
	var floor := home.rooms.ground_height(Vector2(next.x,next.z))
	if not is_finite(floor) or absf(floor-next.y)>.24:
		return
	fight_volume.transform.origin = Vector3(next.x,floor+.84,next.z)
	if get_world_3d().direct_space_state.intersect_shape(fight_volume,1).is_empty():
		person.global_position = Vector3(next.x,floor,next.z)

func land_punch() -> void:
	if not is_instance_valid(impact_target) or not is_instance_valid(impact_attacker):
		return
	var rig = impact_attacker.imported_model
	var fist: Vector3 = rig.skeleton.to_global(rig.skeleton.get_bone_global_pose(rig.arms[rig.punch_side].z).origin)
	var face: Vector3 = rig.combat_target
	if fist.distance_to(face)>.36:
		return
	var ray := PhysicsRayQueryParameters3D.create(fist,face,1)
	if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		return
	var blocked: bool = impact_target.imported_model.combat_guard > .56
	impact_target.imported_model.combat_recoil = .32 if blocked else 1.0
	sounds.global_position = face
	sounds.pitch_scale = 0.88+float(hit_index%4)*.08
	sounds.play()
	if blocked:
		return
	grunt.global_position = face
	grunt.pitch_scale = 1.10 if impact_target.female else .91
	grunt.play()
	hit_counts[impact_target] = int(hit_counts.get(impact_target,0))+1
	impact_target.speech.text = tr(SHOUTS[(hit_index+2)%SHOUTS.size()])
	if int(hit_counts[impact_target])>=4:
		impact_target.imported_model.knockdown_time = 2.3
		impact_target.imported_model.combat = false
		impact_target.speech.text = tr("Всё, блядь, хватит!")
		fight_ending = 1.6

func near_fight() -> bool:
	return fighters.any(func(person): return is_instance_valid(person) and person.global_position.distance_squared_to(home.player.global_position)<8.0)

func end_fight(intervened: bool) -> void:
	for person in fighters:
		if not is_instance_valid(person):
			continue
		person.fighting = false
		person.speech.hide()
		person.imported_model.action_time = 0
		person.imported_model.combat = false
		person.rest = 0.0
		if home.party.active and home.party.has_walkable_area():
			home.party.find_destination(person)
	fighters.clear()
	exchange_time = 0.0
	impact_target = null
	impact_attacker = null
	hit_counts.clear()
	fight_ending = 0
	event_wait = 50.0
	if intervened:
		home.party.bonus = minf(20,home.party.bonus+8)
		GameEvents.notify(tr("Разнял гостей. Атмосфера восстанавливается."))

func vomit_burst() -> void:
	vomit_count += 1
	retching.global_position = home.player.mouth_anchor().global_position
	retching.stream = retch_variants[(vomit_count-1)%retch_variants.size()]
	retching.pitch_scale = .94
	retching.play()
	var emitter := CPUParticles3D.new()
	home.player.mouth_anchor().add_child(emitter)
	emitter.amount = 46
	emitter.lifetime = .48
	emitter.direction = Vector3(0,-.35,-1)
	emitter.spread = 7
	emitter.gravity = Vector3(0,-6,0)
	emitter.local_coords = false
	emitter.initial_velocity_min = 1.0
	emitter.initial_velocity_max = 1.9
	emitter.scale_amount_min = .45
	emitter.scale_amount_max = 1.0
	var drop := SphereMesh.new()
	drop.radius = .005
	drop.height = .016
	drop.radial_segments = 6
	drop.rings = 3
	var surface := StandardMaterial3D.new()
	surface.albedo_color = Color("#82764c")
	surface.roughness = .23
	surface.cull_mode = BaseMaterial3D.CULL_DISABLED
	drop.material = surface
	emitter.mesh = drop
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().create_timer(1.85).timeout.connect(func():
		if is_instance_valid(emitter):
			emitter.emitting = false
	)
	get_tree().create_timer(2.45).timeout.connect(func():
		if is_instance_valid(emitter):
			emitter.queue_free()
	)
	var origin: Vector3 = home.player.mouth_anchor().global_position
	var forward: Vector3 = -home.player.global_basis.z
	var space := get_world_3d().direct_space_state
	var exclude := [home.player.get_rid()]
	var center := origin + forward * .56
	var obstruction := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin,center,1,exclude))
	if not obstruction.is_empty():
		center = obstruction.position - forward * .09
	var result := space.intersect_ray(PhysicsRayQueryParameters3D.create(center,center+Vector3.DOWN*3.5,1,exclude))
	if result.is_empty() or result.normal.y < .88:
		return
	var stream := MeshInstance3D.new()
	stream.mesh = ImmediateMesh.new()
	stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stream.material_override = surface
	add_child(stream)
	streams.append({"node":stream,"age":0.0,"impact":result.position+Vector3.UP*.015})
	var impact: Vector3 = result.position
	get_tree().create_timer(.22).timeout.connect(func():
		FPEffects.splatter(self,impact)
		var splash := AudioStreamPlayer3D.new()
		splash.stream = FPSounds.get_sound("splash")
		splash.volume_db = -14
		add_child(splash)
		splash.global_position = impact
		splash.play()
		splash.finished.connect(splash.queue_free)
	)
	var puddle := Node3D.new()
	add_child(puddle)
	puddle.global_position = result.position+Vector3.UP*.009
	var wet := surface.duplicate() as StandardMaterial3D
	wet.vertex_color_use_as_albedo = true
	wet.albedo_color = Color.WHITE
	var stain := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	stain.mesh = mesh
	stain.material_override = wet
	stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puddle.add_child(stain)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	stain_patch(mesh,Vector3.ZERO,.23,.32,Color("#655332"),22)
	for index in range(20):
		var angle := index * 2.39996
		var radius := randf_range(.12,.43)
		var offset := Vector3(cos(angle)*radius,.0015,sin(angle)*radius)
		var test: Vector3 = result.position + offset + Vector3.UP * .09
		var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(test,test+Vector3.DOWN*.15,1,exclude))
		if floor_hit.is_empty() or absf(floor_hit.position.y-result.position.y) > .02:
			continue
		var width := randf_range(.008,.04)
		stain_patch(mesh,offset,width,width*.76,Color("#938056") if index%3==0 else Color("#715a32"),8)
	mesh.surface_end()
	puddle.scale = Vector3(.06,1,.06)
	var spread := puddle.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	spread.tween_interval(.23)
	spread.tween_property(puddle,"scale",Vector3(.72,1,.72),.30)
	spread.tween_property(puddle,"scale",Vector3.ONE,1.05)
	puddles.append(puddle)
	if puddles.size()>6:
		puddles.pop_front().queue_free()

func stain_patch(mesh: ImmediateMesh, center: Vector3, width: float, length: float, tint: Color, sides: int) -> void:
	var edge := PackedVector3Array()
	for index in range(sides):
		var angle := TAU * index / sides
		var ripple := randf_range(.72,1.14)
		edge.append(center + Vector3(cos(angle)*width*ripple,0,sin(angle)*length*ripple))
	for index in range(sides):
		mesh.surface_set_normal(Vector3.UP)
		mesh.surface_set_color(tint.darkened(.25))
		mesh.surface_add_vertex(center + Vector3.UP*.001)
		for vertex in [edge[index],edge[(index+1)%sides]]:
			mesh.surface_set_color(tint)
			mesh.surface_add_vertex(vertex)

func update_streams(delta: float) -> void:
	for index in range(streams.size()-1,-1,-1):
		var entry: Dictionary = streams[index]
		entry.age += delta
		var stream := entry.node as MeshInstance3D
		if entry.age>=1.6:
			stream.queue_free()
			streams.remove_at(index)
			continue
		retching.global_position = home.player.mouth_anchor().global_position
		var pulse := maxf(0,sin(entry.age*11.5)) * (1.0-smoothstep(1.05,1.6,entry.age))
		stream.visible = pulse>.12
		var mesh := stream.mesh as ImmediateMesh
		mesh.clear_surfaces()
		if not stream.visible:
			continue
		var mouth: Transform3D = home.player.mouth_anchor().global_transform
		var impact: Vector3 = entry.impact
		var control := mouth.origin.lerp(impact,.42)+Vector3.UP*.13
		var previous := PackedVector3Array()
		var previous_normals := PackedVector3Array()
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for ring in range(13):
			var t := float(ring)/12.0
			var center := mouth.origin.lerp(control,t).lerp(control.lerp(impact,t),t)
			var direction := (control-mouth.origin).lerp(impact-control,t).normalized()
			var right := direction.cross(Vector3.UP).normalized()
			if right.length_squared()<.01:
				right = Vector3.RIGHT
			var up := right.cross(direction).normalized()
			var radius := (.008+pulse*.006)*(1.0-float(ring)*.035)
			var points := PackedVector3Array()
			var normals := PackedVector3Array()
			for side in range(6):
				var angle := TAU*side/6.0
				var normal := right*cos(angle)+up*sin(angle)
				points.append(to_local(center+normal*radius))
				normals.append(normal)
			if not previous.is_empty():
				for side in range(6):
					var next := (side+1)%6
					for vertex in [side,next,side+6,side+6,next,next+6]:
						mesh.surface_set_normal(previous_normals[vertex] if vertex<6 else normals[vertex-6])
						mesh.surface_add_vertex(previous[vertex] if vertex<6 else points[vertex-6])
			previous = points
			previous_normals = normals
		mesh.surface_end()
