class_name ArrivalIntro
extends Node

static var SAVE := SavePaths.file("radion_story.cfg")
const VOICE_PATH := "res://assets/story/voice/%s.mp3"
const STREET_BED = preload("res://assets/story/ambience/street.mp3")
const ENGINE_BED = preload("res://assets/story/ambience/engine.mp3")
const DOOR_THUD = preload("res://assets/story/ambience/door.mp3")
const CLUB_BED = preload("res://assets/story/ambience/club_outside.mp3")
const LINES := [
	[0,3.8,"","",""],
	[0,4.3,"You","You sure this is the place? Even the cabbies blow through this block.","line_01"],
	[1,4.7,"Old voicemail","You said ten minutes. We waited forty. I paid the guy from the bar to cover you, and—","arrival_voicemail"],
	[1,4.8,"Kir","You want food? I know a place that sells beer till four. The food stopped being a sure thing in March.","arrival_food"],
	[1,2.5,"You","It's November, man.","arrival_november"],
	[1,2.8,"Kir","Yeah. That's why I said beer.","arrival_beer"],
	[2,4.2,"Kir","Yo, brother. Get out. Easy with the door, man. It's older than both of us.","line_02"],
	[2,3.5,"You","You said somebody was waiting on me. Who?","line_03"],
	[3,6.0,"Kir","See Samir by the door? I left him your name. If their opener doesn't show, you get twenty minutes.","arrival_slot"],
	[3,3.5,"You","You put my name down without asking me?","arrival_name"],
	[3,4.8,"Kir","I told him you could play. I didn't tell him you'd show up.","arrival_promise"],
	[4,3.6,"You","Shit. When's the set?","line_07"],
	[4,4.0,"Kir","Tonight. Keep your phone on. Last thing I need is two DJs I can't get hold of.","arrival_tonight"],
	[5,5.5,"Kir","Here. This one's for the front door. The controller's in the bedroom. You bring your tracks?","arrival_keys"],
	[5,3.8,"You","Two tracks. One clean shirt. Clean-ish.","line_10"],
	[5,4.4,"Kir","Then you're overdressed. Warm the room up first. Save the big shit for later.","line_11"],
	[6,5.5,"Kir","Previous tenant left you a note on the fridge. Read it before you open anything that smells funny.","arrival_note"],
	[6,3.2,"You","You could've led with that.","arrival_led"],
	[6,3.7,"Kir","And miss the look on your face? See you at the club.","arrival_goodbye"],
]

var home: Home
var game: NightGame
var camera: Camera3D
const OVERLAY := preload("res://ui/intro_overlay.tscn")
var layer: CanvasLayer
var subtitle: Label
var speaker: Label
var caption: Label
var objective: Label
var fade: ColorRect
var phone_card: Label
var follow_up: PanelContainer
var follow_up_text: Label
var follow_up_left := 0.0
var follow_up_line := 0
var entrance_leaf: Node3D
var entrance_shape: CollisionShape3D
var entry_opened := false
var note_read := false
var fridge_note: Node3D
var cash_envelope: Node3D
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
var key_prop: Node3D
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
var guard_yaw := 0.0
var guard_tag_visible := true
var origin := Vector3.ZERO

func setup(game_home: Home, night_game: NightGame) -> void:
	home = game_home
	game = night_game
	var config := ConfigFile.new()
	if config.load(SAVE)==OK:
		seen = config.get_value("story","intro_seen",false)
		first_set_done = config.get_value("story","first_set_done",false)
		opening_completed = config.get_value("story","opening_completed",first_set_done)
		entry_opened = config.get_value("story","entry_opened",opening_completed)
		note_read = config.get_value("story","note_read",opening_completed)
	if home.game_mode:
		build_entrance()
	objective = UIKit.label("",15)
	home.hud.root.add_child(objective)
	objective.position = Vector2(20,150)
	objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	update_objective()
	build_overlay()
	build_follow_up()
	add_child(voice)
	voice.volume_db = -2.0

func update_objective() -> void:
	if opening_completed and game.cleanup_remaining() > 0:
		if not entry_opened or not note_read:
			objective.text = tr("Первый вечер · Открой входную дверь") if not entry_opened else tr("Первый вечер · Прочитай записку на холодильнике")
			objective.show()
			return
		game.show_litter()
		objective.text = tr("Убрать дом · %d/%d · награда $%d") % [game.LITTER.size() - game.cleanup_remaining(),game.LITTER.size(),game.CLEANUP_REWARD]
		objective.show()
		return
	objective.text = tr("Первый заказ · В RADION нажми J, чтобы начать сет")
	objective.visible = seen and not first_set_done

