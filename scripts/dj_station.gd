extends Node

const FORMATS := ["mp3", "wav", "ogg"]
const CONFIG := "user://dj_library.cfg"
const DECK_NAMES := ["A", "B"]
const FACE_SIZE := Vector2(.482,.273)
const FACE_HEIGHT := .041
const CHANNELS := 2
const HOT_CUES := 8

class DeckScope extends Control:
	var samples := PackedVector2Array()

	func _ready() -> void:
		custom_minimum_size.y = maxf(68,custom_minimum_size.y)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var middle := size.y*.5
		draw_line(Vector2(0,middle),Vector2(size.x,middle),Color("#24465d"))
		if samples.is_empty():
			return
		for column in range(100):
			var peak := 0.0
			var first := column*samples.size()/100
			var last := (column+1)*samples.size()/100
			for index in range(first,last):
				peak = maxf(peak,maxf(absf(samples[index].x),absf(samples[index].y)))
			var fraction := float(column)/99.0
			var x := fraction*size.x
			var height := clampf(peak*5.5,.01,1)*middle
			var tint := Color("#48cafa").lerp(Color("#e374ff"),fraction)
			draw_line(Vector2(x,middle-height),Vector2(x,middle+height),tint,2,true)

class Dial extends Control:
	signal changed(value: float)
	var value := 0.0
	var dragging := false
	var jog := false

	func _ready() -> void:
		mouse_default_cursor_shape = Control.CURSOR_DRAG

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index==MOUSE_BUTTON_LEFT:
				dragging = event.pressed
				if event.double_click and not jog:
					set_value(0.0)
				accept_event()
			elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
				adjust(.08 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -.08)
				accept_event()
		elif event is InputEventMouseMotion and dragging and event.button_mask&MOUSE_BUTTON_MASK_LEFT:
			adjust((event.relative.x-event.relative.y)*.009)
			accept_event()

	func adjust(amount: float) -> void:
		if jog:
			value = wrapf(value+amount,-1.3158,1.3158)
			changed.emit(amount)
			queue_redraw()
		else:
			set_value(clampf(value+amount,-1,1))

	func set_value(amount: float) -> void:
		value = amount
		changed.emit(value)
		queue_redraw()

var home
var party
var panel: PanelContainer
var library: VBoxContainer
var controller: Control
var face: MeshInstance3D
var controls_view: SubViewport
var control_camera: Camera3D
var world_hint: Label
var using_controller := false
var last_pointer := Vector2.ZERO
var chooser: FileDialog
var listing: ItemList
var search: LineEdit
var folder_label: Label
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
var hardware_dials: Array[Dial] = []
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
var folder := ""
var files := PackedStringArray()
var pending := PackedStringArray()
var directory: DirAccess
var scan_path := ""
var scanning := false
var manual := false
var crossfade := -1.0
var cross_slider: HSlider
var bass := 0.0
var bass_phase := 1.0
var bass_average := 0.0
var refresh_delay := 0.0

func _init(editor, station = null) -> void:
	home = editor
	party = editor.party if station == null else station

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
	build_controller_face()
	build_laptop_display()
	build_sampler()
	var config := ConfigFile.new()
	folder = OS.get_system_dir(OS.SYSTEM_DIR_MUSIC)
	if config.load(CONFIG)==OK:
		folder = str(config.get_value("library","folder",folder))
	if not DirAccess.dir_exists_absolute(folder):
		folder = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)

