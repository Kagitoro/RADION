class_name DJStation
extends Node

const DECK_NAMES := ["A", "B"]
const FACE_SIZE := Vector2(.482,.273)
const FACE_HEIGHT := .041
const CHANNELS := 2
const HOT_CUES := 8

const LAPTOP_PANEL := preload("res://ui/dj/laptop_panel.tscn")

var home: Home
## The venue this station plays in (house Party or Nightclub).
var party: DeckHost
var panel: PanelContainer
var library: VBoxContainer
var controller: Control
var face: MeshInstance3D
var controls_view: SubViewport
var control_camera: Camera3D
var world_hint: Label
var using_controller := false
var last_pointer := Vector2.ZERO
var info: Label
var deck_labels: Array[Label] = []
var positions: Array[HSlider] = []
var titles := ["",""]
var sources := [-1,-1]
var cues := [0.0,0.0]
var loop_starts := [-1.0,-1.0]
var loop_ends := [0.0,0.0]
var bpm_fields: Array[SpinBox] = []
var tempo_faders: Array[VSlider] = []
var loop_buttons: Array[Button] = []
var transport: Array[Button] = []
var time_labels: Array[Label] = []
var paused_decks := [false,false]
var gains := [1.0,1.0]
var trims := [0.0,0.0]
var routing := [0,1]
var hardware_dials: Array[DJDial] = []
var dial_meshes: Array[Node3D] = []
var channel_faders: Array[VSlider] = []
var cross_cap: Node3D
var load_target := -1
var scopes: Array[DeckScope] = []
var laptop_scopes: Array[DeckScope] = []
var laptop_titles: Array[Label] = []
var laptop_times: Array[Label] = []
var laptop_view: SubViewport
var loop_marks := [-1.0,-1.0]
var pad_modes := [0,0]
var pad_mode_buttons: Array[Array] = [[],[]]
var sampler: Array[AudioStreamWAV] = []
var sample_player := AudioStreamPlayer.new()
var channel_meters: Array[ProgressBar] = []
var cue_points := [PackedFloat32Array([-1,-1,-1,-1,-1,-1,-1,-1]),PackedFloat32Array([-1,-1,-1,-1,-1,-1,-1,-1])]
var cue_buttons: Array[Array] = [[],[]]
var echo := AudioEffectDelay.new()
var echo_enabled := false
var echo_beats := .5
var echo_slot := -1
var camera_motion: Tween
var transitioning := false
var eq: Array[AudioEffectEQ6] = []
var low_pass: Array[AudioEffectLowPassFilter] = []
var high_pass: Array[AudioEffectHighPassFilter] = []
var deck_buses: Array[int] = []
var analyzer_slot := -1
var manual := false
var crossfade := -1.0
var cross_slider: HSlider
var bass := 0.0
var bass_phase := 1.0
var bass_average := 0.0
var refresh_delay := 0.0
var music_library := DJLibrary.new(self)
var controller_face := DJControllerFace.new(self)
var laptop_view_builder := DJLaptopView.new(self)

func _init(game_home: Home, station: DeckHost = null) -> void:
	home = game_home
	party = game_home.party if station == null else station

func setup() -> void:
	for index in range(CHANNELS):
		var bus_name := "DJ CH %d" % (index+1) if party == home.party else "Club DJ CH %d" % (index+1)
		var bus := AudioServer.get_bus_index(bus_name)
		if bus<0:
			AudioServer.add_bus()
			bus = AudioServer.bus_count-1
			AudioServer.set_bus_name(bus,bus_name)
		else:
			while AudioServer.get_bus_effect_count(bus)>0:
				AudioServer.remove_bus_effect(bus,0)
		AudioServer.set_bus_send(bus,AudioServer.get_bus_name(party.music_bus))
		deck_buses.append(bus)
		eq.append(AudioEffectEQ6.new())
		low_pass.append(AudioEffectLowPassFilter.new())
		high_pass.append(AudioEffectHighPassFilter.new())
		AudioServer.add_bus_effect(bus,eq[index])
		AudioServer.add_bus_effect(bus,low_pass[index])
		AudioServer.add_bus_effect(bus,high_pass[index])
		var capture := AudioEffectCapture.new()
		capture.buffer_length = .18
		AudioServer.add_bus_effect(bus,capture)
		set_filter(index,0)
	for index in range(2):
		route_deck(index,index)
	var mix_bus: int = party.music_bus
	echo.tap1_active = true
	echo.tap1_level_db = -12
	echo.tap2_active = false
	echo_slot = AudioServer.get_bus_effect_count(mix_bus)
	AudioServer.add_bus_effect(mix_bus,echo)
	AudioServer.set_bus_effect_enabled(mix_bus,echo_slot,false)
	analyzer_slot = AudioServer.get_bus_effect_count(mix_bus)
	AudioServer.add_bus_effect(mix_bus,AudioEffectSpectrumAnalyzer.new())
	build_panel()
	controller_face.build_controller_face()
	laptop_view_builder.build_laptop_display()
	build_sampler()
	music_library.load_folder_setting()

