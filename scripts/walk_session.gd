extends Node
## The host relays player actions and owns shared scene and DJ state.

signal status_changed(text: String)
## A chat line arrived (system: join/leave notices, author is empty).
signal chat_received(author: String, text: String, system: bool)
const CHAT_LIMIT := 200
const CHAT_HISTORY := 60
const NAME_LIMIT := 20
const PORT := 27880
const MAX_GUESTS := 7
const SEND_INTERVAL := 0.0667
const JOIN_TIMEOUT := 10.0

var active := false
var pending := false
var notice := ""
var world: Node
var actors := {}
var poses := {}
var clock := 0.0
var time_left := 0.0
var game_state: RefCounted
## Nicknames of everyone in the session, peer id -> name (kept by the host).
var names := {}
## Recent chat lines [author, text, system], kept across the scene reload.
var chat_log: Array = []

func _ready() -> void:
	multiplayer.connected_to_server.connect(on_connected)
	multiplayer.connection_failed.connect(on_connection_failed)
	multiplayer.server_disconnected.connect(on_server_disconnected)
	multiplayer.peer_disconnected.connect(remove_peer)
	multiplayer.peer_disconnected.connect(on_peer_left)

func host() -> void:
	reset_peer()
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_server(PORT, MAX_GUESTS)
	if result != OK:
		status_changed.emit(tr("Не удалось открыть UDP-порт %d.") % PORT)
		return
	multiplayer.multiplayer_peer = peer
	chat_log.clear()
	names = {1: GameSettings.nickname()}
	add_chat("", tr("%s создал(а) прогулку") % names[1], true)
	enter_world()

func join(address: String) -> void:
	address = address.strip_edges()
	if address.is_empty():
		status_changed.emit(tr("Введи IP-адрес компьютера друга."))
		return
	reset_peer()
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_client(address, PORT)
	if result != OK:
		status_changed.emit(tr("Не удалось начать подключение. Проверь адрес."))
		return
	pending = true
	time_left = JOIN_TIMEOUT
	multiplayer.multiplayer_peer = peer
	status_changed.emit(tr("Подключаемся…"))

func on_connected() -> void:
	if pending:
		chat_log.clear()
		names.clear()
		register_name.rpc_id(1, GameSettings.nickname())
		enter_world()

func enter_world() -> void:
	active = true
	pending = false
	notice = ""
	get_tree().reload_current_scene.call_deferred()

func bind_world(home: Node) -> void:
	world = home
	clock = 0.0
	game_state = load("res://scripts/walk_game_state.gd").new(home)

func can_control_decks() -> bool:
	return not active or multiplayer.is_server()

func operate_party_lights(accent: bool) -> void:
	if active and not multiplayer.is_server():
		request_party_lights.rpc_id(1, accent)
	else:
		get_tree().current_scene.party.operate_lights(accent)

@rpc("any_peer", "call_remote", "reliable")
func request_party_lights(accent: bool) -> void:
	if not active or not multiplayer.is_server() or not is_instance_valid(world) or not world.party.active:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(sender) or not poses.has(sender):
		return
	var position: Vector3 = poses[sender][0]
	if not world.night_world.outside(position) and position.y > -1.0:
		world.party.operate_lights(accent)

func toggle_map_door(door: Node3D) -> void:
	if multiplayer.is_server():
		door.set_open(not door.opened)
	elif game_state != null:
		request_door.rpc_id(1, String(world.get_path_to(door)))

@rpc("any_peer", "call_remote", "reliable")
func request_door(path: String) -> void:
	if not active or not multiplayer.is_server() or game_state == null:
		return
	var id := multiplayer.get_remote_sender_id()
	if not poses.has(id) or not multiplayer.get_peers().has(id):
		return
	var door: Node3D = game_state.doors.get(path)
	if is_instance_valid(door) and door.global_position.distance_to(poses[id][0]) < 3.2:
		door.set_open(not door.opened)

func reset_peer() -> void:
	active = false
	pending = false
	world = null
	game_state = null
	for id in actors.keys():
		remove_peer(id)
	poses.clear()
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer:
		peer.close()
		multiplayer.multiplayer_peer = null

func leave(message: String = "") -> void:
	var was_active := active
	reset_peer()
	if was_active:
		notice = message
		get_tree().reload_current_scene.call_deferred()

