extends RefCounted

const CLUB_TRACK = preload("res://assets/party/DJ Dance.mp3")

var home: Node
var doors := {}
var club_track: AudioStreamMP3
var time_since_snapshot := 0.2

func _init(world: Node) -> void:
	home = world
	club_track = CLUB_TRACK.duplicate()
	club_track.loop = true
	for door in home.get_tree().get_nodes_in_group("map_doors"):
		if home.is_ancestor_of(door):
			doors[String(home.get_path_to(door))] = door

func sync_due(delta: float) -> bool:
	time_since_snapshot += delta
	if time_since_snapshot < 0.19:
		return false
	time_since_snapshot = 0.0
	return true

func local_prop() -> Array:
	var action = home.party.consumables
	if is_instance_valid(action.lip_cigarette) and action.lip_cigarette.is_visible_in_tree():
		return [1, Transform3D.IDENTITY]
	var prop: Node3D = action.reflected
	if not is_instance_valid(prop) or not prop.is_visible_in_tree():
		return [0, Transform3D.IDENTITY]
	var kind := 2
	if String(prop.name).begins_with("Bottle"):
		kind = 3
	elif String(prop.name).begins_with("Can"):
		kind = 4
	return [kind, home.player.global_transform.affine_inverse() * prop.global_transform]

func apply_prop(actor: Node3D, kind: int, pose: Transform3D, blend: float) -> void:
	var prop := actor.get_node_or_null("NetworkProp") as Node3D
	var model: Node3D = actor.imported_model
	if kind == 1 and is_instance_valid(model):
		pose = actor.global_transform.affine_inverse() * model.mouth_transform()
		pose *= Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, -0.01, -0.032))
	elif kind == 1:
		pose = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.01, 1.55, -0.14))
	if prop != null and prop.get_meta("kind") != kind:
		actor.remove_child(prop)
		prop.queue_free()
		prop = null
	if kind == 0:
		return
	if prop == null:
		match kind:
			1, 2: prop = FPProps.cigarette(false)
			3: prop = FPProps.beer_bottle(false)
			4: prop = FPProps.energy_can(false)
		prop.name = "NetworkProp"
		prop.set_meta("kind", kind)
		actor.add_child(prop)
		prop.transform = pose
	else:
		prop.transform = prop.transform.interpolate_with(pose, blend)
	if kind > 1 and is_instance_valid(model) and not model.arms.is_empty():
		var skeleton: Skeleton3D = model.skeleton
		var wrist := prop.global_position
		if kind == 3:
			wrist += prop.global_basis.y * 0.08
		model.point_arm(model.arms[0], skeleton.to_local(wrist), Vector3(0.72, -1.0, -0.28))

func snapshot() -> Dictionary:
	var door_states := {}
	for path in doors:
		if is_instance_valid(doors[path]):
			door_states[path] = doors[path].opened
	return {
		"doors": door_states,
		"party": {
			"active": home.party.active,
			"mood": home.party.atmosphere,
			"request": home.party.requested,
			"full_time": home.party.full_time,
			"won": home.party.won,
			"beat": home.party.beat,
			"track_time": home.party.track_time,
			"deck_color": home.party.deck_light.light_color,
			"deck_energy": home.party.deck_light.light_energy,
			"light_mode": home.party.light_mode,
			"light_accent": home.party.light_accent,
		},
		"house": station_snapshot(home.night_game.dj, false),
		"club": station_snapshot(home.night_game.club_dj, true),
	}

func station_snapshot(station: Node, club: bool) -> Dictionary:
	var tracks := []
	for index in range(2):
		var player: AudioStreamPlayer = station.party.music[index]
		var track := -1
		if player.playing:
			if club:
				if not station.manual or station.sources[index] == 0:
					track = 0
			else:
				track = home.party.tracks.find(player.stream)
		tracks.append([track, player.get_playback_position(), player.stream_paused,
			player.pitch_scale, player.volume_db, station.bpm_fields[index].value,
			station.deck_buses.find(AudioServer.get_bus_index(player.bus))])
	var mixer := []
	for channel in range(station.deck_buses.size()):
		var bus: int = station.deck_buses[channel]
		var bands := []
		for band in range(6):
			bands.append(station.eq[channel].get_band_gain_db(band))
		mixer.append([AudioServer.get_bus_volume_db(bus), bands,
			AudioServer.is_bus_effect_enabled(bus, 1), AudioServer.is_bus_effect_enabled(bus, 2),
			station.low_pass[channel].cutoff_hz, station.high_pass[channel].cutoff_hz])
	return {"tracks": tracks, "mixer": mixer, "fx": [station.echo_enabled, station.reverb_selected,
		station.echo.tap1_level_db, station.reverb.wet]}

func apply_snapshot(state: Dictionary) -> void:
	for path in state.doors:
		if is_instance_valid(doors.get(path)):
			doors[path].set_open(state.doors[path])
	var party: Party = home.party
	if state.has("party"):
		var shared: Dictionary = state.party
		party.active = shared.active
		party.atmosphere = shared.mood
		party.requested = shared.request
		party.full_time = shared.full_time
		party.won = shared.won
		party.beat = shared.beat
		party.track_time = shared.track_time
		party.deck_light.light_color = shared.deck_color
		party.deck_light.light_energy = shared.deck_energy
		party.light_mode = shared.light_mode
		party.light_accent = shared.light_accent
	apply_station(home.night_game.dj, false, state.house)
	apply_station(home.night_game.club_dj, true, state.club)

func apply_station(station: Node, club: bool, state: Dictionary) -> void:
	for index in range(2):
		var player: AudioStreamPlayer = station.party.music[index]
		var track: Array = state.tracks[index]
		var source: int = track[0]
		if source < 0:
			if player.playing:
				player.stop()
			station.titles[index] = ""
			continue
		var stream: AudioStream = club_track if club else home.party.tracks[source]
		if player.stream != stream:
			player.stop()
			player.stream = stream
		if not player.playing:
			player.play(track[1])
		elif absf(player.get_playback_position() - track[1]) > 0.55:
			player.seek(track[1])
		player.stream_paused = track[2]
		player.pitch_scale = track[3]
		player.volume_db = track[4]
		station.bpm_fields[index].set_value_no_signal(track[5])
		station.titles[index] = station.party.track_titles()[source]
		if track[6] >= 0:
			player.bus = AudioServer.get_bus_name(station.deck_buses[track[6]])
	for channel in range(station.deck_buses.size()):
		var bus: int = station.deck_buses[channel]
		var mix: Array = state.mixer[channel]
		AudioServer.set_bus_volume_db(bus, mix[0])
		for band in range(6):
			station.eq[channel].set_band_gain_db(band, mix[1][band])
		AudioServer.set_bus_effect_enabled(bus, 1, mix[2])
		AudioServer.set_bus_effect_enabled(bus, 2, mix[3])
		station.low_pass[channel].cutoff_hz = mix[4]
		station.high_pass[channel].cutoff_hz = mix[5]
	station.echo_enabled = state.fx[0]
	station.reverb_selected = state.fx[1]
	station.echo.tap1_level_db = state.fx[2]
	station.reverb.wet = state.fx[3]
	station.apply_beat_fx()