func build_panel() -> void:
	panel = LAPTOP_PANEL.instantiate()
	home.hud.root.add_child(panel)
	panel.get_node("%ControllerButton").pressed.connect(func(): open(false))
	panel.get_node("%CloseButton").pressed.connect(close)
	info = panel.get_node("%Info")
	library = panel.get_node("%Library")
	for index in range(2):
		laptop_view_builder.build_track_display(panel.get_node("%TrackDisplays"),index)
	music_library.build_ui(panel.get_node("%Toolbar"),library)
	panel.hide()

func move_fader(slider: Slider, cap: Node3D, vertical: bool) -> void:
	var rect := slider.get_global_rect()
	var amount := inverse_lerp(slider.min_value,slider.max_value,slider.value)
	var point := rect.get_center()
	if vertical:
		point.y = lerpf(rect.end.y-8,rect.position.y+8,amount)
	else:
		point.x = lerpf(rect.position.x+8,rect.end.x-8,amount)
	var uv := point/Vector2(controls_view.size)
	cap.position = Vector3((uv.x-.5)*FACE_SIZE.x,FACE_HEIGHT+.005,(uv.y-.5)*FACE_SIZE.y)

func face_pointer(camera: Camera3D, pointer: Vector2) -> Vector2:
	var ray := camera.project_ray_origin(pointer)
	var direction := camera.project_ray_normal(pointer)
	var normal := face.global_basis.z.normalized()
	var distance := direction.dot(normal)
	if absf(distance)<.0001:
		return Vector2(-10000,-10000)
	var along := (face.global_position-ray).dot(normal)/distance
	if along<0:
		return Vector2(-10000,-10000)
	var point := face.to_local(ray+direction*along)
	return Vector2(point.x/FACE_SIZE.x+.5,.5-point.y/FACE_SIZE.y)*Vector2(controls_view.size)

func click_controller() -> bool:
	if home.modal or not party.near_deck() or home.player.collapsed or home.player.vomiting:
		return false
	if not aimed_controller():
		return false
	open(false)
	return true

func aimed_controller() -> bool:
	var center := get_viewport().get_visible_rect().size*.5
	var pointer := face_pointer(home.player.camera,center)
	return Rect2(Vector2.ZERO,Vector2(controls_view.size)).has_point(pointer)

func _input(event: InputEvent) -> void:
	if not using_controller:
		return
	if event.is_action_pressed("pause"):
		close()
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		close()
	elif event is InputEventMouse and not transitioning:
		var mapped := face_pointer(control_camera,event.position)
		var forwarded := event.duplicate() as InputEventMouse
		forwarded.position = mapped
		forwarded.global_position = mapped
		if forwarded is InputEventMouseMotion:
			forwarded.relative = mapped-last_pointer
		last_pointer = mapped
		controls_view.push_input(forwarded,true)
	elif event.is_action_pressed("delegate_staff") and party!=home.party:
		(party as Nightclub).shift.assign_staff()
	elif event is InputEventKey:
		controls_view.push_input(event.duplicate(),true)
	else:
		return
	get_viewport().set_input_as_handled()


static func build_laptop(station) -> void:
	var deck: Node3D = station.deck
	var laptop := preload("res://assets/dj/open_laptop.glb").instantiate() as Node3D
	deck.add_child(laptop)
	laptop.position = Vector3(0,.002,-.311)
	var screen := Node3D.new()
	screen.name = "LaptopScreen"
	deck.add_child(screen)
	screen.position = laptop.position+Vector3(0,.1313,-.136)
	screen.rotation.x = -.250


func build_sampler() -> void:
	sample_player.bus = AudioServer.get_bus_name(party.music_bus)
	sample_player.volume_db = -15
	add_child(sample_player)
	for sample in range(8):
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = 22050
		var data := PackedByteArray()
		data.resize(8820)
		var noise := RandomNumberGenerator.new()
		noise.seed = 331+sample
		for i in range(4410):
			var t := float(i)/22050
			var tone := sin(TAU*(62+sample*41)*t+2.6*(1-exp(-t*65)))
			var decay := exp(-t*(22+sample*5))
			var level := lerpf(tone,noise.randf_range(-1,1),float(sample%4)*.23)*decay
			data.encode_s16(i*2,int(level*22000))
		stream.data = data
		sampler.append(stream)