func build_panel() -> void:
	panel = home.hud.panel()
	panel.add_theme_stylebox_override("panel",panel_style(Color("#0e141f"),Color("#40546b"),18))
	home.hud.root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 48
	panel.offset_right = -48
	panel.offset_top = 42
	panel.offset_bottom = -42
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation",12)
	panel.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	header.add_child(home.hud.label("Ноутбук / Музыка",18))
	header.add_child(home.hud.button("К контроллеру",func(): open(false)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.add_child(home.hud.button("Закрыть · Esc",close))
	info = home.hud.label("",15)
	body.add_child(info)
	library = VBoxContainer.new()
	library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(library)
	var toolbar := HBoxContainer.new()
	library.add_child(toolbar)
	var track_displays := HBoxContainer.new()
	library.add_child(track_displays)
	for index in range(2):
		build_track_display(track_displays,index)
	toolbar.add_child(home.hud.button("Выбрать папку",choose_folder))
	toolbar.add_child(home.hud.button("Обновить",scan_folder))
	search = LineEdit.new()
	search.placeholder_text = "Поиск по названию и подпапке"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(_query): refresh_library())
	toolbar.add_child(search)
	folder_label = home.hud.label("",14)
	folder_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	library.add_child(folder_label)
	listing = ItemList.new()
	listing.size_flags_vertical = Control.SIZE_EXPAND_FILL
	listing.item_activated.connect(func(_index): activate_selection())
	library.add_child(listing)
	var load_row := HBoxContainer.new()
	library.add_child(load_row)
	load_row.add_child(home.hud.button("Включить",play_selection))
	for index in range(2):
		load_row.add_child(home.hud.button("Загрузить в "+DECK_NAMES[index],load_selection.bind(index,false)))
	chooser = FileDialog.new()
	chooser.title = "Папка с музыкой"
	chooser.access = FileDialog.ACCESS_FILESYSTEM
	chooser.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	chooser.dir_selected.connect(func(path):
		folder = path
		var config := ConfigFile.new()
		config.set_value("library","folder",folder)
		config.save(CONFIG)
		scan_folder()
	)
	add_child(chooser)
	panel.hide()

func build_controller_face() -> void:
	controls_view = SubViewport.new()
	controls_view.size = Vector2i(1188,658)
	controls_view.disable_3d = true
	controls_view.gui_disable_input = false
	controls_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(controls_view)
	controller = Control.new()
	controls_view.add_child(controller)
	controller.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var photo := TextureRect.new()
	photo.texture = ImageTexture.create_from_image(Image.load_from_file("res://assets/dj/flx4-face.png"))
	photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	controller.add_child(photo)
	photo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build_photo_controls()
	var quad := QuadMesh.new()
	quad.size = FACE_SIZE
	face = MeshInstance3D.new()
	face.mesh = quad
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = controls_view.get_texture()
	face.material_override = material
	party.deck.add_child(face)
	face.position.y = FACE_HEIGHT
	face.rotation.x = -PI*.5
	face.hide()
	party.box(party.deck,Vector3(0,.019,0),Vector3(FACE_SIZE.x,.040,FACE_SIZE.y),Color("#18191c"))
	party.box(party.deck,Vector3(0,.010,FACE_SIZE.y*.5+.001),Vector3(FACE_SIZE.x-.006,.018,.004),Color("#25272b"))
	face.show()
	call_deferred("build_raised_controls")
	control_camera = Camera3D.new()
	control_camera.fov = 54
	control_camera.near = .025
	control_camera.cull_mask = home.player.camera.cull_mask
	party.deck.add_child(control_camera)
	world_hint = home.hud.label("Esc / ПКМ · отойти от контроллера",16)
	home.hud.root.add_child(world_hint)
	world_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	world_hint.offset_left = -260
	world_hint.offset_right = 260
	world_hint.offset_top = -56
	world_hint.offset_bottom = -29
	world_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	world_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world_hint.hide()

func build_raised_controls() -> void:
	await get_tree().process_frame
	var platter_label := StandardMaterial3D.new()
	platter_label.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	platter_label.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	platter_label.albedo_texture = ImageTexture.create_from_image(Image.load_from_file("res://assets/dj/flx4-platter.png"))
	for dial in hardware_dials:
		var position := dial.get_global_rect().get_center()/Vector2(controls_view.size)
		var base := Node3D.new()
		party.deck.add_child(base)
		base.position = Vector3((position.x-.5)*FACE_SIZE.x,FACE_HEIGHT+.001,(position.y-.5)*FACE_SIZE.y)
		var radius := minf(dial.size.x,dial.size.y)*(.46 if dial.jog else .43)*FACE_SIZE.x/controls_view.size.x
		var height := .013 if dial.jog else .008
		party.cylinder(base,Vector3(0,height*.5,0),radius,height,Color("#252c36"))
		party.cylinder(base,Vector3(0,height+.001,0),radius*.87,.002,Color("#151a24"))
		if dial.jog:
			var rim := MeshInstance3D.new()
			var ring := TorusMesh.new()
			ring.inner_radius = radius*.88
			ring.outer_radius = radius*.99
			ring.rings = 48
			ring.ring_segments = 8
			rim.mesh = ring
			rim.position.y = height
			var metal := StandardMaterial3D.new()
			metal.albedo_color = Color("#33373d")
			metal.metallic = .55
			metal.roughness = .3
			metal.emission_enabled = true
			metal.emission = Color("#111318")
			rim.material_override = metal
			rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			base.add_child(rim)
			var label := MeshInstance3D.new()
			var label_mesh := QuadMesh.new()
			label_mesh.size = Vector2.ONE*radius*.88
			label.mesh = label_mesh
			label.material_override = platter_label
			label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			label.rotation.x = -PI*.5
			label.position.y = height+.003
			base.add_child(label)
		party.box(base,Vector3(0,height+.002,-radius*.54),Vector3(.0018,.001,radius*.52),Color("#a9e5ff"))
		dial_meshes.append(base)
		dial.changed.connect(func(_value): base.rotation.y = -dial.value*PI*.76)
	for slider in channel_faders+tempo_faders:
		var cap := Node3D.new()
		party.deck.add_child(cap)
		party.box(cap,Vector3.ZERO,Vector3(.022,.007,.012),Color("#343b46"))
		party.box(cap,Vector3(0,.004,0),Vector3(.016,.001,.0018),Color("#c6c9ca"))
		move_fader(slider,cap,true)
		slider.value_changed.connect(func(_value): move_fader(slider,cap,true))
	cross_cap = Node3D.new()
	party.deck.add_child(cross_cap)
	party.box(cross_cap,Vector3.ZERO,Vector3(.012,.007,.021),Color("#343b46"))
	party.box(cross_cap,Vector3(0,.004,0),Vector3(.0018,.001,.016),Color("#c6c9ca"))
	move_fader(cross_slider,cross_cap,false)
	cross_slider.value_changed.connect(func(_value): move_fader(cross_slider,cross_cap,false))

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
	if event is InputEventKey and event.pressed and event.physical_keycode==KEY_ESCAPE:
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
	elif event is InputEventKey and event.pressed and event.physical_keycode==KEY_H and party!=home.party:
		party.shift.assign_staff()
	elif event is InputEventKey:
		controls_view.push_input(event.duplicate(),true)
	else:
		return
	get_viewport().set_input_as_handled()

func build_track_display(parent: HBoxContainer, index: int) -> void:
	var display := PanelContainer.new()
	display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display.add_theme_stylebox_override("panel",panel_style(Color("#080d16"),Color("#315a73"),11))
	parent.add_child(display)
	var screen := VBoxContainer.new()
	display.add_child(screen)
	var screen_header := HBoxContainer.new()
	screen.add_child(screen_header)
	var title: Label = home.hud.label("",16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	screen_header.add_child(title)
	screen_header.add_child(home.hud.label(DECK_NAMES[index],14))
	deck_labels.append(title)
	var scope := DeckScope.new()
	scopes.append(scope)
	screen.add_child(scope)
	var position := HSlider.new()
	position.step = .01
	position.value_changed.connect(func(value): seek(index,value))
	screen.add_child(position)
	positions.append(position)
	var clock: Label = home.hud.label("",14)
	screen.add_child(clock)
	time_labels.append(clock)
	var bpm := SpinBox.new()
	bpm.min_value = 40
	bpm.max_value = 250
	bpm.value = 124
	bpm.suffix = "BPM"
	bpm_fields.append(bpm)
	screen.add_child(bpm)

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

func build_laptop_display() -> void:
	laptop_view = SubViewport.new()
	laptop_view.size = Vector2i(768,432)
	laptop_view.disable_3d = true
	laptop_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(laptop_view)
	var frame := PanelContainer.new()
	laptop_view.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_stylebox_override("panel",panel_style(Color("#090f1a"),Color("#344865"),16))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation",10)
	frame.add_child(rows)
	for index in range(2):
		var title: Label = home.hud.label("DECK "+DECK_NAMES[index],26)
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		rows.add_child(title)
		laptop_titles.append(title)
		var scope := DeckScope.new()
		scope.custom_minimum_size.y = 104
		rows.add_child(scope)
		laptop_scopes.append(scope)
		var clock: Label = home.hud.label("",21)
		rows.add_child(clock)
		laptop_times.append(clock)
	var screen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(.333,.200)
	screen.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = laptop_view.get_texture()
	screen.material_override = material
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	party.deck.get_node("LaptopScreen").add_child(screen)
	screen.position.z = .003

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
	if Input.is_key_pressed(KEY_SHIFT):
		cue_points[index][slot] = -1.0
		return
	if not party.music[index].playing:
		return
	if cue_points[index][slot]<0:
		cue_points[index][slot] = deck_position(index)
	else:
		loop_starts[index] = -1.0
		seek(index,cue_points[index][slot])

func build_photo_controls() -> void:
	var browse := photo_button(Vector2(601,295),Vector2(51,47),"Browse · локальная музыка",func(): open(true))
	browse.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	photo_button(Vector2(522,305),Vector2(47,27),"Load A · открыть библиотеку",open_deck_library.bind(0))
	photo_button(Vector2(682,305),Vector2(47,27),"Load B · открыть библиотеку",open_deck_library.bind(1))
	for index in range(2):
		build_photo_deck(index)
		build_photo_channel(index)
	cross_slider = photo_slider(Vector2(602,875),Vector2(117,42),false,-1,1,-1)
	cross_slider.value_changed.connect(func(value):
		engage()
		crossfade = value
		apply_mix()
	)
	var echo_button := photo_button(Vector2(742,806),Vector2(47,47),"Beat FX · Echo",toggle_echo)
	echo_button.toggle_mode = true
	photo_button(Vector2(725,659),Vector2(27,23),"Укоротить Echo",func(): echo_beats = maxf(.25,echo_beats*.5))
	photo_button(Vector2(760,659),Vector2(27,23),"Удлинить Echo",func(): echo_beats = minf(1,echo_beats*2))
	photo_dial(Vector2(742,735),44,"Уровень Echo",func(value): echo.tap1_level_db = -15+value*13)
	photo_dial(Vector2(742,354),44,"Master",func(value): party.music_gain = clampf(.85+value*.85,0,1))

func build_photo_deck(index: int) -> void:
	var shift := Vector2(776*index,0)
	var jog := photo_dial(Vector2(214,537)+shift,330,"Jog · перемотка",func(amount): seek(index,deck_position(index)+amount*2.4),true)
	jog.rotation = 0
	var tempo := photo_slider(Vector2(363,784)+shift,Vector2(43,172),true,-1,1,0)
	tempo.tooltip_text = "TEMPO ±10%"
	tempo.value_changed.connect(func(value): party.music[index].pitch_scale = 1-value*.10)
	tempo_faders.append(tempo)
	transport.append(photo_button(Vector2(64,846)+shift,Vector2(65,65),"PLAY / PAUSE",toggle_deck.bind(index)))
	photo_button(Vector2(64,776)+shift,Vector2(65,65),"CUE · к точке",func(): seek(index,cues[index]))
	photo_button(Vector2(63,329)+shift,Vector2(40,40),"IN · начало лупа",func():
		loop_marks[index] = deck_position(index)
		cues[index] = loop_marks[index]
	)
	photo_button(Vector2(126,329)+shift,Vector2(40,40),"OUT · конец лупа",finish_loop.bind(index))
	var loop_button := photo_button(Vector2(190,329)+shift,Vector2(35,35),"4 BEAT / EXIT",toggle_loop.bind(index))
	loop_button.toggle_mode = true
	loop_buttons.append(loop_button)
	photo_button(Vector2(253,329)+shift,Vector2(25,25),"Назад на бит",func(): seek(index,deck_position(index)-60.0/bpm_fields[index].value))
	photo_button(Vector2(305,329)+shift,Vector2(25,25),"Вперёд на бит",func(): seek(index,deck_position(index)+60.0/bpm_fields[index].value))
	photo_button(Vector2(362,329)+shift,Vector2(32,32),"BEAT SYNC",sync_deck.bind(index))
	for mode in range(4):
		var button := photo_button(Vector2(132+mode*54.5,747)+shift,Vector2(48,22),["HOT CUE","PAD FX","BEAT JUMP","SAMPLER"][mode],set_pad_mode.bind(index,mode))
		button.toggle_mode = true
		pad_mode_buttons[index].append(button)
	for slot in range(HOT_CUES):
		var center := Vector2(132+(slot%4)*54.5,804+int(slot/4)*54)+shift
		var pad := photo_button(center,Vector2(45,45),"Пэд %d" % (slot+1),press_pad.bind(index,slot))
		pad.toggle_mode = true
		cue_buttons[index].append(pad)

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

func build_photo_channel(index: int) -> void:
	var x := 552.0+index*99
	photo_dial(Vector2(x,353),37,"TRIM",func(value):
		engage()
		trims[index] = value*12
		apply_mix()
	)
	for row in range(3):
		photo_dial(Vector2(x,416+row*60),45,["HIGH","MID","LOW"][row],set_eq.bind(index,2-row))
	photo_dial(Vector2(x,596),46,"CFX · Filter",func(value):
		engage()
		set_filter(index,value)
	)
	var level := photo_slider(Vector2(x,756),Vector2(50,113),true,0,1,1)
	level.value_changed.connect(func(value):
		engage()
		gains[index] = value
		apply_mix()
	)
	channel_faders.append(level)
	var vu := ProgressBar.new()
	vu.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	vu.max_value = 1
	vu.show_percentage = false
	vu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vu.add_theme_stylebox_override("background",panel_style(Color("#1b1c1a"),Color("#1b1c1a"),0))
	vu.add_theme_stylebox_override("fill",panel_style(Color("#a6e856"),Color("#a6e856"),0))
	place_control(vu,Vector2(590+index*22,477),Vector2(5,101))
	channel_meters.append(vu)

func place_control(control: Control, center: Vector2, dimensions: Vector2) -> void:
	controller.add_child(control)
	control.position = center-Vector2(8,262)-dimensions*.5
	control.size = dimensions

func photo_button(center: Vector2, dimensions: Vector2, hint: String, callback: Callable) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = hint
	button.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover",panel_style(Color(1,1,1,.06),Color(1,1,1,.35),0))
	button.add_theme_stylebox_override("pressed",panel_style(Color(.9,.65,.2,.18),Color("#e9aa54"),0))
	button.pressed.connect(callback)
	place_control(button,center,dimensions)
	return button

func photo_dial(center: Vector2, diameter: float, hint: String, change: Callable, is_jog: bool = false) -> Dial:
	var dial := Dial.new()
	dial.jog = is_jog
	dial.tooltip_text = hint
	dial.changed.connect(change)
	place_control(dial,center,Vector2.ONE*diameter)
	hardware_dials.append(dial)
	return dial

func photo_slider(center: Vector2, dimensions: Vector2, vertical: bool, low: float, high: float, initial: float) -> Slider:
	var slider: Slider = VSlider.new() if vertical else HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = .01
	slider.value = initial
	slider.focus_mode = Control.FOCUS_NONE
	var invisible := ImageTexture.create_from_image(Image.create_empty(12,12,false,Image.FORMAT_RGBA8))
	for icon in ["grabber","grabber_highlight","grabber_disabled"]:
		slider.add_theme_icon_override(icon,invisible)
	for track in ["slider","grabber_area","grabber_area_highlight"]:
		slider.add_theme_stylebox_override(track,StyleBoxEmpty.new())
	place_control(slider,center,dimensions)
	return slider

func route_deck(index: int, channel: int) -> void:
	routing[index] = channel
	party.music[index].bus = AudioServer.get_bus_name(deck_buses[channel])

func panel_style(fill: Color, border: Color, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(margin)
	return style

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
		if files.is_empty() and not scanning:
			scan_folder()

func open_deck_library(index: int) -> void:
	open(true)
	load_target = index
	info.text = "LOAD %s · двойной щелчок загружает трек" % DECK_NAMES[index]

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

func choose_folder() -> void:
	if DirAccess.dir_exists_absolute(folder):
		chooser.current_dir = folder
	chooser.popup_centered_ratio(.72)

func scan_folder() -> void:
	files.clear()
	pending = PackedStringArray([folder])
	directory = null
	scanning = true
	refresh_library()

func scan_step() -> void:
	for index in range(250):
		if directory==null:
			if pending.is_empty():
				scanning = false
				files.sort()
				refresh_library()
				return
			scan_path = pending[-1]
			pending.resize(pending.size()-1)
			directory = DirAccess.open(scan_path)
			if directory==null:
				continue
			directory.list_dir_begin()
		var entry := directory.get_next()
		if entry.is_empty():
			directory = null
			continue
		if directory.is_link(entry):
			continue
		var path := scan_path.path_join(entry)
		if directory.current_is_dir():
			pending.append(path)
		elif entry.get_extension().to_lower() in FORMATS:
			files.append(path)

func refresh_library() -> void:
	var query := search.text.strip_edges().to_lower()
	listing.clear()
	for path in files:
		var label := path.trim_prefix(folder.trim_suffix("/")+"/")
		if query.is_empty() or label.to_lower().contains(query):
			var index := listing.add_item(label)
			listing.set_item_metadata(index,path)
	folder_label.text = "%s   ·   %s" % [folder,"Поиск файлов…" if scanning else "%d треков" % listing.item_count]

func play_selection() -> void:
	var current := audible_deck()
	load_selection(current,true)

func activate_selection() -> void:
	if load_target>=0:
		load_selection(load_target,false)
	else:
		play_selection()

func load_selection(index: int, play_now: bool) -> void:
	var selected := listing.get_selected_items()
	if selected.is_empty():
		info.text = "Выбери трек в списке."
		return
	var path := str(listing.get_item_metadata(selected[0]))
	if not load_file(path,index,play_now):
		info.text = "Не удалось открыть "+path.get_file()

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
		info.text += " · Короткий файл"
	return true

func engage() -> void:
	if manual:
		return
	manual = true
	if is_instance_valid(party.fader):
		party.fader.kill()
	for index in range(2):
		if index==party.playing and party.music[index].playing:
			titles[index] = party.TRACKS[party.track]
			sources[index] = party.track
			bpm_fields[index].value = party.BPM[party.track]
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
		info.text = "Загрузи трек из ноутбука в деку "+DECK_NAMES[index]+"."
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
	return titles[audible_deck()] if manual else party.TRACKS[party.track]

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
	if scanning:
		scan_step()
	for index in range(2):
		if loop_starts[index]>=0 and party.music[index].playing and deck_position(index)>=loop_ends[index]:
			seek(index,loop_starts[index])
	update_bass(delta)
	if echo_enabled:
		var bpm: float = bpm_fields[audible_deck()].value if manual else party.BPM[party.track]
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
		var title: String = titles[index] if manual else (party.TRACKS[party.track] if player.playing else "")
		deck_labels[index].text = title if not title.is_empty() else "Дека пуста"
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

