extends CharacterBody3D

const Character = preload("res://scripts/party_guest.gd")
const GuestModel = preload("res://scripts/guest_model.gd")
var dj_rig: GuestModel
var dj_mouth: Node3D
var avatar: Node3D
var action_grip: Node3D
var action_amount := 0.0
var action_beer := false

var camera: Camera3D
var paused := false
var airborne := false
var pitch := 0.0
var looking := false
var safe_floor := Vector3.ZERO
var has_safe_floor := false
var intoxication := 0.0
var alcohol_motion := 0.0
var collapsed := false
var vomiting := false
var nausea_cooldown := 0.0
var nausea_time := 0.0
var kneel_amount := 0.0
var retch_clock := 0.0
var blackout: ColorRect
var head_bob := 0.0
var camera_rest := Vector3(0,1.64,0)
var mouse_sensitivity := .0025

func drink_beer() -> void:
	intoxication = minf(1.0,intoxication+.22)
	if intoxication>=.98 and not collapsed:
		fall_over()
	elif intoxication>=.74 and nausea_cooldown<=0:
		nausea_time = 1.2

func fall_over() -> void:
	collapsed = true
	airborne = false
	velocity = Vector3.ZERO
	var overlay := CanvasLayer.new()
	overlay.layer = 40
	add_child(overlay)
	blackout = ColorRect.new()
	blackout.color = Color(0,0,0,0)
	blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(blackout)
	blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var motion := create_tween().set_trans(Tween.TRANS_SINE)
	motion.tween_property(camera,"position",Vector3(.21,.22,-.10),.75)
	motion.parallel().tween_property(camera,"rotation",Vector3(-.95,0,.49),.75)
	motion.parallel().tween_property(avatar,"rotation",Vector3(.18,0,-1.35),.75)
	motion.tween_interval(.32)
	motion.tween_callback(func():
		get_parent().party.events.vomit_burst()
	)
	motion.tween_property(blackout,"color:a",1.0,1.0)
	motion.tween_interval(1.35)
	motion.tween_callback(func():
		camera.position = Vector3(0,1.64,0)
		camera.rotation = Vector3(pitch,0,0)
		avatar.rotation = Vector3.ZERO
		intoxication = .28
	)
	motion.tween_property(blackout,"color:a",0.0,1.2)
	motion.tween_callback(func():
		collapsed = false
		overlay.queue_free()
	)
var surface_at: Callable
var step_audio: AudioStreamPlayer
var steps := {}
var step_distance := .26
var step_index := 0

func _ready() -> void:
	floor_snap_length = .22
	floor_max_angle = deg_to_rad(48)
	safe_margin = .004
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.16
	capsule.height = 1.67
	collider.shape = capsule
	collider.position.y = 0.835
	add_child(collider)
	camera = Camera3D.new()
	camera.position.y = 1.64
	camera.current = true
	camera.fov = 70.0
	camera.near = 0.035
	camera.set_cull_mask_value(3,false)
	add_child(camera)
	make_body()
	setup_steps()

func look_motion(delta: Vector2) -> void:
	if collapsed:
		return
	rotate_y(-delta.x * mouse_sensitivity)
	pitch = clampf(pitch - delta.y * mouse_sensitivity, -1.46, 1.46)
	camera.rotation.x = pitch

func move_to(eye: Vector3, target: Vector3) -> void:
	if collapsed:
		return
	global_position = eye - Vector3(0, camera.position.y, 0)
	var direction := (target - eye).normalized()
	rotation.y = atan2(-direction.x, -direction.z)
	pitch = asin(clampf(direction.y, -1.0, 1.0))
	camera.rotation.x = pitch
	velocity = Vector3.ZERO
	has_safe_floor = false
	step_distance = .26

func return_to_floor() -> void:
	global_position = safe_floor + Vector3.UP*.05
	velocity = Vector3.ZERO

