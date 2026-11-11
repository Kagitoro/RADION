extends Node3D

const Guest = preload("res://scripts/party_guest.gd")
const GuestModel = preload("res://scripts/guest_model.gd")
const PartyEvents = preload("res://scripts/party_events.gd")
var events: Node3D
var guest_models: Array[Array] = [[],[]]
var psx_assets := {}
const CELL := .28
const GOAL := 12
const TRACKS := ["Move Your Body","DJ Dance","Take You Higher"]
const BPM := [122.0,128.0,126.0]

var home
var deck := Node3D.new()
var deck_light := OmniLight3D.new()
var crowd := Node3D.new()
var music: Array[AudioStreamPlayer] = []
var tracks: Array[AudioStreamMP3] = []
var music_bus := -1
var music_gain := .85
var outside_filter := AudioEffectLowPassFilter.new()
var fader: Tween
var playing := 0
var track := 0
var requested := 1
var track_time := 0.0
var request_time := 0.0
var mix_time := 0.0
var arrival := 0.0
var full_time := 0.0
var atmosphere := 50.0
var bonus := 0.0
var beat := 0.0
var active := false
var starting := false
var won := false
var guests: Array[Node3D] = []
var guest_serial := 0
var navigation := AStarGrid2D.new()
var cells := {}
var connected: Array[Vector2i] = []
var dance_floor: Array[Vector2i] = []
var indoor_cells: Array[Vector2i] = []
var outdoor_cells: Array[Vector2i] = []
var entrance := Vector2i.ZERO
var rng := RandomNumberGenerator.new()
var hand_prop: Node3D
var bottle_model: Node3D
var falling_bits: Array[Dictionary] = []
var lip_cigarette: Node3D
var lip_view: Node3D
var hud_elapsed := 0.0
var music_paused := false
var ember_timer := 0.0
var cigarette_hand: Node3D
var cigarette_held := false
var cigarette_burn := 0.0
var cigarettes := 3
var cash := 18
var action_audio := AudioStreamPlayer.new()
var sip_audio: AudioStreamWAV
var breath_audio: AudioStreamWAV
var drinks := 0
var smokes := 0
var conversation := {}
var conversation_wait := 1.5
const EXCHANGES := [
	["Привет! Ты давно здесь?","Недавно. Что сейчас играет?","Пойдём ближе к пульту, там лучше слышно."],
	["Слышишь, как поменялся бас?","Да. Вот этот трек я бы оставил подольше.","Согласен. Пусть пока играет."],
	["Ты уже видел комнату с мониторами?","Да, там сейчас все танцуют.","Давай тоже заглянем."],
	["Здесь уже почти полный дом.","Ага, я даже в коридоре встретил знакомых.","Пойдём поздороваемся."]
]
var panel: PanelContainer
var meter: ProgressBar
var status: Label
var message: Label
var prompt: Label

func _init(editor) -> void:
	home = editor

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
		bottle_model = document.generate_scene(state) as Node3D
		if bottle_model!=null:
			add_child(bottle_model)
			bottle_model.hide()
	add_child(action_audio)
	action_audio.volume_db = -10
	sip_audio = action_sound(true)
	breath_audio = action_sound(false)
	add_child(deck)
	add_child(crowd)
	preload("res://scripts/dj_station.gd").build_laptop(self)
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
		var stream := AudioStreamMP3.load_from_file("res://assets/party/"+title+".mp3")
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
	deck.position = home.room_point("studio",Vector3(6.7,.85,-1.10))

func near_deck() -> bool:
	var player_point: Vector3 = home.player.global_position
	return absf(player_point.y+.9-deck.position.y)<1.05 and Vector2(player_point.x,player_point.z).distance_to(Vector2(deck.position.x,deck.position.z))<1.85

func toggle() -> void:
	if active or starting:
		stop()
	elif near_deck():
		starting = true
		home.hud.notice("Открываем двери гостям…")
	else:
		home.hud.notice("Подойди к DJ-пульту на рабочем столе в спальне-студии.")

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
		guest.queue_free()
	guests.clear()
	conversation.clear()

