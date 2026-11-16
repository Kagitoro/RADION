class_name DJControllerFace
extends RefCounted
## Builds the FLX4 controller: the photo face with clickable controls in a SubViewport and the raised 3D knobs on the deck.


var station: DJStation
var hover_outline: Control
var hover_dashes := PackedVector2Array()
var hover_label: Label
var hovered_control: Control
var fader_caps: Dictionary[Slider, Node3D] = {}
const VERTICAL_CAP_SIZE := Vector3(0.022, 0.007, 0.012)
const CROSS_CAP_SIZE := Vector3(0.012, 0.007, 0.021)
const STROKE_INSET := 0.0017

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
	hover_outline = Control.new()
	hover_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_outline.draw.connect(func():
		if hover_dashes.size() >= 2:
			hover_outline.draw_multiline(hover_dashes, Color(0.02, 0.07, 0.1, 0.92), 3.0, true)
			hover_outline.draw_multiline(hover_dashes, Color("#92edff"), 1.5, true)
	)
	station.home.hud.root.add_child(hover_outline)
	hover_outline.hide()
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
	hover_label = station.world_hint.duplicate() as Label
	station.home.hud.root.add_child(hover_label)
	hover_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hover_label.offset_left = -260
	hover_label.offset_right = 260
	hover_label.offset_top = 14
	hover_label.offset_bottom = 38
	hover_label.add_theme_color_override("font_color", Color("#a6f1ff"))

func update_hover(control: Control) -> void:
	if control != null and not control.has_meta("hardware_hint"):
		control = null
	if control == hovered_control:
		return
	hovered_control = control
	hover_outline.visible = control != null
	hover_label.visible = control != null
	if control == null:
		return
	hover_label.text = str(control.get_meta("hardware_hint"))
	refresh_outline()

func refresh_outline() -> void:
	var control := hovered_control
	var viewport_size := Vector2(station.controls_view.size)
	var bounds := control.get_global_rect()
	var center := (bounds.get_center() / viewport_size - Vector2(0.5, 0.5)) * station.FACE_SIZE
	var dimensions := bounds.size / viewport_size * station.FACE_SIZE
	var height := 0.0
	var is_round := bool(control.get_meta("round_outline", false))
	var face_ring := bool(control.get_meta("outline_face_ring", false))
	if control is DJDial:
		is_round = true
		if not face_ring:
			var radius := dial_radius(control) * (0.99 if control.jog else 0.87)
			dimensions = Vector2.ONE * radius * 2.0
			height = control_height(control)
	elif control is Slider and fader_caps.has(control):
		var cap := fader_caps[control as Slider]
		var local := station.face.to_local(cap.global_position)
		center = Vector2(local.x, -local.y)
		var cap_size := CROSS_CAP_SIZE if control == station.cross_slider else VERTICAL_CAP_SIZE
		dimensions = Vector2(cap_size.x, cap_size.z)
		height = local.z + cap_size.y * 0.5
	var inset := minf(0.0011 if face_ring else STROKE_INSET, minf(dimensions.x, dimensions.y) * 0.14)
	var half_size := dimensions * 0.5 - Vector2.ONE * inset
	var points := PackedVector2Array()
	if is_round:
		for index in range(48):
			points.append(center + Vector2.from_angle(TAU * index / 48.0) * half_size)
	else:
		var rect := Rect2(center - half_size, half_size * 2.0)
		points = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
				rect.end, Vector2(rect.position.x, rect.end.y)])
	var face_limit := station.FACE_SIZE * 0.5 - Vector2.ONE * STROKE_INSET
	for index in points.size():
		var on_face := points[index].clamp(-face_limit, face_limit)
		var point := Vector3(on_face.x, -on_face.y, height)
		points[index] = station.control_camera.unproject_position(station.face.to_global(point))
	hover_dashes = dashed_outline(points)
	hover_outline.queue_redraw()

func dial_radius(dial: DJDial) -> float:
	return minf(dial.size.x, dial.size.y) * (0.46 if dial.jog else 0.43) * station.FACE_SIZE.x / station.controls_view.size.x

