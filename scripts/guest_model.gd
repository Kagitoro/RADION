class_name GuestModel
extends Node3D

var skeleton: Skeleton3D
var animator: AnimationPlayer
var arms: Array[Vector3i] = []
var head_bone := -1
var clip := &""
var ember: Node3D
var psx := false
var mouth_offset := Vector3(.015,.24,.36)
var action := &""
var action_time := 0.0
var dance_seed := 0
var dance_energy := 1.0
var dance_beats := 0
var last_beat := 0.0
var combat := false
var punch_side := 0
var combat_target := Vector3.ZERO
var combat_clock := 0.0
var combat_swing := 0.0
var combat_style := 0
var combat_guard := 0.0
var combat_recoil := 0.0
var street_wear := false
var street_reaction := 0.0
var street_clock := 0.0
var knockdown_time := 0.0
var base_rotations: Array[Quaternion] = []
var base_positions: Array[Vector3] = []
var base_scales: Array[Vector3] = []
var player_body := false
var service_tray: Node3D
var service_time := 0.0

static func load_model(path: String) -> Node3D:
	if not FileAccess.file_exists(path):
		return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path,state)!=OK:
		return null
	return document.generate_scene(state) as Node3D

func setup(model: Node3D, height: float, width: float, skin: Color, shirt: Color, pants: Color) -> bool:
	var skeletons := model.find_children("*","Skeleton3D",true,false)
	var players := model.find_children("*","AnimationPlayer",true,false)
	if skeletons.is_empty() or players.is_empty():
		return false
	skeleton = skeletons[0] as Skeleton3D
	animator = players[0] as AnimationPlayer
	if not animator.has_animation("Idle") or not animator.has_animation("Walk"):
		return false
	for side in [".L",".R"]:
		var arm := Vector3i(skeleton.find_bone("UpperArm"+side),skeleton.find_bone("LowerArm"+side),skeleton.find_bone("Fist"+side))
		if mini(arm.x,mini(arm.y,arm.z))<0:
			return false
		arms.append(arm)
	head_bone = skeleton.find_bone("Head")
	add_child(model)
	model.show()
	model.rotation.y = PI
	model.scale = Vector3(width,height,width*.96)*.52
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for name in [&"Idle",&"Walk"]:
		animator.get_animation(name).loop_mode = Animation.LOOP_LINEAR
	for part in model.find_children("*","MeshInstance3D",true,false):
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in range(part.mesh.get_surface_count()):
			var source := part.get_active_material(surface) as StandardMaterial3D
			if source==null:
				continue
			var tint: Color
			match source.resource_name:
				"Skin": tint = skin
				"Shirt": tint = shirt
				"Pants": tint = pants
				_: continue
			var material := source.duplicate() as StandardMaterial3D
			material.albedo_color = tint
			part.set_surface_override_material(surface,material)
	return true