func on_connection_failed() -> void:
	if pending:
		reset_peer()
		status_changed.emit(tr("Сервер недоступен. Проверь IP и UDP-порт %d.") % PORT)

func on_server_disconnected() -> void:
	if active:
		leave(tr("Хост отключился."))
	elif pending:
		on_connection_failed()

func on_peer_left(id: int) -> void:
	if active and multiplayer.is_server() and names.has(id):
		var name: String = names[id]
		names.erase(id)
		receive_names.rpc(names)
		broadcast_system(tr("%s отключился") % name)

# --- chat -------------------------------------------------------------------

func display_name(id: int) -> String:
	return str(names.get(id, tr("Игрок %d") % (id % 1000)))

static func clean_name(text: String) -> String:
	text = text.strip_edges().replace("
", " ").left(NAME_LIMIT)
	return text if not text.is_empty() else "Игрок"

@rpc("any_peer", "call_remote", "reliable")
func register_name(nickname: String) -> void:
	if not active or not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(id) or names.has(id):
		return
	nickname = clean_name(nickname)
	var taken: Array = names.values()
	var unique := nickname
	var suffix := 2
	while unique in taken:
		unique = "%s %d" % [nickname, suffix]
		suffix += 1
	names[id] = unique
	receive_names.rpc(names)
	receive_history.rpc_id(id, chat_log)
	broadcast_system(tr("%s подключился") % unique)
	if is_instance_valid(actors.get(id)):
		actors[id].name_tag.text = unique

@rpc("authority", "call_remote", "reliable")
func receive_names(all: Dictionary) -> void:
	names = all
	for id in actors:
		if is_instance_valid(actors[id]):
			actors[id].name_tag.text = display_name(id)

@rpc("authority", "call_remote", "reliable")
func receive_history(lines: Array) -> void:
	for line in lines:
		if line is Array and line.size() == 3:
			add_chat(str(line[0]), str(line[1]), bool(line[2]))

func send_chat(text: String) -> void:
	text = text.strip_edges().left(CHAT_LIMIT)
	if text.is_empty() or not active:
		return
	if multiplayer.is_server():
		relay_chat(1, text)
	else:
		submit_chat.rpc_id(1, text)

@rpc("any_peer", "call_remote", "reliable")
func submit_chat(text: String) -> void:
	if not active or not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if multiplayer.get_peers().has(id):
		relay_chat(id, text.strip_edges().left(CHAT_LIMIT))

func relay_chat(id: int, text: String) -> void:
	if text.is_empty():
		return
	receive_chat.rpc(display_name(id), text, false)
	add_chat(display_name(id), text, false)

func broadcast_system(text: String) -> void:
	receive_chat.rpc("", text, true)
	add_chat("", text, true)

@rpc("authority", "call_remote", "reliable")
func receive_chat(author: String, text: String, system: bool) -> void:
	add_chat(author.left(NAME_LIMIT + 4), text.left(CHAT_LIMIT), system)

func add_chat(author: String, text: String, system: bool) -> void:
	chat_log.append([author, text, system])
	if chat_log.size() > CHAT_HISTORY:
		chat_log.pop_front()
	chat_received.emit(author, text, system)

func remove_peer(id: int) -> void:
	if active and multiplayer.is_server() and is_instance_valid(world):
		world.night_world.delivery.release_peer(id)
	poses.erase(id)
	var avatar = actors.get(id)
	if is_instance_valid(avatar):
		avatar.queue_free()
	actors.erase(id)

func _process(delta: float) -> void:
	if pending:
		time_left -= delta
		if time_left <= 0.0:
			on_connection_failed()
	if not active or not is_instance_valid(world):
		return
	var blend := 1.0 - exp(-delta * 14.0)
	for id in actors:
		var actor: Node3D = actors[id]
		var pose: Array = poses[id]
		var delivery := world.night_world.delivery as Node3D
		var seat: int = delivery.peer_seat(id)
		if is_instance_valid(actor.imported_model):
			actor.imported_model.pickup_seat = seat
		if seat >= 0:
			actor.global_position = delivery.seat_root(seat)
			actor.rotation.y = delivery.truck.global_rotation.y + PI
			actor.pose(delta, 0.0, false)
		else:
			actor.global_position = actor.global_position.lerp(pose[0], blend)
			actor.rotation.y = lerp_angle(actor.rotation.y, pose[1], blend)
			actor.pose(delta, 0.0, pose[2])
		game_state.apply_prop(actor, 0 if seat >= 0 else pose[3], pose[4], blend)
	clock += delta
	if clock < SEND_INTERVAL:
		return
	clock = fmod(clock, SEND_INTERVAL)
	var player: CharacterBody3D = world.player
	var walking := Vector2(player.velocity.x, player.velocity.z).length_squared() > 0.025
	var prop: Array = game_state.local_prop()
	var local_pose := [player.global_position, player.rotation.y, walking, prop[0], prop[1]]
	if multiplayer.is_server():
		poses[1] = local_pose
		if not multiplayer.get_peers().is_empty():
			receive_poses.rpc(poses)
			receive_delivery.rpc(world.night_world.delivery.network_state())
			if game_state.sync_due(SEND_INTERVAL):
				receive_game_state.rpc(game_state.snapshot())
				var crowd: Array = world.party.crowd_snapshot()
				receive_crowd.rpc(crowd[0], crowd[1])
	else:
		submit_pose.rpc_id(1, player.global_position, player.rotation.y, walking, prop[0], prop[1])

@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_pose(position: Vector3, yaw: float, walking: bool, kind: int, prop: Transform3D) -> void:
	if not active or not multiplayer.is_server() or not position.is_finite() or not is_finite(yaw):
		return
	var id := multiplayer.get_remote_sender_id()
	if id <= 1 or not multiplayer.get_peers().has(id) or position.length_squared() > 40000.0:
		return
	if kind < 0 or kind > 4 or not prop.is_finite() or prop.origin.length_squared() > 9.0:
		return
	poses[id] = [position, wrapf(yaw, -PI, PI), walking, kind, prop.orthonormalized()]
	ensure_avatar(id)

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func receive_game_state(snapshot: Dictionary) -> void:
	if active and game_state != null:
		game_state.apply_snapshot(snapshot)

@rpc("any_peer", "call_remote", "reliable")
func request_pickup_seat(seat: int) -> void:
	if not active or not multiplayer.is_server() or not is_instance_valid(world):
		return
	var id := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(id) or not poses.has(id):
		pickup_seat_result.rpc_id(id,false,-1,Vector3.ZERO)
		return
	var result: Array = world.night_world.delivery.change_seat(id,seat,poses[id][0])
	pickup_seat_result.rpc_id(id,result[0],result[1],result[2])

@rpc("authority", "call_remote", "reliable")
func pickup_seat_result(accepted: bool, seat: int, exit: Vector3) -> void:
	if active and is_instance_valid(world):
		world.night_world.delivery.apply_seat_result(accepted,seat,exit)

@rpc("authority", "call_remote", "unreliable_ordered", 3)
func receive_delivery(state: Array) -> void:
	if active and is_instance_valid(world):
		world.night_world.delivery.apply_network_state(state)

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func receive_crowd(crowd_poses: PackedFloat32Array, speech: Dictionary) -> void:
	if active and is_instance_valid(world):
		world.party.apply_crowd_snapshot(crowd_poses, speech)

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_poses(snapshot: Dictionary) -> void:
	if not active or not is_instance_valid(world):
		return
	for id in actors.keys():
		if not snapshot.has(id):
			remove_peer(id)
	var local_id := multiplayer.get_unique_id()
	for id in snapshot:
		if id == local_id:
			continue
		poses[id] = snapshot[id]
		ensure_avatar(id)

func ensure_avatar(id: int) -> void:
	if actors.has(id) or not is_instance_valid(world):
		return
	var guest_script := load("res://scripts/party_guest.gd")
	var actor: Node3D = guest_script.new(1 + id % 11, null, world.party.psx_assets)
	actor.name = "WalkPlayer_%d" % id
	world.add_child(actor)
	actor.global_position = poses[id][0]
	actor.rotation.y = poses[id][1]
	actor.name_tag.text = display_name(id)
	actor.name_tag.show()
	if is_instance_valid(actor.smoking_prop):
		actor.smoking_prop.hide()
	actors[id] = actor
