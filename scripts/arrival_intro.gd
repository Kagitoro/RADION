extends Node

const Guest = preload("res://scripts/party_guest.gd")
const District = preload("res://scripts/night_district.gd")
const SAVE := "user://radion_story.cfg"
const VOICE_PATH := "res://assets/story/voice/line_%02d.mp3"
const STREET_BED = preload("res://assets/story/ambience/street.mp3")
const ENGINE_BED = preload("res://assets/story/ambience/engine.mp3")
const DOOR_THUD = preload("res://assets/story/ambience/door.mp3")
const CLUB_BED = preload("res://assets/story/ambience/club_outside.mp3")
const LINES := [
	[0,3.4,"",""],
	[0,4.3,"You","You sure this is the place? Even the cabbies blow through this block."],
	[1,4.2,"Kir","Yo, brother. Get out. Easy with the door, man. It's older than both of us."],
	[1,3.5,"You","You said somebody was waiting on me. Who?"],
	[2,4.5,"Kir","Club owner. I said I knew a guy. He goes, how much does your guy want?"],
	[2,2.4,"You","And what'd you tell him?"],
	[2,4.2,"Kir","That he could ask you himself. I got you a slot, man. I didn't negotiate a treaty."],
	[3,4.1,"You","Shit. When's the set?"],
	[3,4.2,"Kir","Tonight. Hey, breathe. You got time to change your shirt."],
	[4,4.6,"Kir","That's your place. Key's under the mat. The FLX4's in the bedroom. You bring your tracks?"],
	[4,3.8,"You","Two tracks. One clean shirt. Clean-ish."],
	[5,4.4,"Kir","Then you're overdressed. Warm the room up first. Save the big shit for later."],
	[5,4.1,"Kir","RADION's across the street. Tell Samir you're opening. I'll be around."],
]

var home
var game
var camera: Camera3D
var layer: CanvasLayer
var subtitle: Label
var speaker: Label
var caption: Label
var objective: Label
var fade: ColorRect
var street_sound: AudioStreamPlayer
var engine: AudioStreamPlayer3D
var club_sound: AudioStreamPlayer3D
var door_sound: AudioStreamPlayer3D
var kir_voice: AudioStreamPlayer3D
var voice := AudioStreamPlayer.new()
var line_duration := 0.0
var arrival_car: Node3D
var arrival_wheels: Array[Node] = []
var friend: Node3D
var active := false
var seen := false
var opening_completed := false
var first_set_done := false
var replay := false
var line := 0
var elapsed := 0.0
var running_time := 0.0
var opening_fade := 0.0
var closing := false
var close_time := 0.0
var old_hud_visible := true
var old_player_visible := true
var old_club_mute := false
var origin := Vector3.ZERO

func setup(editor, night_game) -> void:
	home = editor
	game = night_game
	var config := ConfigFile.new()
	if config.load(SAVE)==OK:
		seen = config.get_value("story","intro_seen",false)
		first_set_done = config.get_value("story","first_set_done",false)
		opening_completed = config.get_value("story","opening_completed",first_set_done)
	objective = home.hud.label("",15)
	home.hud.root.add_child(objective)
	objective.position = Vector2(20,150)
	objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	update_objective()
	build_overlay()
	add_child(voice)
	voice.volume_db = -2.0

func update_objective() -> void:
	objective.text = "Первый заказ · В RADION нажми J, чтобы начать сет"
	objective.visible = seen and not first_set_done

func build_overlay() -> void:
	layer = CanvasLayer.new()
	layer.layer = 35
	add_child(layer)
	var root := Control.new()
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := ColorRect.new()
	root.add_child(top)
	top.color = Color("#090a0e")
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 69
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bottom := ColorRect.new()
	root.add_child(bottom)
	bottom.color = Color("#090a0e")
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -139
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var group := VBoxContainer.new()
	root.add_child(group)
	group.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	group.offset_left = 50
	group.offset_right = -50
	group.offset_top = -130
	group.offset_bottom = -16
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speaker = home.hud.label("",15)
	speaker.modulate = Color("#eca9c0")
	speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	group.add_child(speaker)
	subtitle = home.hud.label("",23)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	group.add_child(subtitle)
	var hint: Label = home.hud.label("E / Space · continue     Esc · skip",13)
	hint.modulate = Color("#a3a5b3")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	group.add_child(hint)
	caption = home.hud.label("RADION     /     FIRST NIGHT",27)
	root.add_child(caption)
	caption.position = Vector2(24,17)
	fade = ColorRect.new()
	root.add_child(fade)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.color = Color.BLACK
	layer.hide()