func dashed_outline(points: PackedVector2Array) -> PackedVector2Array:
	var perimeter := 0.0
	for index in points.size():
		perimeter += points[index].distance_to(points[(index + 1) % points.size()])
	var result := PackedVector2Array()
	if perimeter <= 0.01:
		return result
	var repeat := perimeter / maxi(4, roundi(perimeter / 13.0))
	var dash_length := repeat * 0.60
	var traveled := 0.0
	for index in points.size():
		var start := points[index]
		var end := points[(index + 1) % points.size()]
		var length := start.distance_to(end)
		if length <= 0.01:
			continue
		var dash := floorf(traveled / repeat) * repeat
		while dash < traveled + length:
			var from := maxf(dash - traveled, 0.0)
			var to := minf(dash + dash_length - traveled, length)
			if to > from:
				result.append(start.lerp(end, from / length))
				result.append(start.lerp(end, to / length))
			dash += repeat
		traveled += length
	return result

func control_height(control: Control) -> float:
	if control is DJDial:
		return 0.017 if control.jog else 0.011
	return 0.013 if control is Slider else 0.0

func pointer_height(screen_point: Vector2) -> float:
	var jog_point := station.face_pointer(station.control_camera, screen_point, 0.017)
	var dial_point := station.face_pointer(station.control_camera, screen_point, 0.011)
	for dial in station.hardware_dials:
		var point := jog_point if dial.jog else dial_point
		var bounds := dial.get_global_rect()
		if point.distance_to(bounds.get_center()) <= bounds.size.x * 0.5:
			return control_height(dial)
	var fader_point := station.face_pointer(station.control_camera, screen_point, 0.013)
	for slider in station.channel_faders + station.tempo_faders + [station.cross_slider]:
		if slider.get_global_rect().has_point(fader_point):
			return control_height(slider)
	return 0.0

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
		var radius := dial_radius(dial)
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
		station.party.box(cap,Vector3.ZERO,VERTICAL_CAP_SIZE,Color("#343b46"))
		station.party.box(cap,Vector3(0,.004,0),Vector3(.016,.001,.0018),Color("#c6c9ca"))
		bind_fader_cap(slider, cap, true)
	station.cross_cap = Node3D.new()
	station.party.deck.add_child(station.cross_cap)
	station.party.box(station.cross_cap,Vector3.ZERO,CROSS_CAP_SIZE,Color("#343b46"))
	station.party.box(station.cross_cap,Vector3(0,.004,0),Vector3(.0018,.001,.016),Color("#c6c9ca"))
	bind_fader_cap(station.cross_slider, station.cross_cap, false)

func bind_fader_cap(slider: Slider, cap: Node3D, vertical: bool) -> void:
	fader_caps[slider] = cap
	station.move_fader(slider, cap, vertical)
	slider.value_changed.connect(func(_value):
		station.move_fader(slider, cap, vertical)
		if hovered_control == slider:
			refresh_outline()
	)

