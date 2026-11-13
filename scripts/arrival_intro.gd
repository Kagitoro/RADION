class_name ArrivalIntro
extends Node

static var SAVE := SavePaths.file("radion_story.cfg")
const VOICE_PATH := "res://assets/story/voice/%s.mp3"
const STREET_BED = preload("res://assets/story/ambience/street.mp3")
const ENGINE_BED = preload("res://assets/story/ambience/engine.mp3")
const DOOR_THUD = preload("res://assets/story/ambience/door.mp3")
const CLUB_BED = preload("res://assets/story/ambience/club_outside.mp3")
const Cabin = preload("res://scripts/arrival_cabin.gd")
const PhoneUI = preload("res://scripts/arrival_phone_ui.gd")
const Highway = preload("res://scripts/arrival_highway.gd")
const DISTANT_KIR := preload("res://assets/story/voice/acted_wakeup.mp3")
const EXTERIOR_END := 4.55
const WAKE_CALL := 5.40
const PHONE_TAPS := [
	[2.84,Vector2(264,550),PhoneUI.Page.DECLINED],
	[4.18,Vector2(264,530),PhoneUI.Page.INBOX],
	[5.66,Vector2(282,258),PhoneUI.Page.THREAD],
	[7.43,Vector2(282,413),PhoneUI.Page.PLAYBACK],
]
const CLEAR_WAKE_LINE := 9.16
const VOICEMAIL_PLAY := 7.58
const PHONE_LINE := 4
const EXIT_LINE := 8
const KEY_LINE := 16
const LINES := [
	[0,13.2,"You","[Exhales] What's up?","acted_groggy"],
	[0,3.1,"Kir","Man, you slept through my whole damn playlist.","acted_playlist"],
	[0,2.5,"You","Yeah? Guess I got lucky.","acted_lucky"],
	[0,3.7,"Kir","Get outta here. That's our exit, by the way.","acted_exit"],
	[1,5.0,"Old voicemail","Hey. Where are you?! You said ten minutes. We've been waiting forty! I put Nico on. Call me back.","acted_maya"],
	[1,4.3,"Kir","Was that Maya from your old club? I thought you two were done talking.","acted_food"],
	[1,2.3,"You","We are. She wants to know why I never showed.","acted_chew"],
	[1,2.8,"Kir","Oh. Yeah, okay. We can talk about it after we get you some food.","acted_heard"],
	[7,7.5,"","",""],
	[2,4.2,"Kir","Easy with the door, man. It's older than both of us.","acted_door"],
	[2,3.5,"You","So who's waiting on me?","acted_waiting"],
	[3,6.0,"Kir","See Samir by the door? I gave him your name. If the opener flakes, you get twenty minutes.","acted_slot"],
	[3,3.5,"You","You gave him my name already?","acted_name"],
	[3,4.8,"Kir","Yeah, because if I asked, you'd find a reason to say no. I know you, man.","acted_promise"],
	[4,3.6,"You","Oh, shit… when do I go on?","acted_when"],
	[4,4.0,"Kir","Tonight. Keep your phone on, all right? Do me that one favor.","acted_tonight"],
	[5,5.5,"Kir","Here, catch. Front door key. Controller's in the bedroom. You bring your tracks?","acted_keys"],
	[5,3.8,"You","Two tracks. One clean shirt. Clean-ish.","acted_shirt"],
	[5,4.4,"Kir","Look at you. Warm the room up first. Save the big stuff for later.","acted_warm"],
	[6,5.5,"Kir","Oh, and there's a note on the fridge. Read it before you open anything that smells funny.","acted_note"],
	[6,3.2,"You","You could've led with that.","acted_led"],
	[6,3.7,"Kir","And miss that face? Nah. See you at the club, man.","acted_goodbye"],
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
var wake_mask: ColorRect
var cabin: Cabin
var city_entry: Node3D
var highway: Highway
var headlights: Array[SpotLight3D] = []
var headlight_mount: Node3D
var arrival_wheels: Array[Node] = []
var wake_voice := AudioStreamPlayer.new()
var ringtone := AudioStreamPlayer.new()
var wake_played := false
var ring_played := false
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
var voice := AudioStreamPlayer.new()
var dialogue: Dictionary[String,AudioStream] = {}
var voice_pending := false
var voice_lead := 0.0
var driving_clock := 0.0
var cabin_glance := 0.0
var line_duration := 0.0
var exit_sound_step := 0
var exit_steps: AudioStreamPlayer3D
const HOME_PARK := Vector3(-7.7,0,-.30)
const KEY_EYE := Vector3(-4.18,1.59,-.27)
const FIRST_PARK := Vector3(-13.05,0,2.10)
const FIRST_KIR := Vector3(-12.35,0,3.47)
const FIRST_EYE := Vector3(-10.43,1.73,4.42)
var arrival_car: Node3D
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
	add_child(wake_voice)
	wake_voice.stream = DISTANT_KIR
	wake_voice.volume_db = -3.5
	add_child(ringtone)
	ringtone.stream = make_ringtone()
	ringtone.volume_db = -13.0
	for row in LINES:
		var clip_name: String = row[4]
		if clip_name.is_empty():
			continue
		var clip := load(VOICE_PATH % clip_name) as AudioStream
		if clip != null:
			dialogue[clip_name] = clip

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
	wake_mask = ColorRect.new()
	layer.get_node("Root").add_child(wake_mask)
	wake_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wake_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform float eyelids = 0.0; void fragment() { float edge = (1.0 - eyelids) * 0.53; float distance = abs(UV.y - 0.49) + pow(abs(UV.x - 0.5), 2.0) * 0.13; COLOR = vec4(0.008,0.009,0.013, smoothstep(edge - 0.065, edge + 0.026, distance)); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	wake_mask.material = material
	wake_mask.hide()
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
	driving_clock = 0.0
	exit_sound_step = 0
	wake_played = false
	ring_played = false
	cabin_glance = 0.0
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
	arrival_car = NightDistrict.place_car(home.night_world.street,1,Vector3(Highway.LANE_X,0,Highway.START_Z))
	arrival_wheels = arrival_car.find_children("Axle-*","Node3D",true,false)
	highway = Highway.new()
	home.night_world.street.add_child(highway)
	highway.build(home.night_world)
	home.night_world.district.highway_gate.hide()
	headlight_mount = Node3D.new()
	highway.add_child(headlight_mount)
	for side in [-1,1]:
		var light := SpotLight3D.new()
		light.position = Vector3(side*.66,.63,1.91)
		light.rotation = Vector3(-.085,PI,0)
		light.light_color = Color("#ffe7c4")
		light.light_energy = 1.1
		light.spot_angle = 43
		light.spot_range = 27
		headlight_mount.add_child(light)
		headlights.append(light)
	cabin = Cabin.new()
	home.night_world.street.add_child(cabin)
	cabin.position = arrival_car.position
	cabin.build(home.night_world)
	build_city_entry()
	friend = PartyGuest.new(12,null,home.party.psx_assets)
	home.night_world.street.add_child(friend)
	friend.name_tag.hide()
	home.night_world.point_light(friend,Vector3(0,1.8,-.82),Color("#f5c7a8"),.68,2.7)
	key_prop = Node3D.new()
	friend.add_child(key_prop)
	key_prop.scale = Vector3.ONE*.78
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
	exit_steps = place_audio(cabin,Vector3.ZERO,null,-16.0,2.0,9.0)
	var club_door := home.club.to_global(Vector3(Nightclub.ENTRY_X,1.26,Nightclub.ENTRY_Z))
	club_sound = place_audio(home.night_world.street,club_door-origin,loop_stream(CLUB_BED),-24.0,3.5,27.0)
	club_sound.play()
	layer.show()
	set_line()
	update_shot(0.0)

func loop_stream(source: AudioStreamMP3) -> AudioStreamMP3:
	var stream := source.duplicate() as AudioStreamMP3
	stream.loop = true
	return stream

func make_ringtone() -> AudioStreamWAV:
	var sample := AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = 22050
	var count := roundi(sample.mix_rate*2.65)
	var data := PackedByteArray()
	data.resize(count*2)
	for index in range(count):
		var time := float(index)/sample.mix_rate
		var phrase := fposmod(time,1.28)
		var note := int(phrase/.19)
		var tone := 0.0
		if note<4:
			var attack := fposmod(phrase,.19)
			var hz: float = [523.25,659.25,783.99,659.25][note]
			var envelope := smoothstep(0,.012,attack)*exp(-attack*16)
			tone = (sin(TAU*hz*time)+.28*sin(TAU*hz*2*time))*envelope*.41
		var motor := (sin(TAU*145*time)+.18*sin(TAU*290*time))*.15
		motor *= smoothstep(0,.035,phrase)*(1.0-smoothstep(.56,.65,phrase))
		data.encode_s16(index*2,roundi(clampf(tone+motor,-1,1)*32767))
	sample.data = data
	return sample

func build_city_entry() -> void:
	var world := home.night_world
	city_entry = Node3D.new()
	world.street.add_child(city_entry)
	city_entry.position = Vector3(-55.30,0,-15.0)
	var metal := Color("#4a525c")
	world.box(city_entry,Vector3(-3.27,1.36,0),Vector3(.085,2.72,.085),metal)
	world.box(city_entry,Vector3(3.27,1.36,0),Vector3(.085,2.72,.085),metal)
	world.box(city_entry,Vector3(0,2.71,0),Vector3(6.60,.085,.085),metal)
	world.box(city_entry,Vector3(0,2.34,0),Vector3(1.57,.63,.062),Color("#294740"))
	world.box(city_entry,Vector3(0,2.62,-.035),Vector3(1.51,.016,.009),Color("#a4b4a1"))
	world.box(city_entry,Vector3(0,2.07,-.035),Vector3(1.51,.016,.009),Color("#a4b4a1"))
	world.add_sign(city_entry,"NIGHT DISTRICT",Vector3(0,2.43,-.039),Vector3(0,PI,0),Color("#ecf0d6"),.0034)
	world.add_sign(city_entry,"8 AVE  ↑",Vector3(0,2.23,-.039),Vector3(0,PI,0),Color("#d0e4cf"),.0024)
	world.point_light(city_entry,Vector3(.12,2.61,-.44),Color("#e0ecd6"),.53,3.8)

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
	if event.is_echo():
		get_viewport().set_input_as_handled()
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
	caption.visible = line<PHONE_LINE
	key_prop.visible = line==KEY_LINE
	line_duration = float(row[1])
	voice.stop()
	wake_voice.stop()
	ringtone.stop()
	var clip: AudioStream = dialogue.get(row[4])
	voice.stream = clip
	voice_pending = clip != null
	if clip == null:
		return
	voice_lead = CLEAR_WAKE_LINE if line==0 else (VOICEMAIL_PLAY if line==PHONE_LINE else .19)
	if line==0:
		voice_lead = maxf(voice_lead,WAKE_CALL+DISTANT_KIR.get_length()+.28)
	voice.volume_db = -1.0 if row[2]=="Old voicemail" else 0.0
	line_duration = clip.get_length()+voice_lead+(.74 if row[2]=="Old voicemail" else .53)
	if line==0:
		line_duration = maxf(line_duration,float(row[1]))

func advance_line() -> void:
	if closing:
		return
	if line>=LINES.size()-1:
		closing = true
		close_time = 0.0
		return
	if line+1==EXIT_LINE:
		engine.stop()
	if LINES[line][0]!=LINES[line+1][0] and LINES[line+1][0]!=1 and line!=EXIT_LINE:
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
	if line==0 and not wake_played and elapsed>=WAKE_CALL:
		wake_played = true
		wake_voice.play()
	if line==PHONE_LINE and not ring_played and elapsed>=.12:
		ring_played = true
		ringtone.play()
	if voice_pending and elapsed>=voice_lead and not wake_voice.playing:
		voice_pending = false
		voice.play()
	if elapsed>=line_duration and (not voice.playing or elapsed>=line_duration+1.0):
		advance_line()
		if closing:
			return
	var speaking := voice_pending or voice.playing
	var inside: bool = LINES[line][0]<=1
	street_sound.volume_db = move_toward(street_sound.volume_db,-37.0 if inside else (-32.0 if speaking else -23.0),delta*25.0)
	club_sound.volume_db = move_toward(club_sound.volume_db,-40.0 if inside else (-29.0 if speaking else -20.0),delta*25.0)
	opening_fade = maxf(0,opening_fade-delta)
	var eyelids := 0.0
	if line==0:
		eyelids = smoothstep(4.10,EXTERIOR_END,elapsed)*(1.0-smoothstep(6.53,8.75,elapsed))
		eyelids += .23*(smoothstep(7.92,8.22,elapsed)-smoothstep(8.27,8.64,elapsed))
		var waking := elapsed>=WAKE_CALL and wake_voice.playing
		subtitle.text = "Heeey, man… You with me?" if waking else str(LINES[0][3])
		speaker.text = "KIR" if waking else "YOU"
		subtitle.visible = waking or elapsed>=voice_lead
		speaker.visible = subtitle.visible
	else:
		subtitle.visible = line!=PHONE_LINE or elapsed>=voice_lead
		speaker.visible = subtitle.visible
	wake_mask.visible = line==0 and elapsed>=EXTERIOR_END and eyelids>.035
	if wake_mask.visible:
		wake_mask.material.set_shader_parameter("eyelids",eyelids)
	fade.color.a = maxf(pow(eyelids,2.8),clampf(opening_fade/.9,0,1))
	update_shot(delta)

func update_shot(delta: float) -> void:
	var shot: int = LINES[line][0]
	if line==EXIT_LINE:
		update_first_exit(delta)
		return
	var motion := sin(running_time*.18)
	var eye := Vector3.ZERO
	var focus := Vector3.ZERO
	if shot<=1:
		driving_clock += delta
		var speed := Highway.speed(cabin.position.z)
		speed *= lerpf(.20,1.0,smoothstep(0.0,6.5,17.9-cabin.position.z))
		if line==7:
			speed = lerpf(speed,.65,smoothstep(0.0,line_duration,elapsed))
		cabin.position.z += speed*delta
		if cabin.position.z>17.9:
			cabin.position.z = 17.9
		cabin.position.x = Highway.LANE_X+sin(driving_clock*.56)*.072
		cabin.position.y = sin(driving_clock*5.6)*.002
		cabin.rotation.y = cos(driving_clock*.56)*.013
		arrival_car.position = cabin.position
		arrival_car.rotation.y = cabin.rotation.y
		headlight_mount.transform = cabin.transform
		var exterior := line==0 and elapsed<EXTERIOR_END
		arrival_car.visible = exterior
		cabin.visible = not exterior
		for light in headlights:
			light.visible = true
		var sleeping := line==0 and elapsed>=EXTERIOR_END and elapsed<7.7
		engine.pitch_scale = lerpf(.76,1.13,speed/22.0)
		var engine_db := -13.0 if exterior else (-32.0 if sleeping else (-27.0 if voice.playing else -20.0))
		engine.volume_db = move_toward(engine.volume_db,engine_db,delta*19.0)
		if exterior:
			for wheel_node in arrival_wheels:
				wheel_node.rotate_x(delta*speed/.44)
			camera.fov = 55.0
			camera.global_position = cabin.to_global(Vector3(2.45,1.04,-5.35+elapsed*.21))
			camera.look_at(cabin.to_global(Vector3(-.05,1.12,.95)))
			friend.hide()
			return
		var clip_length := voice.stream.get_length() if voice.stream != null else line_duration
		var clip_time := voice.get_playback_position() if voice.playing else (clip_length if line==PHONE_LINE and not voice_pending else 0.0)
		var phone_view := PhoneUI.Page.OFF
		var tap_position := Vector2.ZERO
		var touch := 0.0
		var reach := 0.0
		if line==PHONE_LINE and elapsed>.29:
			phone_view = PhoneUI.Page.CALL
			for tap in PHONE_TAPS:
				var at: float = tap[0]
				if elapsed>=at+.10:
					phone_view = tap[2]
				if absf(elapsed-at)<.62:
					tap_position = tap[1]
					reach = smoothstep(at-.62,at-.28,elapsed)*(1.0-smoothstep(at+.24,at+.61,elapsed))
					touch = smoothstep(at-.19,at-.025,elapsed)*(1.0-smoothstep(at+.04,at+.24,elapsed))
		cabin.update_pose(delta,driving_clock,phone_view,clampf(clip_time/maxf(.1,clip_length),0,1),tap_position,reach,touch,wake_voice.playing or (LINES[line][2]=="Kir" and voice.playing))
		var look := smoothstep(0.0,1.0,cabin.phone_amount)
		var sleepy := 1.0-smoothstep(6.55,10.0,elapsed) if line==0 else 0.0
		var base_eye := Cabin.EYE+Vector3(-sleepy*.11,sin(driving_clock*2.5)*.004-sleepy*.18,-sleepy*.07)+Vector3(0,-.033,.046)*look
		eye = cabin.to_global(base_eye)-origin
		cabin_glance = move_toward(cabin_glance,1.0 if line in [1,2,3,5,6,7] else 0.0,delta*1.48)
		var gaze := Vector3(-.31,1.34,2.9).lerp(Vector3(.46,1.36,-.19),smoothstep(0,1,cabin_glance)*.98)
		gaze = gaze.lerp(Vector3(-.57,.87,1.55),sleepy)
		focus = cabin.to_global(gaze.lerp(cabin.phone.position,look))-origin
		camera.fov = lerpf(68.0,48.0,look)
		friend.hide()
	else:
		cabin.hide()
		arrival_car.show()
		for light in headlights:
			light.hide()
		camera.fov = 55.0
		arrival_car.position = Vector3(-11.55,0,.55)
		friend.show()
		if shot==2:
			arrival_car.hide()
			cabin.position = FIRST_PARK
			cabin.show()
			cabin.parked_details.show()
			cabin.driver.hide()
			cabin.set_exit_doors(0,0)
			friend.position = FIRST_KIR
			eye = FIRST_EYE
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
			arrival_car.hide()
			cabin.position = HOME_PARK
			cabin.rotation = Vector3.ZERO
			cabin.show()
			cabin.parked_details.show()
			cabin.driver.hide()
			cabin.set_exit_doors(0.0,0.0)
			friend.position = Vector3(-2.67,0,.75)
			if shot==5:
				eye = Vector3(-4.65,1.75,-.48+motion*.20)
				focus = friend.position+Vector3(0,1.29,0)
				if line==KEY_LINE:
					eye = KEY_EYE
					focus = friend.position+Vector3(0,1.25,0)
			else:
				eye = Vector3(-3.85,1.63,-.73+motion*.14)
				focus = Vector3(-.81,1.52,.17)
		var direction := friend.position.direction_to(eye)
		friend.rotation.y = atan2(-direction.x,-direction.z)
		var rig := friend.imported_model as GuestModel
		if rig != null:
			rig.pose(delta,false,1.0,false,0.0)
			if line in [9,11,13,KEY_LINE,18,19,21] and rig.arms.size()==2:
				var gesture := sin(clampf(elapsed/2.2,0.0,1.0)*PI)
				var held := Vector3(.28,1.31,.43) if line==KEY_LINE else Vector3(.36,1.23,.32)
				var wrist := Vector3(.18,.87,.10).lerp(held,gesture if line!=KEY_LINE else smoothstep(0.0,.9,elapsed))
				rig.point_arm(rig.arms[0],wrist,Vector3(.85,-.4,-.15))
				if key_prop.visible:
					var hand := rig.skeleton.get_bone_global_pose(rig.arms[0].z)
					var pinch := rig.skeleton.to_global(hand*Vector3(.016,.107,-.012))
					var toward_view := pinch.direction_to(origin+eye)
					key_prop.global_position = pinch+toward_view*.028+Vector3.DOWN*.045
					key_prop.rotation = Vector3(.055*sin(elapsed*6),.16,.075*sin(elapsed*7.5))
		else:
			friend.pose(delta,0.0,false)
	camera.global_position = origin+eye
	camera.look_at(origin+focus)
	if line==0:
		camera.rotate_object_local(Vector3.BACK,-.21*(1.0-smoothstep(6.55,10.0,elapsed)))

func update_first_exit(delta: float) -> void:
	var stop := smoothstep(0.0,1.24,elapsed)
	cabin.position = FIRST_PARK+Vector3(0,0,-2.1*(1.0-stop))
	cabin.rotation = Vector3.ZERO
	cabin.show()
	cabin.parked_details.show()
	arrival_car.position = cabin.position
	arrival_car.hide()
	headlight_mount.transform = cabin.transform
	for light in headlights:
		light.visible = elapsed<1.36
	if elapsed<1.37 and not engine.playing:
		engine.volume_db = -23
		engine.pitch_scale = .78
		engine.play()
	if elapsed>=1.37 and engine.playing:
		engine.stop()
	var passenger_open := smoothstep(1.63,2.28,elapsed)*(1.0-smoothstep(3.70,4.20,elapsed))
	var driver_open := smoothstep(1.49,2.16,elapsed)*(1.0-smoothstep(2.94,3.44,elapsed))
	cabin.set_exit_doors(passenger_open,driver_open)
	var driver_step := smoothstep(2.03,2.82,elapsed)
	cabin.driver.visible = elapsed<2.82
	cabin.update_pose(delta,running_time,PhoneUI.Page.OFF,0,Vector2.ZERO,0,0,false)
	cabin.reach_exit_handle(smoothstep(1.29,1.65,elapsed)*(1.0-smoothstep(1.92,2.40,elapsed)))
	cabin.driver.position = Vector3(.42,-.26,-.27).lerp(Vector3(1.18,0,-.20),driver_step)
	cabin.driver.rotation.y = lerp_angle(PI,-PI*.5,driver_step)
	if driver_step>0 and cabin.driver.visible:
		var driver_rig := cabin.driver.imported_model as GuestModel
		if driver_rig != null:
			driver_rig.pose(0,false,1,false,0)
			for side in ["Left","Right"]:
				driver_rig.rotate_local(side+"UpLeg",Vector3(-1.20,0,0)*(1.0-driver_step))
				driver_rig.rotate_local(side+"Leg",Vector3(1.52,0,0)*(1.0-driver_step))
	var driver_walk := smoothstep(2.82,5.46,elapsed)
	friend.visible = elapsed>=2.82
	var driver_start := FIRST_PARK+Vector3(1.18,0,-.20)
	var driver_corner := FIRST_PARK+Vector3(1.18,0,.98)
	friend.position = driver_start.lerp(driver_corner,smoothstep(0,.67,driver_walk))
	friend.position = friend.position.lerp(FIRST_KIR,smoothstep(.48,1,driver_walk))
	var turn := smoothstep(4.75,5.50,elapsed)
	var facing := FIRST_KIR.direction_to(FIRST_EYE)
	friend.rotation.y = lerp_angle(-PI*.5,atan2(-facing.x,-facing.z),turn)
	friend.pose(delta,0.0,elapsed>2.82 and elapsed<5.38)
	var eye := Cabin.EYE
	eye = eye.lerp(Vector3(-.72,1.22,-.43),smoothstep(1.47,2.23,elapsed))
	eye = eye.lerp(Vector3(-1.52,1.58,-.50),smoothstep(2.26,3.47,elapsed))
	eye = eye.lerp(Vector3(-1.52,1.61,2.45),smoothstep(4.12,5.73,elapsed))
	eye = eye.lerp(Vector3(.42,1.60,2.45),smoothstep(5.48,6.43,elapsed))
	eye = eye.lerp(FIRST_EYE-FIRST_PARK,smoothstep(6.25,7.46,elapsed))
	var walk := smoothstep(4.10,4.48,elapsed)*(1.0-smoothstep(7.10,7.43,elapsed))
	eye.y += sin(elapsed*TAU*2.04)*.016*walk
	var look := Vector3(-.38,1.30,2.7).lerp(Vector3(-1.75,.88,-.28),smoothstep(1.12,1.70,elapsed))
	look = look.lerp(Vector3(-.90,1.04,-.05),smoothstep(2.53,3.67,elapsed))
	look = look.lerp(Vector3(-1.43,1.45,3.8),smoothstep(3.90,4.70,elapsed))
	look = look.lerp(friend.position-FIRST_PARK+Vector3.UP*1.33,smoothstep(5.05,6.48,elapsed))
	camera.fov = lerpf(68.0,55.0,smoothstep(6.20,7.46,elapsed))
	camera.global_position = cabin.to_global(eye)
	camera.look_at(cabin.to_global(look))
	var beats := [1.63,3.13,4.17,4.41,4.86,5.31,5.76,6.21,6.66,7.10]
	if exit_sound_step<beats.size() and elapsed>=beats[exit_sound_step]:
		if exit_sound_step in [0,2]:
			door_sound.pitch_scale = .84 if exit_sound_step==0 else 1.0
			door_sound.play()
		else:
			exit_steps.global_position = camera.global_position-Vector3.UP*1.55
			exit_steps.stream = home.player.steps["wood"][exit_sound_step%3]
			exit_steps.play()
		exit_sound_step += 1

func finish() -> void:
	if not active:
		return
	active = false
	voice.stop()
	wake_voice.stop()
	ringtone.stop()
	voice.stream = null
	voice_pending = false
	engine.stop()
	door_sound.stop()
	street_sound.stop()
	club_sound.stop()
	AudioServer.set_bus_mute(home.club.music_bus,old_club_mute)
	home.night_world.district.highway_gate.show()
	var guard := home.club.staff[2] as PartyGuest
	guard.rotation.y = guard_yaw
	guard.name_tag.visible = guard_tag_visible
	layer.hide()
	home.player.camera.make_current()
	for node in [camera,arrival_car,cabin,highway,city_entry,friend,street_sound,club_sound]:
		if is_instance_valid(node):
			node.queue_free()
	camera = null
	arrival_car = null
	cabin = null
	highway = null
	headlight_mount = null
	headlights.clear()
	arrival_wheels.clear()
	city_entry = null
	friend = null
	key_prop = null
	street_sound = null
	club_sound = null
	engine = null
	door_sound = null
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
