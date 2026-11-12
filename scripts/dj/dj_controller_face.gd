class_name DJControllerFace
extends RefCounted
## Builds the FLX4 controller: the photo face with clickable controls in a SubViewport and the raised 3D knobs on the deck.


var station: DJStation

func _init(owner_node: DJStation) -> void:
	station = owner_node

func build_controller_face() -> void:
	station.controls_view = SubViewport.new()
	station.controls_view.size = Vector2i(1188,658)
	station.controls_view.disable_3d = true
	station.controls_view.gui_disable_input = false
	station.controls_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	station.add_child(station.controls_view)
	station.controller = Control.new()
	station.controls_view.add_child(station.controller)
	station.controller.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var photo := TextureRect.new()
	photo.texture = load("res://assets/dj/flx4-face.png")
	photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	station.controller.add_child(photo)
	photo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build_photo_controls()
	var quad := QuadMesh.new()
	quad.size = station.FACE_SIZE
	station.face = MeshInstance3D.new()
	station.face.mesh = quad
	station.face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = station.controls_view.get_texture()
	station.face.material_override = material
	station.party.deck.add_child(station.face)
	station.face.position.y = station.FACE_HEIGHT
	station.face.rotation.x = -PI*.5
	station.face.hide()
	station.party.box(station.party.deck,Vector3(0,.019,0),Vector3(station.FACE_SIZE.x,.040,station.FACE_SIZE.y),Color("#18191c"))
	station.party.box(station.party.deck,Vector3(0,.010,station.FACE_SIZE.y*.5+.001),Vector3(station.FACE_SIZE.x-.006,.018,.004),Color("#25272b"))
	station.face.show()
	build_raised_controls.call_deferred()
	station.control_camera = Camera3D.new()
	station.control_camera.fov = 54
	station.control_camera.near = .025
	station.control_camera.cull_mask = station.home.player.camera.cull_mask
	station.party.deck.add_child(station.control_camera)
	station.world_hint = UIKit.label(tr("Esc / ПКМ · отойти от контроллера"),16)
	station.home.hud.root.add_child(station.world_hint)
	station.world_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	station.world_hint.offset_left = -260
	station.world_hint.offset_right = 260
	station.world_hint.offset_top = -56
	station.world_hint.offset_bottom = -29
	station.world_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	station.world_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	station.world_hint.hide()

func build_raised_controls() -> void:
	await station.get_tree().process_frame
	var platter_label := StandardMaterial3D.new()
	platter_label.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	platter_label.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	platter_label.albedo_texture = load("res://assets/dj/flx4-platter.png")
	for dial in station.hardware_dials:
		var position := dial.get_global_rect().get_center()/Vector2(station.controls_view.size)
		var base := Node3D.new()
		station.party.deck.add_child(base)
		base.position = Vector3((position.x-.5)*station.FACE_SIZE.x,station.FACE_HEIGHT+.001,(position.y-.5)*station.FACE_SIZE.y)
		var radius := minf(dial.size.x,dial.size.y)*(.46 if dial.jog else .43)*station.FACE_SIZE.x/station.controls_view.size.x
		var height := .013 if dial.jog else .008
		station.party.cylinder(base,Vector3(0,height*.5,0),radius,height,Color("#252c36"))
		station.party.cylinder(base,Vector3(0,height+.001,0),radius*.87,.002,Color("#151a24"))
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
		station.party.box(base,Vector3(0,height+.002,-radius*.54),Vector3(.0018,.001,radius*.52),Color("#a9e5ff"))
		station.dial_meshes.append(base)
		dial.changed.connect(func(_value): base.rotation.y = -dial.value*PI*.76)
	for slider in station.channel_faders+station.tempo_faders:
		var cap := Node3D.new()
		station.party.deck.add_child(cap)
		station.party.box(cap,Vector3.ZERO,Vector3(.022,.007,.012),Color("#343b46"))
		station.party.box(cap,Vector3(0,.004,0),Vector3(.016,.001,.0018),Color("#c6c9ca"))
		station.move_fader(slider,cap,true)
		slider.value_changed.connect(func(_value): station.move_fader(slider,cap,true))
	station.cross_cap = Node3D.new()
	station.party.deck.add_child(station.cross_cap)
	station.party.box(station.cross_cap,Vector3.ZERO,Vector3(.012,.007,.021),Color("#343b46"))
	station.party.box(station.cross_cap,Vector3(0,.004,0),Vector3(.0018,.001,.016),Color("#c6c9ca"))
	station.move_fader(station.cross_slider,station.cross_cap,false)
	station.cross_slider.value_changed.connect(func(_value): station.move_fader(station.cross_slider,station.cross_cap,false))

func build_photo_controls() -> void:
	var browse := photo_button(Vector2(601,295),Vector2(51,47),tr("Browse · локальная музыка"),func(): station.open(true))
	browse.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	photo_button(Vector2(522,305),Vector2(47,27),tr("Load A · открыть библиотеку"),station.open_deck_library.bind(0))
	photo_button(Vector2(682,305),Vector2(47,27),tr("Load B · открыть библиотеку"),station.open_deck_library.bind(1))
	for index in range(2):
		build_photo_deck(index)
		build_photo_channel(index)
	station.cross_slider = photo_slider(Vector2(602,875),Vector2(117,42),false,-1,1,-1)
	station.cross_slider.value_changed.connect(func(value):
		station.engage()
		station.crossfade = value
		station.apply_mix()
	)
	var echo_button := photo_button(Vector2(742,806),Vector2(47,47),"Beat FX · Echo",station.toggle_echo)
	echo_button.toggle_mode = true
	photo_button(Vector2(725,659),Vector2(27,23),tr("Укоротить Echo"),func(): station.echo_beats = maxf(.25,station.echo_beats*.5))
	photo_button(Vector2(760,659),Vector2(27,23),tr("Удлинить Echo"),func(): station.echo_beats = minf(1,station.echo_beats*2))
	photo_dial(Vector2(742,735),44,tr("Уровень Echo"),func(value): station.echo.tap1_level_db = -15+value*13)
	photo_dial(Vector2(742,354),44,"Master",func(value): station.party.music_gain = clampf(.85+value*.85,0,1))