func start() -> void:
	starting = false
	if not rebuild_navigation():
		home.hud.notice("Рядом с пультом мало проходов. Освободи место и попробуй снова.")
		return
	active = true
	won = false
	full_time = 0
	arrival = .6
	atmosphere = 54
	bonus = 0
	guest_serial = 0
	requested = 0
	request_time = 40
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
	mix_time = 1.6
	if minf(beat,1.0-beat)<.20:
		bonus = minf(20,bonus+7)
		home.hud.notice("Сведение в бит · атмосфера растёт")
	else:
		home.hud.notice("Нажимай M, когда в индикаторе загорается БИТ.")

func _physics_process(delta: float) -> void:
	if not is_instance_valid(home.player) or not is_instance_valid(status):
		return
	if not home.modal:
		update_falling_bits(delta)
	if is_instance_valid(lip_cigarette) and not home.modal:
		cigarette_burn += delta*.004
		update_cigarette_length()
		if cigarette_burn>=1.0 and not is_instance_valid(hand_prop):
			extinguish()
			return
		ember_timer -= delta
		if ember_timer<=0:
			ember_timer = .32
			ember_smoke()
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
	if not active or pause_music:
		return
	mix_time = maxf(0,mix_time-delta)
	track_time += delta
	var song: int = dj.current_builtin()
	if song<0:
		beat = dj.dance_phase()
	else:
		beat = fposmod(music[dj.audible_deck()].get_playback_position()*BPM[song]/60.0,1.0)
	deck_light.light_energy = .08+exp(-beat*8.0)*atmosphere*.003
	bonus = move_toward(bonus,0,delta*.75)
	request_time -= delta
	if request_time<=0:
		requested = (requested+1+int(guest_serial%2))%3
		request_time = 42
	var matched := 0.0
	for guest in guests:
		if guest.preference==song and not guest.leaving:
			matched += 1
	var mix := matched/maxf(1,float(guests.size()))
	var target := 58.0+(14.0 if song==requested else -3.0)+mix*15.0+bonus-maxf(0,track_time-95.0)*.43
	if dj.manual:
		target += dj.bass*16.0 if dj.has_playback() else -32.0
	atmosphere = move_toward(atmosphere,clampf(target,0,100),delta*5.0)
	arrival -= delta
	if arrival<=0:
		arrival = 2.4 if atmosphere>=67 else 3.7
		if atmosphere>=50 and guests.size()<GOAL+6:
			invite()
		elif atmosphere<36 and guests.size()>0:
			for guest in guests:
				if not guest.leaving:
					guest.leaving = true
					route_to(guest,entrance)
					break
	var music_running: bool = dj.has_playback()
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
			guests.erase(guest)
			guest.queue_free()
		elif is_instance_valid(guest.partner):
			continue
		elif guest.rest>5.0+float(guest.preference):
			find_destination(guest)
		elif music_running and atmosphere>=52 and (guest.position-deck.position).length()<3.6:
			guest.dancing = true
	update_conversation(delta)
	if indoor_count()>=GOAL and atmosphere>=64:
		full_time += delta
		if full_time>=15 and not won:
			won = true
			home.hud.notice("Аншлаг! Ты удержал полный дом и атмосферу.")
	else:
		full_time = 0

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
	speaker.speech.text = conversation.lines[conversation.line]
	speaker.speech.show()
	conversation.time = 2.8

func rebuild_navigation() -> bool:
	var floors: Array[Dictionary] = []
	var bounds := Rect2()
	for row in home.records.values():
		if str(row.kind)=="floor" and not bool(row.deleted):
			floors.append(row)
			var footprint: Rect2 = home.room_world_bounds(row)
			bounds = footprint if not bounds.has_area() else bounds.merge(footprint)
	if not bounds.has_area():
		return false
	var first := Vector2i((bounds.position/CELL).floor())
	var last := Vector2i((bounds.end/CELL).ceil())
	if (last.x-first.x)*(last.y-first.y)>100000:
		return false
	navigation.region = Rect2i(first,last-first+Vector2i.ONE)
	navigation.cell_size = Vector2(CELL,CELL)
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	navigation.update()
	cells.clear()
	connected.clear()
	dance_floor.clear()
	indoor_cells.clear()
	outdoor_cells.clear()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .17
	capsule.height = 1.56
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.exclude = [home.player.get_rid()]
	var physics := get_world_3d().direct_space_state
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var id := Vector2i(x,y)
			var point := Vector2(id)*CELL
			var height := -INF
			for floor_row in floors:
				if home.inside_room(floor_row,point,.01):
					height = maxf(height,home.floor_surface(floor_row))
			if is_finite(height):
				var at := Vector3(point.x,height,point.y)
				query.transform.origin = at+Vector3.UP*.84
				if physics.intersect_shape(query,1).is_empty():
					cells[id] = at
					continue
			navigation.set_point_solid(id)
	if cells.size()<12:
		return false
	var seed := closest_cell(deck.position,cells.keys())
	var seen := {}
	seen[seed] = true
	connected.append(seed)
	var cursor := 0
	while cursor<connected.size():
		var at := connected[cursor]
		cursor += 1
		if home.night_world.outside(cells[at]):
			outdoor_cells.append(at)
		else:
			indoor_cells.append(at)
		if Vector3(cells[at]).distance_to(deck.position)<3.2:
			dance_floor.append(at)
		for step in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var neighbor: Vector2i = at+step
			if cells.has(neighbor) and not seen.has(neighbor) and absf(float(cells[neighbor].y)-float(cells[at].y))<.14:
				seen[neighbor] = true
				connected.append(neighbor)
	var door_point: Vector3 = home.night_world.door_center+Vector3(-5.2,0,-4.9)
	entrance = closest_cell(door_point,connected)
	return connected.size()>=18

