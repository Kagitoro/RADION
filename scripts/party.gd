class_name Party
extends DeckHost

var events: Node3D
var guest_models: Array[Array] = [[],[]]
var psx_assets := {}
const GOAL := 12
const TRACKS := ["Move Your Body","DJ Dance","Take You Higher"]
const BPM := [122.0,128.0,126.0]

var home: Home
var deck_light := OmniLight3D.new()
var crowd := Node3D.new()
var tracks: Array[AudioStreamMP3] = []
var outside_filter := AudioEffectLowPassFilter.new()
var requested := 1
var request_time := 0.0
var mix_time := 0.0
var arrival := 0.0
var full_time := 0.0
var atmosphere := 50.0
var bonus := 0.0
var beat := 0.0
var active := false
var starting := false
var silence_time := 0.0
var departure_delay := 0.0
var departure_side := 1.0
var won := false
var guests: Array[PartyGuest] = []
var guest_serial := 0
var rng := RandomNumberGenerator.new()
var hud_elapsed := 0.0
var music_paused := false
var cigarettes := Balance.START_CIGARETTES
var cash := Balance.START_CASH
var conversation := {}
var conversation_wait := 1.5
var navigation_grid := PartyNavigation.new(self)
var consumables := PartyConsumables.new(self)
const EXCHANGES := [
	["Привет! Ты давно здесь?","Недавно. Что сейчас играет?","Пойдём ближе к пульту, там лучше слышно."],
	["Слышишь, как поменялся бас?","Да. Вот этот трек я бы оставил подольше.","Согласен. Пусть пока играет."],
	["Ты уже видел комнату с мониторами?","Да, там сейчас все танцуют.","Давай тоже заглянем."],
	["Здесь уже почти полный дом.","Ага, я даже в коридоре встретил знакомых.","Пойдём поздороваемся."]
]
const STATUS_VIEW := preload("res://ui/party_status.tscn")
var panel: PanelContainer
var meter: ProgressBar
var status: Label
var message: Label
var prompt: Label

func _init(game_home: Home) -> void:
	home = game_home
	music_gain = .85

## --- Public API used by other systems (keeps PartyConsumables / PartyNavigation internal) ---

## Drink a beer (true) or light / puff a cigarette (false).
func consume(beer: bool) -> void:
	consumables.consume(beer)

func extinguish() -> void:
	consumables.extinguish()

## True while a bottle or cigarette animation occupies the player's hand.
func hands_busy() -> bool:
	return is_instance_valid(consumables.hand_prop)

## Template bottle mesh used to dress the bar; null until the first beer is built.
func bottle_template() -> Node3D:
	return consumables.bottle_model

## Sends a guest somewhere new on the walkable grid.
func find_destination(guest: PartyGuest) -> void:
	navigation_grid.find_destination(guest)

func route_to(guest: PartyGuest, destination: Vector2i) -> void:
	navigation_grid.route_to(guest, destination)

## Walkable cell nearest to a world point.
func cell_near(point: Vector3) -> Vector2i:
	return navigation_grid.closest_cell(point, navigation_grid.connected)

func invite_to_dance(guest: PartyGuest) -> void:
	navigation_grid.find_destination(guest,true)

func has_walkable_area() -> bool:
	return not navigation_grid.connected.is_empty()

func dance_floor_cells() -> Array[Vector2i]:
	return navigation_grid.dance_floor

func track_titles() -> Array:
	return TRACKS

func track_bpm() -> Array:
	return BPM

