extends Node3D

const PICKUP := preload("res://assets/city/street_pickup.glb")
const SPEAKER := preload("res://assets/venue/furniture/speaker.glb")
const ENGINE := preload("res://assets/story/ambience/engine.mp3")
const SPAWN := Vector3(-53.99,.035,-41.65)
const CARGO_SIZE := Vector3(.68,.57,.64)
const BRAKE := 18.0
const VEHICLE_BARRIER := 1 << 11
var world: NightWorld
var truck := CharacterBody3D.new()
var truck_shape := BoxShape3D.new()
var orbit := Camera3D.new()
var tailgate := Node3D.new()
var tailgate_tween: Tween
var engine := AudioStreamPlayer3D.new()
var tower: Node3D
var wheels: Array[Node] = []
var cargo: Array[Node3D] = []
var cargo_zones: Array[AudioStreamPlayer3D] = []
var cargo_slots := [-1, -1]
var held := -1
var open := false
var driving := false
var speed := 0.0
var saved_layer := 1
var saved_mask := 1
var remote_target := Transform3D.IDENTITY
var received := false

func build(city: NightWorld) -> void:
	world = city
	name = "RooftopDelivery"
	tower = preload("res://scripts/skyline_tower.gd").new()
	add_child(tower)
	tower.build(world)
	add_child(truck)
	truck.name = "DeliveryPickup"
	truck.position = SPAWN
	truck.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	truck.safe_margin = .012
	truck.collision_mask |= VEHICLE_BARRIER
	protect_subway()
	truck_shape.size = Vector3(2.06,1.55,4.88)
	var collider := CollisionShape3D.new()
	collider.shape = truck_shape
	collider.position.y = 1.0
	truck.add_child(collider)
	var model := PICKUP.instantiate() as Node3D
	truck.add_child(model)
	wheels = model.find_children("Axle-*", "Node3D", true, false)
	var leaf := model.find_child("tailgate", true, false) as Node3D
	if leaf != null:
		tailgate.position = leaf.position - Vector3.UP * .30
		truck.add_child(tailgate)
		leaf.reparent(tailgate)
	orbit.fov = 69.0
	orbit.near = .07
	add_child(orbit)
	var loop: AudioStreamMP3 = ENGINE.duplicate()
	loop.loop = true
	engine.stream = loop
	engine.max_distance = 22.0
	engine.volume_db = -25.0
	engine.position = Vector3(0,.84,1.54)
	truck.add_child(engine)
	for index in range(2):
		make_cargo(Vector3(-54.46 + index * .95,.02,-45.8), index)

func protect_subway() -> void:
	var opening := SubwayStation.OPENING
	var body := StaticBody3D.new()
	body.name = "SubwayVehicleBarrier"
	body.collision_layer = VEHICLE_BARRIER
	body.collision_mask = 0
	body.position = Vector3(opening.get_center().x,.52,opening.get_center().y)
	add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(opening.size.x,1.04,opening.size.y)
	collision.shape = shape
	body.add_child(collision)

func make_cargo(at: Vector3, index: int) -> void:
	var item := Node3D.new()
	item.name = "Subwoofer%d" % (index + 1)
	add_child(item)
	var cabinet := SPEAKER.instantiate() as Node3D
	item.add_child(cabinet)
	var bounds := AABB()
	var found := false
	for mesh in cabinet.find_children("*", "MeshInstance3D", true, false):
		var local: Transform3D = cabinet.global_transform.affine_inverse() * mesh.global_transform
		var part: AABB = local * mesh.get_aabb()
		bounds = bounds.merge(part) if found else part
		found = true
	if found and bounds.has_volume():
		cabinet.scale = CARGO_SIZE / bounds.size
		cabinet.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * cabinet.scale
	item.position = at
	world.add_sign(item, "SUB 0%d" % (index + 1), Vector3(0,.55,.325), Vector3.ZERO, Color("#a5e9e3"), .00175)
	var zone := AudioStreamPlayer3D.new()
	var bus := AudioServer.get_bus_index("Rooftop Sub")
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus,"Rooftop Sub")
		var filter := AudioEffectLowPassFilter.new()
		filter.cutoff_hz = 145.0
		AudioServer.add_bus_effect(bus,filter)
	zone.bus = &"Rooftop Sub"
	zone.stream = tower.stage_player.stream
	zone.max_distance = 17.0
	zone.unit_size = 4.25
	zone.volume_db = -11.0
	zone.position = Vector3(0,.32,0)
	item.add_child(zone)
	cargo_zones.append(zone)
	cargo.append(item)

func can_control() -> bool:
	return not WalkSession.active or multiplayer.is_server()

func target() -> int:
	if driving:
		return 0
	var camera: Camera3D = world.home.player.camera
	if held < 0:
		for index in cargo.size():
			if cargo_slots[index] == -1 and sees(camera,cargo[index].global_position + Vector3.UP*.3,2.65,.975):
				return 10 + index
	if sees(camera, truck.to_global(Vector3(-1.09,1.17,.57)), 2.7, .67):
		return 1
	if sees(camera, truck.to_global(Vector3(0,1.02,-2.58)), 3.0, .68):
		return 2
	if held < 0 and sees(camera,tower.to_global(tower.stage_switch),2.85,.85):
		return 3
	return -1