func setup_psx(assets: Dictionary, female: bool, index: int, height: float, width: float, skin: Color, shirt: Color, pants: Color, security: bool = false) -> bool:
	var body_name := "woman_1" if female else "man_2"
	if not assets.has(body_name):
		return false
	var body := assets[body_name].duplicate() as Node3D
	skeleton = body.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	animator = body.find_children("*","AnimationPlayer",true,false)[0] as AnimationPlayer
	head_bone = skeleton.find_bone("Head")
	for side in ["Left","Right"]:
		arms.append(Vector3i(skeleton.find_bone(side+"Arm"),skeleton.find_bone(side+"ForeArm"),skeleton.find_bone(side+"Hand")))
	psx = true
	dance_seed = index
	mouth_offset = Vector3(.009,.112,.139)*(0.95 if female else 1.0)
	add_child(body)
	body.show()
	body.rotation.y = PI
	body.scale = Vector3(width,height,width*.96)
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for animation in [&"idle",&"walk"]:
		animator.get_animation(animation).loop_mode = Animation.LOOP_LINEAR
	for part in body.find_children("*","MeshInstance3D",true,false):
		paint_psx(part,skin)
	var clothes := [
		["woman_hair_bob" if index%4==1 else "woman_hair_ponytail",Color("#36251f").lightened(float(index%5)*.10)],
		["woman_hoodie" if index%3 else "woman_tank_top",shirt],
		["woman_jeans" if index%4==1 else "woman_skirt",pants],
		["woman_trainers",Color("#c9c0b8")],
	] if female else [
		["man_cap" if index%4==0 else "man_hair_short",Color("#38281d").lightened(float(index%5)*.10)],
		["man_jacket" if index%3 else "man_tee",shirt],
		["man_jeans",pants],
		["man_boots",Color("#111114") if security else Color("#605653")],
	]
	if female and index%5==0:
		clothes.append(["woman_sunglasses",Color("#312836")])
	if not female and index%5==0:
		clothes.append(["man_beard_moustache",Color("#392820")])
	for piece in clothes:
		if not assets.has(piece[0]):
			continue
		var source := assets[piece[0]].find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D
		var mesh := MeshInstance3D.new()
		mesh.mesh = source.mesh
		mesh.skin = source.skin
		skeleton.add_child(mesh)
		mesh.skeleton = NodePath("..")
		paint_psx(mesh,piece[1])
	if security:
		add_security_glasses()
	return true

func add_security_glasses() -> void:
	var mount := BoneAttachment3D.new()
	mount.bone_name = "Head"
	skeleton.add_child(mount)
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color("#13191e")
	lens.metallic = .42
	lens.roughness = .24
	for side in [-1,1]:
		var pane := BoxMesh.new()
		pane.size = Vector3(.090,.049,.016)
		var model := MeshInstance3D.new()
		model.mesh = pane
		model.material_override = lens
		model.position = Vector3(side*.052,.172,.143)
		model.rotation.y = side*.13
		mount.add_child(model)
		var arm := BoxMesh.new()
		arm.size = Vector3(.012,.012,.12)
		var temple := MeshInstance3D.new()
		temple.mesh = arm
		temple.material_override = lens
		temple.position = Vector3(side*.097,.180,.085)
		mount.add_child(temple)
	var bridge := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = Vector3(.028,.010,.017)
	bridge.mesh = shape
	bridge.material_override = lens
	bridge.position = Vector3(0,.18,.145)
	mount.add_child(bridge)

func paint_psx(part: MeshInstance3D, tint: Color) -> void:
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := part.get_active_material(0).duplicate() as BaseMaterial3D
	material.albedo_color = tint
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	part.material_override = material

func pose(delta: float, walking: bool, speed: float, dance: bool, beat: float) -> void:
	for bone in range(base_rotations.size()):
		skeleton.set_bone_pose_rotation(bone,base_rotations[bone])
		skeleton.set_bone_pose_position(bone,base_positions[bone])
		skeleton.set_bone_pose_scale(bone,base_scales[bone])
	var desired := &"Walk" if walking else &"Idle"
	if psx:
		desired = &"walk" if walking else &"idle"
	if action_time>0.0:
		action_time = maxf(0.0,action_time-delta)
		if action_time>0.0:
			desired = action
	knockdown_time = maxf(0,knockdown_time-delta)
	if knockdown_time>0:
		desired = &"death"
	if desired!=clip:
		clip = desired
		animator.play(clip,.18,clampf(speed,.75,1.25) if walking else 1.0)
	animator.advance(delta)
	base_rotations.clear()
	base_positions.clear()
	base_scales.clear()
	for bone in range(skeleton.get_bone_count()):
		base_rotations.append(skeleton.get_bone_pose_rotation(bone))
		base_positions.append(skeleton.get_bone_pose_position(bone))
		base_scales.append(skeleton.get_bone_pose_scale(bone))
	position.x = 0.0
	position.y = 0.0
	if not player_body:
		position.z = 0.0
		rotation = Vector3.ZERO
	if beat<last_beat-.5:
		dance_beats += 1
	last_beat = beat
	if knockdown_time>0:
		pass
	elif psx and combat:
		combat_stance()
	elif psx and dance and not walking and action_time<=0:
		dance_pose(beat)
	elif action_time<=0.0 and not player_body:
		for index in range(arms.size()):
			pocket(arms[index],1.0 if index==0 else -1.0)
	if street_wear:
		street_clock += delta
		rotate_local("Spine",Vector3(.20,.02,.065*sin(street_clock*1.7)))
		rotate_local("Head",Vector3(-.11,.05*sin(street_clock),.07))
		if absf(street_reaction)>.001:
			var level := absf(street_reaction)/.85
			var gesture := Vector3(.31,1.19,.46) if street_reaction>0 else Vector3(.19,1.13,.25)
			point_arm(arms[0],Vector3(.16,.87,.10).lerp(gesture,level),Vector3.RIGHT+Vector3.DOWN*.5)
			street_reaction = move_toward(street_reaction,0.0,delta*.65)
	if is_instance_valid(service_tray) and arms.size()==2:
		carry_tray(delta,walking)
	if is_instance_valid(ember) and head_bone>=0:
		ember.global_transform = mouth_transform()*Transform3D(Basis(Vector3.RIGHT,PI*.5),Vector3(0,0,-.032))