func build_photo_controls() -> void:
	var browse := photo_button(Vector2(601,295),Vector2(51,47),tr("Browse · локальная музыка"),func(): station.open(true))
	browse.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	photo_button(Vector2(522,305),Vector2(47,27),tr("Load A · открыть библиотеку"),station.open_deck_library.bind(0))
	photo_button(Vector2(682,305),Vector2(47,27),tr("Load B · открыть библиотеку"),station.open_deck_library.bind(1))
	for index in range(2):
		build_photo_deck(index)
		build_photo_channel(index)
	station.cross_slider = photo_slider(Vector2(602,875),Vector2(117,42),false,-1,1,-1)
	station.cross_slider.set_meta("hardware_hint", tr("Кроссфейдер · A / B"))
	station.cross_slider.value_changed.connect(func(value):
		station.engage()
		station.crossfade = value
		station.apply_mix()
	)
	var echo_button := photo_button(Vector2(742,806),Vector2(35,35),tr("Beat FX · вкл. / выкл."),station.toggle_echo,true)
	echo_button.toggle_mode = true
	var fx_select := photo_button(Vector2(742,597),Vector2(40,24),"FX SELECT · Echo / Reverb",station.cycle_beat_fx)
	fx_select.pressed.connect(func():
		fx_select.set_meta("hardware_hint", "FX SELECT · " + ("Reverb" if station.reverb_selected else "Echo"))
		if hovered_control == fx_select:
			hover_label.text = str(fx_select.get_meta("hardware_hint"))
	)
	photo_button(Vector2(725,659),Vector2(27,23),tr("Укоротить Echo"),func(): station.echo_beats = maxf(.25,station.echo_beats*.5))
	photo_button(Vector2(760,659),Vector2(27,23),tr("Удлинить Echo"),func(): station.echo_beats = minf(1,station.echo_beats*2))
	photo_dial(Vector2(742,735),48,tr("Уровень Beat FX"),station.set_fx_depth)
	photo_dial(Vector2(742,354),44,"Master",func(value): station.party.music_gain = clampf(.85+value*.85,0,1))

func build_photo_deck(index: int) -> void:
	var shift := Vector2(776*index,0)
	var jog := photo_dial(Vector2(214,537)+shift,350,tr("Jog · перемотка"),func(amount): station.seek(index,station.deck_position(index)+amount*2.4),true)
	jog.rotation = 0
	var tempo := photo_slider(Vector2(363,784)+shift,Vector2(57,177),true,-1,1,0)
	tempo.set_meta("hardware_hint", "TEMPO ±10%")
	tempo.value_changed.connect(func(value): station.party.music[index].pitch_scale = 1-value*.10)
	station.tempo_faders.append(tempo)
	station.transport.append(photo_button(Vector2(64,846)+shift,Vector2(65,65),"PLAY / PAUSE",station.toggle_deck.bind(index),true))
	var shift_button := photo_button(Vector2(64,710)+shift,Vector2(31,27),
			tr("SHIFT · CUE к началу / удаление Hot Cue"),
			func(): station.deck_shift[index] = not station.deck_shift[index])
	shift_button.toggle_mode = true
	photo_button(Vector2(64,776)+shift,Vector2(65,65),tr("CUE · к точке"),func():
		station.seek(index, 0.0 if station.deck_shift[index] else station.cues[index])
	,true)
	photo_button(Vector2(63,329)+shift,Vector2(40,40),tr("IN · начало лупа"),func():
		station.loop_marks[index] = station.deck_position(index)
		station.cues[index] = station.loop_marks[index]
	,true)
	photo_button(Vector2(126,329)+shift,Vector2(40,40),tr("OUT · конец лупа"),station.finish_loop.bind(index),true)
	var loop_button := photo_button(Vector2(190,329)+shift,Vector2(35,35),"4 BEAT / EXIT",station.toggle_loop.bind(index),true)
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
		var band := photo_dial(Vector2(x,416+row*60),45,["HIGH","MID","LOW"][row],station.set_eq.bind(index,2-row))
		band.set_meta("outline_face_ring", true)
	photo_dial(Vector2(x,596),46,"CFX · Filter",func(value):
		station.engage()
		station.set_filter(index,value)
	)
	var level := photo_slider(Vector2(x,756),Vector2(57,120),true,0,1,1)
	level.set_meta("hardware_hint", tr("Громкость канала %s") % station.DECK_NAMES[index])
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

func photo_button(center: Vector2, dimensions: Vector2, hint: String, callback: Callable, is_round: bool = false) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.set_meta("hardware_hint", hint)
	button.set_meta("round_outline", is_round)
	button.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed",UIKit.frame_style(Color(.9,.65,.2,.18),Color("#e9aa54"),0))
	button.pressed.connect(callback)
	place_control(button,center,dimensions)
	return button

func photo_dial(center: Vector2, diameter: float, hint: String, change: Callable, is_jog: bool = false) -> DJDial:
	var dial := DJDial.new()
	dial.jog = is_jog
	dial.set_meta("hardware_hint", hint)
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