func sees(camera: Camera3D, point: Vector3, reach: float, facing: float) -> bool:
	var offset := point - camera.global_position
	if offset.length_squared() > reach * reach or offset.normalized().dot(-camera.global_basis.z) < facing:
		return false
	var hit := ray(camera.global_position, point)
	return hit.is_empty() or hit.position.distance_to(point) < .25

func ray(from: Vector3, to: Vector3, ignore_truck := false) -> Dictionary:
	var ignored: Array[RID] = [world.home.player.get_rid()]
	if ignore_truck:
		ignored.append(truck.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, ignored)
	return get_world_3d().direct_space_state.intersect_ray(query)

func hint() -> String:
	var action := target()
	if action == 0:
		return tr("WASD · Руль и газ   Пробел · Тормоз   E · Выйти") + "   %d km/h" % roundi(absf(speed) * 3.6)
	if held >= 0:
		if action == 2:
			return tr("E · Погрузить сабвуфер") if open else tr("E · Открыть борт   G · Поставить сабвуфер")
		return tr("G · Поставить сабвуфер")
	if action < 0:
		return ""
	if not can_control():
		return tr("Грузовик и груз · управление у хоста")
	match action:
		1: return tr("E · Сесть за руль грузовика")
		2:
			if not open:
				return tr("E · Открыть грузовой борт")
			return tr("E · Выгрузить сабвуфер   G · Закрыть борт") if cargo_slots.has(0) or cargo_slots.has(1) else tr("E · Закрыть борт")
		3: return tr("E · Остановить саундчек") if tower.stage_player.playing else tr("E · Запустить саундчек")
	return tr("E · Поднять сабвуфер")

func interact() -> bool:
	var action := target()
	if action < 0:
		return false
	if not can_control():
		return true
	match action:
		0: exit_truck()
		1: enter_truck()
		2: interact_bed()
		3: tower.toggle_soundcheck()
		_: held = action - 10
	return true

func cargo_action() -> bool:
	if driving:
		return true
	if held >= 0:
		drop_cargo()
		return true
	if target() == 2 and open and can_control():
		set_bed(false)
		return true
	return false

func set_bed(value: bool) -> void:
	if value == open:
		return
	open = value
	if is_instance_valid(tailgate_tween):
		tailgate_tween.kill()
	tailgate_tween = create_tween()
	tailgate_tween.tween_property(tailgate,"rotation:x", -PI/2 if open else 0.0,.32).set_trans(Tween.TRANS_SINE)

func interact_bed() -> void:
	if not open:
		set_bed(true)
	elif held >= 0:
		var slot := 1 if cargo_slots.has(0) else 0
		if not cargo_slots.has(slot):
			cargo_slots[held] = slot
			held = -1
	else:
		var loaded := cargo_slots.find(0)
		if loaded < 0:
			loaded = cargo_slots.find(1)
		if loaded >= 0:
			cargo_slots[loaded] = -1
			held = loaded
		else:
			set_bed(false)

func drop_cargo() -> void:
	var camera: Camera3D = world.home.player.camera
	var forward := -camera.global_basis.z
	forward.y = 0
	var base := world.home.player.global_position
	var point := base + forward.normalized() * 1.05
	var floor_hit := ray(point + Vector3.UP * .5, point - Vector3.UP*.43)
	if floor_hit.is_empty() or floor_hit.normal.y < .9:
		GameEvents.notify(tr("Поставь сабвуфер на ровный пол."))
		return
	var at: Vector3 = floor_hit.position
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = CARGO_SIZE
	query.shape = shape
	query.transform.origin = at + Vector3.UP * (CARGO_SIZE.y/2 + .026)
	query.collision_mask = 1
	if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():
		GameEvents.notify(tr("Здесь мало места для сабвуфера."))
		return
	for index in cargo.size():
		if index != held and cargo_slots[index] < 0 and cargo[index].global_position.distance_to(at) < .72:
			GameEvents.notify(tr("Здесь уже стоит сабвуфер."))
			return
	cargo[held].global_position = at + Vector3.UP*.012
	cargo[held].rotation.y = world.home.player.rotation.y + PI
	held = -1

func enter_truck() -> void:
	if held >= 0:
		GameEvents.notify(tr("Сначала поставь сабвуфер или погрузи его."))
		return
	var player = world.home.player
	driving = true
	set_bed(false)
	saved_layer = player.collision_layer
	saved_mask = player.collision_mask
	player.collision_layer = 0
	player.collision_mask = 0
	player.velocity = Vector3.ZERO
	player.set_physics_process(false)
	player.avatar.hide()
	player.view_model.hide()
	orbit.make_current()
	update_camera(1.0)
	engine.play()

