extends RefCounted

const CABINET_ID := "base-43"
const FLOOR_ID := "base-41"
const STOVE_ID := "base-44"
const TABLE := preload("res://assets/kitchen/dining_table/dining_table_1k.gltf")
const CHAIR := preload("res://assets/kitchen/dining_chair_02/dining_chair_02_1k.gltf")
const STOVE := preload("res://assets/kitchen/gefest_stove.glb")

static func apply(home: Home) -> void:
	fit_dining_set(home)
	var stove: Node3D = home.nodes.get(STOVE_ID)
	if stove != null:
		hide_meshes(stove)
		# The imported oven door faces +Z, toward the wall in the original slot.
		place_model(stove, STOVE, home.vector(home.originals[STOVE_ID].dimensions), Vector3.ZERO, PI)
	var cabinet: Node3D = home.nodes.get(CABINET_ID)
	if cabinet != null:
		fit_cabinets(cabinet, home.vector(home.originals[CABINET_ID].dimensions))
	var floor: Node3D = home.nodes.get(FLOOR_ID)
	if floor != null:
		var shader := Shader.new()
		shader.code = """
shader_type spatial;
varying vec2 tile_position;
void vertex() {
	tile_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz / 0.45;
}
void fragment() {
	vec2 tile = floor(tile_position);
	vec2 edge = min(fract(tile_position), 1.0 - fract(tile_position));
	float joint = smoothstep(0.006, 0.016, min(edge.x, edge.y));
	float shade = fract(sin(dot(tile, vec2(78.23, 45.91))) * 4385.79);
	vec3 ceramic = mix(vec3(0.28, 0.30, 0.29), vec3(0.39, 0.41, 0.39), shade);
	ALBEDO = mix(vec3(0.17, 0.18, 0.17), ceramic, joint);
	ROUGHNESS = 0.82;
}
"""
		var tile := ShaderMaterial.new()
		tile.shader = shader
		for mesh: MeshInstance3D in floor.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = tile

static func fit_dining_set(home: Home) -> void:
	var table: Node3D = home.nodes.get("base-48")
	if table != null:
		hide_meshes(table)
		place_model(table, TABLE, home.vector(home.originals["base-48"].dimensions), Vector3.ZERO)
	var chairs: Node3D = home.nodes.get("base-49")
	if chairs != null:
		hide_meshes(chairs)
		for offset in [-.54, .54]:
			place_model(chairs, CHAIR, Vector3(.47, .91, .46), Vector3(offset, 0, 0), PI)
	for index in range(59, 71):
		var root: Node3D = home.nodes.get("base-%d" % index)
		if root == null:
			continue
		hide_meshes(root)
		if index in [59, 65]:
			place_model(root, CHAIR, Vector3(.42, .91, .49), Vector3(0, -.4475, 0))

static func hide_meshes(root: Node3D) -> void:
	for part: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		part.hide()

static func place_model(parent: Node3D, scene: PackedScene, size: Vector3, offset: Vector3, yaw := 0.0) -> void:
	var carrier := Node3D.new()
	carrier.position = offset
	carrier.rotation.y = yaw
	parent.add_child(carrier)
	var model := scene.instantiate() as Node3D
	carrier.add_child(model)
	var bounds := AABB()
	var inverse := model.global_transform.affine_inverse()
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var local := (inverse * part.global_transform) * part.get_aabb()
		bounds = bounds.merge(local) if bounds.has_volume() else local
	if not bounds.has_volume():
		carrier.queue_free()
		return
	carrier.scale = size / bounds.size
	model.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z)

static func fit_cabinets(root: Node3D, size: Vector3) -> void:
	hide_meshes(root)
	var kitchen := Node3D.new()
	kitchen.name = "KitchenCabinetry"
	root.add_child(kitchen)
	kitchen.scale = size / Vector3(3.30, 2.41, 0.80)
	var green := finish(Color("#66756a"), 0.74)
	var oak := finish(Color("#a87a53"), 0.68)
	var stone := finish(Color("#dfd5bf"), 0.53)
	var dark := finish(Color("#272a27"), 0.49)
	var metal := finish(Color("#aaa9a5"), 0.29, 0.85)
	var ceramic := finish(Color("#e1d9c8"), 0.43)
	var grout := finish(Color("#8e8880"), 0.92)
	add_box(kitchen, Vector3(0, .066, .031), Vector3(3.24, .132, .58), dark)
	for side in [-1, 1]:
		add_box(kitchen, Vector3(side * 1.025, .51, .030), Vector3(1.23, .76, .66), green)
	add_box(kitchen, Vector3(0, .435, .030), Vector3(.82, .61, .66), green)
	for i in range(5):
		var x := (i - 2) * .656
		add_box(kitchen, Vector3(x, .50, -.317), Vector3(.638, .73, .036), green)
		add_box(kitchen, Vector3(x + .16, .76, -.352), Vector3(.125, .017, .023), metal)
		add_box(kitchen, Vector3(x, 1.98, .19), Vector3(.638, .75, .405), oak)
		add_box(kitchen, Vector3(x, 1.98, -.022), Vector3(.638, .745, .028), oak)
		add_box(kitchen, Vector3(x + .17, 1.70, -.05), Vector3(.015, .10, .023), metal)
	# A real opening in the countertop for the inset sink.
	add_box(kitchen, Vector3(-1.02, .91, 0), Vector3(1.26, .052, .79), stone)
	add_box(kitchen, Vector3(1.02, .91, 0), Vector3(1.26, .052, .79), stone)
	for z in [-.332, .332]:
		add_box(kitchen, Vector3(0, .91, z), Vector3(.78, .052, .126), stone)
	add_box(kitchen, Vector3(0, .769, 0), Vector3(.75, .026, .517), metal)
	for side in [-1, 1]:
		add_box(kitchen, Vector3(side * .378, .847, 0), Vector3(.025, .158, .535), metal)
		add_box(kitchen, Vector3(0, .847, side * .254), Vector3(.756, .158, .025), metal)
	add_box(kitchen, Vector3(.16, 1.058, .319), Vector3(.034, .246, .034), metal)
	add_box(kitchen, Vector3(.16, 1.172, .222), Vector3(.034, .031, .211), metal)
	add_box(kitchen, Vector3(.16, 1.144, .124), Vector3(.034, .064, .034), metal)
	add_box(kitchen, Vector3(0, 1.268, .385), Vector3(3.30, .664, .020), grout)
	var backsplash := MultiMeshInstance3D.new()
	var tile := BoxMesh.new()
	tile.size = Vector3(.295, .160, .014)
	tile.material = ceramic
	var tiles := MultiMesh.new()
	tiles.transform_format = MultiMesh.TRANSFORM_3D
	tiles.mesh = tile
	tiles.instance_count = 44
	for row in range(4):
		for column in range(11):
			var center := Vector3((column - 5) * .30, 1.017 + row * .165, .369)
			tiles.set_instance_transform(row * 11 + column, Transform3D(Basis.IDENTITY, center))
	backsplash.multimesh = tiles
	kitchen.add_child(backsplash)

static func finish(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

static func add_box(parent: Node3D, center: Vector3, dimensions: Vector3, material: Material) -> void:
	var shape := BoxMesh.new()
	shape.size = dimensions
	var mesh := MeshInstance3D.new()
	mesh.mesh = shape
	mesh.material_override = material
	mesh.position = center
	parent.add_child(mesh)