func closest_cell(point: Vector3, candidates: Array) -> Vector2i:
	var best := INF
	var result := Vector2i.ZERO
	for id in candidates:
		var distance := point.distance_squared_to(cells[id])
		if distance<best:
			best = distance
			result = id
	return result

func invite() -> void:
	var variants: Array = guest_models[guest_serial%2]
	var model: Node3D = null
	if not variants.is_empty():
		model = variants[(guest_serial/2)%variants.size()]
	var guest := Guest.new(guest_serial,model,psx_assets)
	guest_serial += 1
	cash += 1
	guest.position = cells[entrance]
	crowd.add_child(guest)
	guests.append(guest)
	find_destination(guest)

func find_destination(guest) -> void:
	var group := indoor_cells if not indoor_cells.is_empty() else connected
	if not outdoor_cells.is_empty() and rng.randf()<guest.outdoor_interest:
		group = outdoor_cells
	elif not dance_floor.is_empty() and rng.randf()<guest.dance_interest:
		group = dance_floor
	var destination: Vector2i = group[rng.randi_range(0,group.size()-1)]
	var player_point: Vector3 = home.player.global_position
	for trial in range(5):
		if player_point.distance_to(cells[destination])>.65 and guests.all(func(other): return other==guest or other.position.distance_to(cells[destination])>.55):
			break
		destination = group[rng.randi_range(0,group.size()-1)]
	route_to(guest,destination)

func route_to(guest, destination: Vector2i) -> void:
	var from := closest_cell(guest.position,connected)
	var path := PackedVector3Array()
	for id in navigation.get_id_path(from,destination):
		path.append(cells[id])
	guest.follow(path)

func build_hud() -> void:
	var root: Control = home.hud.root
	panel = home.hud.panel()
	root.add_child(panel)
	panel.position = Vector2(19,76)
	panel.custom_minimum_size.x = 330
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	status = home.hud.label("",18)
	column.add_child(status)
	meter = ProgressBar.new()
	meter.max_value = 100
	meter.show_percentage = false
	meter.custom_minimum_size.y = 8
	column.add_child(meter)
	message = home.hud.label("",13)
	column.add_child(message)
	prompt = home.hud.label("",14)
	root.add_child(prompt)
	prompt.position = Vector2(20,104)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	refresh_hud()