func carry_tray(delta: float, walking: bool) -> void:
	service_time += delta
	var sway := sin(service_time*6.5)*.022 if walking else sin(service_time*2.2)*.008
	var arm := arms[1]
	point_arm(arm,Vector3(-.29,1.15+sway,.31),Vector3(-.75,-1,-.16))
	set_joint_rotation(arm.z,Basis(Vector3.RIGHT,Vector3.BACK,Vector3.DOWN))
	var wrist := skeleton.get_bone_global_pose(arm.z).origin
	var palm := skeleton.to_global(wrist+Vector3(0,.061,.075))
	service_tray.global_transform = Transform3D(global_basis.orthonormalized(),palm)

func rotate_local(bone_name: String, angles: Vector3) -> void:
	var bone := skeleton.find_bone(bone_name)
	if bone>=0:
		skeleton.set_bone_pose_rotation(bone,(skeleton.get_bone_pose_rotation(bone)*Quaternion.from_euler(angles)).normalized())

func dance_pose(beat: float) -> void:
	var phrase := dance_beats+beat+float(dance_seed%8)*2.0
	var phrase_beat := fposmod(phrase,16.0)
	var style := (dance_seed*5+int(phrase/16.0))%16
	var blend := smoothstep(0.0,.65,minf(phrase_beat,16.0-phrase_beat))
	var phase := phrase*TAU+float(dance_seed%3)*.17
	var swing := sin(phase)
	var sway := sin(phase*.5)
	var kick := pow(maxf(0,cos(phase)),2)
	var alternate := sin(phase*.25)
	var lift := .012+.020*kick
	var drift := Vector3.ZERO
	var turn := Vector3.ZERO
	var spine := Vector3(.03*swing,.035*sway,-.07*sway)
	var left_hip := Vector3.ZERO
	var right_hip := Vector3.ZERO
	var knees := Vector2(.12*kick,.10*(1-kick))
	var hands := [Vector3(.19,1.03,.17),Vector3(-.19,1.03,.17)]
	match style:
		0: # House groove
			turn.z = .05*sway
			hands[0].z += .10*swing
			hands[1].z -= .10*swing
		1: # Side step
			drift.x = .08*sway
			left_hip.z = .13*maxf(0,sway)
			right_hip.z = .13*minf(0,sway)
			hands = [Vector3(.30,1.23,.20+.09*sway),Vector3(-.30,1.23,.20-.09*sway)]
		2: # Hands in the air
			turn.y = .10*sway
			hands = [Vector3(.29,1.62+.09*kick,.20),Vector3(-.29,1.62+.09*(1-kick),.20)]
		3: # Shuffle
			left_hip.x = .26*swing
			right_hip.x = -.26*swing
			knees += Vector2(maxf(0,swing),maxf(0,-swing))*.20
			hands[0].z += .14*sway
			hands[1].z -= .14*sway
		4: # Running man
			drift.z = .036*sway
			left_hip.x = -.33*sway
			right_hip.x = .33*sway
			knees += Vector2(maxf(0,sway),maxf(0,-sway))*.32
			hands = [Vector3(.18,1.19,.27-.14*sway),Vector3(-.18,1.19,.27+.14*sway)]
		5: # Shoulder rolls
			spine = Vector3(.10*cos(phase*.5),.17*sway,-.09*sin(phase*.5))
			hands = [Vector3(.30,1.18+.10*sway,.13),Vector3(-.30,1.18-.10*sway,.13)]
		6: # Claps on alternating beats
			var together := pow(maxf(0,cos(phase*.5)),8)
			hands = [Vector3(lerpf(.32,.028,together),1.37,.30),Vector3(-lerpf(.32,.028,together),1.37,.30)]
		7: # One-arm pump
			var arm := 0 if alternate>=0 else 1
			var side := 1.0 if arm==0 else -1.0
			hands[arm] = Vector3(side*.24,1.39+.37*kick,.21)
			hands[1-arm].z += .11*sway
			turn.z = -.07*side*kick
		8: # Heel-toe twist
			turn.y = .15*swing
			left_hip.y = .27*swing
			right_hip.y = -.27*swing
			drift.x = .044*sway
			hands[0].x += .13*maxf(0,sway)
			hands[1].x -= .13*maxf(0,-sway)
		9: # Double bounce
			lift = .010+.048*pow(maxf(0,cos(phase*2)),3)
			knees += Vector2.ONE*.16*(1-kick)
			hands = [Vector3(.23,1.19+.13*kick,.22),Vector3(-.23,1.19+.13*kick,.22)]
		10: # Cross step
			drift.x = .062*sway
			left_hip = Vector3(.19*sway,-.08,-.14*maxf(0,sway))
			right_hip = Vector3(-.19*sway,.08,-.14*minf(0,sway))
			spine.y = -.18*sway
			hands = [Vector3(.17-.13*sway,1.29,.22),Vector3(-.17-.13*sway,1.29,.22)]
		11: # Body roll
			spine = Vector3(.19*sin(phase*.5),.09*sway,.055*cos(phase*.5))
			lift = .02+.026*cos(phase*.5)
			hands[0].y += .10*cos(phase*.5)
			hands[1].y -= .10*cos(phase*.5)
		12: # Finger point across the floor
			var arm := 0 if sway>=0 else 1
			var side := 1.0 if arm==0 else -1.0
			var reach := absf(sway)
			hands[arm] = Vector3(side*(.22+.22*reach),1.30+.25*kick,.26+.17*reach)
			turn.y = .13*sway
		13: # Knee lifts
			left_hip.x = -.32*maxf(0,sway)
			right_hip.x = -.32*maxf(0,-sway)
			knees += Vector2(maxf(0,sway),maxf(0,-sway))*.23
			hands = [Vector3(.23,1.20,.20-.13*sway),Vector3(-.23,1.20,.20+.13*sway)]
		14: # Side reach with torso turn
			turn.y = .15*alternate
			spine.y = .15*alternate
			drift.x = .05*alternate
			hands = [Vector3(.29,1.32+.18*sway,.21),Vector3(-.29,1.32-.18*sway,.21)]
		15: # Small jumps on the downbeat
			lift = .012+.071*pow(maxf(0,cos(phase*.5)),4)
			knees += Vector2.ONE*.16*(1-kick)
			hands = [Vector3(.28,1.27+.31*kick,.20),Vector3(-.28,1.27+.31*kick,.20)]
	var strength := clampf(dance_energy,.3,1.6)*blend
	position += (drift+Vector3.UP*lift)*strength
	rotation += turn*strength
	rotate_local("Spine",spine*strength)
	rotate_local("Head",Vector3(.050*swing,.04*sway,0)*strength)
	rotate_local("LeftUpLeg",left_hip*strength)
	rotate_local("RightUpLeg",right_hip*strength)
	rotate_local("LeftLeg",Vector3(knees.x*strength,0,0))
	rotate_local("RightLeg",Vector3(knees.y*strength,0,0))
	for index in range(2):
		var side := 1.0 if index==0 else -1.0
		var rest := Vector3(side*.16,.87,.10)
		point_arm(arms[index],rest.lerp(hands[index],clampf(strength,0,1)),Vector3(side,-.25,-.40))