func build_photo_deck(index: int) -> void:
	var shift := Vector2(776*index,0)
	var jog := photo_dial(Vector2(214,537)+shift,330,tr("Jog · перемотка"),func(amount): station.seek(index,station.deck_position(index)+amount*2.4),true)
	jog.rotation = 0
	var tempo := photo_slider(Vector2(363,784)+shift,Vector2(43,172),true,-1,1,0)
	tempo.tooltip_text = "TEMPO ±10%"
	tempo.value_changed.connect(func(value): station.party.music[index].pitch_scale = 1-value*.10)
	station.tempo_faders.append(tempo)
	station.transport.append(photo_button(Vector2(64,846)+shift,Vector2(65,65),"PLAY / PAUSE",station.toggle_deck.bind(index)))
	photo_button(Vector2(64,776)+shift,Vector2(65,65),tr("CUE · к точке"),func(): station.seek(index,station.cues[index]))
	photo_button(Vector2(63,329)+shift,Vector2(40,40),tr("IN · начало лупа"),func():
		station.loop_marks[index] = station.deck_position(index)
		station.cues[index] = station.loop_marks[index]
	)
	photo_button(Vector2(126,329)+shift,Vector2(40,40),tr("OUT · конец лупа"),station.finish_loop.bind(index))
	var loop_button := photo_button(Vector2(190,329)+shift,Vector2(35,35),"4 BEAT / EXIT",station.toggle_loop.bind(index))
	loop_button.toggle_mode = true
	station.loop_buttons.append(loop_button)
	photo_button(Vector2(253,329)+shift,Vector2(25,25),tr("Назад на бит"),func(): station.seek(index,station.deck_position(index)-60.0/station.bpm_fields[index].value))
	photo_button(Vector2(305,329)+shift,Vector2(25,25),tr("Вперёд на бит"),func(): station.seek(index,station.deck_position(index)+60.0/station.bpm_fields[index].value))
	photo_button(Vector2(362,329)+shift,Vector2(32,32),"BEAT SYNC",station.sync_deck.bind(index))
	for mode in range(4):
		var button := photo_button(Vector2(132+mode*54.5,747)+shift,Vector2(48,22),["HOT CUE","PAD FX","BEAT JUMP","SAMPLER"][mode],station.set_pad_mode.bind(index,mode))
		button.toggle_mode = true
		station.pad_mode_buttons[index].append(button)
	for slot in range(station.HOT_CUES):
		var center := Vector2(132+(slot%4)*54.5,804+int(slot/4)*54)+shift
		var pad := photo_button(center,Vector2(45,45),tr("Пэд %d") % (slot+1),station.press_pad.bind(index,slot))
		pad.toggle_mode = true
		station.cue_buttons[index].append(pad)

func build_photo_channel(index: int) -> void:
	var x := 552.0+index*99
	photo_dial(Vector2(x,353),37,"TRIM",func(value):
		station.engage()
		station.trims[index] = value*12
		station.apply_mix()
	)
	for row in range(3):
		photo_dial(Vector2(x,416+row*60),45,["HIGH","MID","LOW"][row],station.set_eq.bind(index,2-row))
	photo_dial(Vector2(x,596),46,"CFX · Filter",func(value):
		station.engage()
		station.set_filter(index,value)
	)
	var level := photo_slider(Vector2(x,756),Vector2(50,113),true,0,1,1)
	level.value_changed.connect(func(value):
		station.engage()
		station.gains[index] = value
		station.apply_mix()
	)
	station.channel_faders.append(level)
	var vu := ProgressBar.new()
	vu.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	vu.max_value = 1
	vu.show_percentage = false
	vu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vu.add_theme_stylebox_override("background",UIKit.frame_style(Color("#1b1c1a"),Color("#1b1c1a"),0))
	vu.add_theme_stylebox_override("fill",UIKit.frame_style(Color("#a6e856"),Color("#a6e856"),0))
	place_control(vu,Vector2(590+index*22,477),Vector2(5,101))
	station.channel_meters.append(vu)

func place_control(control: Control, center: Vector2, dimensions: Vector2) -> void:
	station.controller.add_child(control)
	control.position = center-Vector2(8,262)-dimensions*.5
	control.size = dimensions

func photo_button(center: Vector2, dimensions: Vector2, hint: String, callback: Callable) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = hint
	button.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover",UIKit.frame_style(Color(1,1,1,.06),Color(1,1,1,.35),0))
	button.add_theme_stylebox_override("pressed",UIKit.frame_style(Color(.9,.65,.2,.18),Color("#e9aa54"),0))
	button.pressed.connect(callback)
	place_control(button,center,dimensions)
	return button

func photo_dial(center: Vector2, diameter: float, hint: String, change: Callable, is_jog: bool = false) -> DJDial:
	var dial := DJDial.new()
	dial.jog = is_jog
	dial.tooltip_text = hint
	dial.changed.connect(change)
	place_control(dial,center,Vector2.ONE*diameter)
	station.hardware_dials.append(dial)
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
