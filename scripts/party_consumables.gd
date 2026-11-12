class_name PartyConsumables
extends RefCounted
## Beer and cigarettes in the player hands: props, sips, ash, smoke and their sounds.

var hand_prop: Node3D
var bottle_model: Node3D
var falling_bits: Array[Dictionary] = []
var lip_cigarette: Node3D
var lip_view: Node3D
var ember_timer := 0.0
var cigarette_hand: Node3D
var cigarette_held := false
var cigarette_burn := 0.0
var action_audio := AudioStreamPlayer.new()
var sip_audio: AudioStreamWAV
var breath_audio: AudioStreamWAV
var drinks := 0
var smokes := 0
var party: Party

func _init(owner_node: Party) -> void:
	party = owner_node

func consume(beer: bool) -> void:
	if party.home.player.collapsed or party.home.player.vomiting or is_instance_valid(hand_prop):
		return
	if is_instance_valid(lip_cigarette):
		if beer:
			GameEvents.notify(tr("Сначала потуши сигарету · K"))
		else:
			handle_cigarette()
		return
	var shop = party.home.shop
	if beer:
		if shop.beer<=0:
			GameEvents.notify(tr("Пива нет · купи в Night Shop"))
			return
		shop.beer -= 1
	else:
		if party.cigarettes<=0:
			GameEvents.notify(tr("Сигареты закончились · купи в Night Shop"))
			return
		party.cigarettes -= 1
		cigarette_burn = 0.0
	shop.save_stock()
	var prop := Node3D.new()
	party.home.player.camera.add_child(prop)
	hand_prop = prop
	prop.position = Vector3(.27,-.27,-.61)
	var skin := Color("#ae785b")
	party.oval(prop,Vector3(.042,-.043,.051),Vector3(.086,.085,.073),skin)
	var sleeve := party.oval(prop,Vector3(.091,-.114,.12),Vector3(.09,.185,.088),Color("#5b6557"))
	sleeve.rotation.z = .35
	var item := Node3D.new()
	prop.add_child(item)
	if beer:
		build_bottle(item)
		for index in range(4):
			party.oval(prop,Vector3(.009,-.057+index*.018,-.035),Vector3(.067,.017,.025),skin)
		party.oval(prop,Vector3(.037,.016,.019),Vector3(.028,.044,.026),skin)
	else:
		var paper := party.cylinder(item,Vector3(0,.018,-.031),.0048,.066,Color("#eee9df"))
		paper.rotation.x = PI*.5
		paper.name = "Paper"
		detail_surface(paper,Color("#d3cdc0"),Color("#f1ece1"),.92)
		var filter := party.cylinder(item,Vector3(0,.018,.011),.005,.022,Color("#bb8c52"))
		filter.rotation.x = PI*.5
		detail_surface(filter,Color("#795331"),Color("#ceaa76"),.90)
		var ember := party.cylinder(item,Vector3(0,.018,-.066),.005,.008,Color("#e47b45"))
		ember.rotation.x = PI*.5
		ember.name = "Ember"
		var ash := party.cylinder(item,Vector3(0,.018,-.063),.0052,.011,Color("#72716d"))
		ash.rotation.x = PI*.5
		ash.name = "Ash"
		detail_surface(ash,Color("#2c2b2a"),Color("#a39d95"),.97)
		var glow := ember.material_override as StandardMaterial3D
		glow.emission_enabled = true
		glow.emission = Color("#ff6724")
		glow.emission_energy_multiplier = .65
		for index in range(2):
			party.oval(prop,Vector3(.007+index*.014,.005,-.01),Vector3(.016,.028,.054),skin)
		party.oval(prop,Vector3(-.006,-.006,.005),Vector3(.020,.022,.035),skin)
	for part in prop.find_children("*","GeometryInstance3D",true,false):
		part.layers = 8
	var actor = party.home.player
	var reflected := item.duplicate() as Node3D
	actor.action_grip.add_child(reflected)
	reflected.position = actor.held_item_offset(beer)
	for part in reflected.find_children("*","GeometryInstance3D",true,false):
		part.layers = 5 if is_instance_valid(actor.dj_rig) else 4
	if is_instance_valid(actor.dj_rig):
		prop.hide()
	if not beer:
		for part in item.get_children():
			var material := part.material_override.duplicate() as StandardMaterial3D
			# The camera prop draws over the torso while the mirrored copy keeps scene depth.
			material.no_depth_test = true
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			part.material_override = material
	actor.action_beer = beer
	actor.set_action_pose(.001)
	var motion := party.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
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
	if is_instance_valid(actor.dj_rig):
		lip_view.show()
		set_prop_layers(reflected,4)
	ember_timer = 0.0