func combat_stance() -> void:
	var strike := sin(PI*clampf(combat_swing,0,1))
	var side_sign := 1.0 if punch_side==0 else -1.0
	rotate_local("Spine",Vector3(.12+.20*strike-.23*combat_recoil,.27*strike*side_sign,.08*sin(combat_clock*9.0)+.16*combat_guard*side_sign))
	rotate_local("Head",Vector3(.14*combat_guard-.32*combat_recoil,.12*combat_recoil*side_sign,0))
	for side in range(2):
		var sign_side := 1.0 if side==0 else -1.0
		var step := sin(combat_clock*9.0+side*PI)
		var target := Vector3(sign_side*.18,1.39+.045*step,.27)
		target = target.lerp(Vector3(sign_side*.11,1.58,.24),combat_guard)
		if strike>.001 and side==punch_side:
			var goal := skeleton.to_local(combat_target)
			goal.x += sin(TAU*combat_swing)*sign_side*(.27 if combat_style==1 else .055)
			goal.y -= sin(TAU*combat_swing)*(.18 if combat_style==2 else .035)
			target = target.lerp(goal,strike)
		rotate_local(["LeftUpLeg","RightUpLeg"][side],Vector3(.08*step,0,.08*sign_side))
		rotate_local(["LeftLeg","RightLeg"][side],Vector3(.12+.08*step,0,0))
		point_arm(arms[side],target,Vector3(sign_side,-.15,-.25))