func refresh_hud() -> void:
	var club_shift = home.night_world.nightclub.shift
	var at_club: bool = is_instance_valid(club_shift) and club_shift.nearby()
	panel.visible = not at_club and active and not home.modal and not is_instance_valid(home.night_game.guest)
	prompt.visible = not at_club and not active and not home.modal
	if prompt.visible:
		prompt.text = ("J · Начать вечеринку" if near_deck() else "Найди DJ-пульт в спальне-студии")+"    B · Пиво    N · Сигарета"
	if not panel.visible or not is_instance_valid(home.night_game.dj):
		return
	meter.value = atmosphere
	var signal_text := "БИТ" if beat<.20 else "·"
	var dj = home.night_game.dj
	var song: int = dj.current_builtin()
	var now_playing: String = dj.current_title()
	if now_playing.is_empty():
		now_playing = "Выбери трек на ноутбуке"
	status.text = "%s   %d/%d внутри   %d%%" % ["Аншлаг!" if won else "Вечеринка",indoor_count(),GOAL,roundi(atmosphere)]
	message.text = "%s%s · запрос %s · %s\n%s\nB пиво · N сигарета · K потушить · P купить · V тошнит" % [
		now_playing,(" %d BPM" % roundi(BPM[song])) if song>=0 else "",TRACKS[requested],signal_text,
		"E ноутбук · C контроллер · 1–3 хаус" if near_deck() else "Вернись к пульту, чтобы сменить трек."]
	message.text += "\nНа улице %d · $%d · сигарет %d" % [guests.size()-indoor_count(),cash,cigarettes]
	if song>=0:
		message.text += "\n"+["Hotham · CC BY 4.0","Play House · CC0","1000 Handz · CC BY 4.0"][song]
	if full_time>0 and not won:
		message.text += "\nУдержи аншлаг ещё %d с" % ceili(maxf(0,15-full_time))

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

func consume(beer: bool) -> void:
	if home.player.collapsed or home.player.vomiting or is_instance_valid(hand_prop):
		return
	if is_instance_valid(lip_cigarette):
		if beer:
			home.hud.notice("Сначала потуши сигарету · K")
		else:
			handle_cigarette()
		return
	if not beer:
		if cigarettes<=0:
			home.hud.notice("Сигареты закончились · P купить пачку")
			return
		cigarettes -= 1
		cigarette_burn = 0.0
	var prop := Node3D.new()
	home.player.camera.add_child(prop)
	hand_prop = prop
	prop.position = Vector3(.27,-.27,-.61)
	var skin := Color("#ae785b")
	oval(prop,Vector3(.042,-.043,.051),Vector3(.086,.085,.073),skin)
	var sleeve := oval(prop,Vector3(.091,-.114,.12),Vector3(.09,.185,.088),Color("#5b6557"))
	sleeve.rotation.z = .35
	var item := Node3D.new()
	prop.add_child(item)
	if beer:
		build_bottle(item)
		for index in range(4):
			oval(prop,Vector3(.009,-.057+index*.018,-.035),Vector3(.067,.017,.025),skin)
		oval(prop,Vector3(.037,.016,.019),Vector3(.028,.044,.026),skin)
	else:
		var paper := cylinder(item,Vector3(0,.018,-.031),.0048,.066,Color("#eee9df"))
		paper.rotation.x = PI*.5
		paper.name = "Paper"
		detail_surface(paper,Color("#d3cdc0"),Color("#f1ece1"),.92)
		var filter := cylinder(item,Vector3(0,.018,.011),.005,.022,Color("#bb8c52"))
		filter.rotation.x = PI*.5
		detail_surface(filter,Color("#795331"),Color("#ceaa76"),.90)
		var ember := cylinder(item,Vector3(0,.018,-.066),.005,.008,Color("#e47b45"))
		ember.rotation.x = PI*.5
		ember.name = "Ember"
		var ash := cylinder(item,Vector3(0,.018,-.063),.0052,.011,Color("#72716d"))
		ash.rotation.x = PI*.5
		ash.name = "Ash"
		detail_surface(ash,Color("#2c2b2a"),Color("#a39d95"),.97)
		var glow := ember.material_override as StandardMaterial3D
		glow.emission_enabled = true
		glow.emission = Color("#ff6724")
		glow.emission_energy_multiplier = .65
		for index in range(2):
			oval(prop,Vector3(.007+index*.014,.005,-.01),Vector3(.016,.028,.054),skin)
		oval(prop,Vector3(-.006,-.006,.005),Vector3(.020,.022,.035),skin)
	for part in prop.find_children("*","GeometryInstance3D",true,false):
		part.layers = 8
	var actor = home.player
	var reflected := item.duplicate() as Node3D
	actor.action_grip.add_child(reflected)
	reflected.position = Vector3(-.018,0,-.015) if beer else Vector3(-.012,.0,-.017)
	for part in reflected.find_children("*","GeometryInstance3D",true,false):
		part.layers = 4
	if not beer:
		for part in item.get_children():
			var material := part.material_override.duplicate() as StandardMaterial3D
			# The camera prop draws over the torso while the mirrored copy keeps scene depth.
			material.no_depth_test = true
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			part.material_override = material
	actor.action_beer = beer
	actor.set_action_pose(.001)
	var motion := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if beer:
		var lip := Vector3(.023,-.112,-.132)
		var tilt := Basis.from_euler(Vector3(1.17,0,-.12))
		motion.tween_property(prop,"position",Vector3(.17,-.10,-.48),.21)
		motion.parallel().tween_method(actor.set_action_pose,.001,.52,.21)
		motion.tween_property(prop,"position",lip-tilt*Vector3(0,.158,0),.22)
		motion.parallel().tween_property(prop,"rotation",Vector3(1.17,0,-.12),.22)
		motion.parallel().tween_method(actor.set_action_pose,.52,1.0,.22)
		motion.tween_interval(.30)
		motion.tween_callback(finish_sip)
		motion.tween_property(prop,"rotation",Vector3(.26,0,-.10),.36)
		motion.parallel().tween_method(actor.set_action_pose,1.0,.20,.36)
	else:
		motion.tween_property(prop,"position",Vector3(.060,-.125,-.24),.38)
		motion.parallel().tween_method(actor.set_action_pose,.001,1.0,.38)
		motion.tween_interval(.66)
		motion.tween_callback(func():
			cigarette_burn = .12
			leave_cigarette(item,reflected,actor,prop)
		)
		motion.tween_property(prop,"position",Vector3(.27,-.27,-.50),.36)
		motion.parallel().tween_method(actor.set_action_pose,1.0,.20,.36)
		motion.tween_callback(exhale)
		smokes += 1
	motion.tween_property(prop,"position",Vector3(.31,-.44,-.52),.33)
	motion.parallel().tween_method(actor.set_action_pose,.20,0.0,.33)
	if beer:
		motion.tween_callback(reflected.queue_free)
		motion.tween_callback(prop.queue_free)
		motion.tween_callback(func(): hand_prop = null)
	else:
		motion.tween_callback(func():
			prop.hide()
			hand_prop = null
		)

