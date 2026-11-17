extends Node
## The host relays player actions and owns shared scene and DJ state.

signal status_changed(text: String)
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

func _ready() -> void:
	multiplayer.connected_to_server.connect(on_connected)
	multiplayer.connection_failed.connect(on_connection_failed)
	multiplayer.server_disconnected.connect(on_server_disconnected)
	multiplayer.peer_disconnected.connect(remove_peer)

func host() -> void:
	reset_peer()
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_server(PORT, MAX_GUESTS)
	if result != OK:
		status_changed.emit(tr("Не удалось открыть UDP-порт %d.") % PORT)
		return
	multiplayer.multiplayer_peer = peer
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

func remove_peer(id: int) -> void:
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
		actor.global_position = actor.global_position.lerp(pose[0], blend)
		actor.rotation.y = lerp_angle(actor.rotation.y, pose[1], blend)
		actor.pose(delta, 0.0, pose[2])
		game_state.apply_prop(actor, pose[3], pose[4], blend)
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
			if game_state.sync_due(SEND_INTERVAL):
				receive_game_state.rpc(game_state.snapshot())
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
	actor.name_tag.text = tr("Игрок %d") % (id % 1000)
	actor.name_tag.show()
	if is_instance_valid(actor.smoking_prop):
		actor.smoking_prop.hide()
	actors[id] = actor