func handle_cigarette() -> void:
	var actor = party.home.player
	var grip := cigarette_hand
	hand_prop = grip
	var motion := party.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if not cigarette_held:
		grip.position = Vector3(.060,-.125,-.24)
		if not is_instance_valid(actor.dj_rig):
			grip.show()
		motion.tween_method(actor.set_action_pose,0.0,1.0,.28)
		motion.tween_callback(func():
			lip_view.reparent(grip,false)
			lip_view.transform = Transform3D.IDENTITY
			lip_cigarette.reparent(actor.action_grip,false)
			lip_cigarette.position = actor.held_item_offset(false)
			lip_cigarette.rotation = Vector3.ZERO
			if is_instance_valid(actor.dj_rig):
				set_prop_layers(lip_cigarette,5)
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

func set_prop_layers(prop: Node3D, layers: int) -> void:
	for part in prop.find_children("*","GeometryInstance3D",true,false):
		part.layers = layers

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
	party.home.player.set_action_pose(0)
	GameEvents.notify(tr("Сигарета потушена · осталось %d") % party.cigarettes)

func ember_smoke() -> void:
	var tip := lip_cigarette.get_node("Ember") as Node3D
	var at := tip.global_position
	var cloud := party.oval(party,party.to_local(at),Vector3.ONE*.013,Color("#b9bfc5"))
	var paint := cloud.material_override as StandardMaterial3D
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.albedo_color.a = .16
	var drift := party.create_tween().set_parallel()
	drift.tween_property(cloud,"position",cloud.position+Vector3(party.rng.randf_range(-.04,.04),.16,party.rng.randf_range(-.04,.04)),1.25)
	drift.tween_property(cloud,"scale",Vector3.ONE*.057,1.25)
	drift.tween_property(paint,"albedo_color:a",0.0,1.25)
	drift.chain().tween_callback(cloud.queue_free)

func finish_sip() -> void:
	var actor := party.home.player
	var grip: Node3D = actor.action_grip
	spill_bits(grip.to_global(actor.held_item_offset(true)+Vector3(0,.158,-.01)),true,3)
	drinks += 1
	party.home.player.drink_beer()
	action_audio.stream = sip_audio
	action_audio.play()
	GameEvents.notify(tr("Опьянение · %d%%") % roundi(party.home.player.intoxication*100))

func exhale() -> void:
	action_audio.stream = breath_audio
	action_audio.play()
	var vapor := Node3D.new()
	var camera: Camera3D = party.home.player.camera
	party.add_child(vapor)
	vapor.global_transform = camera.global_transform
	for index in range(6):
		var cloud := party.oval(vapor,Vector3(.02,-.19,-.25-index*.016),Vector3.ONE*(.035+index*.006),Color("#c4c9cd"))
		var paint := cloud.material_override as StandardMaterial3D
		paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		paint.albedo_color.a = .07
		var drift := party.create_tween().set_parallel()
		drift.tween_property(cloud,"position",cloud.position+Vector3(sin(index*2.4)*.13,.26+index*.024,-.28),1.5)
		drift.tween_property(cloud,"scale",Vector3.ONE*2.1,1.5)
		drift.tween_property(paint,"albedo_color:a",0.0,1.5)
	party.get_tree().create_timer(1.6).timeout.connect(vapor.queue_free)

func detail_surface(mesh: MeshInstance3D, dark: Color, light: Color, roughness: float) -> void:
	var key := dark.to_html()+light.to_html()
	if not party.detail_textures.has(key):
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
		party.detail_textures[key] = texture
	var material := mesh.material_override as StandardMaterial3D
	material.albedo_color = Color.WHITE
	material.albedo_texture = party.detail_textures[key]
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
		party.cylinder(item,Vector3(0,-.023,0),.0357,.166,Color("#4c2e19"))
		party.oval(item,Vector3(0,.059,0),Vector3(.071,.063,.071),Color("#4c2e19"))
		party.cylinder(item,Vector3(0,.113,0),.019,.09,Color("#55331d"))
	var paper := party.cylinder(item,Vector3(0,-.021,0),.0359,.064,Color("#d1ba83"))
	(paper.mesh as CylinderMesh).radial_segments = 64
	detail_surface(paper,Color("#9d895c"),Color("#e0c99b"),.81)
	var band := party.cylinder(item,Vector3(0,-.046,0),.0361,.011,Color("#78352a"))
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
		var droplet := party.oval(item,at,Vector3(.0014,.0027,.0014),Color(.9,.83,.73,.64))
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
		var size := party.rng.randf_range(.003,.006) if beer else party.rng.randf_range(.0015,.004)
		var tint := Color("#b77a31") if beer else Color("#77716b").darkened(party.rng.randf_range(0,.45))
		var bit := party.oval(party,party.to_local(origin),Vector3(size,size*1.3,size),tint)
		var material := bit.material_override as StandardMaterial3D
		material.roughness = .13 if beer else .98
		var forward: Vector3 = -party.home.player.camera.global_basis.z
		var velocity := forward*party.rng.randf_range(.12,.35)+Vector3(party.rng.randf_range(-.15,.15),party.rng.randf_range(-.05,.1),party.rng.randf_range(-.14,.14))
		falling_bits.append({"node":bit,"velocity":velocity,"age":0.0,"beer":beer})

func update_falling_bits(delta: float) -> void:
	var space := party.get_world_3d().direct_space_state
	for index in range(falling_bits.size()-1,-1,-1):
		var entry := falling_bits[index]
		var bit: MeshInstance3D = entry.node
		entry.age += delta
		entry.velocity += Vector3.DOWN*delta*(8.0 if entry.beer else 3.4)
		var next: Vector3 = bit.global_position+entry.velocity*delta
		var ray := PhysicsRayQueryParameters3D.create(bit.global_position,next,1,[party.home.player.get_rid()])
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			var normal: Vector3 = hit.normal
			bit.global_position = hit.position+normal*.0015
			bit.scale *= Vector3(1.75,.19,1.75)
			party.get_tree().create_timer(4.0 if entry.beer else 9.0).timeout.connect(bit.queue_free)
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