func leave_cigarette(item: Node3D, reflected: Node3D, actor: Node3D, grip: Node3D) -> void:
	lip_view = item
	lip_cigarette = reflected
	cigarette_hand = grip
	cigarette_held = false
	lip_view.reparent(actor.camera,false)
	lip_view.position = Vector3(.012,-.063,-.018)
	lip_view.rotation = Vector3(-.12,-.06,0)
	reflected.reparent(actor.mouth_anchor(),false)
	reflected.position = Vector3(0,-.018,-.009) if is_instance_valid(actor.dj_rig) else Vector3(.014,-.064,-.109)
	reflected.rotation = Vector3.ZERO
	ember_timer = 0.0

func handle_cigarette() -> void:
	var actor = home.player
	var grip := cigarette_hand
	hand_prop = grip
	var motion := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if not cigarette_held:
		grip.position = Vector3(.060,-.125,-.24)
		grip.show()
		motion.tween_method(actor.set_action_pose,0.0,1.0,.28)
		motion.tween_callback(func():
			lip_view.reparent(grip,false)
			lip_view.transform = Transform3D.IDENTITY
			lip_cigarette.reparent(actor.action_grip,false)
			lip_cigarette.position = Vector3(-.012,0,-.017)
			lip_cigarette.rotation = Vector3.ZERO
			cigarette_held = true
		)
		motion.tween_property(grip,"position",Vector3(.24,-.26,-.44),.36)
		motion.parallel().tween_method(actor.set_action_pose,1.0,.22,.36)
	else:
		motion.tween_property(grip,"position",Vector3(.060,-.125,-.24),.38)
		motion.parallel().tween_method(actor.set_action_pose,.22,1.0,.38)
		motion.tween_interval(.48)
		motion.tween_callback(func():
			shed_ash()
			cigarette_burn = minf(1.0,cigarette_burn+.16)
			leave_cigarette(lip_view,lip_cigarette,actor,grip)
			exhale()
		)
		motion.tween_property(grip,"position",Vector3(.29,-.44,-.52),.34)
		motion.parallel().tween_method(actor.set_action_pose,1.0,0.0,.34)
	motion.tween_callback(func():
		if not cigarette_held:
			grip.hide()
		hand_prop = null
	)