func _physics_process(delta: float) -> void:
	nausea_cooldown = maxf(0,nausea_cooldown-delta)
	if nausea_time>0:
		nausea_time -= delta
		if nausea_time<=0 and not collapsed:
			vomit()
	if paused:
		velocity = Vector3.ZERO
		return
	if collapsed or vomiting:
		retch_clock += delta
		update_body(delta)
		velocity.y = 0.0 if is_on_floor() else velocity.y-13.0*delta
		move_and_slide()
		return
	var sideways := float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	var forward := float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
	var direction := global_transform.basis * Vector3(sideways, 0.0, -forward).limit_length(1.0)
	var running := Input.is_physical_key_pressed(KEY_SHIFT)
	var speed := 3.30 if running else 1.75
	intoxication = move_toward(intoxication,0.0,delta*.004)
	alcohol_motion += delta
	var sway := sin(alcohol_motion*2.9)*intoxication
	camera.rotation.z = sway*.046
	if not airborne:
		direction = direction.rotated(Vector3.UP,sway*.17)
		speed *= 1.0-intoxication*.16
	var desired := direction*speed
	var acceleration := 10.0 if direction.length_squared()>.01 else 14.0
	velocity.x = move_toward(velocity.x,desired.x,acceleration*delta)
	velocity.z = move_toward(velocity.z,desired.z,acceleration*delta)
	if airborne:
		velocity.y = (float(Input.is_physical_key_pressed(KEY_SPACE)) - float(Input.is_physical_key_pressed(KEY_Q))) * speed
	else:
		velocity.y = 0.0 if is_on_floor() else velocity.y - 13.0 * delta
		if is_on_floor() and Input.is_physical_key_pressed(KEY_SPACE):
			velocity.y = 3.5
	var horizontal := Vector3(velocity.x,0,velocity.z)*delta
	if is_on_floor() and horizontal.length_squared()>.00001 and test_move(global_transform,horizontal):
		var raised := global_transform
		raised.origin.y += .16
		if not test_move(global_transform,Vector3.UP*.16) and not test_move(raised,horizontal):
			global_position.y += .16
	move_and_slide()
	var pace := Vector2(velocity.x,velocity.z).length()
	if is_on_floor():
		head_bob += delta*pace*5.4
	var bob := Vector3(sin(head_bob*.5)*.007,absf(sin(head_bob))*.013,0) if pace>.15 and is_on_floor() else Vector3.ZERO
	camera.position = camera.position.lerp(camera_rest+bob,minf(1,delta*12))
	camera.fov = lerpf(camera.fov,76.0 if running and pace>2 else 72.0,minf(1,delta*5))
	if is_on_floor() and global_position.y>-.25:
		safe_floor = global_position
		has_safe_floor = true
	update_body(delta)
	update_steps(direction)
func make_body() -> void:
	var templates := {}
	for asset in ["man_2","man_tee","man_jacket","man_jeans","man_boots","man_hair_short"]:
		var loaded := GuestModel.load_model("res://assets/psx/glb/"+asset+".glb")
		if loaded!=null:
			templates[asset] = loaded
	var rig := GuestModel.new()
	var ready := rig.setup_psx(templates,false,2,1.0,1.0,Color("#c99570"),Color("#454b68"),Color("#303645"))
	for template in templates.values():
		template.free()
	if ready:
		dj_rig = rig
		rig.player_body = true
		avatar = rig
		add_child(avatar)
		avatar.position.z = .075
		rig.make_first_person()
		dj_mouth = Node3D.new()
		avatar.add_child(dj_mouth)
		action_grip = Node3D.new()
		avatar.add_child(action_grip)
		update_body(0)
		return
	rig.free()
	avatar = Character.new(5)
	add_child(avatar)
	avatar.position.z = .11
	avatar.name_tag.hide()
	avatar.speech.hide()
	for part in avatar.head.get_children():
		part.layers = 4
	action_grip = Node3D.new()
	avatar.figure.add_child(action_grip)
	update_body(0)

func mouth_anchor() -> Node3D:
	return dj_mouth if is_instance_valid(dj_mouth) else avatar.head

func set_action_pose(amount: float) -> void:
	action_amount = amount
	update_body(0)

func update_body(delta: float) -> void:
	var moving := is_on_floor() and Vector2(velocity.x,velocity.z).length()>.14
	if is_instance_valid(dj_rig):
		update_dj_body(delta,moving)
		return
	avatar.pose(delta,0,moving)
	avatar.head.rotation.z = 0.0
	if action_amount<=.001:
		action_grip.position = Vector3(.215,.91,-.075)
		return
	var upper: Node3D = avatar.arms[1]
	var lower: Node3D = avatar.elbows[1]
	var shoulder := upper.position
	var idle := Vector3(.215,.91,-.075)
	avatar.head.rotation.x = -.12*action_amount if action_beer else .07*action_amount
	avatar.head.rotation.z = -.045*action_amount
	var tilt := Vector3(1.17*action_amount if action_beer else 0.0,0,-.10*action_amount)
	var mouth: Vector3 = avatar.figure.to_local(avatar.head.to_global(Vector3(.005,-.046,-.090)))
	var contact := Vector3(-.018,.158,-.015) if action_beer else Vector3(-.012,.018,.005)
	mouth -= Basis.from_euler(tilt)*contact
	var wrist := idle.lerp(mouth,action_amount)
	var toward := (wrist-shoulder).normalized()
	var distance := clampf(wrist.distance_to(shoulder),.08,.455)
	const UPPER := .237
	const LOWER := .224
	var along := (UPPER*UPPER-LOWER*LOWER+distance*distance)/(2*distance)
	var outward := Vector3(.72,-1,.28)
	var bend := (outward-toward*outward.dot(toward)).normalized()
	var elbow := shoulder+toward*along+bend*sqrt(maxf(0,UPPER*UPPER-along*along))
	wrist = shoulder+toward*distance
	upper.basis = arm_basis(elbow-shoulder)
	lower.basis = upper.basis.inverse()*arm_basis(wrist-elbow)
	action_grip.position = wrist
	action_grip.rotation = tilt