func hot_cue(index: int, slot: int) -> void:
	if Input.is_action_pressed("cue_clear_modifier"):
		cue_points[index][slot] = -1.0
		return
	if not party.music[index].playing:
		return
	if cue_points[index][slot]<0:
		cue_points[index][slot] = deck_position(index)
	else:
		loop_starts[index] = -1.0
		seek(index,cue_points[index][slot])



func set_pad_mode(index: int, mode: int) -> void:
	pad_modes[index] = mode

func press_pad(index: int, slot: int) -> void:
	match int(pad_modes[index]):
		0: hot_cue(index,slot)
		1:
			echo_beats = [.25,.5,1.0][slot%3]
			echo.tap1_level_db = -17+slot*1.5
			toggle_echo()
		2:
			loop_starts[index] = -1.0
			var beats := [-8,-4,-2,-1,1,2,4,8]
			seek(index,deck_position(index)+beats[slot]*60.0/bpm_fields[index].value)
		3:
			sample_player.stream = sampler[slot]
			sample_player.play()

func finish_loop(index: int) -> void:
	var end := deck_position(index)
	if not party.music[index].playing or loop_marks[index]<0 or end-loop_marks[index]<.06:
		return
	loop_starts[index] = loop_marks[index]
	loop_ends[index] = end
	seek(index,loop_starts[index])

func sync_deck(index: int) -> void:
	var other := 1-index
	if not party.music[index].playing or not party.music[other].playing:
		return
	var own_bpm := bpm_fields[index].value
	var other_bpm: float = bpm_fields[other].value*party.music[other].pitch_scale
	tempo_faders[index].value = clampf((1-other_bpm/own_bpm)*10,-1,1)
	var beat_length := 60.0/own_bpm
	var other_phase := fposmod(deck_position(other)*bpm_fields[other].value/60.0,1.0)
	var position := deck_position(index)
	seek(index,floorf(position/beat_length)*beat_length+other_phase*beat_length)






func route_deck(index: int, channel: int) -> void:
	routing[index] = channel
	party.music[index].bus = AudioServer.get_bus_name(deck_buses[channel])

func open(show_files: bool) -> void:
	load_target = -1
	home.set_modal(true)
	panel.visible = show_files
	if show_files and using_controller:
		home.player.camera.make_current()
	using_controller = not show_files
	world_hint.visible = using_controller
	if using_controller:
		var club_view: bool = party != home.party
		var target: Vector3 = party.deck.to_global(Vector3(0,.44,.51) if club_view else Vector3(0,.53,.30))
		var look: Vector3 = party.deck.to_global(Vector3(0,.20,-.18) if club_view else Vector3(0,.075,-.117))
		var destination := Transform3D(Basis.IDENTITY,target).looking_at(look,Vector3.UP)
		control_camera.global_transform = home.player.camera.global_transform
		control_camera.fov = home.player.camera.fov
		control_camera.make_current()
		controls_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		move_camera(destination,65 if club_view else 54,.48)
	else:
		controls_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		if music_library.files.is_empty() and not music_library.scanning:
			music_library.scan_folder()

func open_deck_library(index: int) -> void:
	open(true)
	load_target = index
	info.text = tr("LOAD %s · двойной щелчок загружает трек") % DECK_NAMES[index]

func close() -> void:
	panel.hide()
	if using_controller:
		move_camera(home.player.camera.global_transform,home.player.camera.fov,.34)
		camera_motion.finished.connect(finish_close)
		return
	finish_close()

func finish_close() -> void:
	home.player.camera.make_current()
	controls_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	using_controller = false
	world_hint.hide()
	home.set_modal(false)

func move_camera(destination: Transform3D, fov: float, duration: float) -> void:
	if is_instance_valid(camera_motion):
		camera_motion.kill()
	transitioning = true
	camera_motion = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	camera_motion.tween_property(control_camera,"global_transform",destination,duration)
	camera_motion.tween_property(control_camera,"fov",fov,duration)
	camera_motion.finished.connect(func():
		transitioning = false
		last_pointer = face_pointer(control_camera,get_viewport().get_mouse_position())
	)

func is_open() -> bool:
	return panel.visible or using_controller