func setup() -> void:
	var outfits := [
		["Casual_Male.glb","Casual2_Male.gltf","Casual3_Male.gltf","Casual_Bald.gltf","Worker_Male.gltf"],
		["Casual_Female.glb","Casual2_Female.gltf","Casual3_Female.gltf","Worker_Female.gltf"],
	]
	for group in range(outfits.size()):
		for asset in outfits[group]:
			var model := GuestModel.load_model("res://assets/guests/"+asset)
			if model != null:
				add_child(model)
				model.hide()
				guest_models[group].append(model)
	for file in DirAccess.get_files_at("res://assets/psx/glb"):
		if not file.ends_with(".glb"):
			continue
		var model := GuestModel.load_model("res://assets/psx/glb/"+file)
		if model != null:
			add_child(model)
			model.hide()
			psx_assets[file.get_basename()] = model
	music_bus = AudioServer.get_bus_index("Night music")
	if music_bus<0:
		AudioServer.add_bus()
		music_bus = AudioServer.bus_count-1
		AudioServer.set_bus_name(music_bus,"Night music")
		outside_filter.cutoff_hz = 18000
		AudioServer.add_bus_effect(music_bus,outside_filter)
	else:
		outside_filter = AudioServer.get_bus_effect(music_bus,0) as AudioEffectLowPassFilter
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file("res://assets/party/beer-bottle.glb",state)==OK:
		consumables.bottle_model = document.generate_scene(state) as Node3D
		if consumables.bottle_model!=null:
			add_child(consumables.bottle_model)
			consumables.bottle_model.hide()
	add_child(consumables.action_audio)
	consumables.action_audio.volume_db = -10
	consumables.sip_audio = consumables.action_sound(true)
	consumables.breath_audio = consumables.action_sound(false)
	add_child(deck)
	add_child(crowd)
	DJStation.build_laptop(self)
	deck.add_child(deck_light)
	deck_light.position = Vector3(0,.32,.15)
	deck_light.omni_range = 2.6
	deck_light.light_energy = 0.0
	for index in range(2):
		var channel := AudioStreamPlayer.new()
		channel.bus = "Night music"
		add_child(channel)
		music.append(channel)
	for title in TRACKS:
		var stream := (load("res://assets/party/"+title+".mp3") as AudioStreamMP3).duplicate() as AudioStreamMP3
		if stream!=null:
			stream.loop = true
		tracks.append(stream)
	build_hud()
	sync_deck()
	events = PartyEvents.new(home)
	add_child(events)
	events.setup()

func sync_deck() -> void:
	for row in home.records.values():
		if str(row.label)!="Рабочий стол" or bool(row.deleted):
			continue
		var angle := deg_to_rad(float(row.r))
		deck.position = Vector3(float(row.x),float(row.y)+float(row.h)*.56+.036,float(row.z))+Vector3(float(row.w)*.16,0,float(row.d)*.23).rotated(Vector3.UP,angle)
		deck.rotation.y = angle
		return
	deck.position = home.rooms.room_point("studio",Vector3(6.7,.85,-1.10))

func near_deck() -> bool:
	var player_point: Vector3 = home.player.global_position
	return absf(player_point.y+.9-deck.position.y)<1.05 and Vector2(player_point.x,player_point.z).distance_to(Vector2(deck.position.x,deck.position.z))<1.85

func toggle() -> void:
	if active or starting:
		stop()
	elif near_deck():
		starting = true
		GameEvents.notify(tr("Открываем двери гостям…"))
	else:
		GameEvents.notify(tr("Подойди к DJ-пульту на рабочем столе в спальне-студии."))

func stop() -> void:
	starting = false
	active = false
	if is_instance_valid(events):
		events.end_fight(false)
	deck_light.light_energy = 0
	if is_instance_valid(fader):
		fader.kill()
	for channel in music:
		channel.stop()
	for guest in guests:
		guest.dancing = false
	departure_delay = .4
	silence_time = 0.0
	if not conversation.is_empty():
		for guest in [conversation.first,conversation.second]:
			if is_instance_valid(guest):
				guest.partner = null
				guest.speech.hide()
		conversation.clear()

func start() -> void:
	starting = false
	if not navigation_grid.rebuild_navigation():
		GameEvents.notify(tr("Рядом с пультом мало проходов. Освободи место и попробуй снова."))
		return
	active = true
	won = false
	full_time = 0
	arrival = Balance.PARTY_FIRST_ARRIVAL
	atmosphere = Balance.PARTY_START_ATMOSPHERE
	bonus = 0
	if guests.is_empty():
		guest_serial = 0
	silence_time = 0.0
	departure_delay = 0.0
	requested = 0
	request_time = Balance.PARTY_FIRST_REQUEST
	mix_time = 0
	conversation_wait = 1.5
	if not home.night_game.dj.has_playback():
		switch_track(0)

func switch_track(index: int) -> void:
	if not active or index<0 or index>=tracks.size() or tracks[index]==null:
		return
	var dj = home.night_game.dj
	if dj.manual:
		for channel in music:
			channel.stop()
		dj.use_builtin()
	if music[playing].playing and track==index:
		return
	if is_instance_valid(fader):
		fader.kill()
	var old := music[playing]
	playing = 1-playing
	var next := music[playing]
	next.stream = tracks[index]
	next.volume_db = -42.0
	next.play()
	fader = create_tween().set_parallel()
	fader.tween_property(next,"volume_db",-13.0,.56)
	fader.tween_property(old,"volume_db",-45.0,.56)
	fader.chain().tween_callback(old.stop)
	track = index
	deck_light.light_color = [Color("#6ba5ff"),Color("#ed83cd"),Color("#ffbe80")][index]
	track_time = 0.0
	beat = 0.0