func update_dj_body(delta: float, moving: bool) -> void:
	dj_rig.pose(delta,moving,1.0,false,0.0)
	var skeleton: Skeleton3D = dj_rig.skeleton
	if kneel_amount>0:
		dj_rig.kneel(kneel_amount,sin(retch_clock*12))
	else:
		dj_rig.rotate_local("Head",Vector3(-pitch*.65,0,0))
	dj_mouth.global_transform = dj_rig.mouth_transform()
	if kneel_amount>.01:
		return
	var arm := dj_rig.arms[0]
	var idle := skeleton.get_bone_global_pose(arm.z).origin
	var tilt := Vector3(1.17*action_amount if action_beer else 0.0,0,-.10*action_amount)
	var contact := Vector3(-.018,.158,-.015) if action_beer else Vector3(-.012,.018,-.006)
	var mouth_target := skeleton.to_local(dj_mouth.global_position-avatar.global_basis*Basis.from_euler(tilt)*contact)
	if action_amount>.001:
		dj_rig.point_arm(arm,idle.lerp(mouth_target,action_amount),Vector3(.72,-1,-.28))
	action_grip.global_position = skeleton.to_global(skeleton.get_bone_global_pose(arm.z).origin)
	action_grip.rotation = tilt

func vomit() -> void:
	if vomiting or collapsed or intoxication<.65 or nausea_cooldown>0:
		return
	var party = get_parent().party
	if is_instance_valid(party.hand_prop):
		nausea_time = .4
		return
	party.extinguish()
	vomiting = true
	nausea_time = 0
	nausea_cooldown = 35.0
	velocity = Vector3.ZERO
	get_parent().hud.notice("Тошнит…")
	retch_clock = 0.0
	var motion := create_tween().set_trans(Tween.TRANS_SINE)
	motion.tween_property(self,"kneel_amount",1.0,.65)
	motion.parallel().tween_property(camera,"rotation:x",-.72,.65)
	motion.parallel().tween_property(camera,"position:y",.96,.65)
	motion.tween_callback(party.events.vomit_burst)
	motion.tween_interval(2.35)
	motion.tween_property(self,"kneel_amount",0.0,.85)
	motion.parallel().tween_property(camera,"rotation:x",pitch,.85)
	motion.parallel().tween_property(camera,"position:y",camera_rest.y,.85)
	motion.tween_callback(func():
		vomiting = false
		intoxication = maxf(.35,intoxication-.14)
	)

func arm_basis(direction: Vector3) -> Basis:
	var up := -direction.normalized()
	var side := Vector3.RIGHT
	if absf(up.dot(side))>.95:
		side = Vector3.FORWARD
	var forward := side.cross(up).normalized()
	return Basis(up.cross(forward).normalized(),up,forward)

func setup_steps() -> void:
	step_audio = AudioStreamPlayer.new()
	step_audio.volume_db = -20
	add_child(step_audio)
	for surface in ["wood","tile","rug"]:
		var variants: Array[AudioStreamWAV] = []
		for index in range(3):
			variants.append(synthesize_step(surface,index))
		steps[surface] = variants

func synthesize_step(surface: String, index: int) -> AudioStreamWAV:
	const RATE := 24000
	var pcm := PackedByteArray()
	pcm.resize(5400*2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7759+index*137
	var filtered := 0.0
	var frequency := {"wood":96.0,"tile":126.0,"rug":67.0}[surface] as float
	var brightness := {"wood":.075,"tile":.12,"rug":.035}[surface] as float
	for i in range(pcm.size()/2):
		var t := float(i)/RATE
		var noise := rng.randf_range(-1.0,1.0)
		filtered = lerpf(filtered,noise,.15)
		var heel := sin(TAU*(frequency+index*6)*t)*exp(-t*62.0)*.29
		var toe := maxf(0.0,t-.064)
		var cloth := filtered*(exp(-t*43.0)+(exp(-toe*47.0)*minf(1.0,toe*320.0))*.55)
		var click := filtered*exp(-t*55.0)*brightness
		var attack := smoothstep(0.0,.023,t)
		var sample := (heel*.71+cloth*.64+click)*attack
		pcm.encode_s16(i*2,roundi(clampf(sample,-1,1)*32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = pcm
	return wav

func update_steps(direction: Vector3) -> void:
	if airborne or not is_on_floor() or direction.length_squared()<.01:
		return
	var displacement := get_position_delta()
	step_distance += Vector2(displacement.x,displacement.z).length()
	var stride := .75 if Input.is_physical_key_pressed(KEY_SHIFT) else .57
	if step_distance<stride:
		return
	step_distance -= stride
	var surface := str(surface_at.call(global_position)) if surface_at.is_valid() else "wood"
	step_audio.stream = steps[surface][step_index%3]
	step_audio.pitch_scale = 1.0+float(step_index%5-2)*.035
	step_audio.play()
	step_index += 1