func build_overlay() -> void:
	layer = OVERLAY.instantiate()
	add_child(layer)
	speaker = layer.get_node("%Speaker")
	subtitle = layer.get_node("%Subtitle")
	caption = layer.get_node("%Caption")
	fade = layer.get_node("%Fade")
	phone_card = UIKit.label("▸  SAVED VOICEMAIL   /   LAST MONTH",19)
	layer.get_node("Root").add_child(phone_card)
	phone_card.position = Vector2(26,88)
	phone_card.hide()
	layer.hide()

func build_entrance() -> void:
	entrance_leaf = Node3D.new()
	home.night_world.street.add_child(entrance_leaf)
	entrance_leaf.position = Vector3(.02,0,-.53)
	var world := home.night_world
	world.box(entrance_leaf,Vector3(0,1.09,.53),Vector3(.086,2.16,1.06),Color("#55483e"),true)
	var body := entrance_leaf.find_children("*","StaticBody3D",false,false)[0] as StaticBody3D
	entrance_shape = body.get_child(0)
	for height in [.56,1.52]:
		world.box(entrance_leaf,Vector3(-.047,height,.53),Vector3(.015,.72,.72),Color("#685747"))
	world.box(entrance_leaf,Vector3(-.09,1.02,.94),Vector3(.09,.047,.13),Color("#c4955f"))
	if entry_opened:
		entrance_leaf.rotation.y = 1.48
		entrance_shape.disabled = true

func attach_fridge_note(cabinet: Node3D) -> void:
	fridge_note = Node3D.new()
	cabinet.add_child(fridge_note)
	fridge_note.position = Vector3(.40,1.45,-.071)
	var world := home.night_world
	world.box(fridge_note,Vector3.ZERO,Vector3(.22,.16,.004),Color("#e8d7a1"))
	world.box(fridge_note,Vector3(0,.057,-.006),Vector3(.052,.027,.011),Color("#b85043"))
	world.add_sign(fridge_note,"$12",Vector3(0,.006,-.005),Vector3(0,PI,0),Color("#49372a"),.00115)
	cash_envelope = Node3D.new()
	fridge_note.add_child(cash_envelope)
	world.box(cash_envelope,Vector3(.013,-.062,-.009),Vector3(.125,.048,.009),Color("#93a380"))
	cash_envelope.visible = game.cleanup_remaining() > 0

func place_at_door() -> void:
	var door := home.night_world.door_center
	home.player.move_to(door+Vector3(-2.25,1.64,0),door+Vector3(0,1.45,0))

func entry_aimed() -> bool:
	if not opening_completed or entry_opened or entrance_leaf == null:
		return false
	var eye := home.player.camera.global_position
	var offset := entrance_leaf.to_global(Vector3(-.06,1.18,.53))-eye
	return offset.length_squared()<2.8*2.8 and offset.normalized().dot(-home.player.camera.global_basis.z)>.87

func open_entrance() -> void:
	if entry_opened:
		return
	entry_opened = true
	entrance_shape.set_deferred("disabled",true)
	create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(entrance_leaf,"rotation:y",1.48,.58)
	place_audio(entrance_leaf,Vector3(0,1,.75),DOOR_THUD,-17.0,1.6,8.0).play()
	save_story()
	update_objective()

func read_note() -> void:
	note_read = true
	save_story()
	update_objective()
	show_message(tr("Записка · «Убери мусор. $12 под магнитом твои, когда закончишь. Пиво можешь брать сразу.»"),8.0)

func build_follow_up() -> void:
	follow_up = UIKit.panel()
	home.hud.root.add_child(follow_up)
	follow_up.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	follow_up.offset_left = -330
	follow_up.offset_right = 330
	follow_up.offset_top = -204
	follow_up.offset_bottom = -120
	follow_up.mouse_filter = Control.MOUSE_FILTER_IGNORE
	follow_up_text = UIKit.label("",17)
	follow_up_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	follow_up_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	follow_up.add_child(follow_up_text)
	follow_up.hide()