func start(is_replay: bool = false) -> void:
	if active:
		return
	active = true
	replay = is_replay
	origin = home.night_world.door_center
	line = 0
	elapsed = 0.0
	running_time = 0.0
	opening_fade = .9
	closing = false
	close_time = 0.0
	old_hud_visible = home.hud.root.visible
	home.hud.root.hide()
	old_player_visible = home.player.visible
	home.player.hide()
	home.set_modal(true)
	var venue_bus: int = home.night_world.nightclub.music_bus
	old_club_mute = AudioServer.is_bus_mute(venue_bus)
	AudioServer.set_bus_mute(venue_bus,true)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

	camera = Camera3D.new()
	camera.cull_mask = home.player.camera.cull_mask
	camera.fov = 55
	camera.near = .06
	home.add_child(camera)
	camera.make_current()
	arrival_car = District.place_car(home.night_world.street,1,Vector3(-56.8,0,-17.5))
	arrival_wheels = arrival_car.find_children("Axle-*","Node3D",true,false)
	friend = Guest.new(12,null,home.party.psx_assets)
	home.night_world.street.add_child(friend)
	friend.name_tag.hide()
	home.night_world.point_light(friend,Vector3(0,1.8,-.82),Color("#f5c7a8"),.68,2.7)
	friend.hide()
	street_sound = AudioStreamPlayer.new()
	street_sound.stream = loop_stream(STREET_BED)
	street_sound.volume_db = -25.0
	add_child(street_sound)
	street_sound.play()
	engine = place_audio(arrival_car,Vector3(0,.70,1.0),loop_stream(ENGINE_BED),-12.0,3.1,22.0)
	engine.play()
	door_sound = place_audio(arrival_car,Vector3(-.90,1.0,.40),DOOR_THUD,-10.0,2.5,16.0)
	club_sound = place_audio(home.night_world.street,Vector3(-21.97,1.26,0),loop_stream(CLUB_BED),-24.0,3.5,27.0)
	club_sound.play()
	kir_voice = place_audio(friend,Vector3(0,1.57,-.14),null,-2.0,3.9,12.0)
	kir_voice.attenuation_filter_cutoff_hz = 5100.0
	kir_voice.attenuation_filter_db = -5.0
	layer.show()
	set_line()
	update_shot(0.0)

func loop_stream(source: AudioStreamMP3) -> AudioStreamMP3:
	var stream := source.duplicate() as AudioStreamMP3
	stream.loop = true
	return stream

func place_audio(parent: Node3D, at: Vector3, stream: AudioStream, db: float, unit: float, reach: float) -> AudioStreamPlayer3D:
	var source := AudioStreamPlayer3D.new()
	source.position = at
	source.stream = stream
	source.volume_db = db
	source.unit_size = unit
	source.max_distance = reach
	source.panning_strength = .52
	parent.add_child(source)
	return source

func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE: finish()
			KEY_E,KEY_SPACE,KEY_ENTER: advance_line()
	get_viewport().set_input_as_handled()

func set_line() -> void:
	var row: Array = LINES[line]
	speaker.text = str(row[2]).to_upper()
	subtitle.text = row[3]
	caption.visible = line<2
	line_duration = float(row[1])
	voice.stop()
	voice.stream = null
	kir_voice.stop()
	kir_voice.stream = null
	if subtitle.text.is_empty():
		return
	var path := VOICE_PATH % line
	if not ResourceLoader.exists(path):
		return
	var clip := load(path) as AudioStream
	if clip == null:
		return
	var talking: Node = kir_voice if row[2]=="Kir" else voice
	talking.stream = clip
	line_duration = clip.get_length()+.48
	if line==1:
		line_duration = maxf(line_duration,float(row[1]))
	talking.play()

func advance_line() -> void:
	if closing:
		return
	if line>=LINES.size()-1:
		closing = true
		close_time = 0.0
		return
	if line==1:
		engine.stop()
		door_sound.play()
	if LINES[line][0]!=LINES[line+1][0]:
		opening_fade = .15
	line += 1
	elapsed = 0.0
	set_line()