func beat_mix() -> void:
	if not active or mix_time>0:
		return
	mix_time = Balance.BEAT_MIX_COOLDOWN
	if minf(beat,1.0-beat)<Balance.BEAT_MIX_WINDOW:
		bonus = minf(Balance.BEAT_MIX_BONUS_MAX,bonus+Balance.BEAT_MIX_BONUS)
		GameEvents.notify(tr("Сведение в бит · атмосфера растёт"))
	else:
		GameEvents.notify(tr("Нажимай M, когда в индикаторе загорается БИТ."))

func _physics_process(delta: float) -> void:
	if not is_instance_valid(home.player) or not is_instance_valid(status):
		return
	consumables.sync_mirror()
	if not home.modal:
		consumables.update_falling_bits(delta)
	if consumables.smoking() and not home.modal:
		consumables.cigarette_burn += delta*.004
		consumables.update_cigarette_length()
		if consumables.cigarette_burn>=1.0 and not is_instance_valid(consumables.hand_prop):
			consumables.extinguish()
			return
		consumables.ember_timer -= delta
		if consumables.ember_timer<=0:
			consumables.ember_timer = .32
			consumables.ember_smoke()
	if starting and not home.modal:
		start()
	hud_elapsed += delta
	if hud_elapsed >= .10:
		hud_elapsed = 0.0
		refresh_hud()
	var dj = home.night_game.dj
	var pause_music: bool = home.modal and not dj.is_open()
	if music_paused != pause_music:
		music_paused = pause_music
		for index in range(music.size()):
			music[index].stream_paused = music_paused or (dj.manual and dj.paused_decks[index])
	var outdoors: bool = home.night_world.outside(home.player.global_position)
	outside_filter.cutoff_hz = lerpf(outside_filter.cutoff_hz,2600.0 if outdoors else 18000.0,minf(1,delta*3))
	var bus_volume := AudioServer.get_bus_volume_db(music_bus)
	var distance_from_house: float = home.night_world.door_center.x-home.player.global_position.x
	var street_fade := minf(48.0,maxf(0.0,distance_from_house-12.0)*4.0)
	var volume_target := (-12.0-street_fade if outdoors else 0.0)+linear_to_db(maxf(.0001,music_gain))
	AudioServer.set_bus_volume_db(music_bus,lerpf(bus_volume,volume_target,minf(1,delta*3)))
	if pause_music:
		return
	var music_running: bool = active and music_gain>.02 and dj.has_playback()
	silence_time = 0.0 if music_running else silence_time+delta
	departure_delay = maxf(0.0,departure_delay-delta)
	if not active or silence_time>=6.0:
		begin_departure()
	if not active:
		update_guests(delta,false)
		return
	mix_time = maxf(0,mix_time-delta)
	track_time += delta
	var song: int = dj.current_builtin()
	if song<0:
		beat = dj.dance_phase()
	else:
		beat = fposmod(music[dj.audible_deck()].get_playback_position()*BPM[song]/60.0,1.0)
	deck_light.light_energy = .08+exp(-beat*8.0)*atmosphere*.003
	bonus = move_toward(bonus,0,delta*Balance.BEAT_MIX_BONUS_DECAY)
	request_time -= delta
	if request_time<=0:
		requested = (requested+1+int(guest_serial%2))%3
		request_time = Balance.PARTY_REQUEST_INTERVAL
	var matched := 0.0
	for guest in guests:
		if guest.preference==song and not guest.leaving:
			matched += 1
	var mix := matched/maxf(1,float(guests.size()))
	var target := Balance.PARTY_BASE_MOOD+(Balance.PARTY_REQUEST_BONUS if song==requested else -Balance.PARTY_OFF_REQUEST_PENALTY)+mix*Balance.PARTY_TASTE_WEIGHT+bonus-maxf(0,track_time-Balance.PARTY_TRACK_FATIGUE_AFTER)*Balance.PARTY_TRACK_FATIGUE_RATE
	if dj.manual:
		target += dj.bass*Balance.PARTY_BASS_WEIGHT if dj.has_playback() else -Balance.PARTY_SILENCE_PENALTY
	atmosphere = move_toward(atmosphere,clampf(target,0,100),delta*Balance.PARTY_ATMOSPHERE_RATE)
	arrival -= delta
	if arrival<=0:
		arrival = Balance.PARTY_ARRIVAL_FAST if atmosphere>=Balance.PARTY_HOT_ATMOSPHERE else Balance.PARTY_ARRIVAL_SLOW
		if music_running and atmosphere>=Balance.PARTY_INVITE_ATMOSPHERE and guests.size()<GOAL+Balance.PARTY_OVERFLOW_GUESTS:
			invite()
		elif music_running and atmosphere<Balance.PARTY_LEAVE_ATMOSPHERE:
			begin_departure()
	update_guests(delta,music_running)
	update_conversation(delta)
	if indoor_count()>=GOAL and atmosphere>=64:
		full_time += delta
		if full_time>=15 and not won:
			won = true
			GameEvents.notify(tr("Аншлаг! Ты удержал полный дом и атмосферу."))
	else:
		full_time = 0