func show_message(text: String, seconds: float) -> void:
	follow_up_text.text = text
	follow_up_left = seconds
	follow_up.show()

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
	var venue_bus: int = home.club.music_bus
	old_club_mute = AudioServer.is_bus_mute(venue_bus)
	AudioServer.set_bus_mute(venue_bus,true)
	var guard := home.club.staff[2] as PartyGuest
	guard_yaw = guard.rotation.y
	guard_tag_visible = guard.name_tag.visible
	guard.name_tag.hide()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

	camera = Camera3D.new()
	camera.cull_mask = home.player.camera.cull_mask
	camera.fov = 55
	camera.near = .06
	home.add_child(camera)
	camera.make_current()
	arrival_car = NightDistrict.place_car(home.night_world.street,1,Vector3(-56.8,0,-17.5))
	arrival_wheels = arrival_car.find_children("Axle-*","Node3D",true,false)
	friend = PartyGuest.new(12,null,home.party.psx_assets)
	home.night_world.street.add_child(friend)
	friend.name_tag.hide()
	home.night_world.point_light(friend,Vector3(0,1.8,-.82),Color("#f5c7a8"),.68,2.7)
	key_prop = Node3D.new()
	friend.add_child(key_prop)
	var ring := TorusMesh.new()
	ring.inner_radius = .013
	ring.outer_radius = .019
	var brass := Color("#e5b971")
	var loop := home.night_world.mesh(key_prop,ring,Vector3.ZERO,brass)
	loop.rotation.x = PI*.5
	home.night_world.box(key_prop,Vector3(0,-.041,0),Vector3(.018,.061,.006),brass)
	home.night_world.box(key_prop,Vector3(.013,-.059,0),Vector3(.019,.012,.006),brass)
	key_prop.hide()
	friend.hide()
	street_sound = AudioStreamPlayer.new()
	street_sound.stream = loop_stream(STREET_BED)
	street_sound.volume_db = -25.0
	add_child(street_sound)
	street_sound.play()
	engine = place_audio(arrival_car,Vector3(0,.70,1.0),loop_stream(ENGINE_BED),-12.0,3.1,22.0)
	engine.play()
	door_sound = place_audio(arrival_car,Vector3(-.90,1.0,.40),DOOR_THUD,-10.0,2.5,16.0)
	var club_door := home.club.to_global(Vector3(Nightclub.ENTRY_X,1.26,Nightclub.ENTRY_Z))
	club_sound = place_audio(home.night_world.street,club_door-origin,loop_stream(CLUB_BED),-24.0,3.5,27.0)
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
	if event.is_action_pressed("pause"):
		finish()
	elif event.is_action_pressed("dialogue_advance"):
		advance_line()
	get_viewport().set_input_as_handled()

func set_line() -> void:
	var row: Array = LINES[line]
	speaker.text = tr(str(row[2])).to_upper()
	subtitle.text = tr(str(row[3]))
	caption.visible = line<2
	phone_card.visible = row[2]=="Old voicemail"
	key_prop.visible = line==13
	line_duration = float(row[1])
	voice.stop()
	voice.stream = null
	kir_voice.stop()
	kir_voice.stream = null
	if subtitle.text.is_empty():
		return
	var path := VOICE_PATH % row[4]
	if not ResourceLoader.exists(path):
		return
	var clip := load(path) as AudioStream
	if clip == null:
		return
	var talking: Node = kir_voice if row[2]=="Kir" else voice
	# Stop first: swapping the stream of a player whose playback has not started yet
	# leaves an orphaned playback in the AudioServer.
	talking.stop()
	talking.stream = clip
	line_duration = maxf(clip.get_length()+.40,float(row[1]))
	talking.play()

func advance_line() -> void:
	if closing:
		return
	if line>=LINES.size()-1:
		closing = true
		close_time = 0.0
		return
	if LINES[line][0]==1 and LINES[line+1][0]==2:
		engine.stop()
		door_sound.play()
	if LINES[line][0]!=LINES[line+1][0]:
		opening_fade = .15
	line += 1
	elapsed = 0.0
	set_line()