func kneel(amount: float, retch: float) -> void:
	position.y -= .66*amount
	rotate_local("Spine",Vector3((.62+.10*retch)*amount,0,0))
	rotate_local("Head",Vector3(.12*amount,0,0))
	for side in ["Left","Right"]:
		rotate_local(side+"UpLeg",Vector3(-1.10*amount,0,0))
		rotate_local(side+"Leg",Vector3(2.48*amount,0,0))
		rotate_local(side+"Foot",Vector3(-.35*amount,0,0))
	for side in range(2):
		var target := Vector3(.17 if side==0 else -.17,.92,.36)
		var fist := skeleton.get_bone_global_pose(arms[side].z).origin
		point_arm(arms[side],fist.lerp(target,amount),Vector3(1 if side==0 else -1,-.2,-.25))

func mouth_transform() -> Transform3D:
	var head := skeleton.global_transform*skeleton.get_bone_global_pose(head_bone)
	return Transform3D((head.basis*Basis(Vector3.UP,PI)).orthonormalized(),head*mouth_offset)

func play_action(animation: StringName, duration: float) -> void:
	if not animator.has_animation(animation):
		return
	action = animation
	action_time = duration
	clip = &""

func make_first_person(visible_bones := PackedStringArray(), hidden_bones := PackedStringArray()) -> void:
	var roots: Array[int] = [head_bone]
	var hidden: Array[int] = []
	for name in hidden_bones:
		hidden.append(skeleton.find_bone(name))
	if not visible_bones.is_empty():
		roots.clear()
		for name in visible_bones:
			roots.append(skeleton.find_bone(name))
	for node in find_children("*","MeshInstance3D",true,false):
		var part := node as MeshInstance3D
		part.layers = 4
		if part.skin == null:
			continue
		var mesh := ArrayMesh.new()
		for surface in range(part.mesh.get_surface_count()):
			var arrays := part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var source: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if source.is_empty():
				for vertex in range(vertices.size()):
					source.append(vertex)
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			@warning_ignore("integer_division")
			var stride := bones.size() / vertices.size()
			var visible_vertices := PackedByteArray()
			visible_vertices.resize(vertices.size())
			for vertex in range(vertices.size()):
				var weight := 0.0
				var hidden_weight := 0.0
				for influence in range(stride):
					var index := vertex * stride + influence
					var bone := part.skin.get_bind_bone(bones[index])
					if bone < 0:
						bone = skeleton.find_bone(part.skin.get_bind_name(bones[index]))
					while bone >= 0 and not roots.has(bone) and not hidden.has(bone):
						bone = skeleton.get_bone_parent(bone)
					if hidden.has(bone):
						hidden_weight += weights[index]
					elif bone >= 0:
						weight += weights[index]
				visible_vertices[vertex] = int((weight <= .4 if visible_bones.is_empty() else weight > .22) and hidden_weight < .65)
			var indices := PackedInt32Array()
			for triangle in range(0,source.size(),3):
				var keep := true
				for corner in range(3):
					keep = keep and visible_vertices[source[triangle+corner]] != 0
				if keep:
					indices.append_array(source.slice(triangle,triangle+3))
			if indices.is_empty():
				continue
			arrays[Mesh.ARRAY_INDEX] = indices
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			mesh.surface_set_material(mesh.get_surface_count()-1,part.get_active_material(surface))
		if mesh.get_surface_count()==0:
			continue
		var visible_body := MeshInstance3D.new()
		visible_body.mesh = mesh
		visible_body.skin = part.skin
		visible_body.skeleton = part.skeleton
		visible_body.transform = part.transform
		visible_body.layers = 16
		visible_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.get_parent().add_child(visible_body)