func begin_departure() -> void:
	if departure_delay>0.0:
		return
	for node in guests:
		var guest := node as PartyGuest
		if guest.leaving or guest.fighting or is_instance_valid(guest.partner):
			continue
		if navigation_grid.route_out(guest,departure_side):
			guest.leaving = true
			departure_side = -departure_side
			departure_delay = 1.1
			return
	departure_delay = 1.1

func update_guests(delta: float, music_running: bool) -> void:
	var dj := home.night_game.dj
	for guest in guests.duplicate():
		if not music_running:
			guest.dancing = false
		guest.social_cooldown = maxf(0,guest.social_cooldown-delta)
		if is_instance_valid(guest.smoking_prop):
			guest.smoking_prop.visible = home.night_world.outside(guest.position)
			guest.smoke_timer -= delta
			if guest.smoking_prop.visible and guest.smoke_timer<=0:
				guest.smoke_timer = 1.8
				guest_smoke(guest.smoking_prop)
		var distance: float = guest.position.distance_squared_to(home.player.global_position)
		guest.name_tag.visible = distance<16.0
		guest.pose_interval = 1.0/30.0 if distance<25.0 else 1.0/12.0
		if is_instance_valid(guest.imported_model):
			guest.imported_model.dance_energy = .45+dj.bass*1.35 if dj.manual else 1.0
		if not guest.advance(delta,beat):
			continue
		if guest.fighting:
			continue
		if guest.leaving:
			if guest.cursor<guest.route.size():
				continue
			var view := get_viewport().get_camera_3d()
			if view==null or not view.is_position_in_frustum(guest.global_position+Vector3.UP*.85) or distance>32.0*32.0:
				guests.erase(guest)
				guest.queue_free()
		elif is_instance_valid(guest.partner) or not active:
			continue
		elif guest.rest>5.0+float(guest.preference):
			navigation_grid.find_destination(guest)
		else:
			guest.dancing = music_running and atmosphere>=52 and (guest.position-deck.position).length()<3.6 				and navigation_grid.space_available(guest,guest.position,false)

func update_conversation(delta: float) -> void:
	if not conversation.is_empty():
		var first = conversation.first
		var second = conversation.second
		conversation.time -= delta
		if not is_instance_valid(first) or not is_instance_valid(second) or first.leaving or second.leaving or (conversation.time<=0 and conversation.line>=2):
			for guest in [first,second]:
				if is_instance_valid(guest):
					guest.partner = null
					guest.speech.hide()
					guest.rest = 0
			conversation.clear()
			conversation_wait = 3.0
		elif conversation.time<=0:
			conversation.line += 1
			show_dialogue()
		return
	conversation_wait -= delta
	if conversation_wait>0:
		return
	conversation_wait = .65
	for first in guests:
		if first.leaving or first.fighting or is_instance_valid(first.partner) or first.cursor<first.route.size():
			continue
		for second in guests:
			if second==first or second.leaving or second.fighting or is_instance_valid(second.partner) or second.cursor<second.route.size():
				continue
			var distance: float = first.position.distance_to(second.position)
			if distance<.55 or distance>1.85:
				continue
			var query := PhysicsRayQueryParameters3D.create(first.position+Vector3.UP*1.43,second.position+Vector3.UP*1.43,1,[home.player.get_rid()])
			if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
				continue
			first.partner = second
			second.partner = first
			first.dancing = false
			second.dancing = false
			conversation = {"first":first,"second":second,"line":0,"time":0.0,"lines":EXCHANGES[rng.randi_range(0,EXCHANGES.size()-1)]}
			show_dialogue()
			return

func show_dialogue() -> void:
	var speaker = conversation.first if conversation.line%2==0 else conversation.second
	conversation.first.speech.hide()
	conversation.second.speech.hide()
	speaker.speech.text = tr(conversation.lines[conversation.line])
	speaker.speech.show()
	conversation.time = 2.8



