class_name ClubShift
extends Node

const SHIFT_SECONDS := 180.0
const GOAL := 8
const HOLD_SECONDS := 18.0
const EVENT_TIMES := [31.0,68.0,106.0]
const EVENT_NAMES := ["Просьба о треке","Очередь у бара","Спор у входа"]
const EVENT_STAFF := [1,0,2]
const ENTRY := Vector3(-4.2,.015,5.4)
const AISLE := Vector3(-4.2,.015,2.35)

var club: Nightclub
var dj: DJStation
var home: Home
const PANEL := preload("res://ui/club_shift_panel.tscn")
var panel: PanelContainer
var summary: Label
var detail: Label
var active := false
var finished := false
var won := false
var time := 0.0
var energy := 54.0
var held := 0.0
var admitted := 10
var crowd_timer := 0.0
var next_event := 0
var event := -1
var event_deadline := 0.0
var delegated := false
var feedback := ""
var feedback_time := 0.0
var sample_timer := 0.0
var last_track := ""
var requested_track := ""
var request_played := 0.0
var last_level := -80.0
var overlap := 0.0
var aligned := 0.0
var slots: Array[Vector3] = []
var paths: Array[PackedVector3Array] = []
var destinations: Array[Vector3] = []
var on_floor := 0
var incident_guests: Array[Node3D] = []

func setup(venue: Nightclub) -> void:
	club = venue
	home = club.world.home
	dj = club.dj
	for guest in club.dancers:
		slots.append(guest.position)
		paths.append(PackedVector3Array())
		destinations.append(guest.position)
	panel = PANEL.instantiate()
	home.hud.root.add_child(panel)
	summary = panel.get_node("%Summary")
	detail = panel.get_node("%Detail")
	panel.hide()

func nearby() -> bool:
	var at: Vector3 = club.to_local(home.player.global_position)
	return absf(at.x)<club.WALL_X and at.z>-6.6 and at.z<7.7

func start() -> void:
	active = true
	finished = false
	won = false
	time = 0.0
	energy = Balance.CLUB_START_ENERGY
	held = 0.0
	admitted = Balance.CLUB_START_GUESTS
	on_floor = 4
	clear_incident()
	crowd_timer = 0.0
	next_event = 0
	event = -1
	delegated = false
	feedback_time = 0.0
	sample_timer = 0.0
	overlap = 0.0
	aligned = 0.0
	last_level = -80.0
	last_track = track_key(dj.audible_deck())
	for index in range(club.dancers.size()):
		var guest: Node3D = club.dancers[index]
		guest.visible = index<admitted
		guest.position = slots[index] if index<admitted else ENTRY
		guest.dancing = index<admitted
		paths[index] = PackedVector3Array()
		destinations[index] = guest.position

func _process(delta: float) -> void:
	panel.visible = nearby() and (not home.modal or dj.using_controller)
	if not active:
		refresh()
		return
	if home.night_game.pause_panel.visible or home.night_game.menu.opened:
		return
	time += delta
	feedback_time = maxf(0,feedback_time-delta)
	sample_timer += delta
	if sample_timer>=.20:
		evaluate_mix(sample_timer)
		sample_timer = 0.0
	update_events(delta)
	update_crowd(delta)
	held = held+delta if on_floor>=GOAL and energy>=65.0 else 0.0
	if time>=SHIFT_SECONDS:
		active = false
		finished = true
		won = held>=HOLD_SECONDS
		if won:
			home.night_game.intro.first_booking_complete()
		if event>=0:
			club.staff[EVENT_STAFF[event]].speech.hide()
		event = -1
		clear_incident()
	refresh()

func track_key(index: int) -> String:
	var stream: AudioStream = club.music[index].stream
	return "" if stream==null else str(stream.get_instance_id())

func level_for(index: int) -> float:
	if not club.music[index].playing or club.music[index].stream_paused:
		return -80.0
	var bus: int = dj.deck_buses[dj.routing[index]]
	return maxf(AudioServer.get_bus_peak_volume_left_db(bus,0),AudioServer.get_bus_peak_volume_right_db(bus,0))

