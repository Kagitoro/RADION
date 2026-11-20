extends Node3D
## Imported street vehicles share this wrapper so their wheels, cabin and collider agree.

const MODELS := [
	preload("res://assets/city/traffic/hatchback.glb"),
	preload("res://assets/city/traffic/city_bus.glb"),
	preload("res://assets/city/traffic/rally.glb"),
	preload("res://assets/city/traffic/sedan.glb"),
	preload("res://assets/city/traffic/suv.glb"),
	preload("res://assets/city/traffic/sport_coupe.glb"),
	preload("res://assets/city/traffic/supercar.glb"),
]
const NAMES := ["Hatchback","CityBus","Rally","Sedan","Crossover","ClassicCoupe","Supercar"]
const SIZES := [
	Vector3(1.82,1.48,4.10), Vector3(2.56,3.08,12.0), Vector3(1.82,1.39,4.12),
	Vector3(1.89,1.46,4.85), Vector3(1.89,1.70,4.65), Vector3(1.78,1.29,4.62), Vector3(2.07,1.14,4.60),
]
const DRIVER_EYES := [
	Vector3(.36,1.24,-.28), Vector3(.72,1.93,5.00), Vector3(.37,1.15,-.29),
	Vector3(.37,1.23,-.29), Vector3(.38,1.40,-.36), Vector3(.37,1.10,-.78), Vector3(.365,.99,-.19),
]
const RADII := [.316,.48,.32,.335,.355,.305,.334]
var kind := 0
var length_m := 0.0
var wheel_meshes: Array[Node3D] = []
var front_pivots: Array[Node3D] = []
var wheel_angle := 0.0
var driver: PartyGuest
var cabin_light: OmniLight3D
var wheel: Node3D
var wheel_rest := Basis.IDENTITY
var windows := 0
var model: Node3D

func build(index: int, moving: bool) -> void:
	kind = index
	name = NAMES[kind]
	var size: Vector3 = SIZES[kind]
	length_m = size.z
	model = MODELS[kind].instantiate() as Node3D
	add_child(model)
	for part_name in ["wheel_FL","wheel_FR","wheel_RL","wheel_RR"]:
		var hub := model.find_child(part_name,true,false) as Node3D
		if hub != null and hub.get_child_count() > 0:
			wheel_meshes.append(hub.get_child(0) as Node3D)
	for part_name in ["steer_FL","steer_FR"]:
		var pivot := model.find_child(part_name,true,false) as Node3D
		if pivot != null:
			front_pivots.append(pivot)
	wheel = model.find_child("steering_wheel",true,false) as Node3D
	if wheel != null:
		wheel_rest = wheel.basis
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.albedo_color = Color(.44,.65,.69,.09)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	for item in model.find_children("*","MeshInstance3D",true,false):
		var part := item as MeshInstance3D
		for surface in part.mesh.get_surface_count():
			var material := part.mesh.surface_get_material(surface)
			if material != null and material.resource_name.to_lower().begins_with("glass"):
				part.set_surface_override_material(surface,glass)
				part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				windows += 1
	var body: StaticBody3D = AnimatableBody3D.new() if moving else StaticBody3D.new()
	if body is AnimatableBody3D:
		body.sync_to_physics = false
	body.collision_mask = 0
	add_child(body)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.position.y = size.y*.5
	collider.shape = box
	body.add_child(collider)

func add_driver(index: int, assets: Dictionary) -> void:
	driver = PartyGuest.new(4+index*2,null,assets)
	driver.name = "Driver"
	add_child(driver)
	driver.name_tag.hide()
	driver.speech.hide()
	if is_instance_valid(driver.smoking_prop):
		driver.smoking_prop.hide()
	driver.rotation.y = PI
	var height := 1.0 if kind == 1 else (.84 if kind == 6 else .92)
	driver.scale = Vector3.ONE*height
	var eye: Vector3 = DRIVER_EYES[kind]
	driver.position = eye-Vector3.UP*1.45*height
	var rig := driver.imported_model
	if is_instance_valid(rig):
		rig.pickup_seat = 0
		driver.pose(.10,0.0,false)
		driver.position += eye - Vector3(0,.075,0) - to_local(rig.mouth_transform().origin)
	cabin_light = OmniLight3D.new()
	cabin_light.position = eye+Vector3(-.26,.13,.24)
	cabin_light.light_color = Color("#d6e1f3")
	cabin_light.light_energy = .48
	cabin_light.omni_range = .88
	add_child(cabin_light)

func animate_wheels(step: float, steering: float) -> void:
	wheel_angle = fposmod(wheel_angle+step/float(RADII[kind]),TAU)
	for index in wheel_meshes.size():
		wheel_meshes[index].rotation.x = wheel_angle * (1.0 if index%2==0 else -1.0)
	for pivot in front_pivots:
		pivot.rotation.y = steering*.31
	if wheel != null:
		wheel.basis = wheel_rest * Basis(Vector3.UP,-steering*.79)

func animate_driver(delta: float, steering: float, nearby: bool) -> void:
	if not is_instance_valid(driver):
		return
	cabin_light.visible = nearby
	if not nearby:
		return
	if is_instance_valid(driver.imported_model):
		driver.imported_model.pickup_steering = steering*.7
	driver.pose(delta,0.0,false)