func load_file(path: String, index: int, play_now: bool) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var stream: AudioStream
	match path.get_extension().to_lower():
		"mp3": stream = AudioStreamMP3.load_from_file(path)
		"wav": stream = AudioStreamWAV.load_from_file(path)
		"ogg": stream = AudioStreamOggVorbis.load_from_file(path)
	if stream==null or stream.get_length()<=0:
		return false
	var source_bpm: float = stream.bpm if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis else 0
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	else:
		stream.loop = false
		stream.bpm = 0
		stream.beat_count = 0
	engage()
	var player: AudioStreamPlayer = party.music[index]
	player.stop()
	player.stream = stream
	tempo_faders[index].value = 0.0
	player.stream_paused = false
	paused_decks[index] = false
	titles[index] = path.get_file().get_basename()
	sources[index] = -1
	cues[index] = 0.0
	loop_marks[index] = -1.0
	cue_points[index].fill(-1.0)
	loop_starts[index] = -1.0
	bpm_fields[index].value = source_bpm if source_bpm>=40 else 124
	if play_now:
		player.play()
		crossfade = -1.0 if index==0 else 1.0
		cross_slider.set_value_no_signal(crossfade)
		party.track_time = 0
	apply_mix()
	info.text = "%s · %s · %s" % [DECK_NAMES[index],titles[index],format_time(stream.get_length())]
	if stream.get_length()<10:
		info.text += tr(" · Короткий файл")
	return true

func engage() -> void:
	if manual:
		return
	manual = true
	if is_instance_valid(party.fader):
		party.fader.kill()
	for index in range(2):
		if index==party.playing and party.music[index].playing:
			titles[index] = party.track_titles()[party.track]
			sources[index] = party.track
			bpm_fields[index].value = party.track_bpm()[party.track]
		else:
			party.music[index].stop()
	crossfade = -1.0 if party.playing==0 else 1.0
	cross_slider.set_value_no_signal(crossfade)
	apply_mix()

func use_builtin() -> void:
	manual = false
	for bus in deck_buses:
		AudioServer.set_bus_volume_db(bus,0.0)
	for index in range(2):
		titles[index] = ""
		sources[index] = -1
		cue_points[index].fill(-1.0)
		loop_starts[index] = -1.0
		loop_marks[index] = -1.0
		paused_decks[index] = false
		party.music[index].stream_paused = false
		tempo_faders[index].value = 0.0

func has_playback() -> bool:
	return party.music.any(func(player): return player.playing and not player.stream_paused)

func audible_deck() -> int:
	if not manual:
		return party.playing
	var weights := mix_weights()
	for index in range(2):
		if not party.music[index].playing or party.music[index].stream_paused:
			weights[index] = -1.0
	return 1 if weights[1]>weights[0] else 0

func mix_weights() -> Vector2:
	var angle := (crossfade+1)*PI*.25
	return Vector2(cos(angle)*gains[routing[0]],sin(angle)*gains[routing[1]])

func apply_mix() -> void:
	var weights := mix_weights()
	for index in range(2):
		party.music[index].volume_db = -13+trims[routing[index]]
		AudioServer.set_bus_volume_db(deck_buses[routing[index]],linear_to_db(maxf(.0001,weights[index])))

func toggle_deck(index: int) -> void:
	engage()
	var player: AudioStreamPlayer = party.music[index]
	if titles[index].is_empty():
		info.text = tr("Загрузи трек из ноутбука в деку %s.") % DECK_NAMES[index]
		return
	if not player.playing:
		player.play(cues[index])
		paused_decks[index] = false
	else:
		paused_decks[index] = not paused_decks[index]
	player.stream_paused = paused_decks[index]

func deck_position(index: int) -> float:
	return party.music[index].get_playback_position()

func seek(index: int, seconds: float) -> void:
	var player: AudioStreamPlayer = party.music[index]
	if player.playing:
		player.seek(clampf(seconds,0,maxf(0,player.stream.get_length()-.02)))

func toggle_loop(index: int) -> void:
	engage()
	var player: AudioStreamPlayer = party.music[index]
	if loop_starts[index]>=0:
		loop_starts[index] = -1.0
	elif player.playing:
		var start := deck_position(index)
		loop_starts[index] = start
		loop_ends[index] = minf(player.stream.get_length()-.03,start+240.0/bpm_fields[index].value)
		if loop_ends[index]-start<.06:
			loop_starts[index] = -1.0

func set_eq(value: float, index: int, band: int) -> void:
	engage()
	var gain := value*12.0 if value>=0 else value*30.0
	eq[index].set_band_gain_db(band*2,gain)
	eq[index].set_band_gain_db(band*2+1,gain)

func toggle_echo() -> void:
	echo_enabled = not echo_enabled
	AudioServer.set_bus_effect_enabled(party.music_bus,echo_slot,echo_enabled)