func evaluate_mix(delta: float) -> void:
	var deck: int = dj.audible_deck()
	var weights: Vector2 = dj.mix_weights()
	var level := maxf(level_for(0),level_for(1))
	var playing: bool = dj.has_playback() and club.music_gain>.08 and (not dj.manual or weights[deck]>.075)
	var target := 20.0
	if playing:
		target = 64.0 if not dj.manual else 75.0
		if dj.manual and weights[deck]<.35:
			target -= 12.0
		if level> -2.0:
			target -= 16.0
		target += clampf(dj.bass*12.0,0,8)
	if event>=0 and not delegated:
		target -= 4.0
	var old_energy := energy
	energy = move_toward(energy,target,delta*(Balance.CLUB_ENERGY_FALL_RATE if target<energy else Balance.CLUB_ENERGY_RISE_RATE))
	if not playing:
		overlap = 0.0
		aligned = 0.0
		last_level = -80.0
		return
	if club.music[0].playing and club.music[1].playing and not club.music[0].stream_paused and not club.music[1].stream_paused and minf(weights.x,weights.y)>.14:
		overlap = minf(6.0,overlap+delta)
		var a: float = dj.bpm_fields[0].value
		var b: float = dj.bpm_fields[1].value
		var tempo_difference := absf(a*club.music[0].pitch_scale-b*club.music[1].pitch_scale)
		var phase := fposmod((dj.deck_position(0)*a-dj.deck_position(1)*b)/60.0,1.0)
		if tempo_difference<4.0 and minf(phase,1.0-phase)<.26:
			aligned += delta
	else:
		overlap = maxf(0,overlap-delta*.4)
		aligned = minf(aligned,overlap)
	var current := track_key(deck)
	if current!=last_track:
		if not last_track.is_empty():
			if overlap>=.6 and aligned>=.25:
				energy = minf(100,energy+Balance.CLUB_SMOOTH_TRANSITION_BONUS)
				note(tr("Ровный переход · публика прибавляет"))
			elif overlap<.40:
				energy = maxf(0,energy-Balance.CLUB_HARD_CUT_PENALTY)
				note(tr("Резкая смена трека · часть гостей отходит"))
			else:
				note(tr("Переход услышали · выровняй темп и фазы"))
		last_track = current
		overlap = 0.0
		aligned = 0.0
	if level> -3.0 and last_level> -60.0 and level-last_level>9.0:
		energy = minf(energy,maxf(0,old_energy-Balance.CLUB_VOLUME_JUMP_PENALTY))
		note(tr("Скачок громкости · убавь Gain или Master"))
	last_level = level

func update_crowd(delta: float) -> void:
	crowd_timer += delta
	if crowd_timer>=Balance.CLUB_CROWD_TICK:
		crowd_timer = 0.0
		if energy>=Balance.CLUB_ADMIT_ENERGY and admitted<club.dancers.size():
			var newcomer: Node3D = club.dancers[admitted]
			newcomer.position = ENTRY
			newcomer.show()
			destinations[admitted] = ENTRY
			paths[admitted] = PackedVector3Array()
			admitted += 1
		elif energy<Balance.CLUB_DISMISS_ENERGY and admitted>Balance.CLUB_MIN_GUESTS:
			admitted -= 1
	on_floor = 0
	var dancing_limit := admitted if energy>=59.0 else maxi(1,admitted-3)
	for index in range(club.dancers.size()):
		var guest: Node3D = club.dancers[index]
		if not guest.visible:
			continue
		var destination := slots[index]
		if index>=admitted:
			destination = ENTRY
		elif index>=dancing_limit:
			destination = Vector3(5.9,.015,2.45-float(index%3)*.72) if index%2==0 else Vector3(-4.62,.015,1.38+float(index%3)*.58)
		if destinations[index]!=destination:
			var route := PackedVector3Array()
			if guest.position.z>4.8:
				route.append(AISLE)
			elif destination==ENTRY:
				route.append(Vector3(guest.position.x,.015,2.35))
				route.append(AISLE)
			elif absf(guest.position.x)>4.0 or absf(destination.x)>4.0:
				route.append(Vector3(guest.position.x,.015,2.35))
				route.append(Vector3(destination.x,.015,2.35))
			route.append(destination)
			paths[index] = route
			destinations[index] = destination
		var route := paths[index]
		if not route.is_empty() and guest.position.distance_to(route[0])<.065:
			route.remove_at(0)
			paths[index] = route
		guest.dancing = route.is_empty() and index<dancing_limit
		if guest.dancing:
			on_floor += 1
		elif not route.is_empty():
			var direction := guest.position.direction_to(route[0])
			guest.rotation.y = lerp_angle(guest.rotation.y,atan2(-direction.x,-direction.z),minf(1.0,delta*8))
			guest.position = guest.position.move_toward(route[0],delta*1.23)
		elif index>=admitted:
			guest.hide()