func pocket(arm: Vector3i, side: float) -> void:
	var target := Vector3(side*.16,.87,.10) if psx else Vector3(side*.32,1.06,.27)
	point_arm(arm,target,Vector3(side,-.12,-.53))

func point_arm(arm: Vector3i, target: Vector3, outward: Vector3) -> void:
	var shoulder := skeleton.get_bone_global_pose(arm.x)
	var elbow := skeleton.get_bone_global_pose(arm.y)
	var fist := skeleton.get_bone_global_pose(arm.z)
	var upper_length := shoulder.origin.distance_to(elbow.origin)
	var lower_length := elbow.origin.distance_to(fist.origin)
	if minf(upper_length,lower_length)<.01:
		return
	var direction := (target-shoulder.origin).normalized()
	var reach := clampf(target.distance_to(shoulder.origin),absf(upper_length-lower_length)+.001,upper_length+lower_length-.001)
	var along := (upper_length*upper_length-lower_length*lower_length+reach*reach)/(2.0*reach)
	var bend := (outward-direction*outward.dot(direction)).normalized()
	var elbow_target := shoulder.origin+direction*along+bend*sqrt(maxf(0,upper_length*upper_length-along*along))
	var wrist_target := shoulder.origin+direction*reach
	var upper_turn := Basis(Quaternion((elbow.origin-shoulder.origin).normalized(),(elbow_target-shoulder.origin).normalized()))
	set_joint_rotation(arm.x,upper_turn*shoulder.basis.orthonormalized())
	var current_elbow := skeleton.get_bone_global_pose(arm.y)
	var current_fist := skeleton.get_bone_global_pose(arm.z)
	var lower_direction := (current_fist.origin-current_elbow.origin).normalized()
	var target_direction := (wrist_target-current_elbow.origin).normalized()
	var adjusted := Basis(Quaternion(lower_direction,target_direction))*current_elbow.basis.orthonormalized()
	set_joint_rotation(arm.y,adjusted)

func set_joint_rotation(bone: int, basis: Basis) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent>=0 else Basis.IDENTITY
	var local := parent_basis.inverse()*basis.orthonormalized()
	skeleton.set_bone_pose_rotation(bone,local.get_rotation_quaternion().normalized())