func invite() -> void:
	var arrival_point: Vector3 = navigation_grid.cells[navigation_grid.entrance]
	for guest in guests:
		if guest.position.distance_squared_to(arrival_point)<.65*.65:
			return
	var variants: Array = guest_models[guest_serial%2]
	var model: Node3D = null
	if not variants.is_empty():
		model = variants[(guest_serial/2)%variants.size()]
	var guest := PartyGuest.new(guest_serial,model,psx_assets)
	guest_serial += 1
	cash += 1
	home.shop.save_stock()
	guest.position = arrival_point
	crowd.add_child(guest)
	guests.append(guest)
	navigation_grid.find_destination(guest)



func build_hud() -> void:
	var view: Control = STATUS_VIEW.instantiate()
	home.hud.root.add_child(view)
	panel = view.get_node("%Panel")
	status = view.get_node("%Status")
	meter = view.get_node("%Meter")
	message = view.get_node("%Message")
	prompt = view.get_node("%Prompt")
	refresh_hud()

func refresh_hud() -> void:
	var club_shift = home.club.shift
	var at_club: bool = is_instance_valid(club_shift) and club_shift.nearby()
	panel.visible = not at_club and active and not home.modal and not is_instance_valid(home.night_game.guest)
	prompt.visible = not at_club and not active and not home.modal
	if prompt.visible:
		prompt.text = tr("J · Начать вечеринку    B · Пиво    N · Сигарета") if near_deck() else tr("Найди DJ-пульт в спальне-студии    B · Пиво    N · Сигарета")
	if not panel.visible or not is_instance_valid(home.night_game.dj):
		return
	meter.value = atmosphere
	var signal_text := tr("БИТ") if beat<.20 else "·"
	var dj = home.night_game.dj
	var song: int = dj.current_builtin()
	var now_playing: String = dj.current_title()
	if now_playing.is_empty():
		now_playing = tr("Выбери трек на ноутбуке")
	status.text = tr("%s   %d/%d внутри   %d%%") % [tr("Аншлаг!") if won else tr("Вечеринка"),indoor_count(),GOAL,roundi(atmosphere)]
	message.text = tr("%s%s · запрос %s · %s\n%s\nB пиво · N сигарета · K потушить · R энергетик · V тошнит") % [
		now_playing,(" %d BPM" % roundi(BPM[song])) if song>=0 else "",TRACKS[requested],signal_text,
		tr("E ноутбук · C контроллер · 1–3 хаус") if near_deck() else tr("Вернись к пульту, чтобы сменить трек.")]
	message.text += tr("\nНа улице %d · $%d · сигарет %d") % [guests.size()-indoor_count(),cash,cigarettes]
	if song>=0:
		message.text += "\n"+["Hotham · CC BY 4.0","Play House · CC0","1000 Handz · CC BY 4.0"][song]
	if full_time>0 and not won:
		message.text += tr("\nУдержи аншлаг ещё %d с") % ceili(maxf(0,15-full_time))

func indoor_count() -> int:
	var count := 0
	for person in guests:
		if not person.leaving and not home.night_world.outside(person.position):
			count += 1
	return count

func guest_smoke(source: Node3D) -> void:
	var cloud := oval(self,to_local(source.global_position),Vector3.ONE*.018,Color("#a6abb1"))
	var finish := cloud.material_override as StandardMaterial3D
	finish.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	finish.albedo_color.a = .13
	var vapor := create_tween().set_parallel()
	vapor.tween_property(cloud,"position",cloud.position+Vector3(.08,.27,.02),1.8)
	vapor.tween_property(cloud,"scale",Vector3.ONE*.065,1.8)
	vapor.tween_property(finish,"albedo_color:a",0.0,1.8)
	vapor.chain().tween_callback(cloud.queue_free)









var detail_textures := {}







func oval(parent: Node3D, at: Vector3, size: Vector3, tint: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radial_segments = 14
	mesh.rings = 7
	var model := shape(parent,mesh,at,tint)
	model.scale = size
	return model

func box(parent: Node3D, at: Vector3, size: Vector3, tint: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	shape(parent,mesh,at,tint)

func cylinder(parent: Node3D, at: Vector3, radius: float, height: float, tint: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 14
	return shape(parent,mesh,at,tint)

func shape(parent: Node3D, mesh: Mesh, at: Vector3, tint: Color) -> MeshInstance3D:
	var model := MeshInstance3D.new()
	model.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = .48
	model.material_override = material
	model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(model)
	model.position = at
	return model