func begin_event(index: int) -> void:
	event = index
	event_deadline = time+Balance.CLUB_EVENT_TIME
	delegated = false
	request_played = 0.0
	requested_track = track_key(dj.audible_deck())
	if is_instance_valid(club.responding):
		club.responding.speech.hide()
	club.response_time = 0.0
	club.staff[EVENT_STAFF[index]].speech.text = [
		tr("Гость просит новый трек от 124 BPM."),
		tr("У бара очередь. Помоги раздать воду."),
		tr("У входа спорят. Подойди к охране."),
	][index]
	club.staff[EVENT_STAFF[index]].speech.show()
	spawn_incident(index)

func update_events(delta: float) -> void:
	if event<0:
		if next_event<EVENT_TIMES.size() and time>=EVENT_TIMES[next_event]:
			begin_event(next_event)
			next_event += 1
		return
	if time>=event_deadline:
		resolve(delegated,delegated)
		return
	if event==0 and not delegated:
		var deck: int = dj.audible_deck()
		var tempo: float = dj.bpm_fields[deck].value*club.music[deck].pitch_scale
		if dj.has_playback() and club.music_gain>.08 and dj.mix_weights()[deck]>.14 and track_key(deck)!=requested_track and tempo>=123.95:
			request_played += delta
			if request_played>=6.0:
				resolve(true,false)
		else:
			request_played = 0.0

func assign_staff() -> void:
	if active and event>=0 and not delegated and nearby():
		delegated = true
		event_deadline = time+Balance.CLUB_STAFF_EVENT_TIME
		note(tr("Персонал занялся ситуацией"))

func handle_staff(worker: Node3D) -> bool:
	if not active or event<0 or worker!=club.staff[EVENT_STAFF[event]]:
		return false
	if event==0:
		note(tr("Поставь новый трек от 124 BPM или поручи ответ официанту через H"))
	elif not delegated:
		resolve(true,false)
	return true

func spawn_incident(index: int) -> void:
	clear_incident()
	if index==0:
		return
	var locations: Array[Vector3] = [Vector3(-5.08,0,-.75),Vector3(-5.08,0,-.10)]
	if index==2:
		locations = [Vector3(-3.22,0,6.28),Vector3(-2.52,0,6.44)]
	for slot in range(locations.size()):
		var person = PartyGuest.new(12+slot,null,home.party.psx_assets)
		club.add_child(person)
		person.position = locations[slot]
		person.rotation.y = PI*.5 if index==1 or slot==1 else -PI*.5
		person.name_tag.hide()
		if index==2:
			person.speech.text = [tr("Я тут уже жду."),tr("Давай спокойно, разберёмся.")][slot]
			person.speech.show()
		incident_guests.append(person)

func clear_incident() -> void:
	for person in incident_guests:
		person.queue_free()
	incident_guests.clear()

func resolve(success: bool, by_staff: bool) -> void:
	clear_incident()
	club.staff[EVENT_STAFF[event]].speech.hide()
	if success:
		energy = minf(100,energy+(Balance.CLUB_EVENT_STAFF_BONUS if by_staff else Balance.CLUB_EVENT_SOLVED_BONUS))
		note(tr("Персонал всё уладил") if by_staff else [tr("Гость услышал новый трек"),tr("Очередь у бара рассосалась"),tr("У входа снова спокойно")][event])
	else:
		energy = maxf(0,energy-Balance.CLUB_EVENT_FAILED_PENALTY)
		note(tr("Ситуацию не решили · энергия упала"))
	event = -1
	delegated = false

func note(message: String) -> void:
	feedback = message
	feedback_time = 4.5

func refresh() -> void:
	if not panel.visible:
		return
	if not active:
		summary.text = (tr("Смена удалась") if won else tr("Смена окончена")) if finished else tr("RADION · Клубная смена")
		detail.text = tr("Финал: %d на танцполе · энергия %d%%. J · Начать смену") % [on_floor,roundi(energy)] if finished else tr("J · Начать смену")
		return
	var remaining := maxi(0,ceili(SHIFT_SECONDS-time))
	summary.text = tr("%d:%02d   •   Танцпол %d   •   Энергия %d%%") % [remaining/60,remaining%60,on_floor,roundi(energy)]
	var objective := tr("Финал: %d гостей, 65%% энергии · %d/%d с") % [GOAL,mini(int(held),int(HOLD_SECONDS)),int(HOLD_SECONDS)]
	if event>=0:
		var action: String = [tr("Новый трек от 124 BPM"),tr("E у бармена · помочь с очередью"),tr("E у охраны · уладить спор")][event]
		var status := tr("Персонал уже занимается") if delegated else tr("%s  /  H · поручить") % action
		detail.text = tr("%s\n%s · %d с\n%s") % [objective,tr(EVENT_NAMES[event]),maxi(0,ceili(event_deadline-time)),status]
	elif feedback_time>0.0:
		detail.text = objective+"\n"+feedback
	else:
		detail.text = objective