func exit_truck() -> void:
	if absf(speed) > .55:
		GameEvents.notify(tr("Сначала останови грузовик."))
		return
	var player = world.home.player
	for side in [-1.0,1.0]:
		var at := truck.to_global(Vector3(side * 1.5,0,.56))
		var ground := ray(at+Vector3.UP*.75,at-Vector3.UP*.35,true)
		if ground.is_empty() or not ray(truck.to_global(Vector3(side*1.1,1.18,.56)),at+Vector3.UP*1.18,true).is_empty():
			continue
		driving = false
		truck.velocity = Vector3.ZERO
		speed = 0.0
		player.global_position = ground.position + Vector3.UP*.04
		player.rotation.y = truck.rotation.y + PI
		player.collision_layer = saved_layer
		player.collision_mask = saved_mask
		player.avatar.show()
		player.view_model.show()
		player.camera.make_current()
		player.set_physics_process(true)
		engine.stop()
		return
	GameEvents.notify(tr("Оставь место сбоку, чтобы открыть дверь."))

func _physics_process(delta: float) -> void:
	if world == null or not is_instance_valid(world.home.player):
		return
	if driving:
		handle_driving(delta)
	elif not can_control() and received:
		truck.transform = truck.transform.interpolate_with(remote_target,1.0-exp(-delta*12.0))
	update_cargo()

func handle_driving(delta: float) -> void:
	var paused := world.home.modal
	var throttle := 0.0 if paused else Input.get_axis("move_back","move_forward")
	var steering := 0.0 if paused else Input.get_axis("move_right","move_left")
	var braking := paused or Input.is_action_pressed("jump")
	var target_speed := throttle * (12.0 if throttle >= 0.0 else 4.0)
	speed = move_toward(speed,0.0 if braking else target_speed,delta*(BRAKE if braking else (5.0 if absf(throttle)>.1 else 3.5)))
	if absf(speed) > .22 and absf(steering) > .04:
		var candidate := truck.rotation.y + steering * signf(speed) * delta * minf(1.46,absf(speed)*.62)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = truck_shape
		query.transform = Transform3D(Basis(Vector3.UP,candidate),truck.global_position + Vector3.UP*1.0)
		query.exclude = [truck.get_rid()]
		query.collision_mask = truck.collision_mask
		if get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():
			truck.rotation.y = candidate
	truck.velocity = truck.global_basis.z * speed
	var distance := speed * delta
	if truck.move_and_slide():
		speed *= .28
	for wheel in wheels:
		wheel.rotate_x(distance / .46)
	engine.pitch_scale = .76 + absf(speed)*.064
	world.home.player.global_position = truck.to_global(Vector3(-.42,.73,.64))
	world.home.player.rotation.y = truck.rotation.y + PI
	update_camera(delta)

func update_camera(delta: float) -> void:
	var look := truck.to_global(Vector3(0,1.24,.62))
	var desired := truck.to_global(Vector3(0,3.3,-6.6))
	var hit := ray(look,desired,true)
	if not hit.is_empty():
		desired = hit.position.lerp(look,.10)
	var snap := hit.is_empty() and orbit.global_position.distance_squared_to(desired)<20.0
	orbit.global_position = orbit.global_position.lerp(desired,1.0-exp(-delta*13.0)) if snap else desired
	orbit.look_at(look)

func update_cargo() -> void:
	for index in cargo.size():
		var item := cargo[index]
		if cargo_slots[index] >= 0:
			var x := -.43 if cargo_slots[index] == 0 else .43
			item.global_position = truck.to_global(Vector3(x,.87,-1.54))
			item.rotation.y = truck.rotation.y + PI
		elif index == held:
			var camera: Camera3D = world.home.player.camera
			item.global_position = camera.to_global(Vector3(.17,-.72,-.89))
			item.rotation.y = world.home.player.rotation.y
		var playing: bool = tower.stage_player.playing and cargo_slots[index] < 0 and index != held and not item.get_meta("remote_held",false)
		var on_roof: bool = absf(tower.to_local(item.global_position).y - tower.ROOF) < .35
		var zone := cargo_zones[index]
		if playing and on_roof:
			if not zone.playing:
				zone.play(tower.stage_player.get_playback_position())
		elif zone.playing:
			zone.stop()

func network_state() -> Array:
	var positions := []
	for index in cargo.size():
		positions.append([cargo[index].transform,cargo_slots[index],index == held])
	return [truck.transform,open,driving,absf(speed),positions,tower.stage_player.playing,tower.stage_player.get_playback_position()]

func apply_network_state(state: Array) -> void:
	remote_target = state[0]
	if not received:
		truck.transform = remote_target
		received = true
	set_bed(state[1])
	if state[2] and not engine.playing:
		engine.play()
	elif not state[2] and engine.playing:
		engine.stop()
	engine.pitch_scale = .76 + float(state[3])*.064
	for index in cargo.size():
		cargo[index].transform = state[4][index][0]
		cargo_slots[index] = state[4][index][1]
		cargo[index].set_meta("remote_held",state[4][index][2])
	if state[5] and not tower.stage_player.playing:
		tower.stage_player.play(state[6])
	elif not state[5] and tower.stage_player.playing:
		tower.stage_player.stop()
