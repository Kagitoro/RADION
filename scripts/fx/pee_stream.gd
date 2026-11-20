class_name PeeStream
extends Node3D
## Hold the "pee" action (U): a yellow arc from the player's hips that leaves
## growing puddles where it lands. Beer fills the bladder, peeing empties it.

const COLOR := Color(1.0,.86,.18,.85)
## Launch speed of the stream (m/s) and its spread.
const SPEED := 2.6
const HIP := Vector3(0,.92,-.20)
const PUDDLE_MAX := .55
const PUDDLE_GROWTH := .12
const PUDDLE_LIFE := 90.0
const DRAIN := .07
const BEER_FILL := .30

var player: Player
var bladder := .45
var active := false
var particles: CPUParticles3D
var sound: AudioStreamPlayer3D
var puddles: Array[MeshInstance3D] = []
var current: MeshInstance3D
var puddle_material: StandardMaterial3D
var empty_hint := 0.0

func _init(owner_player: Player) -> void:
	player = owner_player

func _ready() -> void:
	position = HIP
	particles = CPUParticles3D.new()
	particles.emitting = false
	particles.amount = 140
	particles.lifetime = .75
	particles.local_coords = false
	particles.direction = Vector3(0,.35,-1)
	particles.spread = 2.5
	particles.initial_velocity_min = SPEED*.95
	particles.initial_velocity_max = SPEED*1.05
	particles.gravity = Vector3(0,-9.8,0)
	particles.scale_amount_min = .6
	particles.scale_amount_max = 1.0
	var drop := SphereMesh.new()
	drop.radius = .009
	drop.height = .03
	drop.radial_segments = 4
	drop.rings = 2
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = .15
	drop.material = material
	particles.mesh = drop
	add_child(particles)
	puddle_material = StandardMaterial3D.new()
	puddle_material.albedo_color = Color(COLOR.r,COLOR.g*.92,COLOR.b,.55)
	puddle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puddle_material.roughness = .05
	puddle_material.metallic_specular = .8
	sound = AudioStreamPlayer3D.new()
	sound.stream = make_trickle()
	sound.volume_db = -14.0
	sound.unit_size = 2.0
	add_child(sound)

func drink() -> void:
	bladder = minf(1.0,bladder+BEER_FILL)

func can_pee() -> bool:
	return not player.paused and not player.collapsed and not player.vomiting

func _process(delta: float) -> void:
	# Aim with the camera's yaw so the stream follows where the player looks.
	rotation.y = player.camera.rotation.y
	var wants := Input.is_action_pressed("pee") and can_pee()
	empty_hint = maxf(0.0,empty_hint-delta)
	if wants and bladder<=0.0:
		if empty_hint<=0.0:
			GameEvents.notify(tr("Пусто. Выпей пива."))
			empty_hint = 3.0
		wants = false
	set_active(wants)
	if active:
		bladder = maxf(0.0,bladder-DRAIN*delta)
		grow_puddle(delta)
	for puddle in puddles.duplicate():
		var age: float = puddle.get_meta("age")+delta
		puddle.set_meta("age",age)
		if age>PUDDLE_LIFE:
			var fade := 1.0-(age-PUDDLE_LIFE)/10.0
			if fade<=0.0:
				puddles.erase(puddle)
				if puddle==current:
					current = null
				puddle.queue_free()
			else:
				puddle.transparency = 1.0-fade

func set_active(value: bool) -> void:
	if value==active:
		return
	active = value
	particles.emitting = value
	if value:
		sound.play()
	else:
		sound.stop()
		current = null

## Traces the arc in short steps and grows a puddle where it hits the floor.
func grow_puddle(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var dir := (global_basis*particles.direction.normalized())*SPEED
	var point := global_position
	var hit := {}
	for step in 24:
		var t := .04
		var next := point+dir*t
		dir.y -= 9.8*t
		var query := PhysicsRayQueryParameters3D.create(point,next,1,[player.get_rid()])
		hit = space.intersect_ray(query)
		if not hit.is_empty():
			break
		point = next
	if hit.is_empty() or (hit.normal as Vector3).y<.6:
		return
	var at: Vector3 = hit.position+Vector3.UP*.004
	if current==null or current.global_position.distance_to(at)>current.get_meta("radius")*.7+.05:
		current = make_puddle(at)
	var radius: float = minf(PUDDLE_MAX,current.get_meta("radius")+PUDDLE_GROWTH*delta)
	current.set_meta("radius",radius)
	current.set_meta("age",0.0)
	current.transparency = 0.0
	current.scale = Vector3(radius,1,radius*.8)

func make_puddle(at: Vector3) -> MeshInstance3D:
	var puddle := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = .002
	disc.radial_segments = 14
	disc.rings = 0
	puddle.mesh = disc
	puddle.material_override = puddle_material
	puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puddle.set_meta("radius",.04)
	puddle.set_meta("age",0.0)
	get_tree().current_scene.add_child(puddle)
	puddle.global_position = at
	puddle.rotation.y = randf()*TAU
	puddle.scale = Vector3(.04,1,.032)
	puddles.append(puddle)
	if puddles.size()>24:
		puddles.pop_front().queue_free()
	return puddle

## Filtered noise loop: a soft trickle without shipping an audio file.
static func make_trickle() -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	data.resize(rate*2)
	var low := 0.0
	for i in rate:
		low = lerpf(low,randf_range(-1.0,1.0),.35)
		var wobble := .75+.25*sin(i*TAU*7.0/rate)
		data.encode_s16(i*2,int(clampf(low*wobble*.6,-1,1)*32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = rate
	return stream