func update_cigarette_length() -> void:
	var remaining := 1.0-clampf(cigarette_burn,0,1)*.86
	for item in [lip_view,lip_cigarette]:
		var paper: MeshInstance3D = item.get_node("Paper")
		paper.scale.y = remaining
		paper.position.z = .002-.033*remaining
		item.get_node("Ash").position.z = .002-.066*remaining
		item.get_node("Ember").position.z = .002-.066*remaining-.005

func extinguish() -> void:
	if is_instance_valid(hand_prop) or not is_instance_valid(lip_cigarette):
		return
	shed_ash()
	lip_view.queue_free()
	lip_cigarette.queue_free()
	cigarette_hand.queue_free()
	lip_view = null
	lip_cigarette = null
	cigarette_hand = null
	cigarette_held = false
	home.player.set_action_pose(0)
	home.hud.notice("Сигарета потушена · осталось %d" % cigarettes)

func buy_cigarettes() -> void:
	if cash<6:
		home.hud.notice("Пачка стоит $6 игровых денег. Гости оставляют чаевые.")
		return
	cash -= 6
	cigarettes += 5
	home.hud.notice("Куплено 5 сигарет · запас %d · $%d" % [cigarettes,cash])

func ember_smoke() -> void:
	var tip := lip_cigarette.get_node("Ember") as Node3D
	var at := tip.global_position
	var cloud := oval(self,to_local(at),Vector3.ONE*.013,Color("#b9bfc5"))
	var paint := cloud.material_override as StandardMaterial3D
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.albedo_color.a = .16
	var drift := create_tween().set_parallel()
	drift.tween_property(cloud,"position",cloud.position+Vector3(rng.randf_range(-.04,.04),.16,rng.randf_range(-.04,.04)),1.25)
	drift.tween_property(cloud,"scale",Vector3.ONE*.057,1.25)
	drift.tween_property(paint,"albedo_color:a",0.0,1.25)
	drift.chain().tween_callback(cloud.queue_free)

func finish_sip() -> void:
	var grip: Node3D = home.player.action_grip
	spill_bits(grip.to_global(Vector3(-.018,.158,-.025)),true,3)
	drinks += 1
	home.player.drink_beer()
	action_audio.stream = sip_audio
	action_audio.play()
	home.hud.notice("Опьянение · %d%%" % roundi(home.player.intoxication*100))

func exhale() -> void:
	action_audio.stream = breath_audio
	action_audio.play()
	var vapor := Node3D.new()
	var camera: Camera3D = home.player.camera
	add_child(vapor)
	vapor.global_transform = camera.global_transform
	for index in range(6):
		var cloud := oval(vapor,Vector3(.02,-.19,-.25-index*.016),Vector3.ONE*(.035+index*.006),Color("#c4c9cd"))
		var paint := cloud.material_override as StandardMaterial3D
		paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		paint.albedo_color.a = .07
		var drift := create_tween().set_parallel()
		drift.tween_property(cloud,"position",cloud.position+Vector3(sin(index*2.4)*.13,.26+index*.024,-.28),1.5)
		drift.tween_property(cloud,"scale",Vector3.ONE*2.1,1.5)
		drift.tween_property(paint,"albedo_color:a",0.0,1.5)
	get_tree().create_timer(1.6).timeout.connect(vapor.queue_free)

var detail_textures := {}

func detail_surface(mesh: MeshInstance3D, dark: Color, light: Color, roughness: float) -> void:
	var key := dark.to_html()+light.to_html()
	if not detail_textures.has(key):
		var grain := FastNoiseLite.new()
		grain.frequency = .23
		var ramp := Gradient.new()
		ramp.colors = PackedColorArray([dark,light])
		var texture := NoiseTexture2D.new()
		texture.width = 128
		texture.height = 128
		texture.seamless = true
		texture.noise = grain
		texture.color_ramp = ramp
		detail_textures[key] = texture
	var material := mesh.material_override as StandardMaterial3D
	material.albedo_color = Color.WHITE
	material.albedo_texture = detail_textures[key]
	material.roughness = roughness