func set_filter(index: int, value: float) -> void:
	var bus := deck_buses[index]
	AudioServer.set_bus_effect_enabled(bus,1,value<-.01)
	AudioServer.set_bus_effect_enabled(bus,2,value>.01)
	low_pass[index].cutoff_hz = 18000*pow(.012,-minf(value,0))
	high_pass[index].cutoff_hz = 30*pow(130,maxf(value,0))

func current_title() -> String:
	return titles[audible_deck()] if manual else party.track_titles()[party.track]

func current_builtin() -> int:
	return sources[audible_deck()] if manual else party.track

func dance_phase() -> float:
	var deck := audible_deck()
	return fposmod(deck_position(deck)*bpm_fields[deck].value/60.0,1.0)

func update_bass(delta: float) -> void:
	var instance := AudioServer.get_bus_effect_instance(party.music_bus,analyzer_slot) as AudioEffectSpectrumAnalyzerInstance
	var sample := 0.0
	if instance!=null and has_playback():
		var channels := instance.get_magnitude_for_frequency_range(38,155)
		sample = maxf(channels.x,channels.y)
	bass = lerpf(bass,clampf(sample*30,0,1),minf(1,delta*12))
	bass_phase = minf(1,bass_phase+delta*2.2)
	if bass_phase>.42 and sample>maxf(.004,bass_average*1.55):
		bass_phase = 0.0
	bass_average = lerpf(bass_average,sample,minf(1,delta*2))

func _process(delta: float) -> void:
	if not is_instance_valid(panel):
		return
	if music_library.scanning:
		music_library.scan_step()
	for index in range(2):
		if loop_starts[index]>=0 and party.music[index].playing and deck_position(index)>=loop_ends[index]:
			seek(index,loop_starts[index])
	update_bass(delta)
	if echo_enabled:
		var bpm: float = bpm_fields[audible_deck()].value if manual else party.track_bpm()[party.track]
		echo.tap1_delay_ms = 60000.0/bpm*echo_beats
	if not using_controller and not party.near_deck():
		return
	refresh_delay -= delta
	if refresh_delay>0:
		return
	refresh_delay = .10
	var channel_samples: Array[PackedVector2Array] = []
	for channel in range(CHANNELS):
		var bus := deck_buses[channel]
		var capture := AudioServer.get_bus_effect(bus,3) as AudioEffectCapture
		var available := capture.get_frames_available()
		channel_samples.append(capture.get_buffer(mini(available,4096)) if available>0 else PackedVector2Array())
		capture.clear_buffer()
		var peak := maxf(AudioServer.get_bus_peak_volume_left_db(bus,0),AudioServer.get_bus_peak_volume_right_db(bus,0))
		channel_meters[channel].value = clampf((peak+48.0)/48.0,0,1)
	if is_instance_valid(cross_cap):
		move_fader(cross_slider,cross_cap,false)
	if not using_controller:
		controls_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	laptop_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	for index in range(2):
		var player: AudioStreamPlayer = party.music[index]
		scopes[index].samples = channel_samples[routing[index]] if player.playing and not player.stream_paused else PackedVector2Array()
		scopes[index].queue_redraw()
		laptop_scopes[index].samples = scopes[index].samples
		laptop_scopes[index].queue_redraw()
		for mode in range(4):
			pad_mode_buttons[index][mode].set_pressed_no_signal(pad_modes[index]==mode)
		for slot in range(HOT_CUES):
			cue_buttons[index][slot].set_pressed_no_signal(pad_modes[index]==0 and cue_points[index][slot]>=0)
		var title: String = titles[index] if manual else (party.track_titles()[party.track] if player.playing else "")
		deck_labels[index].text = title if not title.is_empty() else tr("Дека пуста")
		loop_buttons[index].set_pressed_no_signal(loop_starts[index]>=0)
		transport[index].tooltip_text = "PAUSE" if player.playing and not player.stream_paused else "PLAY"
		var length: float = player.stream.get_length() if player.stream!=null else 0.0
		positions[index].max_value = length
		time_labels[index].text = "%s / %s" % [format_time(deck_position(index)),format_time(length)]
		laptop_titles[index].text = "%s   %s" % [DECK_NAMES[index],deck_labels[index].text]
		laptop_times[index].text = "%s     %.1f BPM" % [time_labels[index].text,bpm_fields[index].value*player.pitch_scale]
		if not positions[index].has_focus() or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			positions[index].set_value_no_signal(deck_position(index))

func format_time(seconds: float) -> String:
	var whole := int(seconds)
	return "%02d:%02d" % [whole/60,whole%60]