func _process(delta: float) -> void:
	if not active:
		return
	if closing:
		close_time += delta
		fade.color.a = clampf(close_time/.55,0,1)
		street_sound.volume_db = move_toward(street_sound.volume_db,-55.0,delta*42.0)
		club_sound.volume_db = move_toward(club_sound.volume_db,-55.0,delta*42.0)
		if close_time>=.58:
			finish()
		return
	elapsed += delta
	running_time += delta
	if elapsed>=line_duration:
		advance_line()
		if closing:
			return
	var speaking := voice.playing or kir_voice.playing
	street_sound.volume_db = move_toward(street_sound.volume_db,-28.0 if speaking else -23.0,delta*12.0)
	club_sound.volume_db = move_toward(club_sound.volume_db,-25.0 if speaking else -20.0,delta*12.0)
	opening_fade = maxf(0,opening_fade-delta)
	fade.color.a = clampf(opening_fade/.9,0,1)
	update_shot(delta)

func update_shot(delta: float) -> void:
	var shot: int = LINES[line][0]
	var motion := sin(running_time*.18)
	var eye := Vector3.ZERO
	var focus := Vector3.ZERO
	if shot==0:
		engine.pitch_scale = .82+.31*sin(clampf(running_time/7.8,0.0,1.0)*PI)
		engine.volume_db = -18.0 if voice.playing else -12.0
		arrival_car.position.z = lerpf(-17.5,-7.0,smoothstep(0.0,7.8,running_time))
		for wheel in arrival_wheels:
			if arrival_car.position.z< -7.03:
				wheel.rotate_x(delta*3.0)
		eye = Vector3(-52.0+motion*.38,2.42,-10.5+motion*1.3)
		focus = arrival_car.position+Vector3(-.8,.93,.70)
		friend.hide()
	else:
		arrival_car.position = Vector3(-11.55,0,.55)
		friend.show()
		if shot<4:
			friend.position = Vector3(-12.35,0,3.47)
			match shot:
				1:
					eye = Vector3(-10.43,1.73,4.42+motion*.20)
					focus = friend.position+Vector3.UP*1.33
				2:
					eye = Vector3(-11.03,1.62,4.72+motion*.15)
					focus = friend.position+Vector3.UP*1.49
				3:
					eye = Vector3(-10.47,1.69,3.42+motion*.17)
					focus = friend.position+Vector3.UP*1.35
		else:
			friend.position = Vector3(-2.67,0,.75)
			if shot==4:
				eye = Vector3(-4.65,1.75,-.48+motion*.20)
				focus = friend.position+Vector3(0,1.29,0)
			else:
				eye = Vector3(-3.85,1.63,-.73+motion*.14)
				focus = Vector3(-.81,1.52,.17)
		var direction := friend.position.direction_to(eye)
		friend.rotation.y = atan2(-direction.x,-direction.z)
		friend.pose(delta,0.0,false)
		if speaker.text=="KIR" and is_instance_valid(friend.imported_model):
			var rig = friend.imported_model
			if line in [2,4,8,9,12] and rig.arms.size()==2:
				var gesture := sin(clampf(elapsed/2.2,0.0,1.0)*PI)
				var wrist := Vector3(.18,.87,.10).lerp(Vector3(.36,1.23,.32),gesture)
				rig.point_arm(rig.arms[0],wrist,Vector3(.85,-.4,-.15))
	camera.global_position = origin+eye
	camera.look_at(origin+focus)

func finish() -> void:
	if not active:
		return
	active = false
	voice.stop()
	voice.stream = null
	kir_voice.stop()
	engine.stop()
	door_sound.stop()
	street_sound.stop()
	club_sound.stop()
	AudioServer.set_bus_mute(home.night_world.nightclub.music_bus,old_club_mute)
	layer.hide()
	home.player.camera.make_current()
	for node in [camera,arrival_car,friend,street_sound,club_sound]:
		if is_instance_valid(node):
			node.queue_free()
	camera = null
	arrival_car = null
	arrival_wheels.clear()
	friend = null
	street_sound = null
	club_sound = null
	engine = null
	door_sound = null
	kir_voice = null
	if not replay:
		seen = true
		opening_completed = true
		save_story()
		home.player.move_to(origin+Vector3(-2.25,1.64,0),origin+Vector3(0,1.58,0))
	home.player.visible = old_player_visible
	home.hud.root.visible = old_hud_visible
	home.set_modal(false)
	update_objective()

func first_booking_complete() -> void:
	if not seen or first_set_done:
		return
	first_set_done = true
	save_story()
	update_objective()
	home.hud.notice("Первый заказ закрыт · Кир обещал узнать про следующий слот")

func save_story() -> void:
	var config := ConfigFile.new()
	config.set_value("story","intro_seen",seen)
	config.set_value("story","opening_completed",opening_completed)
	config.set_value("story","first_set_done",first_set_done)
	if config.save(SAVE)!=OK:
		push_warning("Не удалось сохранить прогресс вступления")