func build_bottle(item: Node3D) -> void:
	if is_instance_valid(bottle_model):
		var glass_root := bottle_model.duplicate() as Node3D
		item.add_child(glass_root)
		glass_root.show()
		glass_root.scale = Vector3.ONE*(.264/.230)
		glass_root.position.y = -.106
		for mesh in glass_root.find_children("*","MeshInstance3D",true,false):
			if not str(mesh.name).contains("Hollow"):
				mesh.hide()
	else:
		cylinder(item,Vector3(0,-.023,0),.0357,.166,Color("#4c2e19"))
		oval(item,Vector3(0,.059,0),Vector3(.071,.063,.071),Color("#4c2e19"))
		cylinder(item,Vector3(0,.113,0),.019,.09,Color("#55331d"))
	var paper := cylinder(item,Vector3(0,-.021,0),.0359,.064,Color("#d1ba83"))
	(paper.mesh as CylinderMesh).radial_segments = 64
	detail_surface(paper,Color("#9d895c"),Color("#e0c99b"),.81)
	var band := cylinder(item,Vector3(0,-.046,0),.0361,.011,Color("#78352a"))
	(band.mesh as CylinderMesh).radial_segments = 64
	(band.material_override as StandardMaterial3D).roughness = .86
	var nameplate := Label3D.new()
	nameplate.text = "NIGHT\nLAGER"
	nameplate.font_size = 30
	nameplate.outline_size = 0
	nameplate.modulate = Color("#4a2e21")
	nameplate.pixel_size = .00042
	nameplate.position = Vector3(0,-.019,.0364)
	item.add_child(nameplate)
	for index in range(26):
		var angle := float(index)*2.4
		var at := Vector3(cos(angle)*.0357,.017+float(index%9)*.004,sin(angle)*.0357)
		var droplet := oval(item,at,Vector3(.0014,.0027,.0014),Color(.9,.83,.73,.64))
		var wet := droplet.material_override as StandardMaterial3D
		wet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wet.roughness = .09

func shed_ash() -> void:
	if not is_instance_valid(lip_cigarette):
		return
	var ash := lip_cigarette.get_node("Ash") as Node3D
	spill_bits(ash.global_position,false,5)

func spill_bits(origin: Vector3, beer: bool, count: int) -> void:
	for index in range(count):
		if falling_bits.size()>=36:
			return
		var size := rng.randf_range(.003,.006) if beer else rng.randf_range(.0015,.004)
		var tint := Color("#b77a31") if beer else Color("#77716b").darkened(rng.randf_range(0,.45))
		var bit := oval(self,to_local(origin),Vector3(size,size*1.3,size),tint)
		var material := bit.material_override as StandardMaterial3D
		material.roughness = .13 if beer else .98
		var forward: Vector3 = -home.player.camera.global_basis.z
		var velocity := forward*rng.randf_range(.12,.35)+Vector3(rng.randf_range(-.15,.15),rng.randf_range(-.05,.1),rng.randf_range(-.14,.14))
		falling_bits.append({"node":bit,"velocity":velocity,"age":0.0,"beer":beer})

func update_falling_bits(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	for index in range(falling_bits.size()-1,-1,-1):
		var entry := falling_bits[index]
		var bit: MeshInstance3D = entry.node
		entry.age += delta
		entry.velocity += Vector3.DOWN*delta*(8.0 if entry.beer else 3.4)
		var next: Vector3 = bit.global_position+entry.velocity*delta
		var ray := PhysicsRayQueryParameters3D.create(bit.global_position,next,1,[home.player.get_rid()])
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			var normal: Vector3 = hit.normal
			bit.global_position = hit.position+normal*.0015
			bit.scale *= Vector3(1.75,.19,1.75)
			get_tree().create_timer(4.0 if entry.beer else 9.0).timeout.connect(bit.queue_free)
			falling_bits.remove_at(index)
		elif entry.age>2.2:
			bit.queue_free()
			falling_bits.remove_at(index)
		else:
			bit.global_position = next

func action_sound(beer: bool) -> AudioStreamWAV:
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = 24000
	var samples := PackedByteArray()
	var count := 7400 if beer else 15600
	samples.resize(count*2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 52
	var low := 0.0
	for index in range(count):
		var time := float(index)/24000.0
		var raw := noise.randf_range(-1,1)
		low = lerpf(low,raw,.085)
		var envelope := pow(sin(PI*float(index)/count),2)
		var value := (raw-low)*envelope*.12
		if beer:
			var pulse := exp(-pow((time-.085)/.034,2))+.66*exp(-pow((time-.186)/.044,2))
			value = pulse*(low*.74+sin(TAU*(110*time-48*time*time))*.25)*envelope
		samples.encode_s16(index*2,roundi(clampf(value,-1,1)*32767))
	audio.data = samples
	return audio

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