func _process(delta: float) -> void:
	if not active:
		if follow_up_left>0:
			follow_up_left -= delta
			if follow_up_left<=0:
				if follow_up_line==1:
					follow_up_line = 2
					show_message(tr("Ты · Я дошёл до дверей. Услышал зал и струсил. Потом соврал про автобус."),6.5)
				elif follow_up_line==2:
					follow_up_line = 0
					show_message(tr("Кир · В следующий раз позвони. Даже если ты всё ещё стоишь у дверей."),6.5)
				else:
					follow_up.hide()
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
	if shot<=1:
		engine.pitch_scale = .82+.31*sin(clampf(running_time/7.8,0.0,1.0)*PI)
		engine.volume_db = -18.0 if voice.playing else -12.0
		arrival_car.position.z = lerpf(-17.5,-7.0,smoothstep(0.0,16.8,running_time))
		for wheel in arrival_wheels:
			if arrival_car.position.z< -7.03:
				wheel.rotate_x(delta*3.0)
		eye = Vector3(-52.0+motion*.38,2.42,-10.5+motion*1.3) if shot==0 else arrival_car.position+Vector3(4.0,3.55,-2.8)
		focus = arrival_car.position+Vector3(-.8,.93,.70)
		friend.hide()
	else:
		arrival_car.position = Vector3(-11.55,0,.55)
		friend.show()
		if shot==2:
			friend.position = Vector3(-12.35,0,3.47)
			eye = Vector3(-10.43,1.73,4.42+motion*.20)
			focus = friend.position+Vector3.UP*1.33
		elif shot in [3,4]:
			var venue := home.club
			arrival_car.position = venue.to_global(Vector3(-.7,0,9.1))-origin
			arrival_car.rotation.y = venue.global_rotation.y+PI*.5
			friend.position = venue.to_global(Vector3(-5.86,0,7.22))-origin
			var guard := venue.staff[2] as PartyGuest
			var turn := guard.position.direction_to(venue.to_local(origin+friend.position))
			guard.rotation.y = lerp_angle(guard.rotation.y,atan2(-turn.x,-turn.z),minf(1.0,delta*2.3))
			if shot==3:
				eye = venue.to_global(Vector3(-6.60+motion*.18,1.88,9.76))-origin
				focus = venue.to_global(Vector3(-4.38,1.89,5.87))-origin
			else:
				eye = venue.to_global(Vector3(-4.56,1.68,7.82+motion*.15))-origin
				focus = friend.position+Vector3.UP*1.46
		else:
			arrival_car.rotation.y = 0
			friend.position = Vector3(-2.67,0,.75)
			if shot==5:
				eye = Vector3(-4.65,1.75,-.48+motion*.20)
				focus = friend.position+Vector3(0,1.29,0)
			else:
				eye = Vector3(-3.85,1.63,-.73+motion*.14)
				focus = Vector3(-.81,1.52,.17)
		var direction := friend.position.direction_to(eye)
		friend.rotation.y = atan2(-direction.x,-direction.z)
		friend.pose(delta,0.0,false)
		if LINES[line][2]=="Kir" and is_instance_valid(friend.imported_model):
			var rig = friend.imported_model
			if line in [6,8,10,13,15,16,18] and rig.arms.size()==2:
				var gesture := sin(clampf(elapsed/2.2,0.0,1.0)*PI)
				var held := Vector3(.27,1.32,.51) if line==13 else Vector3(.36,1.23,.32)
				var wrist := Vector3(.18,.87,.10).lerp(held,gesture if line!=13 else smoothstep(0.0,1.0,elapsed))
				rig.point_arm(rig.arms[0],wrist,Vector3(.85,-.4,-.15))
				if key_prop.visible:
					var bone: Transform3D = rig.skeleton.get_bone_global_pose(rig.arms[0].z)
					key_prop.global_position = rig.skeleton.to_global(bone.origin+Vector3(.015,-.045,.09))
					key_prop.rotation.y = -.23
	camera.global_position = origin+eye
	camera.look_at(origin+focus)

func finish() -> void:
	if not active:
		return
	active = false
	voice.stop()
	voice.stream = null
	kir_voice.stop()
	kir_voice.stream = null
	engine.stop()
	door_sound.stop()
	street_sound.stop()
	club_sound.stop()
	AudioServer.set_bus_mute(home.club.music_bus,old_club_mute)
	var guard := home.club.staff[2] as PartyGuest
	guard.rotation.y = guard_yaw
	guard.name_tag.visible = guard_tag_visible
	layer.hide()
	home.player.camera.make_current()
	for node in [camera,arrival_car,friend,street_sound,club_sound]:
		if is_instance_valid(node):
			node.queue_free()
	camera = null
	arrival_car = null
	arrival_wheels.clear()
	friend = null
	key_prop = null
	street_sound = null
	club_sound = null
	engine = null
	door_sound = null
	kir_voice = null
	if not replay:
		seen = true
		opening_completed = true
		save_story()
		place_at_door()
	home.player.visible = old_player_visible
	home.hud.root.visible = old_hud_visible
	home.set_modal(false)
	update_objective()

func cleanup_complete() -> void:
	if is_instance_valid(cash_envelope):
		cash_envelope.hide()
	if seen and not first_set_done:
		show_message(tr("Кир · Диджей не приехал. Разогрев твой. Скажи Самиру, что ты от меня."),7.0)

func first_booking_complete() -> void:
	if not seen or first_set_done:
		return
	first_set_done = true
	save_story()
	update_objective()
	follow_up_line = 1
	show_message(tr("Кир · Хороший сет. Теперь скажи честно: где ты был в тот вечер?"),6.5)

func save_story() -> void:
	var config := ConfigFile.new()
	config.set_value("story","intro_seen",seen)
	config.set_value("story","opening_completed",opening_completed)
	config.set_value("story","first_set_done",first_set_done)
	config.set_value("story","entry_opened",entry_opened)
	config.set_value("story","note_read",note_read)
	if config.save(SAVE)!=OK:
		push_warning("Не удалось сохранить прогресс вступления")
